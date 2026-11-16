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

/// A resume whose part file already holds the whole file (the app stopped, or
/// an error happened, while finalizing) gets "416 Range Not Satisfiable" from a
/// server that honours ranges. That must finish the download, not fail it.
void main() {
  HttpOverrides.global = null;

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('download_resume_complete_test_');
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

  Uint8List mp3Bytes(int length) {
    final bytes = Uint8List(length);
    bytes[0] = 0x49; // "ID3"
    bytes[1] = 0x44;
    bytes[2] = 0x33;
    return bytes;
  }

  test('416 with a total equal to the part size completes the download', () async {
    const size = 64 * 1024;
    final ranges = <String?>[];
    final (server, client) = await startServer((req) async {
      ranges.add(req.headers.value(HttpHeaders.rangeHeader));
      req.response.statusCode = 416;
      req.response.headers.set('content-range', 'bytes */$size');
      await req.response.close();
    });
    try {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir);
      const id = '1700000000777';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}/song.mp3'),
        displayName: 'Song',
        suggestedFileName: 'song.mp3',
      );
      File(p.join(tempDir.path, '$id.part')).writeAsBytesSync(mp3Bytes(size), flush: true);

      await engine.runTask(id);

      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
      expect(ranges.single, 'bytes=$size-', reason: 'it asked to resume at the end');
      expect(row.state, DownloadTaskState.completed.name);
      expect(row.finalPath, isNotNull);
      expect(File(row.finalPath!).lengthSync(), size);
      expect(File(p.join(tempDir.path, '$id.part')).existsSync(), isFalse);
    } finally {
      await server.close(force: true);
    }
  });

  test('416 with a different total still fails (the file changed on the server)', () async {
    const partSize = 64 * 1024;
    final (server, client) = await startServer((req) async {
      req.response.statusCode = 416;
      req.response.headers.set('content-range', 'bytes */${partSize - 10}');
      await req.response.close();
    });
    try {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir);
      const id = '1700000000778';
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}/song.mp3'),
        displayName: 'Song',
        suggestedFileName: 'song.mp3',
      );
      File(p.join(tempDir.path, '$id.part')).writeAsBytesSync(mp3Bytes(partSize), flush: true);

      await engine.runTask(id);

      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
      expect(row.state, DownloadTaskState.failed.name);
      expect(row.errorCode, 'http_416');
      expect(File(p.join(tempDir.path, '$id.part')).existsSync(), isTrue, reason: 'bytes are kept');
    } finally {
      await server.close(force: true);
    }
  });
}
