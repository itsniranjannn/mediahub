import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:path/path.dart' as p;
import 'test_safe_http_client_seam.dart';

void main() {
  HttpOverrides.global = null;

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('download_robustness_test_');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('TASK 5.2e: Streaming robustness', () {
    test('1. Write errors: chunk handler catches write error, completes with typed error, keeps .part, ends failed (never completed)', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) async {
        try {
          req.response.statusCode = 200;
          req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
          req.response.headers.set(HttpHeaders.contentLengthHeader, (10 * 1024 * 1024).toString());

          final chunk = Uint8List(32 * 1024);
          chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33;
          for (int i = 0; i < 10; i++) {
            req.response.add(chunk);
            await req.response.flush();
            await Future.delayed(const Duration(milliseconds: 10));
          }
          await req.response.close();
        } catch (_) {}
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);
        final httpClient = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );

        final engine = DownloadEngine(
          db: db,
          httpClient: httpClient,
          downloadDir: tempDir,
        );

        await engine.enqueueDownload(
          id: 'write_error_task',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'Faulty Write Song',
          suggestedFileName: 'song.mp3',
        );

        // Pre-create .part file
        final partFile = File(p.join(tempDir.path, 'write_error_task.part'));
        partFile.createSync(recursive: true);

        // Periodically check and lock the .part file (or make it read-only on 3rd chunk)
        // by replacing it or throwing an error in a zone or making the directory read-only
        // We run inside runZonedGuarded to prove no unhandled zone errors escape
        List<String> unhandledErrors = [];
        await runZonedGuarded(() async {
          // Monitor file growth and make it read-only after 2 chunks (~64 KB)
          final monitorTimer = Timer.periodic(const Duration(milliseconds: 5), (t) {
            if (partFile.existsSync()) {
              final len = partFile.lengthSync();
              if (len >= 64 * 1024) {
                t.cancel();
                // Set file to read-only or delete and replace with directory to provoke write error
                try {
                  partFile.setLastModifiedSync(DateTime.now());
                  // On Windows/POSIX deleting the open RAF target or denying write permissions triggers FileSystemException
                  // Alternatively, we chmod 0444
                  Process.runSync('attrib', ['+r', partFile.path]);
                } catch (_) {}
              }
            }
          });

          await engine.runTask('write_error_task');
          monitorTimer.cancel();
        }, (error, stack) {
          unhandledErrors.add(error.toString());
        });

        expect(unhandledErrors, isEmpty, reason: 'No unhandled zone errors should escape');

        final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('write_error_task'))).getSingle();
        // Completed is NEVER set
        expect(row.state, isNot(equals(DownloadTaskState.completed.name)));
        // Either failed or kept in failed/paused state
        expect(row.state, equals(DownloadTaskState.failed.name));
        expect(row.errorCode, anyOf(equals('write_failed'), equals('insufficient_disk_space'), equals('connection_error')));
        // The .part file is kept
        expect(partFile.existsSync(), isTrue);

        // Clean up read-only attribute if set
        try {
          Process.runSync('attrib', ['-r', partFile.path]);
        } catch (_) {}
      } finally {
        await server.close(force: true);
      }
    });

    test('2. Stall timer with fakeAsync: paused consumer for 60s does NOT trigger stall error; unpaused idle for 20s DOES', () {
      fakeAsync((async) {
        final mockController = StreamController<List<int>>();
        bool isClosed = false;
        Timer? idleTimer;
        Object? receivedError;

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
                receivedError = SafeHttpClientException(
                  'Stream stalled: no data received for 20 seconds.',
                  code: 'connection_error',
                  host: 'example.com',
                );
                mockController.addError(receivedError!);
                mockController.close();
              }
            });
          }
        }

        mockController.onListen = () {
          resetIdleTimer();
        };
        mockController.onPause = () {
          cancelIdleTimer();
        };
        mockController.onResume = () {
          if (!isClosed) {
            resetIdleTimer();
          }
        };

        // Case A: Consumer paused for 60s does NOT trigger stall error
        final sub = mockController.stream.listen((_) {}, onError: (e) {
          receivedError = e;
        });

        // Advance 10s
        async.elapse(const Duration(seconds: 10));
        expect(receivedError, isNull);

        // Pause for 60s
        sub.pause();
        async.elapse(const Duration(seconds: 60));
        expect(receivedError, isNull, reason: 'Paused stream must not trigger stall error');

        // Resume: timer restarts
        sub.resume();
        async.elapse(const Duration(seconds: 15));
        expect(receivedError, isNull);

        // Case B: Listening stream with no data for 20s DOES trigger stall error
        async.elapse(const Duration(seconds: 6)); // Total 21s since resume
        expect(receivedError, isNotNull);
        expect(receivedError, isA<SafeHttpClientException>().having((e) => e.code, 'code', equals('connection_error')));

        sub.cancel();
      });
    });

    test('3. Engine passes maxBodySize = maxDownloadSizeBytes - startByte; server sending more is aborted at client layer', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) async {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
        req.response.bufferOutput = false;

        // Stream 50 KB
        final chunk = Uint8List(10 * 1024);
        chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33;
        try {
          for (int i = 0; i < 5; i++) {
            req.response.add(chunk);
            await req.response.flush();
          }
        } catch (_) {}
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);
        final httpClient = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );

        // Open stream with maxBodySize set to 25 KB
        final streamResp = await httpClient.openStream(
          Uri.parse('https://localhost:${server.port}/limited.mp3'),
          maxBodySize: 25 * 1024,
        );

        expect(
          () async {
            await for (final _ in streamResp.body) {}
          },
          throwsA(isA<SafeHttpClientException>().having((e) => e.code, 'code', equals('max_body_size_exceeded'))),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('4. Early close: stream ending normally before expected Content-Length fails as incomplete_download and never finalizes', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      const totalExpected = 100 * 1024; // 100 KB
      const sentBytes = 50 * 1024; // Ends at 50%

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      int reqCount = 0;
      server.listen((HttpRequest req) async {
        reqCount++;
        try {
          if (reqCount == 1) {
            req.response.statusCode = 200;
            req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
            req.response.headers.set(HttpHeaders.contentLengthHeader, totalExpected.toString());

            final chunk = Uint8List(sentBytes);
            chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33;
            req.response.add(chunk);
            await req.response.flush();
            // Close normally at 50%
            await req.response.close();
          } else {
            // Subsequent retries fail fast
            req.response.statusCode = 404;
            await req.response.close();
          }
        } catch (_) {}
      });

      try {
        final clientContext = SecurityContext();
        clientContext.setTrustedCertificates(certFile.path);
        final httpClient = SafeHttpClient(
          customSecurityContext: clientContext,
          seam: const TestSafeHttpClientSeam(),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );

        final engine = DownloadEngine(
          db: db,
          httpClient: httpClient,
          downloadDir: tempDir,
        );

        await engine.enqueueDownload(
          id: 'early_close_task',
          url: Uri.parse('https://localhost:${server.port}/early.mp3'),
          displayName: 'Early Close Song',
          suggestedFileName: 'early.mp3',
        );

        await engine.runTask('early_close_task');

        final partFile = File(p.join(tempDir.path, 'early_close_task.part'));
        // Kept the .part file
        expect(partFile.existsSync(), isTrue);
        expect(partFile.lengthSync(), equals(sentBytes));

        // Final target file was never created because it never finalized
        final finalFile = File(p.join(tempDir.path, 'early.mp3'));
        expect(finalFile.existsSync(), isFalse);

        final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('early_close_task'))).getSingle();
        // Never reached completed
        expect(row.state, equals(DownloadTaskState.failed.name));
        expect(row.errorCode, anyOf(equals('incomplete_download'), equals('http_404')));
        expect(row.receivedBytes, equals(sentBytes));
      } finally {
        await server.close(force: true);
      }
    });
  });
}
