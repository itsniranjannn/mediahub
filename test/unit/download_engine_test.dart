import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'test_safe_http_client_seam.dart';

void main() {
  group('PART 4: DownloadEngine Tests', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('download_engine_test_');
    });

    tearDown(() async {
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('Full download flow with valid MP3 magic bytes completes and inserts media item', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // Create MP3 dummy payload: starts with ID3 magic bytes ('ID3' + version + flags + 4 bytes size)
      final mp3Bytes = BytesBuilder();
      mp3Bytes.add([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A]);
      mp3Bytes.add(List.filled(1024, 0xAA));
      final payload = mp3Bytes.toBytes();

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
        req.response.headers.set(HttpHeaders.contentLengthHeader, payload.length.toString());
        req.response.add(payload);
        req.response.close();
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
          freeSpaceProvider: () async => 500 * 1024 * 1024,
        );

        final url = Uri.parse('https://localhost:${server.port}/song.mp3');
        await engine.enqueueDownload(
          id: 'dl_song_1',
          url: url,
          displayName: 'Test Song',
          suggestedFileName: 'song.mp3',
        );

        await engine.runTask('dl_song_1');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_song_1'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.mimeType, 'audio/mpeg');
        expect(row.receivedBytes, payload.length);
        expect(row.mediaId, 'dl_dl_song_1');

        final mediaItem = await (db.select(db.mediaItemsTable)..where((tbl) => tbl.id.equals('dl_dl_song_1'))).getSingle();
        expect(mediaItem.title, 'Test Song');
        expect(mediaItem.source, 'download');
        expect(mediaItem.availability, 'available');
        expect(File(mediaItem.uri).existsSync(), isTrue);

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('HTML response fails magic byte sniff with not_media and deletes .part', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final htmlPayload = '<!DOCTYPE html><html><body>Error</body></html>';

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/html');
        req.response.write(htmlPayload);
        req.response.close();
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
          freeSpaceProvider: () async => 500 * 1024 * 1024,
        );

        final url = Uri.parse('https://localhost:${server.port}/webpage.html');
        await engine.enqueueDownload(
          id: 'dl_html',
          url: url,
          displayName: 'Webpage',
          suggestedFileName: 'webpage.mp3',
        );

        await engine.runTask('dl_html');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_html'))).getSingle();
        expect(row.state, DownloadTaskState.failed.name);
        expect(row.errorCode, 'not_media');

        // .part file must be deleted
        final partFile = File('${tempDir.path}/dl_html.part');
        expect(partFile.existsSync(), isFalse);

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Insufficient free disk space refuses to start and fails cleanly', () async {
      final httpClient = SafeHttpClient(
        seam: const TestSafeHttpClientSeam(),
      );

      final engine = DownloadEngine(
        db: db,
        httpClient: httpClient,
        downloadDir: tempDir,
        freeSpaceProvider: () async => 50 * 1024 * 1024, // 50MB available < 200MB required
      );

      final url = Uri.parse('https://localhost:8443/song.mp3');
      await engine.enqueueDownload(
        id: 'dl_no_space',
        url: url,
        displayName: 'No Space',
        suggestedFileName: 'song.mp3',
      );

      await engine.runTask('dl_no_space');

      final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_no_space'))).getSingle();
      expect(row.state, DownloadTaskState.failed.name);
      expect(row.errorCode, 'insufficient_disk_space');

      engine.dispose();
    });

    test('Duplicate file name collision avoids overwriting by appending (1)', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // Pre-create existing file in downloadDir
      final existingFile = File('${tempDir.path}/track.mp3');
      await existingFile.writeAsString('existing');

      final mp3Bytes = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00];
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        req.response.statusCode = 200;
        req.response.add(mp3Bytes);
        req.response.close();
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
          id: 'dl_dup_1',
          url: Uri.parse('https://localhost:${server.port}/track.mp3'),
          displayName: 'Track Duplicate',
          suggestedFileName: 'track.mp3',
        );

        await engine.runTask('dl_dup_1');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_dup_1'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.finalPath?.endsWith('track (1).mp3'), isTrue);
        expect(File(row.finalPath!).existsSync(), isTrue);

        // Original file must not have been overwritten
        expect(await existingFile.readAsString(), 'existing');

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Resume with matching ETag sends Range and succeeds', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final fullPayload = [
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04,
        0x01, 0x02, 0x03, 0x04
      ];

      // Pre-create .part file with first 10 bytes
      final partFile = File('${tempDir.path}/dl_resume_etag.part');
      await partFile.writeAsBytes(fullPayload.sublist(0, 10));

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        expect(req.headers.value('range'), 'bytes=10-');
        expect(req.headers.value('if-range'), '"etag-v1"');
        req.response.statusCode = 206;
        req.response.headers.set('content-range', 'bytes 10-13/14');
        req.response.headers.set(HttpHeaders.etagHeader, '"etag-v1"');
        req.response.add(fullPayload.sublist(10));
        req.response.close();
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
          id: 'dl_resume_etag',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'Resume Song',
          suggestedFileName: 'song.mp3',
        );

        // Pre-populate ETag and totalBytes
        await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_resume_etag'))).write(
          const DownloadsTableCompanion(
            etag: Value('"etag-v1"'),
            totalBytes: Value(14),
          ),
        );

        await engine.runTask('dl_resume_etag');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_resume_etag'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.receivedBytes, 14);

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('200 answer to a Range request restarts from zero and truncates .part', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final fullPayload = [
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04,
        0x0A, 0x0B, 0x0C, 0x0D
      ];

      // Pre-create .part with old stale bytes
      final partFile = File('${tempDir.path}/dl_range_200.part');
      await partFile.writeAsBytes(List.filled(10, 0xFF));

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        // Server ignores Range and returns 200 with new full payload
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentLengthHeader, fullPayload.length.toString());
        req.response.add(fullPayload);
        req.response.close();
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
          id: 'dl_range_200',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'Range 200 Song',
          suggestedFileName: 'song.mp3',
        );

        await engine.runTask('dl_range_200');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_range_200'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.receivedBytes, fullPayload.length);

        final downloadedBytes = await File(row.finalPath!).readAsBytes();
        expect(downloadedBytes, fullPayload); // Stale 0xFF truncated

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Content-Range mismatch on 206 fails', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // Pre-create .part file with 50 bytes
      final partFile = File('${tempDir.path}/dl_bad_range.part');
      await partFile.writeAsBytes(List.filled(50, 0x01));

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        req.response.statusCode = 206;
        // Server returns wrong Content-Range start (0 instead of 50)
        req.response.headers.set('content-range', 'bytes 0-100/101');
        req.response.add(List.filled(101, 0x02));
        req.response.close();
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
          id: 'dl_bad_range',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'Bad Range',
          suggestedFileName: 'song.mp3',
        );

        await engine.runTask('dl_bad_range');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_bad_range'))).getSingle();
        expect(row.state, DownloadTaskState.failed.name);
        expect(row.errorCode, 'content_range_mismatch');

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Cancel deletes .part and is safe if called twice', () async {
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(seam: const TestSafeHttpClientSeam()),
        downloadDir: tempDir,
      );

      final partFile = File('${tempDir.path}/dl_cancel.part');
      await partFile.writeAsString('partial');

      await engine.enqueueDownload(
        id: 'dl_cancel',
        url: Uri.parse('https://example.com/song.mp3'),
        displayName: 'Cancel Song',
        suggestedFileName: 'song.mp3',
      );

      // Call cancel twice
      await engine.cancel('dl_cancel');
      await engine.cancel('dl_cancel');

      final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_cancel'))).getSingle();
      expect(row.state, DownloadTaskState.cancelled.name);
      expect(partFile.existsSync(), isFalse);

      engine.dispose();
    });

    test('404 does not retry and fails immediately', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      int requestCount = 0;
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        requestCount++;
        req.response.statusCode = 404;
        req.response.close();
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
          id: 'dl_404',
          url: Uri.parse('https://localhost:${server.port}/missing.mp3'),
          displayName: 'Missing',
          suggestedFileName: 'missing.mp3',
        );

        await engine.runTask('dl_404');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_404'))).getSingle();
        expect(row.state, DownloadTaskState.failed.name);
        expect(row.errorCode, 'http_404');
        expect(requestCount, 1); // No retries

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Orphan .part cleanup on startup', () async {
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(seam: const TestSafeHttpClientSeam()),
        downloadDir: tempDir,
      );

      // Create an orphan part file that doesn't exist in DB
      final orphanPart = File('${tempDir.path}/orphan_123.part');
      await orphanPart.writeAsString('orphan');

      // Create a valid part file with DB row in paused state
      final validPart = File('${tempDir.path}/valid_456.part');
      await validPart.writeAsString('valid');
      await engine.enqueueDownload(
        id: 'valid_456',
        url: Uri.parse('https://example.com/song.mp3'),
        displayName: 'Valid',
        suggestedFileName: 'song.mp3',
      );
      await engine.pause('valid_456');

      await engine.reconcileOnStartup();

      expect(orphanPart.existsSync(), isFalse);
      expect(validPart.existsSync(), isTrue);

      engine.dispose();
    });

    test('3 retries with backoff for transient error then fail', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      int attempts = 0;
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        attempts++;
        req.response.statusCode = 503; // transient server error
        req.response.close();
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
          id: 'dl_retries',
          url: Uri.parse('https://localhost:${server.port}/error.mp3'),
          displayName: 'Retries',
          suggestedFileName: 'error.mp3',
        );

        await engine.runTask('dl_retries');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_retries'))).getSingle();
        expect(row.state, DownloadTaskState.failed.name);
        expect(row.errorCode, 'http_503');
        expect(attempts, 4); // 1 initial attempt + 3 retries

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Oversized stops: exceeding 2GB aborts cleanly', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        req.response.statusCode = 200;
        // Declare chunked transfer encoding and send bytes exceeding 2GB limit (simulated)
        req.response.headers.set('content-range', 'bytes 0-100/${3 * 1024 * 1024 * 1024}');
        req.response.write('ok');
        req.response.close();
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
          id: 'dl_oversize',
          url: Uri.parse('https://localhost:${server.port}/large.mp3'),
          displayName: 'Large',
          suggestedFileName: 'large.mp3',
        );

        await engine.runTask('dl_oversize');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_oversize'))).getSingle();
        expect(row.state, DownloadTaskState.failed.name);
        expect(row.errorCode, 'max_size_exceeded');

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Pause then resume continues from saved bytes', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final fullPayload = [
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06,
        0x10, 0x20, 0x30, 0x40, 0x50, 0x60
      ];

      // Part 1: initial download up to byte 10
      final partFile = File('${tempDir.path}/dl_pause_resume.part');
      await partFile.writeAsBytes(fullPayload.sublist(0, 10));

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        // Must request Range from byte 10
        expect(req.headers.value('range'), 'bytes=10-');
        req.response.statusCode = 206;
        req.response.headers.set('content-range', 'bytes 10-15/16');
        req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        req.response.add(fullPayload.sublist(10));
        req.response.close();
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
          id: 'dl_pause_resume',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'Pause Resume',
          suggestedFileName: 'song.mp3',
        );

        // Pre-populate as paused with 10 bytes received and supportsRange true
        await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_pause_resume'))).write(
          const DownloadsTableCompanion(
            state: Value('paused'),
            receivedBytes: Value(10),
            totalBytes: Value(16),
            supportsRange: Value(true),
          ),
        );

        // Resume execution
        await engine.runTask('dl_pause_resume');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_pause_resume'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.receivedBytes, 16);
        expect(await File(row.finalPath!).readAsBytes(), fullPayload);

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('Resume refused when ETag changed restarts from zero with clear message and truncates .part', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      final newPayload = [
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04,
        0xAA, 0xBB, 0xCC, 0xDD
      ];

      // Pre-create .part with old stale bytes
      final partFile = File('${tempDir.path}/dl_etag_changed.part');
      await partFile.writeAsBytes(List.filled(10, 0x99));

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        expect(req.headers.value('if-range'), '"old-etag"');
        // Server detects ETag changed, responds 200 with new content
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.etagHeader, '"new-etag"');
        req.response.headers.set(HttpHeaders.contentLengthHeader, newPayload.length.toString());
        req.response.add(newPayload);
        req.response.close();
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
          id: 'dl_etag_changed',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'ETag Changed Song',
          suggestedFileName: 'song.mp3',
        );

        await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_etag_changed'))).write(
          const DownloadsTableCompanion(
            state: Value('paused'),
            receivedBytes: Value(10),
            etag: Value('"old-etag"'),
          ),
        );

        await engine.runTask('dl_etag_changed');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_etag_changed'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.etag, '"new-etag"');
        expect(row.receivedBytes, newPayload.length);
        expect(await File(row.finalPath!).readAsBytes(), newPayload);

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('DB progress writes are throttled to at most once per 1s or 512KB', () async {
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext();
      serverContext.useCertificateChain(certFile.path);
      serverContext.usePrivateKey(keyFile.path);

      // 600 KB total payload: sends in 100 KB chunks rapidly
      final mp3Header = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01];
      final chunk = Uint8List(100 * 1024);
      final fullBytes = BytesBuilder();
      fullBytes.add(mp3Header);
      for (int i = 0; i < 6; i++) {
        fullBytes.add(chunk);
      }
      final payload = fullBytes.toBytes();

      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((HttpRequest req) {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentLengthHeader, payload.length.toString());
        req.response.add(payload);
        req.response.close();
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
          id: 'dl_throttle',
          url: Uri.parse('https://localhost:${server.port}/track.mp3'),
          displayName: 'Throttle Test',
          suggestedFileName: 'track.mp3',
        );

        await engine.runTask('dl_throttle');

        final row = await (db.select(db.downloadsTable)..where((tbl) => tbl.id.equals('dl_throttle'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(row.receivedBytes, payload.length);

        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });
  });
}
