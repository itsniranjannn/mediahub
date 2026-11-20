import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/safe_http_client.dart';

import 'test_safe_http_client_seam.dart';

/// SafeHttpClient connects to the checked addresses the way browsers do
/// (RFC 8305): one broken address family must cost a quarter of a second,
/// not a full connection timeout per address. Found on the emulator, where
/// IPv4 to Cloudflare hosts hung while IPv6 worked: direct links there timed
/// out at "Inspect" although Chrome loaded them.
void main() {
  final v6a = InternetAddress('2606:4700:3033::ac43:b2f4');
  final v6b = InternetAddress('2606:4700:3033::6815:1a2b');
  final v4a = InternetAddress('172.67.178.244');
  final v4b = InternetAddress('104.21.26.43');

  group('interleaveByFamily', () {
    test('the families take turns, starting with the first one returned', () {
      expect(SafeHttpClient.interleaveByFamily([v6a, v6b, v4a, v4b]), [v6a, v4a, v6b, v4b]);
      expect(SafeHttpClient.interleaveByFamily([v4a, v4b, v6a]), [v4a, v6a, v4b]);
    });

    test('one family or one address stays as it is', () {
      expect(SafeHttpClient.interleaveByFamily([v4a, v4b]), [v4a, v4b]);
      expect(SafeHttpClient.interleaveByFamily([v6a]), [v6a]);
      expect(SafeHttpClient.interleaveByFamily(const []), isEmpty);
    });
  });

  group('raceConnect', () {
    // Fake attempts: each waits for the test to settle it and records a cancel.
    late Map<InternetAddress, Completer<String>> pending;
    late List<InternetAddress> attempts;
    late List<InternetAddress> cancelledAttempts;
    late List<String> discarded;

    ConnectAttempt<String> start(InternetAddress a) {
      attempts.add(a);
      final c = Completer<String>();
      pending[a] = c;
      return ConnectAttempt(c.future, () {
        cancelledAttempts.add(a);
        if (!c.isCompleted) c.completeError(const SocketException('Connection cancelled'));
      });
    }

    setUp(() {
      pending = {};
      attempts = [];
      cancelledAttempts = [];
      discarded = [];
    });

    test('a family that never answers costs one delay; the winner stops the rest', () {
      fakeAsync((async) {
        String? won;
        SafeHttpClient.raceConnect<String>([v4a, v4b, v6a, v6b], start, discard: discarded.add).then((s) => won = s);
        async.flushMicrotasks();
        expect(attempts, [v4a], reason: 'one attempt at first');

        async.elapse(const Duration(milliseconds: 249));
        expect(attempts, [v4a]);
        async.elapse(const Duration(milliseconds: 1));
        expect(attempts, [v4a, v6a], reason: 'the other family 250 ms later');

        pending[v6a]!.complete('v6a');
        async.flushMicrotasks();
        expect(won, 'v6a');
        expect(cancelledAttempts, [v4a], reason: 'the hanging attempt is stopped, not left open');

        async.elapse(const Duration(seconds: 5));
        expect(attempts, [v4a, v6a], reason: 'nothing else starts once one has won');
      });
    });

    test('an attempt that connects after the winner is closed, not used', () {
      fakeAsync((async) {
        String? won;
        // A connector whose cancel cannot stop it any more (it already connected).
        ConnectAttempt<String> stubborn(InternetAddress a) {
          attempts.add(a);
          final c = Completer<String>();
          pending[a] = c;
          return ConnectAttempt(c.future, () => cancelledAttempts.add(a));
        }

        SafeHttpClient.raceConnect<String>([v4a, v6a], stubborn, discard: discarded.add).then((s) => won = s);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 250));
        pending[v6a]!.complete('v6a');
        async.flushMicrotasks();
        pending[v4a]!.complete('v4a');
        async.flushMicrotasks();
        expect(won, 'v6a');
        expect(discarded, ['v4a']);
      });
    });

    test('a failed attempt hands over at once, without waiting for the delay', () {
      fakeAsync((async) {
        String? won;
        SafeHttpClient.raceConnect<String>([v6a, v4a], start, discard: discarded.add).then((s) => won = s);
        async.flushMicrotasks();
        pending[v6a]!.completeError(const SocketException('Network is unreachable'));
        async.flushMicrotasks();
        expect(attempts, [v6a, v4a]);
        pending[v4a]!.complete('v4a');
        async.flushMicrotasks();
        expect(won, 'v4a');
      });
    });

    test('a fast first address wins alone', () {
      fakeAsync((async) {
        String? won;
        SafeHttpClient.raceConnect<String>([v4a, v6a, v4b], start, discard: discarded.add).then((s) => won = s);
        async.flushMicrotasks();
        pending[v4a]!.complete('v4a');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(won, 'v4a');
        expect(attempts, [v4a]);
        expect(cancelledAttempts, isEmpty);
      });
    });

    test('fails with the last error only after every address failed', () {
      fakeAsync((async) {
        Object? error;
        SafeHttpClient.raceConnect<String>([v4a, v6a], start, discard: discarded.add).then((_) {}, onError: (Object e) {
          error = e;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 250));
        expect(attempts, [v4a, v6a]);
        pending[v6a]!.completeError(const SocketException('second'));
        async.flushMicrotasks();
        expect(error, isNull, reason: 'the first attempt is still running');
        pending[v4a]!.completeError(const SocketException('first'));
        async.flushMicrotasks();
        expect(error, isA<SocketException>().having((e) => e.message, 'message', 'first'));
      });
    });

    test('no address is an error, not a hang', () async {
      await expectLater(
        SafeHttpClient.raceConnect<String>(const [], start, discard: discarded.add),
        throwsA(isA<SocketException>()),
      );
    });

    test('a cancel stops every running attempt, starts no new one and fails at once', () {
      fakeAsync((async) {
        final cancel = Completer<void>();
        Object? error;
        SafeHttpClient.raceConnect<String>([v4a, v6a, v4b], start, discard: discarded.add, cancelled: cancel.future)
            .then((_) {}, onError: (Object e) {
          error = e;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 250));
        expect(attempts, [v4a, v6a]);
        cancel.complete();
        async.flushMicrotasks();
        expect(error, isA<SocketException>().having((e) => e.message, 'message', 'Connection cancelled'));
        expect(cancelledAttempts, unorderedEquals([v4a, v6a]));
        async.elapse(const Duration(seconds: 2));
        expect(attempts, [v4a, v6a], reason: 'no new attempt after a cancel');
      });
    });

    test('only the addresses it was given are tried, each once', () {
      fakeAsync((async) {
        SafeHttpClient.raceConnect<String>([v6a, v6b, v4a, v4b], start, discard: discarded.add)
            .then((_) {}, onError: (_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(attempts, [v6a, v4a, v6b, v4b]);
        for (final c in pending.values) {
          if (!c.isCompleted) c.completeError(const SocketException('x'));
        }
        async.flushMicrotasks();
        expect(attempts.length, 4);
      });
    });
  });

  group('startTcp (real sockets)', () {
    test('connects to a listening port', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((s) => s.destroy());
      final attempt = SafeHttpClient.startTcp(InternetAddress.loopbackIPv4, server.port, const Duration(seconds: 5));
      final (address, socket) = await attempt.result;
      expect(address, InternetAddress.loopbackIPv4);
      socket.destroy();
    });

    test('a refused port fails', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final attempt = SafeHttpClient.startTcp(InternetAddress.loopbackIPv4, port, const Duration(seconds: 10));
      await expectLater(attempt.result, throwsA(isA<SocketException>()));
    });

    test('a cancel fails the attempt at once', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final attempt = SafeHttpClient.startTcp(InternetAddress.loopbackIPv4, server.port, const Duration(seconds: 5));
      attempt.cancel();
      await expectLater(attempt.result, throwsA(isA<SocketException>()));
    });
  });

  group('SafeHttpClient over HTTPS with several addresses', () {
    final certFile = File('test/certs/localhost.crt');
    final keyFile = File('test/certs/localhost.key');

    Future<HttpServer> secureServer() async {
      final serverContext = SecurityContext()
        ..useCertificateChain(certFile.path)
        ..usePrivateKey(keyFile.path);
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..write('secure-data')
          ..close();
      });
      return server;
    }

    SafeHttpClient clientFor(List<InternetAddress> addresses) {
      final clientContext = SecurityContext()..setTrustedCertificates(certFile.path);
      return SafeHttpClient(
        customSecurityContext: clientContext,
        seam: const TestSafeHttpClientSeam(),
        dnsResolver: (host) async => addresses,
      );
    }

    test('an address that refuses does not stop the request', () async {
      final server = await secureServer();
      addTearDown(() => server.close(force: true));
      // Nothing listens on [::1] (the server is IPv4 only).
      final client = clientFor([InternetAddress.loopbackIPv6, InternetAddress.loopbackIPv4]);
      final res = await client.request(Uri.parse('https://localhost:${server.port}/x'));
      expect(res.statusCode, 200);
      expect(res.bodyText, 'secure-data');
    });

    test('a TLS failure at the first address moves on to the next one', () async {
      final server = await secureServer();
      addTearDown(() => server.close(force: true));
      // A plain TCP server on 127.0.0.2, same port: it accepts and hangs up,
      // so the TLS handshake there fails.
      ServerSocket plain;
      try {
        plain = await ServerSocket.bind(InternetAddress('127.0.0.2'), server.port);
      } on SocketException {
        markTestSkipped('127.0.0.2 cannot be bound on this machine');
        return;
      }
      addTearDown(plain.close);
      var plainAccepted = 0;
      plain.listen((s) {
        plainAccepted++;
        s.destroy();
      });
      final client = clientFor([InternetAddress('127.0.0.2'), InternetAddress.loopbackIPv4]);
      final res = await client.request(Uri.parse('https://localhost:${server.port}/x'));
      expect(res.statusCode, 200);
      expect(plainAccepted, 1, reason: 'the failing address was tried once, first');
    });

    test('a certificate for another name still fails everywhere', () async {
      final server = await secureServer();
      addTearDown(() => server.close(force: true));
      final client = clientFor([InternetAddress.loopbackIPv6, InternetAddress.loopbackIPv4]);
      await expectLater(
        client.request(Uri.parse('https://wronghost.local:${server.port}/x')),
        throwsA(isA<SafeHttpClientException>()
            .having((e) => e.code, 'code', 'connection_error')
            // The certificate error is the one reported, not the refusal of
            // [::1] (which is not dialled a second time).
            .having((e) => e.message, 'message', matches(RegExp('Handshake|CERTIFICATE', caseSensitive: false)))),
      );
    });
  });
}
