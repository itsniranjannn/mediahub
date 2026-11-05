import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../logging/diagnostics_service.dart';
import 'ip_guard.dart';
import 'url_policy.dart';

typedef DnsResolver = Future<List<InternetAddress>> Function(String host);

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

  SafeHttpClient({
    DnsResolver? dnsResolver,
    this.connectionTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 20),
    this.maxRedirects = 5,
    this.maxHeaderSize = 64 * 1024, // 64 KB
  }) : _dnsResolver = dnsResolver ?? InternetAddress.lookup;

  /// Performs a secure request with DNS pinning, manual redirect handling,
  /// IP verification on each hop, and body size limits.
  Future<SafeHttpResponse> request(
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
      // 1. Validate URL with UrlPolicy
      final policyResult = UrlPolicy.validate(currentUri.toString());
      if (!policyResult.isValid) {
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
      final normalizedUri = policyResult.normalizedUri!;

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
        if (IpGuard.isBlocked(addr)) {
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

      final targetIp = addresses.first;

      // 3. Setup HttpClient with custom connectionFactory pinned to the validated IP
      final client = HttpClient();
      // Ensure badCertificateCallback is NOT set (strict TLS validation)
      client.badCertificateCallback = null;
      client.connectionTimeout = connectionTimeout;
      client.autoUncompress = true;

      client.connectionFactory = (uri, proxyHost, proxyPort) {
        final completer = Completer<Socket>();
        Socket.connect(targetIp, uri.port, timeout: connectionTimeout).then((rawSocket) {
          SecureSocket.secure(
            rawSocket,
            host: uri.host, // SNI and certificate hostname matching with the original host
            context: SecurityContext.defaultContext,
            onBadCertificate: null, // strict certificate validation
          ).then((secureSocket) {
            completer.complete(secureSocket);
          }).catchError((err, st) {
            rawSocket.destroy();
            completer.completeError(err, st);
          });
        }).catchError((err, st) {
          completer.completeError(err, st);
        });

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
        httpRequest = await client.openUrl(method, normalizedUri).timeout(connectionTimeout);
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

        // Switch method to GET on 303 or on 301/302 for POST
        if (status == 303 || ((status == 301 || status == 302) && method.toUpperCase() == 'POST')) {
          method = 'GET';
          body = null;
        }

        currentUri = nextUri;
        continue;
      }

      // Read response body with size limit
      final bodyBuilder = BytesBuilder(copy: false);
      try {
        await for (final chunk in httpResponse.timeout(readTimeout)) {
          bodyBuilder.add(chunk);
          if (maxBodySize != null && bodyBuilder.length > maxBodySize) {
            client.close(force: true);
            DiagnosticsService.instance.logEvent('safe_http_blocked', {
              'code': 'max_body_size_exceeded',
              'host': normalizedUri.host,
            });
            throw SafeHttpClientException(
              'Response body exceeded maximum allowed limit of $maxBodySize bytes.',
              code: 'max_body_size_exceeded',
              host: normalizedUri.host,
            );
          }
        }
      } finally {
        client.close();
      }

      return SafeHttpResponse(
        statusCode: httpResponse.statusCode,
        reasonPhrase: httpResponse.reasonPhrase,
        headers: httpResponse.headers,
        bodyBytes: bodyBuilder.takeBytes(),
        finalUri: normalizedUri,
      );
    }
  }
}
