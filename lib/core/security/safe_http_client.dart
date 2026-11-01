import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../logging/diagnostics_service.dart';
import 'safe_http_client_seam.dart';
import 'url_policy.dart';

typedef DnsResolver = Future<List<InternetAddress>> Function(String host);

class SafeStreamResponse {
  final int statusCode;
  final String reasonPhrase;
  final HttpHeaders headers;
  final Uri finalUri;
  final Stream<List<int>> body;
  final void Function() close;

  const SafeStreamResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.finalUri,
    required this.body,
    required this.close,
  });
}

class SafeHttpResponse {
  final int statusCode;
  final String reasonPhrase;
  final HttpHeaders headers;
  final List<int> bodyBytes;
  final Uri finalUri;

  const SafeHttpResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.bodyBytes,
    required this.finalUri,
  });

  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);
}

class SafeHttpClientException implements Exception {
  final String message;
  final String? code;
  final String? host;

  const SafeHttpClientException(this.message, {this.code, this.host});

  @override
  String toString() => 'SafeHttpClientException($code): $message';
}

class SafeHttpClient {
  final DnsResolver _dnsResolver;
  final Duration connectionTimeout;
  final Duration readTimeout;
  final int maxRedirects;
  final int maxHeaderSize;
  final SecurityContext? _customSecurityContext;
  final SafeHttpClientSeam _seam;

  SafeHttpClient({
    DnsResolver? dnsResolver,
    this.connectionTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 20),
    this.maxRedirects = 5,
    this.maxHeaderSize = 64 * 1024,
    SecurityContext? customSecurityContext,
    SafeHttpClientSeam seam = const StrictSafeHttpClientSeam(),
  })  : _dnsResolver = dnsResolver ?? InternetAddress.lookup,
        // ignore: prefer_initializing_formals
        _customSecurityContext = customSecurityContext,
        // ignore: prefer_initializing_formals
        _seam = seam;

  /// Performs a secure request with DNS pinning, manual redirect handling,
  /// IP verification on each hop, and body size limits.
  /// Default maxBodySize is 1 MB so it can never buffer large bodies.
  Future<SafeHttpResponse> request(
    Uri initialUri, {
    String method = 'GET',
    Map<String, String>? headers,
    List<int>? body,
    int? maxBodySize = 1024 * 1024,
  }) async {
    final streamResponse = await openStream(
      initialUri,
      method: method,
      headers: headers,
      body: body,
      maxBodySize: maxBodySize,
    );

    final bodyBuilder = BytesBuilder(copy: false);
    try {
      await for (final chunk in streamResponse.body) {
        bodyBuilder.add(chunk);
      }
    } finally {
      streamResponse.close();
    }

    return SafeHttpResponse(
      statusCode: streamResponse.statusCode,
      reasonPhrase: streamResponse.reasonPhrase,
      headers: streamResponse.headers,
      bodyBytes: bodyBuilder.takeBytes(),
      finalUri: streamResponse.finalUri,
    );
  }

  /// Opens a streaming connection with DNS pinning, manual redirect handling,
  /// IP verification on each hop, arriving byte limit enforcement, and an idle
  /// chunk timeout of 20 seconds.
  Future<SafeStreamResponse> openStream(
    Uri initialUri, {
    String method = 'GET',
    Map<String, String>? headers,
    List<int>? body,
    int? maxBodySize,
  }) async {
    Uri currentUri = initialUri;
    int redirectCount = 0;

    // Track host of original request to restrict credential/cookie leakage across hosts
    final initialHost = initialUri.host.toLowerCase();
    Map<String, String> activeHeaders = Map<String, String>.from(headers ?? {});

    while (true) {
      // 1. Validate URL with UrlPolicy (or allow non-standard port in seam)
      final policyResult = UrlPolicy.validate(currentUri.toString());
      if (!policyResult.isValid && !_seam.shouldAllowNonStandardPort(policyResult.errorCode)) {
        DiagnosticsService.instance.logEvent('safe_http_blocked', {
          'code': policyResult.errorCode?.name ?? 'url_policy_violation',
          'host': currentUri.host,
        });
        throw SafeHttpClientException(
          policyResult.message ?? 'URL policy validation failed.',
          code: policyResult.errorCode?.name,
          host: currentUri.host,
        );
      }
      final normalizedUri = policyResult.normalizedUri ?? currentUri;

      // Remove sensitive headers if redirected to a different host
      if (normalizedUri.host.toLowerCase() != initialHost) {
        activeHeaders.removeWhere((k, _) {
          final lk = k.toLowerCase();
          return lk == 'authorization' || lk == 'cookie';
        });
      }

      // 2. Resolve DNS and verify every returned address
      List<InternetAddress> addresses;
      try {
        addresses = await _dnsResolver(normalizedUri.host);
      } catch (e) {
        DiagnosticsService.instance.logEvent('safe_http_error', {
          'code': 'dns_resolution_failed',
          'host': normalizedUri.host,
        });
        throw SafeHttpClientException(
          'Failed to resolve DNS for ${normalizedUri.host}: $e',
          code: 'dns_resolution_failed',
          host: normalizedUri.host,
        );
      }

      if (addresses.isEmpty) {
        DiagnosticsService.instance.logEvent('safe_http_error', {
          'code': 'dns_no_addresses',
          'host': normalizedUri.host,
        });
        throw SafeHttpClientException(
          'DNS resolved no IP addresses for ${normalizedUri.host}',
          code: 'dns_no_addresses',
          host: normalizedUri.host,
        );
      }

      for (final addr in addresses) {
        if (_seam.isIpBlocked(addr)) {
          DiagnosticsService.instance.logEvent('safe_http_blocked', {
            'code': 'blocked_ip',
            'host': normalizedUri.host,
          });
          throw SafeHttpClientException(
            'Address for host is blocked or private.',
            code: 'blocked_ip',
            host: normalizedUri.host,
          );
        }
      }

      // 3. Setup HttpClient with custom connectionFactory pinned to the validated IP
      final client = HttpClient(context: _customSecurityContext);
      client.findProxy = (uri) => 'DIRECT'; // Prevent system proxy bypass
      client.badCertificateCallback = null; // Strict certificate validation
      client.connectionTimeout = connectionTimeout * addresses.length;
      client.autoUncompress = false; // autoUncompress is off

      client.connectionFactory = (uri, proxyHost, proxyPort) {
        final completer = Completer<Socket>();

        Future<void> tryConnect(int index) async {
          if (index >= addresses.length) {
            if (!completer.isCompleted) {
              completer.completeError(
                SocketException('Failed to connect to any resolved address for ${uri.host}'),
              );
            }
            return;
          }

          final targetAddr = addresses[index];
          try {
            final rawSocket = await Socket.connect(targetAddr, uri.port, timeout: connectionTimeout);
            try {
              final secureSocket = await SecureSocket.secure(
                rawSocket,
                host: uri.host,
                context: _customSecurityContext ?? SecurityContext.defaultContext,
                onBadCertificate: null,
              );
              if (!completer.isCompleted) {
                completer.complete(secureSocket);
              } else {
                secureSocket.destroy();
              }
            } catch (err, st) {
              rawSocket.destroy();
              if (index + 1 < addresses.length) {
                await tryConnect(index + 1);
              } else if (!completer.isCompleted) {
                completer.completeError(err, st);
              }
            }
          } catch (err, st) {
            if (index + 1 < addresses.length) {
              await tryConnect(index + 1);
            } else if (!completer.isCompleted) {
              completer.completeError(err, st);
            }
          }
        }

        tryConnect(0);

        return Future.value(ConnectionTask.fromSocket<Socket>(
          completer.future,
          () {
            if (!completer.isCompleted) {
              completer.completeError(const SocketException('Connection cancelled'));
            }
          },
        ));
      };

      HttpClientRequest httpRequest;
      HttpClientResponse httpResponse;
      try {
        final totalConnectTimeout = connectionTimeout * addresses.length;
        httpRequest = await client.openUrl(method, normalizedUri).timeout(totalConnectTimeout);
        httpRequest.followRedirects = false; // Manual redirect handling

        // Apply headers
        activeHeaders.forEach((k, v) {
          httpRequest.headers.set(k, v);
        });

        if (body != null && body.isNotEmpty) {
          httpRequest.add(body);
        }

        httpResponse = await httpRequest.close().timeout(readTimeout);
      } catch (e) {
        client.close(force: true);
        DiagnosticsService.instance.logEvent('safe_http_error', {
          'code': 'connection_error',
          'host': normalizedUri.host,
        });
        throw SafeHttpClientException(
          'Connection failed: $e',
          code: 'connection_error',
          host: normalizedUri.host,
        );
      }

      // Check redirect codes (301, 302, 303, 307, 308)
      final status = httpResponse.statusCode;
      if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
        // Drain redirect body or close connection cleanly
        try {
          await httpResponse.drain().timeout(const Duration(seconds: 2));
        } catch (_) {}
        client.close(force: true);

        redirectCount++;
        if (redirectCount > maxRedirects) {
          DiagnosticsService.instance.logEvent('safe_http_blocked', {
            'code': 'too_many_redirects',
            'host': normalizedUri.host,
          });
          throw SafeHttpClientException(
            'Maximum redirect limit ($maxRedirects) exceeded.',
            code: 'too_many_redirects',
            host: normalizedUri.host,
          );
        }

        final location = httpResponse.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          DiagnosticsService.instance.logEvent('safe_http_error', {
            'code': 'missing_redirect_location',
            'host': normalizedUri.host,
          });
          throw SafeHttpClientException(
            'Redirect response missing Location header.',
            code: 'missing_redirect_location',
            host: normalizedUri.host,
          );
        }

        Uri nextUri;
        try {
          nextUri = normalizedUri.resolve(location);
        } catch (e) {
          DiagnosticsService.instance.logEvent('safe_http_error', {
            'code': 'invalid_redirect_uri',
            'host': normalizedUri.host,
          });
          throw SafeHttpClientException(
            'Failed to resolve redirect Location: $e',
            code: 'invalid_redirect_uri',
            host: normalizedUri.host,
          );
        }

        if (status == 303 || ((status == 301 || status == 302) && method.toUpperCase() == 'POST')) {
          method = 'GET';
          body = null;
        }

        currentUri = nextUri;
        continue;
      }

      // Check range fallback: if request requested range (bytes=0-0) and server replied 200 with full body, abort after headers
      final requestedRange = activeHeaders[HttpHeaders.rangeHeader];
      if (requestedRange != null && requestedRange.trim() == 'bytes=0-0' && status == 200) {
        client.close(force: true);
        return SafeStreamResponse(
          statusCode: 200,
          reasonPhrase: httpResponse.reasonPhrase,
          headers: httpResponse.headers,
          finalUri: normalizedUri,
          body: const Stream.empty(),
          close: () {},
        );
      }

      // Build streaming response with chunk idle timeout (20s) and maxBodySize enforcement
      final bodyController = StreamController<List<int>>();
      int receivedBytes = 0;
      bool isClosed = false;
      bool sizeLimitExceeded = false;
      StreamSubscription<List<int>>? subscription;
      Timer? idleTimer;

      void cancelIdleTimer() {
        idleTimer?.cancel();
        idleTimer = null;
      }

      void resetIdleTimer() {
        cancelIdleTimer();
        if (!isClosed) {
          idleTimer = Timer(const Duration(seconds: 20), () {
            if (!isClosed) {
              isClosed = true;
              client.close(force: true);
              subscription?.cancel();
              final err = SafeHttpClientException(
                'Stream stalled: no data received for 20 seconds.',
                code: 'connection_error',
                host: normalizedUri.host,
              );
              if (!bodyController.isClosed) {
                bodyController.addError(err);
                bodyController.close();
              }
            }
          });
        }
      }

      void doClose({bool force = false}) {
        if (!isClosed) {
          isClosed = true;
          cancelIdleTimer();
          subscription?.cancel();
          client.close(force: force);
        }
      }

      bodyController.onListen = () {
        resetIdleTimer();
        subscription = httpResponse.listen(
          (chunk) {
            if (sizeLimitExceeded || isClosed) return;
            resetIdleTimer();
            receivedBytes += chunk.length;
            if (maxBodySize != null && receivedBytes > maxBodySize) {
              sizeLimitExceeded = true;
              isClosed = true;
              cancelIdleTimer();
              final err = SafeHttpClientException(
                'Response body exceeded maximum allowed limit of $maxBodySize bytes.',
                code: 'max_body_size_exceeded',
                host: normalizedUri.host,
              );
              if (!bodyController.isClosed) {
                bodyController.addError(err);
                bodyController.close();
              }
              final sub = subscription;
              subscription = null;
              sub?.cancel();
              client.close(force: true);
              return;
            }
            if (!bodyController.isClosed) {
              bodyController.add(chunk);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (sizeLimitExceeded) return;
            if (isClosed) return;
            isClosed = true;
            cancelIdleTimer();
            if (!bodyController.isClosed) {
              final err = (error is HttpException || error is SocketException)
                  ? SafeHttpClientException(
                      'Connection error while receiving stream data: $error',
                      code: 'connection_error',
                      host: normalizedUri.host,
                    )
                  : error;
              bodyController.addError(err, stackTrace);
              bodyController.close();
            }
            subscription?.cancel();
            client.close(force: true);
          },
          onDone: () {
            if (isClosed) return;
            doClose(force: false);
            if (!bodyController.isClosed) {
              bodyController.close();
            }
          },
          cancelOnError: true,
        );
      };

      bodyController.onPause = () {
        subscription?.pause();
      };

      bodyController.onResume = () {
        subscription?.resume();
      };

      bodyController.onCancel = () {
        if (!sizeLimitExceeded) {
          doClose(force: true);
        }
      };

      return SafeStreamResponse(
        statusCode: httpResponse.statusCode,
        reasonPhrase: httpResponse.reasonPhrase,
        headers: httpResponse.headers,
        finalUri: normalizedUri,
        body: bodyController.stream,
        close: () => doClose(force: true),
      );
    }
  }
}
