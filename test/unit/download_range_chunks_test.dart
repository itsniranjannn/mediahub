import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:path/path.dart' as p;

import 'test_safe_http_client_seam.dart';

/// YouTube's media servers are read in fixed byte ranges (like yt-dlp does),
/// because one long response for a whole file gets slowed down or cut off.
/// These tests run the engine against a local server with a small range size.
void main() {
  HttpOverrides.global = null;

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('download_range_chunks_test_');
  });

  tearDown(() async {
    await db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(HttpServer, SafeHttpClient)> startServer(void Function(HttpRequest req) handler) async {
    final certFile = File('test/certs/localhost.crt');
    final keyFile = File('test/certs/localhost.key');
    final serverContext = SecurityContext()
      ..useCertificateChain(certFile.path)
      ..usePrivateKey(keyFile.path);
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
    server.listen(handler);
    final clientContext = SecurityContext()..setTrustedCertificates(certFile.path);
    final client = SafeHttpClient(
      customSecurityContext: clientContext,
      seam: const TestSafeHttpClientSeam(),
      dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
    );
    return (server, client);
  }

  /// An audio-only M4A as YouTube serves it: ISO-BMFF with the "dash" brand,
  /// then a recognisable byte pattern so the saved file can be compared.
  Uint8List dashAudio(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = (i * 31 + 7) & 0xFF;
    }
    const header = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x64, 0x61, 0x73, 0x68]; // ....ftypdash
    bytes.setRange(0, header.length, header);
    return bytes;
  }

  /// Serves [body], honouring `Range: bytes=a-b` / `bytes=a-` with 206 answers.
  Future<void> serveRanges(HttpRequest req, Uint8List body, {int? capPieceAt}) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (match == null) {
      req.response.statusCode = 200;
      req.response.headers.set(HttpHeaders.contentLengthHeader, body.length.toString());
      req.response.add(body);
      await req.response.close();
      return;
    }
    final start = int.parse(match.group(1)!);
    var end = match.group(2)!.isEmpty ? body.length - 1 : int.parse(match.group(2)!);
    if (end > body.length - 1) end = body.length - 1;
    if (capPieceAt != null && end - start + 1 > capPieceAt) end = start + capPieceAt - 1;
    req.response.statusCode = 206;
    req.response.headers.set('content-range', 'bytes $start-$end/${body.length}');
    req.response.headers.set(HttpHeaders.contentLengthHeader, (end - start + 1).toString());
    req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    req.response.add(body.sublist(start, end + 1));
    await req.response.close();
  }

  Future<DownloadEntry> row(String id) => (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();

  test('the file is fetched range by range and saved byte for byte; an audio row stays audio', () async {
    const chunk = 40 * 1024;
    final body = dashAudio(150 * 1024); // 3 full ranges + a short last one
    final ranges = <String?>[];
    final (server, client) = await startServer((req) async {
      ranges.add(req.headers.value(HttpHeaders.rangeHeader));
      await serveRanges(req, body);
    });
    try {
      final engine = DownloadEngine(
        db: db,
        httpClient: client,
        downloadDir: tempDir,
        rangeChunkBytes: (_) => chunk,
      );
      const id = '1700000000101';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}/videoplayback?itag=140'),
        displayName: 'Song',
        suggestedFileName: 'Song.m4a',
        kind: 'audio',
        totalBytes: body.length,
      );
      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.completed.name, reason: 'error ${done.errorCode}');
      expect(ranges, [
        'bytes=0-40959',
        'bytes=40960-81919',
        'bytes=81920-122879',
        'bytes=122880-', // the last piece of a file of known size is open-ended
      ]);
      final saved = File(done.finalPath!);
      expect(p.basename(saved.path), 'Song.m4a');
      expect(saved.readAsBytesSync(), body);
      // The "dash" brand sniffs as video/mp4; the row was queued as audio.
      expect(done.kind, 'audio');
      expect(done.mimeType, 'audio/mp4');
      final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('dl_$id'))).getSingle();
      expect(media.mediaType, 'audio');
    } finally {
      await server.close(force: true);
    }
  });

  test('without a known size the ranges continue until the server reports the end', () async {
    const chunk = 50 * 1024;
    final body = dashAudio(120 * 1024);
    final ranges = <String?>[];
    final (server, client) = await startServer((req) async {
      ranges.add(req.headers.value(HttpHeaders.rangeHeader));
      await serveRanges(req, body);
    });
    try {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, rangeChunkBytes: (_) => chunk);
      const id = '1700000000102';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}/videoplayback?itag=18'),
        displayName: 'Clip',
        suggestedFileName: 'Clip.mp4',
        kind: 'video',
      );
      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.completed.name, reason: 'error ${done.errorCode}');
      // The first answer tells the total, so the last range is open-ended.
      expect(ranges, ['bytes=0-51199', 'bytes=51200-102399', 'bytes=102400-']);
      expect(File(done.finalPath!).readAsBytesSync(), body);
      expect(done.kind, 'video');
      expect(done.totalBytes, body.length);
    } finally {
      await server.close(force: true);
    }
  });

  test('a server that ignores Range and sends the whole file still completes in one go', () async {
    final body = dashAudio(90 * 1024);
    var requests = 0;
    final (server, client) = await startServer((req) async {
      requests++;
      req.response.statusCode = 200;
      req.response.headers.set(HttpHeaders.contentLengthHeader, body.length.toString());
      req.response.add(body);
      await req.response.close();
    });
    try {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, rangeChunkBytes: (_) => 32 * 1024);
      const id = '1700000000103';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}/whole.m4a'),
        displayName: 'Whole',
        suggestedFileName: 'Whole.m4a',
        kind: 'audio',
      );
      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.completed.name, reason: 'error ${done.errorCode}');
      expect(requests, 1);
      expect(File(done.finalPath!).readAsBytesSync(), body);
    } finally {
      await server.close(force: true);
    }
  });

  test('ranges shorter than asked for (without reaching the end) fail instead of looping', () async {
    final body = dashAudio(200 * 1024);
    var requests = 0;
    final (server, client) = await startServer((req) async {
      requests++;
      await serveRanges(req, body, capPieceAt: 1024); // 1 KB pieces of a 200 KB file
    });
    try {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, rangeChunkBytes: (_) => 64 * 1024);
      const id = '1700000000104';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}/tiny.m4a'),
        displayName: 'Tiny',
        suggestedFileName: 'Tiny.m4a',
        kind: 'audio',
        totalBytes: body.length,
      );
      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.failed.name);
      expect(done.errorCode, 'content_range_mismatch');
      expect(requests, 1, reason: 'a mismatch is not retried');
    } finally {
      await server.close(force: true);
    }
  });

  test('only YouTube media hosts are read in ranges by default', () {
    expect(DownloadEngine.defaultRangeChunkBytes(Uri.parse('https://rr3---sn-abc.googlevideo.com/videoplayback')),
        DownloadEngine.youtubeRangeChunkBytes);
    expect(DownloadEngine.defaultRangeChunkBytes(Uri.parse('https://googlevideo.com/x')),
        DownloadEngine.youtubeRangeChunkBytes);
    expect(DownloadEngine.defaultRangeChunkBytes(Uri.parse('https://googlevideo.com.evil.example/x')), isNull);
    expect(DownloadEngine.defaultRangeChunkBytes(Uri.parse('https://example.com/song.mp3')), isNull);
  });

  test('the queued kind only re-labels containers that hold both audio and video', () {
    expect(DownloadEngine.applyKindHint('video/mp4', 'audio'), 'audio/mp4');
    expect(DownloadEngine.applyKindHint('video/webm', 'audio'), 'audio/webm');
    expect(DownloadEngine.applyKindHint('video/mp4', 'video'), 'video/mp4');
    expect(DownloadEngine.applyKindHint('video/mp4', null), 'video/mp4');
    expect(DownloadEngine.applyKindHint('audio/mpeg', 'video'), 'audio/mpeg');
    expect(DownloadEngine.applyKindHint(null, 'audio'), isNull);
    expect(DownloadEngine.extensionForMime('audio/webm'), 'webm');
  });
}
