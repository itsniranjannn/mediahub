import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/ios_playable_formats.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

import 'test_safe_http_client_seam.dart';

/// iPhone only: files Apple's players cannot open are never saved, and the
/// phone's free space (which nothing on iPhone reports) is never made up.

/// The start of a WebM / MKV file (EBML header) and of an MP3 (ID3 tag).
final Uint8List _webm = Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, ...List.filled(2048, 0x42)]);
final Uint8List _mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0, 0, 0, 0, 0, 0x0A, ...List.filled(2048, 0xAA)]);

const _mediaStore = MethodChannel('mediahub/media_store');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The engine talks to a real local server.
  HttpOverrides.global = null;

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    PlatformInfo.resetForTests();
    messenger.setMockMethodCallHandler(_mediaStore, null);
  });

  void useIPhone() {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
  }

  void useAndroid() {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
  }

  /// Answers the Android free-space call with [bytes] and records each call.
  List<String> answerFreeSpace(int bytes) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(_mediaStore, (call) async {
      calls.add(call.method);
      return call.method == 'freeSpaceBytes' ? bytes : null;
    });
    return calls;
  }

  group('IosPlayableFormats', () {
    test('Ogg, Opus, WebM, MKV and AVI are named by their type', () {
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'video/webm'), 'WebM');
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'audio/webm'), 'WebM');
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'audio/ogg; codecs=opus'), 'Ogg');
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'application/ogg'), 'Ogg');
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'audio/opus'), 'Opus');
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'VIDEO/X-MATROSKA'), 'MKV');
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'video/x-msvideo'), 'AVI');
    });

    test('files iPhone plays are never refused', () {
      for (final mime in [
        'audio/mpeg',
        'audio/mp4',
        'audio/aac',
        'audio/flac',
        'audio/wav',
        'video/mp4',
        'video/quicktime',
      ]) {
        expect(IosPlayableFormats.unplayableFormat(mimeType: mime, fileName: 'x.mkv'), isNull, reason: mime);
      }
    });

    test('the file name decides only when the type says nothing', () {
      expect(IosPlayableFormats.unplayableFormat(mimeType: 'application/octet-stream', fileName: 'Clip.MKV'), 'MKV');
      expect(IosPlayableFormats.unplayableFormat(fileName: 'song.opus'), 'Opus');
      expect(IosPlayableFormats.unplayableFormat(fileName: 'song.oga'), 'Ogg');
      expect(IosPlayableFormats.unplayableFormat(fileName: 'film.avi'), 'AVI');
      expect(IosPlayableFormats.unplayableFormat(fileName: 'song.mp3'), isNull);
      expect(IosPlayableFormats.unplayableFormat(fileName: 'no-extension'), isNull);
      expect(IosPlayableFormats.unplayableFormat(fileName: 'ends-with-dot.'), isNull);
      expect(IosPlayableFormats.unplayableFormat(), isNull);
    });
  });

  group('DownloadEngine', () {
    late AppDatabase db;
    late Directory tempDir;
    late HttpServer server;
    late SafeHttpClient client;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('download_ios_formats_test_');
      final serverContext = SecurityContext()
        ..useCertificateChain('test/certs/localhost.crt')
        ..usePrivateKey('test/certs/localhost.key');
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((req) async {
        final webm = req.uri.path.endsWith('.webm');
        final data = webm ? _webm : _mp3;
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentTypeHeader, webm ? 'video/webm' : 'audio/mpeg');
        req.response.headers.set(HttpHeaders.contentLengthHeader, data.length.toString());
        req.response.add(data);
        await req.response.close();
      });
      client = SafeHttpClient(
        customSecurityContext: SecurityContext()..setTrustedCertificates('test/certs/localhost.crt'),
        seam: const TestSafeHttpClientSeam(),
        dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
      );
    });

    tearDown(() async {
      await server.close(force: true);
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Downloads [path] from the local server with the engine's own free-space
    /// check (no test override) and returns the finished row.
    Future<DownloadEntry> download(String id, String path) async {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir);
      addTearDown(engine.dispose);
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}$path'),
        displayName: 'Clip',
        suggestedFileName: path.substring(1),
      );
      await engine.runTask(id);
      return (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
    }

    List<String> filesLeft() => tempDir.listSync().map((e) => e.uri.pathSegments.last).toList();

    test('iPhone: a WebM file is not saved, and nothing is left behind', () async {
      useIPhone();
      final row = await download('1700000000101', '/clip.webm');

      expect(row.state, DownloadTaskState.failed.name);
      expect(row.errorCode, IosPlayableFormats.errorCode);
      expect(row.finalPath, isNull);
      expect(filesLeft(), isEmpty, reason: 'the partial file is removed');
      expect(await db.select(db.mediaItemsTable).get(), isEmpty, reason: 'nothing unplayable in the library');
    });

    test('iPhone: an MP3 is saved as usual', () async {
      useIPhone();
      final row = await download('1700000000102', '/song.mp3');

      expect(row.state, DownloadTaskState.completed.name, reason: 'error ${row.errorCode}');
      expect((await db.select(db.mediaItemsTable).get()).single.mediaType, 'audio');
    });

    test('Android: the same WebM file is saved, as before', () async {
      useAndroid();
      answerFreeSpace(50 * 1024 * 1024 * 1024);
      final row = await download('1700000000103', '/clip.webm');

      expect(row.state, DownloadTaskState.completed.name, reason: 'error ${row.errorCode}');
      expect(File(row.finalPath!).existsSync(), isTrue);
      expect((await db.select(db.mediaItemsTable).get()).single.mediaType, 'video');
    });

    test('Android: the up-front space check still refuses a too-full phone', () async {
      useAndroid();
      answerFreeSpace(10 * 1024 * 1024); // 10 MB: less than the 200 MB asked for a file of unknown size
      final row = await download('1700000000104', '/song.mp3');

      expect(row.state, DownloadTaskState.failed.name);
      expect(row.errorCode, 'insufficient_disk_space');
    });

    test('iPhone: no made-up space check stops a download (the phone cannot tell)', () async {
      useIPhone();
      // Even a channel that answered "full" is never asked on iPhone.
      final calls = answerFreeSpace(0);
      final row = await download('1700000000105', '/song.mp3');

      expect(row.state, DownloadTaskState.completed.name, reason: 'error ${row.errorCode}');
      expect(calls, isEmpty);
    });
  });

  group('free space', () {
    test('iPhone: unknown (null), not a made-up 10 GB', () async {
      useIPhone();
      final calls = answerFreeSpace(123);
      expect(await DownloadEngine.defaultFreeSpaceProvider(), isNull);
      expect(calls, isEmpty);
    });

    test('Android: the phone answers, as before', () async {
      useAndroid();
      final calls = answerFreeSpace(123456789);
      expect(await DownloadEngine.defaultFreeSpaceProvider(), 123456789);
      expect(calls, ['freeSpaceBytes']);
    });

    Future<StorageInfo> storageInfo() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);
      final sub = container.listen(storageInfoProvider.future, (_, _) {});
      return sub.read();
    }

    test('Downloads screen figures: iPhone shows no free space', () async {
      useIPhone();
      final calls = answerFreeSpace(123);
      final info = await storageInfo();
      expect(info.freeBytes, isNull);
      expect(info.usedBytes, 0);
      expect(calls, isEmpty);
    });

    test('Downloads screen figures: Android shows what the phone says', () async {
      useAndroid();
      answerFreeSpace(5 * 1024 * 1024 * 1024);
      expect((await storageInfo()).freeBytes, 5 * 1024 * 1024 * 1024);
    });
  });
}
