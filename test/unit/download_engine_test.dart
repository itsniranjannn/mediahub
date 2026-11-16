import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mediahub/core/security/safe_filename.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:path/path.dart' as p;
import 'fake_failing_database.dart';
import 'test_safe_http_client_seam.dart';

/// A small valid MP3 (ID3 header + payload).
final List<int> _mp3Bytes = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A, ...List.filled(512, 0xAA)];

/// Local HTTPS server that answers every request with [payload].
Future<HttpServer> _serveBytes(List<int> payload) async {
  final serverContext = SecurityContext()
    ..useCertificateChain('test/certs/localhost.crt')
    ..usePrivateKey('test/certs/localhost.key');
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
  server.listen((HttpRequest req) {
    req.response.statusCode = 200;
    req.response.headers.set(HttpHeaders.contentLengthHeader, payload.length.toString());
    req.response.add(payload);
    req.response.close();
  });
  return server;
}

SafeHttpClient _localClient() {
  final clientContext = SecurityContext()..setTrustedCertificates('test/certs/localhost.crt');
  return SafeHttpClient(
    customSecurityContext: clientContext,
    seam: const TestSafeHttpClientSeam(),
    dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
  );
}

Future<void> _insertRow(
  AppDatabase db, {
  required String id,
  required DownloadTaskState state,
  required String fileName,
  String? finalPath,
}) {
  final now = DateTime.now();
  return db.into(db.downloadsTable).insert(
        DownloadsTableCompanion.insert(
          id: id,
          url: 'https://example.com/$fileName',
          host: 'example.com',
          displayName: fileName,
          fileName: fileName,
          state: state.name,
          finalPath: Value(finalPath),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<String> _stateOf(AppDatabase db, String id) async =>
    (await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle()).state;

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

      // Create an orphan part file that doesn't exist in DB. It uses the
      // engine's own partial-file naming (`<numeric task id>.part`): the sweep
      // only ever considers names of that shape.
      final orphanPart = File('${tempDir.path}/1700000000123.part');
      await orphanPart.writeAsString('orphan');

      // Create a valid part file with DB row in paused state. Same numeric
      // shape as the orphan, so it is a sweep candidate and only the paused
      // row protects it.
      final validPart = File('${tempDir.path}/1700000000456.part');
      await validPart.writeAsString('valid');
      await engine.enqueueDownload(
        id: '1700000000456',
        url: Uri.parse('https://example.com/song.mp3'),
        displayName: 'Valid',
        suggestedFileName: 'song.mp3',
      );
      await engine.pause('1700000000456');

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

  group('Download integrity', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('download_integrity_test_');
    });

    tearDown(() async {
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    File fileIn(String name) => File(p.join(tempDir.path, name));

    test('startup cleanup keeps a completed download named "song.part" and still removes real orphans', () async {
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(seam: const TestSafeHttpClientSeam()),
        downloadDir: tempDir,
      );

      // Completed downloads whose finished names end in ".part" (possible
      // before finished names were kept clear of internal extensions), one of
      // them even shaped like an engine partial.
      final songPart = fileIn('song.part')..writeAsStringSync('finished audio');
      await _insertRow(db,
          id: '1700000000001', state: DownloadTaskState.completed, fileName: 'song.part', finalPath: songPart.path);
      final numericFinished = fileIn('1700000000777.part')..writeAsStringSync('finished audio 2');
      await _insertRow(db,
          id: '1700000000002',
          state: DownloadTaskState.completed,
          fileName: '1700000000777.part',
          finalPath: numericFinished.path);

      // A paused task's own partial file must stay (it resumes from it).
      final pausedPart = fileIn('1700000000003.part')..writeAsStringSync('partial');
      await _insertRow(db, id: '1700000000003', state: DownloadTaskState.paused, fileName: 'paused.mp3');

      // Real orphans: no row at all, and a leftover partial of a completed task.
      final orphanNoRow = fileIn('1700000000555.part')..writeAsStringSync('orphan');
      final orphanOfCompleted = fileIn('1700000000001.part')..writeAsStringSync('leftover');

      // Not the engine's naming: never a candidate, whatever its extension.
      final foreignPart = fileIn('notes.part')..writeAsStringSync('not ours');
      final media = fileIn('track.mp3')..writeAsStringSync('media');

      await engine.reconcileOnStartup();

      expect(songPart.existsSync(), isTrue, reason: 'a completed download must never be deleted');
      expect(numericFinished.existsSync(), isTrue, reason: 'finalPath of a row is protected');
      expect(pausedPart.existsSync(), isTrue);
      expect(foreignPart.existsSync(), isTrue);
      expect(media.existsSync(), isTrue);
      expect(orphanNoRow.existsSync(), isFalse);
      expect(orphanOfCompleted.existsSync(), isFalse);

      engine.dispose();
    });

    test('a file name ending in an internal extension is saved with the sniffed media extension', () async {
      final server = await _serveBytes(_mp3Bytes);
      try {
        final engine = DownloadEngine(db: db, httpClient: _localClient(), downloadDir: tempDir);
        await engine.enqueueDownload(
          id: '1700000000100',
          url: Uri.parse('https://localhost:${server.port}/song.part'),
          displayName: 'Song',
          suggestedFileName: 'song.part',
        );
        await engine.runTask('1700000000100');

        final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('1700000000100'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(p.basename(row.finalPath!), 'song.mp3');
        expect(row.fileName, 'song.mp3', reason: 'the card shows the real file name');
        final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(row.mediaId!))).getSingle();
        expect(media.format, 'mp3');

        // ... and it survives the next startup.
        await engine.reconcileOnStartup();
        expect(File(row.finalPath!).existsSync(), isTrue);
        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('an error while finalizing ends the task failed, not stuck in finalizing', () async {
      final failingDb = FailingFinalizeDatabase(NativeDatabase.memory())..failMediaInsert = true;
      final server = await _serveBytes(_mp3Bytes);
      try {
        final engine = DownloadEngine(db: failingDb, httpClient: _localClient(), downloadDir: tempDir);
        await engine.enqueueDownload(
          id: '1700000000200',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: 'Song',
          suggestedFileName: 'song.mp3',
        );

        // Must complete normally: an escaped error would also be unhandled in
        // the queue coordinator.
        await engine.runTask('1700000000200');

        final row =
            await (failingDb.select(failingDb.downloadsTable)..where((t) => t.id.equals('1700000000200'))).getSingle();
        expect(row.state, DownloadTaskState.failed.name);
        expect(row.errorCode, 'download_error');
        expect(row.errorDetail, 'Unexpected error (StateError)');
        expect(row.errorDetail, isNot(contains('/data/')), reason: 'no raw exception text (paths) in the reason');

        // The renamed file was moved back to the task's partial file: no
        // media file without a row is left in the downloads folder, and no
        // library row points at a file that is not there.
        final names = tempDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList();
        expect(names, ['1700000000200.part']);
        expect(File(p.join(tempDir.path, '1700000000200.part')).lengthSync(), _mp3Bytes.length);
        expect(await failingDb.select(failingDb.mediaItemsTable).get(), isEmpty);

        // The failed row still owns those bytes: startup keeps them ...
        await engine.reconcileOnStartup();
        expect(File(p.join(tempDir.path, '1700000000200.part')).existsSync(), isTrue);

        // ... and a retry saves under the original name, not "song (1).mp3".
        failingDb.failMediaInsert = false;
        await engine.runTask('1700000000200');
        final retried =
            await (failingDb.select(failingDb.downloadsTable)..where((t) => t.id.equals('1700000000200'))).getSingle();
        expect(retried.state, DownloadTaskState.completed.name);
        expect(p.basename(retried.finalPath!), 'song.mp3');
        expect(tempDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList(), ['song.mp3']);
        engine.dispose();
      } finally {
        await server.close(force: true);
        await failingDb.close();
      }
    });

    test('a pause while the task waits for the download folder is not overwritten with "downloading"', () async {
      final folder = Completer<Directory>();
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(seam: const TestSafeHttpClientSeam()),
        downloadDir: folder.future,
      );
      const id = '1700000000500';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://example.com/song.mp3'),
        displayName: 'Song',
        suggestedFileName: 'song.mp3',
      );

      final running = engine.runTask(id);
      for (var i = 0; i < 50 && await _stateOf(db, id) != DownloadTaskState.preparing.name; i++) {
        await pumpEventQueue();
      }
      expect(await _stateOf(db, id), DownloadTaskState.preparing.name);

      await engine.pause(id);
      folder.complete(tempDir);
      await running;

      // Not left 'downloading' with no worker (a lost slot, a service that
      // never stops), and nothing was downloaded.
      expect(await _stateOf(db, id), DownloadTaskState.paused.name);
      expect(tempDir.listSync(), isEmpty);
      engine.dispose();
    });

    test('a cancel while free space is being checked is not overwritten with "downloading"', () async {
      final space = Completer<int>();
      var asked = false;
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(seam: const TestSafeHttpClientSeam()),
        downloadDir: tempDir,
        freeSpaceProvider: () {
          asked = true;
          return space.future;
        },
      );
      const id = '1700000000600';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://example.com/song.mp3'),
        displayName: 'Song',
        suggestedFileName: 'song.mp3',
      );

      final running = engine.runTask(id);
      for (var i = 0; i < 50 && !asked; i++) {
        await pumpEventQueue();
      }
      expect(asked, isTrue);

      await engine.cancel(id);
      space.complete(500 * 1024 * 1024);
      await running;

      expect(await _stateOf(db, id), DownloadTaskState.cancelled.name);
      engine.dispose();
    });

    test('a file-system error is classified and its reason carries no path', () {
      const err = FileSystemException(
        "Cannot rename file to 'C:\\Users\\me\\downloads\\song.mp3'",
        'C:\\Users\\me\\downloads\\1.part',
        OSError('Access is denied', 5),
      );
      expect(DownloadEngine.unexpectedErrorCode(err), 'write_failed');
      expect(DownloadEngine.sanitizedErrorReason(err), 'File system error: Access is denied');
      expect(
        DownloadEngine.unexpectedErrorCode(const FileSystemException('x', null, OSError('No space left', 28))),
        'insufficient_disk_space',
      );
      expect(DownloadEngine.unexpectedErrorCode(StateError('db')), 'download_error');
    });

    test('while the download folder is still resolving, queueing does not wait and nothing is written elsewhere', () async {
      final folder = Completer<Directory>();
      final server = await _serveBytes(_mp3Bytes);
      final name = 'folder_wait_${DateTime.now().microsecondsSinceEpoch}.mp3';
      try {
        final engine = DownloadEngine(db: db, httpClient: _localClient(), downloadDir: folder.future);

        // Queueing works before the folder is known.
        await engine.enqueueDownload(
          id: '1700000000300',
          url: Uri.parse('https://localhost:${server.port}/$name'),
          displayName: 'Waiting',
          suggestedFileName: name,
        );

        final running = engine.runTask('1700000000300');
        Future<String> stateNow() async =>
            (await (db.select(db.downloadsTable)..where((t) => t.id.equals('1700000000300'))).getSingle()).state;
        for (var i = 0; i < 50 && await stateNow() != DownloadTaskState.preparing.name; i++) {
          await pumpEventQueue();
        }
        // Give it time to (wrongly) start downloading if it did not wait.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(await stateNow(), DownloadTaskState.preparing.name, reason: 'the task waits for the real folder');
        expect(tempDir.listSync(), isEmpty);

        folder.complete(tempDir);
        await running;

        final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('1700000000300'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        expect(File(row.finalPath!).parent.path, tempDir.path);
        expect(File(p.join(Directory.systemTemp.path, name)).existsSync(), isFalse);
        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('a download folder that cannot be resolved fails the task instead of using a fallback', () async {
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(seam: const TestSafeHttpClientSeam()),
        downloadDir: Future<Directory>.error(Exception('documents folder unavailable')),
      );
      await engine.enqueueDownload(
        id: '1700000000400',
        url: Uri.parse('https://example.com/song.mp3'),
        displayName: 'No Folder',
        suggestedFileName: 'song.mp3',
      );
      await engine.runTask('1700000000400');

      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('1700000000400'))).getSingle();
      expect(row.state, DownloadTaskState.failed.name);
      expect(row.errorCode, 'write_failed');

      // pause / cancel stay safe too.
      await engine.cancel('1700000000400');
      engine.dispose();
    });
  });

  group('SafeFilename.finalMediaName', () {
    test('replaces internal extensions with the media extension', () {
      expect(SafeFilename.finalMediaName('song.part', mediaExtension: 'mp3'), 'song.mp3');
      expect(SafeFilename.finalMediaName('clip.THUMB', mediaExtension: '.mp4'), 'clip.mp4');
      expect(SafeFilename.finalMediaName('a.ytdl', mediaExtension: 'm4a'), 'a.m4a');
      expect(SafeFilename.finalMediaName('b.temp', mediaExtension: 'webm'), 'b.webm');
      expect(SafeFilename.finalMediaName('c.tmp', mediaExtension: 'flac'), 'c.flac');
      // Stacked internal extensions are all removed; an existing media
      // extension is not doubled.
      expect(SafeFilename.finalMediaName('song.mp3.part', mediaExtension: 'mp3'), 'song.mp3');
      expect(SafeFilename.finalMediaName('x.part.tmp', mediaExtension: 'mp3'), 'x.mp3');
      // An unusable media extension falls back to .bin.
      expect(SafeFilename.finalMediaName('d.part', mediaExtension: ''), 'd.bin');
      expect(SafeFilename.finalMediaName('e.part', mediaExtension: 'part'), 'e.bin');
    });

    test('leaves ordinary names exactly as sanitize does', () {
      expect(SafeFilename.finalMediaName('track.mp3', mediaExtension: 'mp4'), 'track.mp3');
      expect(SafeFilename.finalMediaName('../evil/partner.mp3', mediaExtension: 'mp3'), 'partner.mp3');
      expect(SafeFilename.hasReservedExtension('song.part'), isTrue);
      expect(SafeFilename.hasReservedExtension('song.mp3'), isFalse);
      expect(SafeFilename.hasReservedExtension('part'), isFalse);
    });
  });
}
