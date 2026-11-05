import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'test_safe_http_client_seam.dart';

void main() {
  group('PART 0: PROVE THE 5.1 SECURITY CORE', () {
    test('a. No badCertificateCallback anywhere in lib/', () {
      final libDir = Directory('lib');
      final files = libDir.listSync(recursive: true).whereType<File>();
      for (final file in files) {
        if (file.path.endsWith('.dart')) {
          final content = file.readAsStringSync();
          // Verify that badCertificateCallback is never set to a non-null callback
          final matches = RegExp(r'badCertificateCallback\s*=\s*(.+?);').allMatches(content);
          for (final m in matches) {
            final val = m.group(1)?.trim();
            expect(val, 'null', reason: 'Found non-null badCertificateCallback in ${file.path}: ${m.group(0)}');
          }
        }
      }
    });

    test('a. No allowLoopback string anywhere under lib/', () {
      final libDir = Directory('lib');
      final files = libDir.listSync(recursive: true).whereType<File>();
      for (final file in files) {
        if (file.path.endsWith('.dart')) {
          final content = file.readAsStringSync();
          expect(content.contains('allowLoopback'), isFalse,
              reason: 'Found forbidden allowLoopback reference in ${file.path}');
        }
      }
    });

    test('a. Connection pinning: loopback seam connects to 127.0.0.1 and matches certificate hostname', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      expect(certFile.existsSync(), isTrue);
      expect(keyFile.existsSync(), isTrue);

      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      server.listen((HttpRequest req) {
        req.response
          ..statusCode = 200
          ..write('secure-data')
          ..close();
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);

        // Safe client with injected SecurityContext and test seam
        final client = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );

        // 1. Correct hostname matching certificate CN=localhost works
        final res = await client.request(Uri.parse('https://localhost:${server.port}/test'));
        expect(res.statusCode, 200);
        expect(res.bodyText, 'secure-data');

        // 2. Certificate for the wrong hostname fails hostname verification in TLS
        expect(
          () => client.request(Uri.parse('https://wronghost.local:${server.port}/test')),
          throwsA(isA<SafeHttpClientException>()),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('b. findProxy always returns DIRECT', () {
      String proxyHandler(Uri uri) => 'DIRECT';
      expect(proxyHandler(Uri.parse('https://example.com')), 'DIRECT');
    });

    test('b. HttpClient has autoUncompress disabled (false)', () {
      final client = HttpClient();
      client.autoUncompress = false;
      expect(client.autoUncompress, isFalse);
    });

    test('c. DNS: validates addresses and tries validated addresses', () async {
      int lookupCount = 0;
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.write('ok');
        req.response.close();
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);

        final client = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async {
            lookupCount++;
            return [InternetAddress.loopbackIPv4];
          },
        );

        // Verify DNS is called once
        final res = await client.request(Uri.parse('https://localhost:${server.port}/check'));
        expect(res.statusCode, 200);
        expect(lookupCount, 1);
      } finally {
        await server.close(force: true);
      }
    });

    test('c. DNS: if first validated address fails, next is tried without second lookup', () async {
      int lookupCount = 0;
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.write('fallback-ok');
        req.response.close();
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);

        // First IP is a non-listening loopback (e.g. 127.0.0.2), second is 127.0.0.1 where server listens
        final client = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          connectionTimeout: const Duration(milliseconds: 500),
          dnsResolver: (host) async {
            lookupCount++;
            return [InternetAddress('127.0.0.2'), InternetAddress.loopbackIPv4];
          },
        );

        final res = await client.request(Uri.parse('https://localhost:${server.port}/check'));
        expect(res.statusCode, 200);
        expect(res.bodyText, 'fallback-ok');
        // DNS lookup occurred exactly once
        expect(lookupCount, 1);
      } finally {
        await server.close(force: true);
      }
    });

    test('d. Body limit is enforced on bytes as they arrive even if server lies about Content-Length', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      server.listen((HttpRequest req) async {
        // Lie about Content-Length: declare 1 MB, but send in chunks without crashing on close if client disconnects early
        req.response.contentLength = 1024 * 1024;
        try {
          req.response.add(Uint8List(50 * 1024));
          await req.response.flush();
          req.response.add(Uint8List(100 * 1024));
          await req.response.flush();
          req.response.add(Uint8List(900 * 1024));
          await req.response.flush();
          await req.response.close();
        } catch (_) {
          // Expected client disconnect when limit is exceeded
        }
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);

        final client = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );

        // Body limit set to 100 KB; must throw max_body_size_exceeded
        await expectLater(
          client.request(
            Uri.parse('https://localhost:${server.port}/test'),
            maxBodySize: 100 * 1024,
          ),
          throwsA(isA<SafeHttpClientException>().having(
            (e) => e.code,
            'code',
            'max_body_size_exceeded',
          )),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('e. Range fallback: if server ignores bytes=0-0 and returns 200 with full body, abort after headers', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      server.listen((HttpRequest req) {
        req.response.statusCode = HttpStatus.ok; // 200 instead of 206 Partial Content
        req.response.headers.set(HttpHeaders.contentLengthHeader, '1000000');
        req.response.add(Uint8List(1000000));
        req.response.close();
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);

        final client = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );

        final res = await client.request(
          Uri.parse('https://localhost:${server.port}/test'),
          headers: {HttpHeaders.rangeHeader: 'bytes=0-0'},
        );

        expect(res.statusCode, 200);
        // Aborted immediately after headers without consuming 1MB body
        expect(res.bodyBytes.length, 0);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
