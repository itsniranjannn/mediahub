import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'test_safe_http_client_seam.dart';

// These tests drive real TLS sockets, file writes and SQLite on one isolate.
// On a slow or busy machine (the whole suite running in parallel) each step
// can take many times longer than on an idle one, so no fixed sleep decides
// what state a download is in. Where a test needs the transfer to be "mid
// stream", the server holds its body at that point until the test has seen
// the bytes on disk, and every wait polls a condition with a generous deadline.

/// Limit for the real-socket tests (the default 30 s is too short under load).
const _realSocketTimeout = Timeout(Duration(minutes: 3));

/// How long a poll may wait for a state the server is holding the stream at.
const _holdDeadline = Duration(minutes: 2);

/// Polls [condition] every [every] until it holds or [within] has passed.
/// Returns whether it held.
Future<bool> _waitUntil(
  bool Function() condition, {
  required Duration within,
  Duration every = const Duration(milliseconds: 20),
}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed >= within) return condition();
    await Future<void>.delayed(every);
  }
  return true;
}

/// Current size of [file], 0 while it does not exist.
int _lengthOf(File file) {
  try {
    return file.existsSync() ? file.lengthSync() : 0;
  } on FileSystemException {
    return 0; // removed between the two calls
  }
}

Future<DownloadEntry> _row(AppDatabase db, String id) =>
    (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();

void main() {
  group('TASK 5.2d Item 3: Streaming Download Engine Tests', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('dl_stream_test_');
    });

    tearDown(() async {
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
      '1. A large stream is written to disk while it is still downloading (not buffered in RAM) and progress arrives during transfer',
      // 100 MB through TLS on one isolate: about 2.5 min on a busy PC, more
      // when the whole suite runs. The wait below is bounded separately.
      timeout: const Timeout(Duration(minutes: 12)),
      () async {
        const totalChunks = 100;
        const chunkSize = 1024 * 1024; // 1 MB
        const pauseAtChunk = 60;
        const minBytesOnDiskWhileServerWaits = 40 * 1024 * 1024;

        // The server stops after 60 MB until the test has seen those bytes on
        // disk. It has no timed fallback: on a slow machine that would send the
        // rest before the check below and the check would prove nothing. The
        // finally block releases it.
        final releaseServer = Completer<void>();

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
            req.response.headers.set(HttpHeaders.contentLengthHeader, (totalChunks * chunkSize).toString());

            for (int i = 0; i < totalChunks; i++) {
              if (i == pauseAtChunk) await releaseServer.future;
              final chunk = Uint8List(chunkSize);
              if (i == 0) {
                chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33; // ID3 header
              }
              req.response.add(chunk);
              await req.response.flush();
            }
            await req.response.close();
          } catch (_) {
            // The client went away (the test failed and closed the server).
          }
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

          int progressEventCount = 0;
          final sub = engine.progressStream.listen((update) {
            progressEventCount++;
          });

          await engine.enqueueDownload(
            id: 'large_stream_task',
            url: Uri.parse('https://localhost:${server.port}/stream.mp3'),
            displayName: 'Large Stream',
            suggestedFileName: 'stream.mp3',
          );

          var runFinished = false;
          final run = engine.runTask('large_stream_task').whenComplete(() => runFinished = true);

          // While the server is still holding back the last 40 MB the first 60 MB
          // must already be on disk: that proves the body is streamed to the file
          // instead of being collected in memory.
          final part = File('${tempDir.path}/large_stream_task.part');
          await _waitUntil(
            () => runFinished || _lengthOf(part) >= minBytesOnDiskWhileServerWaits,
            within: const Duration(minutes: 7),
            every: const Duration(milliseconds: 50),
          );
          final bytesOnDisk = _lengthOf(part);
          if (runFinished) {
            final row = await _row(db, 'large_stream_task');
            fail('the download ended while the server was still holding the stream: '
                'state ${row.state}, error ${row.errorCode}, $bytesOnDisk bytes on disk');
          }
          expect(bytesOnDisk, greaterThanOrEqualTo(minBytesOnDiskWhileServerWaits),
              reason: 'download must reach the disk progressively');
          expect(bytesOnDisk, lessThan(totalChunks * chunkSize),
              reason: 'the transfer must still be in progress at this point');

          releaseServer.complete();
          await run;
          await sub.cancel();

          // More than 5 progress updates arrived during transfer
          expect(progressEventCount, greaterThan(5));

          // Part file was finalized into stream.mp3 with exact size
          final finalFile = File('${tempDir.path}/stream.mp3');
          expect(finalFile.existsSync(), isTrue);
          expect(finalFile.lengthSync(), equals(totalChunks * chunkSize));
        } finally {
          if (!releaseServer.isCompleted) releaseServer.complete();
          await server.close(force: true);
        }
      },
    );

    test('2. Pause mid-stream leaves .part with bytes written so far; resume continues and completes byte-identical', timeout: _realSocketTimeout, () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // 40 KB total test payload: ID3 tag + sequence bytes
      final fullPayload = Uint8List(40 * 1024);
      fullPayload[0] = 0x49; fullPayload[1] = 0x44; fullPayload[2] = 0x33;
      for (int i = 3; i < fullPayload.length; i++) {
        fullPayload[i] = (i % 256);
      }
      const firstSegment = 15 * 1024;

      // The first (full) response stops after 15 KB until the test has paused,
      // so the pause always lands mid-stream however slow the machine is.
      final releaseRest = Completer<void>();
      int fullRequests = 0;
      int? resumedFrom;

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) async {
        try {
          final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final start = int.parse(rangeHeader.substring(6).replaceAll('-', ''));
            resumedFrom = start;
            req.response.statusCode = 206;
            req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
            req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            req.response.headers.set(HttpHeaders.etagHeader, '"etag_stable_1"');
            req.response.headers.set('content-range', 'bytes $start-${fullPayload.length - 1}/${fullPayload.length}');
            req.response.add(fullPayload.sublist(start));
            await req.response.close();
          } else {
            fullRequests++;
            req.response.statusCode = 200;
            req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
            req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            req.response.headers.set(HttpHeaders.etagHeader, '"etag_stable_1"');
            req.response.headers.set(HttpHeaders.contentLengthHeader, fullPayload.length.toString());

            // Send the first 15 KB, then hold (first request only)
            req.response.add(fullPayload.sublist(0, firstSegment));
            await req.response.flush();
            if (fullRequests == 1) await releaseRest.future;
            // Keep sending remainder in slow chunks
            for (int i = firstSegment; i < fullPayload.length; i += 1024) {
              await Future.delayed(const Duration(milliseconds: 50));
              req.response.add(fullPayload.sublist(i, i + 1024));
              await req.response.flush();
            }
            await req.response.close();
          }
        } catch (_) {
          // Socket closed by client disconnect
        }
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
          id: 'pause_resume_task',
          url: Uri.parse('https://localhost:${server.port}/pause.mp3'),
          displayName: 'Pause Resume Song',
          suggestedFileName: 'pause.mp3',
        );

        // Run task in background and pause once the first 15 KB is on disk
        final partFile = File('${tempDir.path}/pause_resume_task.part');
        final runFuture = engine.runTask('pause_resume_task');
        final reachedDisk = await _waitUntil(
          () => _lengthOf(partFile) >= firstSegment,
          within: _holdDeadline,
        );
        await engine.pause('pause_resume_task');
        await runFuture;
        expect(reachedDisk, isTrue, reason: 'the first 15 KB never reached the disk before the pause');

        // Check part file exists and receivedBytes equals part file length
        expect(partFile.existsSync(), isTrue);
        final midLength = partFile.lengthSync();
        expect(midLength, greaterThan(0));
        expect(midLength, lessThan(fullPayload.length));
        expect(midLength, equals(firstSegment));
        final pausedRow = await _row(db, 'pause_resume_task');
        expect(pausedRow.state, equals(DownloadTaskState.paused.name));
        expect(pausedRow.receivedBytes, equals(midLength));

        // Now resume
        await engine.runTask('pause_resume_task');

        // Verify it continued from the paused offset, completed, and is byte-identical
        expect(resumedFrom, equals(midLength), reason: 'resume must request the rest with a Range header');
        final finalFile = File('${tempDir.path}/pause.mp3');
        expect(finalFile.existsSync(), isTrue);
        expect(finalFile.readAsBytesSync(), equals(fullPayload));
      } finally {
        if (!releaseRest.isCompleted) releaseRest.complete();
        await server.close(force: true);
      }
    });

    test('3. Cancel mid-stream stops reading and deletes .part file immediately', timeout: _realSocketTimeout, () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // The body stops after the first chunk until the test has cancelled, so
      // the cancel always lands mid-stream.
      final releaseServer = Completer<void>();

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) async {
        try {
          req.response.statusCode = 200;
          req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
          req.response.headers.set(HttpHeaders.contentLengthHeader, (10 * 1024 * 1024).toString());

          final chunk = Uint8List(64 * 1024);
          chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33;
          for (int i = 0; i < 20; i++) {
            if (i == 1) await releaseServer.future;
            req.response.add(chunk);
            await req.response.flush();
            await Future.delayed(const Duration(milliseconds: 20));
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
          id: 'cancel_mid_task',
          url: Uri.parse('https://localhost:${server.port}/cancel.mp3'),
          displayName: 'Cancel Song',
          suggestedFileName: 'cancel.mp3',
        );

        final partFile = File('${tempDir.path}/cancel_mid_task.part');
        final runFuture = engine.runTask('cancel_mid_task');
        final midStream = await _waitUntil(() => _lengthOf(partFile) > 0, within: _holdDeadline);
        await engine.cancel('cancel_mid_task');
        await runFuture;
        expect(midStream, isTrue, reason: 'no bytes reached the disk, so the cancel was not mid-stream');

        expect(partFile.existsSync(), isFalse);

        final taskRow = await _row(db, 'cancel_mid_task');
        expect(taskRow.state, equals(DownloadTaskState.cancelled.name));
      } finally {
        if (!releaseServer.isCompleted) releaseServer.complete();
        await server.close(force: true);
      }
    });

    test('4. Connection error mid-stream keeps .part and fails or retries gracefully', timeout: _realSocketTimeout, () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // The first response drops its connection once the test has seen its
      // 32 KB on disk (dropping it earlier could lose bytes still in flight).
      final dropConnection = Completer<void>();

      int requestCount = 0;
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) async {
        requestCount++;
        try {
          if (requestCount == 1) {
            req.response.statusCode = 200;
            req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
            req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            req.response.headers.set(HttpHeaders.etagHeader, '"test_etag"');
            req.response.headers.set(HttpHeaders.contentLengthHeader, (5 * 1024 * 1024).toString());

            final chunk = Uint8List(32 * 1024);
            chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33;
            req.response.add(chunk);
            await req.response.flush();

            await dropConnection.future;

            // Destroy the socket mid-body (Content-Length promised 5 MB).
            // detachSocket() cannot be used once headers are sent; an expired
            // response deadline destroys the connection.
            req.response.deadline = Duration.zero;
          } else {
            // On retry, check Range header: bytes=32768-
            final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
            if (rangeHeader != null && rangeHeader.startsWith('bytes=32768-')) {
              // Server fails retry with 500 until attempts exhausted, or immediately fails
              req.response.statusCode = 404;
              await req.response.close();
            } else {
              req.response.statusCode = 404;
              await req.response.close();
            }
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
          id: 'conn_error_task',
          url: Uri.parse('https://localhost:${server.port}/error.mp3'),
          displayName: 'Error Song',
          suggestedFileName: 'error.mp3',
        );

        final partFile = File('${tempDir.path}/conn_error_task.part');
        final run = engine.runTask('conn_error_task');
        await _waitUntil(() => _lengthOf(partFile) >= 32 * 1024, within: _holdDeadline);
        dropConnection.complete();
        await run;

        // Part file was kept
        expect(partFile.existsSync(), isTrue);
        expect(partFile.lengthSync(), equals(32 * 1024));

        final taskRow = await _row(db, 'conn_error_task');
        expect(taskRow.state, equals(DownloadTaskState.failed.name));
        expect(taskRow.receivedBytes, equals(32 * 1024));
      } finally {
        if (!dropConnection.isCompleted) dropConnection.complete();
        await server.close(force: true);
      }
    });

    test('5. Server sending more than maxBodySize limit is aborted cleanly', timeout: _realSocketTimeout, () async {
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

        // Send enough data to exceed maxBodySize
        final chunk = Uint8List(128 * 1024);
        chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33;
        try {
          for (int i = 0; i < 10; i++) {
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

        // Open stream with 20 KB limit
        final streamResp = await httpClient.openStream(
          Uri.parse('https://localhost:${server.port}/oversized'),
          maxBodySize: 20 * 1024,
        );

        // Awaited: the server must stay up until the body has been read, or a
        // slow client would see the forced close instead of the size limit.
        await expectLater(
          () async {
            await for (final _ in streamResp.body) {}
          },
          throwsA(isA<SafeHttpClientException>().having((e) => e.code, 'code', equals('max_body_size_exceeded'))),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('6. Real-socket test: Stream 20 MB slowly and verify progress callbacks arrive before completion', timeout: _realSocketTimeout, () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      const totalSize = 20 * 1024 * 1024; // 20 MB
      const chunkSize = 256 * 1024; // 256 KB chunks

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) async {
        try {
          req.response.statusCode = 200;
          req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
          req.response.headers.set(HttpHeaders.contentLengthHeader, totalSize.toString());

          final chunk = Uint8List(chunkSize);
          chunk[0] = 0x49; chunk[1] = 0x44; chunk[2] = 0x33; // ID3

          for (int sent = 0; sent < totalSize; sent += chunkSize) {
            req.response.add(chunk);
            await req.response.flush();
            await Future.delayed(const Duration(milliseconds: 30));
          }
          await req.response.close();
        } catch (_) {
          // The client went away (the test failed and closed the server).
        }
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

        final progressList = <int>[];
        final sub = engine.progressStream.listen((update) {
          progressList.add(update.receivedBytes);
        });

        await engine.enqueueDownload(
          id: 'slow_20mb_task',
          url: Uri.parse('https://localhost:${server.port}/slow20mb.mp3'),
          displayName: 'Slow 20MB',
          suggestedFileName: 'slow20mb.mp3',
        );

        await engine.runTask('slow_20mb_task');
        await sub.cancel();

        // Reported first: if the download itself failed, say why.
        final row = await _row(db, 'slow_20mb_task');
        expect(row.state, equals(DownloadTaskState.completed.name),
            reason: 'download ended as ${row.state} (${row.errorCode})');

        // The events were all delivered by the time runTask returned.
        expect(progressList.length, greaterThan(5));
        expect(progressList.first, lessThan(totalSize));
        expect(progressList.last, equals(totalSize));

        final finalFile = File('${tempDir.path}/slow20mb.mp3');
        expect(finalFile.existsSync(), isTrue);
        expect(finalFile.lengthSync(), equals(totalSize));
      } finally {
        await server.close(force: true);
      }
    });
  });
}
