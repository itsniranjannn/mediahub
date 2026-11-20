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

/// One connection attempt of [SafeHttpClient.raceConnect]: its result, and a
/// way to stop it while it is still connecting.
class ConnectAttempt<T> {
  ConnectAttempt(this.result, this.cancel);

  final Future<T> result;
  final void Function() cancel;
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

  /// Delay before the next address is tried while the current one has not
  /// answered yet (RFC 8305 recommends 250 ms).
  static const Duration connectionAttemptDelay = Duration(milliseconds: 250);

  /// [addresses] with the two families taking turns, starting with the
  /// resolver's first family: `[v6a, v6b, v4a]` becomes `[v6a, v4a, v6b]`.
  static List<InternetAddress> interleaveByFamily(List<InternetAddress> addresses) {
    if (addresses.length < 2) return List.of(addresses);
    final firstType = addresses.first.type;
    final first = addresses.where((a) => a.type == firstType).toList();
    final other = addresses.where((a) => a.type != firstType).toList();
    final out = <InternetAddress>[];
    for (var i = 0; i < first.length || i < other.length; i++) {
      if (i < first.length) out.add(first[i]);
      if (i < other.length) out.add(other[i]);
    }
    return out;
  }

  /// Races connection attempts to [addresses] the way browsers do ("Happy
  /// Eyeballs", RFC 8305): the families take turns ([interleaveByFamily]),
  /// the next address starts [attemptDelay] after the previous one (at once
  /// when that one failed), and the first attempt that connects wins. The
  /// moment there is a winner, or [cancelled] completes, every attempt still
  /// running is cancelled, and one that connects anyway goes to [discard].
  /// Fails with the last error once every address failed, or with
  /// "Connection cancelled".
  ///
  /// So a family that is advertised but broken (IPv6 on some Wi-Fi, or IPv4
  /// to some servers) costs a quarter of a second, not a full connection
  /// timeout per address. It only connects to the addresses it is given
  /// (every one was checked against the blocklist before) and resolves no
  /// name itself.
  static Future<T> raceConnect<T>(
    List<InternetAddress> addresses,
    ConnectAttempt<T> Function(InternetAddress address) start, {
    required void Function(T connection) discard,
    Duration attemptDelay = connectionAttemptDelay,
    Future<void>? cancelled,
  }) {
    final ordered = interleaveByFamily(addresses);
    if (ordered.isEmpty) {
      return Future<T>.error(const SocketException('No address to connect to'));
    }
    final completer = Completer<T>();
    final inFlight = <ConnectAttempt<T>>[];
    var started = 0;
    var failed = 0;
    var stopped = false;
    Timer? next;

    void stopAll() {
      stopped = true;
      next?.cancel();
      next = null;
      final running = List.of(inFlight);
      inFlight.clear();
      for (final attempt in running) {
        attempt.cancel();
      }
    }

    void startNext() {
      next?.cancel();
      next = null;
      if (stopped || started >= ordered.length) return;
      final attempt = start(ordered[started++]);
      inFlight.add(attempt);
      attempt.result.then((connection) {
        inFlight.remove(attempt);
        if (stopped || completer.isCompleted) {
          discard(connection);
          return;
        }
        stopAll();
        completer.complete(connection);
      }, onError: (Object error, StackTrace stack) {
        inFlight.remove(attempt);
        failed++;
        if (stopped || completer.isCompleted) return;
        if (failed >= ordered.length) {
          stopAll();
          completer.completeError(error, stack);
          return;
        }
        // A failed attempt hands over at once.
        if (started < ordered.length) startNext();
      });
      if (started < ordered.length) next = Timer(attemptDelay, startNext);
    }

    cancelled?.then((_) {
      if (stopped || completer.isCompleted) return;
      stopAll();
      completer.completeError(const SocketException('Connection cancelled'));
    });
    startNext();
    return completer.future;
  }

  /// The error a cancelled [startTcp] attempt fails with (not a failure of
  /// the address itself).
  static const SocketException tcpCancelled = SocketException('Connection cancelled');

  /// One TCP connection attempt to [address] that can be cancelled while it
  /// connects. Fails after [timeout]; a socket that connects after a cancel
  /// or the timeout is closed at once.
  static ConnectAttempt<(InternetAddress, Socket)> startTcp(InternetAddress address, int port, Duration timeout) {
    final out = Completer<(InternetAddress, Socket)>();
    ConnectionTask<Socket>? task;
    var over = false;
    Timer? timer;

    void giveUp(Object error) {
      if (out.isCompleted) return;
      over = true;
      timer?.cancel();
      task?.cancel();
      out.completeError(error);
    }

    timer = Timer(timeout, () => giveUp(SocketException('Connection timed out', address: address, port: port)));
    Socket.startConnect(address, port).then((t) {
      task = t;
      if (over) t.cancel();
      t.socket.then((socket) {
        timer?.cancel();
        if (over || out.isCompleted) {
          socket.destroy();
          return;
        }
        out.complete((address, socket));
      }, onError: (Object e, StackTrace st) {
        timer?.cancel();
        if (!out.isCompleted) out.completeError(e, st);
      });
    }, onError: (Object e, StackTrace st) {
      timer?.cancel();
      if (!out.isCompleted) out.completeError(e, st);
    });
    return ConnectAttempt(out.future, () => giveUp(tcpCancelled));
  }

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
    // Ask for the file exactly as it is. Dart's HttpClient always offers
    // gzip, and with autoUncompress off a server that takes the offer (a
    // download script with compression on) hands over a compressed copy,
    // which is then refused as "not media" or fails the size check.
    if (!activeHeaders.keys.any((k) => k.toLowerCase() == 'accept-encoding')) {
      activeHeaders[HttpHeaders.acceptEncodingHeader] = 'identity';
    }

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
        // TCP is raced across the checked addresses (raceConnect); TLS then
        // runs once, on the winner. If TLS fails there, the remaining
        // addresses are raced again, as the old one-by-one loop did. So there
        // is never more than one TLS handshake in flight per connection.
        final cancel = Completer<void>();
        final result = Completer<Socket>();

        Future<void> run() async {
          var remaining = List.of(addresses);
          Object lastError = SocketException('Failed to connect to any resolved address for ${uri.host}');
          StackTrace? lastStack;
          // A TLS error (a certificate for another name, say) says more than
          // the TCP error of an address tried after it, so it is the one kept.
          Object? tlsError;
          StackTrace? tlsStack;
          // Addresses whose TCP connect failed are not dialled again in a
          // later round (a cancelled loser is not a failure).
          final tcpFailed = <InternetAddress>[];
          ConnectAttempt<(InternetAddress, Socket)> dial(InternetAddress address) {
            final attempt = startTcp(address, uri.port, connectionTimeout);
            attempt.result.then((_) {}, onError: (Object e) {
              if (!identical(e, tcpCancelled)) tcpFailed.add(address);
            });
            return attempt;
          }

          while (remaining.isNotEmpty && !result.isCompleted) {
            final (InternetAddress, Socket) won;
            try {
              won = await raceConnect<(InternetAddress, Socket)>(
                remaining,
                dial,
                discard: (c) => c.$2.destroy(),
                cancelled: cancel.future,
              );
            } catch (e, st) {
              lastError = e;
              lastStack = st;
              break;
            }
            if (result.isCompleted) {
              won.$2.destroy();
              return;
            }
            remaining = remaining
                .where((a) => !identical(a, won.$1) && !tcpFailed.any((f) => identical(f, a)))
                .toList();
            try {
              final secure = await SecureSocket.secure(
                won.$2,
                host: uri.host,
                context: _customSecurityContext ?? SecurityContext.defaultContext,
                onBadCertificate: null,
              );
              if (result.isCompleted) {
                secure.destroy();
              } else {
                result.complete(secure);
              }
              return;
            } catch (e, st) {
              won.$2.destroy();
              tlsError = e;
              tlsStack = st;
            }
          }
          if (!result.isCompleted) result.completeError(tlsError ?? lastError, tlsError != null ? tlsStack : lastStack);
        }

        run();

        // Cancelling (HttpClient's own timeout) fails the connection at once,
        // as before, and stops every TCP attempt still running.
        return Future.value(ConnectionTask.fromSocket<Socket>(
          result.future,
          () {
            if (!cancel.isCompleted) cancel.complete();
            if (!result.isCompleted) {
              result.completeError(const SocketException('Connection cancelled'));
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
        cancelIdleTimer();
        subscription?.pause();
      };

      bodyController.onResume = () {
        if (!isClosed) {
          resetIdleTimer();
        }
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
