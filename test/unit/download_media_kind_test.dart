import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/media_kind_classifier.dart';
import 'package:mediahub/core/downloads/media_sniffer.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:path/path.dart' as p;

import 'test_safe_http_client_seam.dart';

/// Video downloads stay in Videos and audio downloads in Music: the file's
/// own tracks decide, not the server's word or the first bytes.

// ------------------------------------------------------------ tiny files

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _box(String type, List<int> payload) => [..._u32(8 + payload.length), ...ascii.encode(type), ...payload];
List<int> _ftyp(String brand) => _box('ftyp', [...ascii.encode(brand), ..._u32(0), ...ascii.encode(brand), ...ascii.encode('mp41')]);
List<int> _hdlr(String handler) =>
    _box('hdlr', [0, 0, 0, 0, ..._u32(0), ...ascii.encode(handler), ...List.filled(12, 0), ...ascii.encode('h'), 0]);
List<int> _tkhd(int id) => _box('tkhd', [0, 0, 0, 3, ..._u32(0), ..._u32(0), ..._u32(id), ...List.filled(68, 0)]);
List<int> _trak(int id, String handler, {List<int> chapters = const []}) => _box('trak', [
      ..._tkhd(id),
      if (chapters.isNotEmpty) ..._box('tref', _box('chap', [for (final c in chapters) ..._u32(c)])),
      ..._box('mdia', [..._box('mdhd', List.filled(24, 0)), ..._hdlr(handler), ..._box('minf', List.filled(16, 0))]),
    ]);
List<int> _moov(List<List<int>> traks) => _box('moov', [..._box('mvhd', List.filled(100, 0)), for (final t in traks) ...t]);
List<int> _mdat(int n) => _box('mdat', List.filled(n, 0x11));

/// An MP4 / M4A whose track list holds [handlers] ('soun', 'vide').
Uint8List _mp4(List<String> handlers, {String brand = 'isom', bool moovLast = false}) {
  final moov = _moov([for (var i = 0; i < handlers.length; i++) _trak(i + 1, handlers[i])]);
  return Uint8List.fromList(moovLast ? [..._ftyp(brand), ..._mdat(4096), ...moov] : [..._ftyp(brand), ...moov, ..._mdat(4096)]);
}

List<int> _ebml(List<int> id, List<int> payload) {
  final n = payload.length;
  return [...id, 0x01, 0, (n >> 40) & 0xFF, (n >> 32) & 0xFF, (n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF, ...payload];
}

/// A WebM / MKV file with tracks of [types] (1 video, 2 audio).
Uint8List _matroska(List<int> types, {String docType = 'webm', bool tracks = true}) {
  final header = _ebml([0x1A, 0x45, 0xDF, 0xA3], _ebml([0x42, 0x82], ascii.encode(docType)));
  final entries = [
    for (var i = 0; i < types.length; i++) ..._ebml([0xAE], [..._ebml([0xD7], [i + 1]), ..._ebml([0x83], [types[i]])]),
  ];
  final segment = _ebml([0x18, 0x53, 0x80, 0x67], [
    ..._ebml([0x15, 0x49, 0xA9, 0x66], List.filled(20, 0)),
    if (tracks) ..._ebml([0x16, 0x54, 0xAE, 0x6B], entries),
    ..._ebml([0x1F, 0x43, 0xB6, 0x75], List.filled(2048, 0x22)),
  ]);
  return Uint8List.fromList([...header, ...segment]);
}

/// An Ogg file whose first packet starts with [packet].
Uint8List _ogg(List<int> packet) => Uint8List.fromList([
      ...ascii.encode('OggS'), 0, 2, ...List.filled(8, 0), ...List.filled(4, 1), ...List.filled(4, 0), ...List.filled(4, 0),
      1, packet.length, ...packet, ...List.filled(512, 0),
    ]);

final Uint8List _mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0, 0, 0, 0, 0, 0x0A, ...List.filled(2048, 0xAA)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('download_media_kind_test_');
  });

  tearDown(() {
    PlatformInfo.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File write(String name, List<int> bytes) => File(p.join(tempDir.path, name))..writeAsBytesSync(bytes);

  MediaKindDecision? classify(List<int> bytes, {String name = 'file', String? hint}) =>
      MediaKindClassifier.classifyFile(write(name, bytes), kindHint: hint, fileName: name);

  group('MediaKindClassifier', () {
    test('an MP4 with sound only is a song, whatever its brand or the server said', () {
      for (final brand in ['isom', 'mp42', 'dash', 'M4A ']) {
        final d = classify(_mp4(['soun'], brand: brand), name: 'song.mp4', hint: 'video')!;
        expect(d.isVideo, isFalse, reason: brand);
        expect(d.mimeType, 'audio/mp4', reason: brand);
        expect(d.byContent, isTrue, reason: brand);
      }
    });

    test('an MP4 with pictures and sound is a video, even if queued as audio', () {
      final d = classify(_mp4(['vide', 'soun']), name: 'clip.m4a', hint: 'audio')!;
      expect(d.isVideo, isTrue);
      expect(d.mimeType, 'video/mp4');
      expect(d.kind, 'video');
    });

    test('the track list is found after the media data too (no fast start)', () {
      expect(classify(_mp4(['soun'], moovLast: true))!.isVideo, isFalse);
      expect(classify(_mp4(['vide', 'soun'], moovLast: true))!.isVideo, isTrue);
    });

    test('a 64-bit media data size is skipped, not read', () {
      final bigMdat = [..._u32(1), ...ascii.encode('mdat'), ..._u32(0), ..._u32(16 + 64), ...List.filled(64, 0)];
      final bytes = [..._ftyp('isom'), ...bigMdat, ..._moov([_trak(1, 'soun')])];
      expect(classify(bytes)!.isVideo, isFalse);
    });

    test('chapter pictures in an audiobook or podcast are not video', () {
      final bytes = [
        ..._ftyp('M4A '),
        ..._moov([_trak(1, 'soun', chapters: [2]), _trak(2, 'vide')]),
        ..._mdat(64),
      ];
      final d = classify(bytes, name: 'book.m4b')!;
      expect(d.isVideo, isFalse);
      expect(d.byContent, isTrue);
    });

    test('a QuickTime MOV without ftyp is recognised and read', () {
      final mov = [..._moov([_trak(1, 'vide'), _trak(2, 'soun')]), ..._mdat(64)];
      expect(MediaSniffer.sniff(mov), 'video/quicktime');
      final d = classify(mov, name: 'camera.mov')!;
      expect(d.isVideo, isTrue);
      expect(d.mimeType, 'video/quicktime');
      final qt = [..._ftyp('qt  '), ..._moov([_trak(1, 'vide')])];
      expect(classify(qt)!.mimeType, 'video/quicktime');
      // A filler box first, then the movie: still QuickTime.
      expect(MediaSniffer.sniff([..._box('wide', []), ..._mdat(64)]), 'video/quicktime');
      expect(MediaSniffer.sniff([..._box('free', List.filled(8, 0)), ...mov]), 'video/quicktime');
    });

    // Review finding: any file with "free" or "skip" at bytes 4-7 passed the
    // media check as a QuickTime video.
    test('four letters alone are not a QuickTime file', () {
      final notMedia = [0, 0, 0, 40, ...ascii.encode('free'), ...ascii.encode('this is a text file, not a video....')];
      expect(MediaSniffer.sniff(notMedia), isNull);
      expect(MediaSniffer.sniff([0, 0, 0, 12, ...ascii.encode('skip'), 1, 2, 3, 4, ...List.filled(40, 0x41)]), isNull);
      expect(MediaSniffer.sniff([0, 0, 1, 0, ...ascii.encode('moov'), ...List.filled(40, 0x41)]), isNull,
          reason: 'a moov without its movie header');
    });

    test('a WebM with sound only is a song; with a picture track a video', () {
      final audio = classify(_matroska([2]), name: 'track.webm', hint: 'video')!;
      expect(audio.isVideo, isFalse);
      expect(audio.mimeType, 'audio/webm');
      expect(audio.byContent, isTrue);
      final video = classify(_matroska([1, 2]), name: 'clip.webm', hint: 'audio')!;
      expect(video.isVideo, isTrue);
      expect(video.mimeType, 'video/webm');
    });

    test('an MKV is named as one', () {
      expect(classify(_matroska([1, 2], docType: 'matroska'))!.mimeType, 'video/x-matroska');
      expect(classify(_matroska([2], docType: 'matroska'))!.mimeType, 'audio/x-matroska');
    });

    test('Ogg: Opus or Vorbis is a song, Theora a video', () {
      expect(classify(_ogg(ascii.encode('OpusHead')))!.isVideo, isFalse);
      expect(classify(_ogg([0x01, ...ascii.encode('vorbis')]))!.isVideo, isFalse);
      final theora = classify(_ogg([0x80, ...ascii.encode('theora')]))!;
      expect(theora.isVideo, isTrue);
      expect(theora.mimeType, 'video/ogg');
    });

    test('MP3 is always a song, AVI always a video', () {
      final mp3 = classify(_mp3, name: 'x.mp4', hint: 'video')!;
      expect(mp3.isVideo, isFalse);
      expect(mp3.mimeType, 'audio/mpeg');
      final avi = [...ascii.encode('RIFF'), ..._u32(100), ...ascii.encode('AVI '), ...List.filled(100, 0)];
      expect(MediaSniffer.sniff(avi), 'video/x-msvideo');
      expect(classify(avi, hint: 'audio')!.isVideo, isTrue);
    });

    test('when the file cannot tell, the queued kind decides, then the name', () {
      // An MP4 whose track list is missing (damaged or cut short).
      final noMoov = [..._ftyp('isom'), ..._mdat(64)];
      expect(classify(noMoov, hint: 'audio')!.isVideo, isFalse);
      expect(classify(noMoov, hint: 'audio')!.byContent, isFalse);
      expect(classify(noMoov, name: 'song.m4a')!.isVideo, isFalse);
      expect(classify(noMoov, name: 'clip.mp4')!.isVideo, isTrue);
      final noTracks = _matroska(const [], tracks: false);
      expect(classify(noTracks, name: 'song.weba')!.isVideo, isFalse);
      expect(classify(noTracks, name: 'clip.webm')!.isVideo, isTrue);
    });

    test('not media: no decision', () {
      expect(classify(utf8.encode('<!doctype html><html><body>Hi</body></html>')), isNull);
      expect(classify(const []), isNull);
      expect(MediaKindClassifier.classifyFile(File(p.join(tempDir.path, 'missing'))), isNull);
    });

    test('a damaged box size never loops or throws', () {
      final bytes = [..._ftyp('isom'), ..._u32(3), ...ascii.encode('moov'), ...List.filled(64, 0)];
      expect(classify(bytes, hint: 'audio')!.isVideo, isFalse);
      final zero = [..._ftyp('isom'), ..._u32(0), ...ascii.encode('moov'), ..._trak(1, 'vide')];
      expect(classify(zero)!.isVideo, isTrue, reason: 'a size of 0 runs to the end of the file');
    });

    test('saved names get a media extension when they have none', () {
      expect(MediaKindClassifier.nameWithMediaExtension('track', 'mp3'), 'track.mp3');
      expect(MediaKindClassifier.nameWithMediaExtension('get.bin', 'mp3'), 'get.mp3');
      expect(MediaKindClassifier.nameWithMediaExtension('download.php', 'mp4'), 'download.mp4');
      expect(MediaKindClassifier.nameWithMediaExtension('Mr.Smith', 'm4a'), 'Mr.Smith.m4a');
      expect(MediaKindClassifier.nameWithMediaExtension('song.mp3', 'mp3'), 'song.mp3');
      expect(MediaKindClassifier.nameWithMediaExtension('song.mp4', 'm4a'), 'song.mp4', reason: 'a media name is kept');
      expect(MediaKindClassifier.nameWithMediaExtension('clip.MKV', 'webm'), 'clip.MKV');
      expect(MediaKindClassifier.nameWithMediaExtension('thing', 'bin'), 'thing', reason: 'nothing better to add');
      expect(MediaKindClassifier.nameWithMediaExtension('.bin', 'mp3'), '.bin.mp3');
    });
  });

  group('DownloadEngine: finished downloads land in the right section', () {
    late AppDatabase db;
    late HttpServer server;
    late SafeHttpClient client;
    final served = <String, (List<int>, String)>{};

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final serverContext = SecurityContext()
        ..useCertificateChain('test/certs/localhost.crt')
        ..usePrivateKey('test/certs/localhost.key');
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((req) async {
        final (data, type) = served[req.uri.path] ?? (const <int>[], 'text/plain');
        req.response.statusCode = data.isEmpty ? 404 : 200;
        req.response.headers.set(HttpHeaders.contentTypeHeader, type);
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
      served.clear();
      await server.close(force: true);
      await db.close();
    });

    Future<(DownloadEntry, MediaItemEntry?)> download(String id, String path, {String? kind, String? name}) async {
      final engine = DownloadEngine(
        db: db,
        httpClient: client,
        downloadDir: tempDir,
        freeSpaceProvider: () async => 1 << 40,
      );
      addTearDown(engine.dispose);
      await engine.enqueueDownload(
        id: id,
        url: Uri.parse('https://localhost:${server.port}$path'),
        displayName: 'Item',
        suggestedFileName: name ?? path.substring(1),
        kind: kind,
      );
      await engine.runTask(id);
      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
      final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('dl_$id'))).getSingleOrNull();
      return (row, media);
    }

    test('a song served as video/mp4 goes to Music', () async {
      served['/song.mp4'] = (_mp4(['soun']), 'video/mp4');
      final (row, media) = await download('1700000000301', '/song.mp4', kind: 'video');
      expect(row.state, DownloadTaskState.completed.name);
      expect(row.kind, 'audio');
      expect(row.mimeType, 'audio/mp4');
      expect(media!.mediaType, 'audio');
      expect(p.basename(row.finalPath!), 'song.mp4', reason: 'a media name is kept');
    });

    test('a video served as audio/mp4 goes to Videos', () async {
      served['/clip.m4a'] = (_mp4(['vide', 'soun']), 'audio/mp4');
      final (row, media) = await download('1700000000302', '/clip.m4a', kind: 'audio');
      expect(row.kind, 'video');
      expect(row.mimeType, 'video/mp4');
      expect(media!.mediaType, 'video');
    });

    test('YouTube-style audio only (dash M4A queued as audio) stays in Music', () async {
      served['/videoplayback'] = (_mp4(['soun'], brand: 'dash'), 'audio/mp4');
      final (row, media) = await download('1700000000303', '/videoplayback', kind: 'audio', name: 'Song (Audio).m4a');
      expect(media!.mediaType, 'audio');
      expect(row.mimeType, 'audio/mp4');
    });

    test('a link without a file extension is saved with the real one', () async {
      served['/get'] = (_mp3, 'application/octet-stream');
      final (row, media) = await download('1700000000304', '/get');
      expect(row.state, DownloadTaskState.completed.name);
      expect(p.basename(row.finalPath!), 'get.mp3');
      expect(row.fileName, 'get.mp3', reason: 'the card shows the real name');
      expect(media!.format, 'mp3');
      expect(media.mediaType, 'audio');
    });

    test('a web page saved by mistake is still refused', () async {
      served['/page'] = (utf8.encode('<!doctype html><html></html>${' ' * 200}'), 'text/html');
      final (row, media) = await download('1700000000305', '/page');
      expect(row.state, DownloadTaskState.failed.name);
      expect(row.errorCode, 'not_media');
      expect(media, isNull);
    });
  });

  group('one-time repair of downloads saved in the wrong section', () {
    late AppDatabase db;
    late DownloadEngine engine;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      engine = DownloadEngine(db: db, httpClient: SafeHttpClient(), downloadDir: tempDir);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    Future<void> addMedia(
      String id,
      String uri,
      String type, {
      String source = 'download',
      String? engine,
      String? formatSelector,
    }) async {
      final now = DateTime(2026, 1, 1);
      await db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
            id: id,
            uri: uri,
            mediaType: type,
            title: id,
            durationMs: 0,
            sizeBytes: 1,
            dateAdded: now,
            source: Value(source),
          ));
      if (source == 'download') {
        await db.into(db.downloadsTable).insert(DownloadsTableCompanion.insert(
              id: id.replaceFirst('dl_', ''),
              url: 'https://example.com/$id',
              host: 'example.com',
              displayName: id,
              fileName: p.basename(uri),
              state: DownloadTaskState.completed.name,
              createdAt: now,
              updatedAt: now,
              kind: Value(type),
              mimeType: Value(type == 'video' ? 'video/mp4' : 'audio/mpeg'),
              finalPath: Value(uri),
              mediaId: Value(id),
              engine: engine == null ? const Value.absent() : Value(engine),
              formatSelector: Value(formatSelector),
            ));
      }
    }

    Future<String> typeOf(String id) async =>
        (await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(id))).getSingle()).mediaType;

    test('a song saved as a video moves to Music, once; nothing else changes', () async {
      final song = write('song.mp4', _mp4(['soun']));
      final video = write('clip.mp4', _mp4(['vide', 'soun']));
      final mp3 = write('tune.mp3', _mp3);
      final unknown = write('cut.mp4', [..._ftyp('isom'), ..._mdat(64)]);
      final outside = await Directory.systemTemp.createTemp('download_media_kind_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final elsewhere = File(p.join(outside.path, 'other.mp4'))..writeAsBytesSync(_mp4(['soun']));

      await addMedia('dl_1700000000401', song.path, 'video');
      await addMedia('dl_1700000000402', video.path, 'video');
      await addMedia('dl_1700000000403', mp3.path, 'audio');
      await addMedia('dl_1700000000404', unknown.path, 'video');
      await addMedia('dl_1700000000405', elsewhere.path, 'video');
      await addMedia('dl_1700000000406', p.join(tempDir.path, 'gone.mp4'), 'video');
      // A video on the phone (MediaStore) is never looked at.
      await addMedia('phone_1', 'content://media/external/video/media/1', 'video', source: 'device');

      expect(await engine.repairLibraryKinds(), 1);
      expect(await typeOf('dl_1700000000401'), 'audio');
      final dl = await (db.select(db.downloadsTable)..where((t) => t.id.equals('1700000000401'))).getSingle();
      expect(dl.kind, 'audio');
      expect(dl.mimeType, 'audio/mp4');

      expect(await typeOf('dl_1700000000402'), 'video');
      expect(await typeOf('dl_1700000000403'), 'audio');
      expect(await typeOf('dl_1700000000404'), 'video', reason: 'the file cannot tell: left as it was');
      expect(await typeOf('dl_1700000000405'), 'video', reason: 'outside the download folder');
      expect(await typeOf('dl_1700000000406'), 'video');
      expect(await typeOf('phone_1'), 'video');
      expect(File(p.join(tempDir.path, DownloadEngine.kindsCheckedMarker)).existsSync(), isTrue);

      // Done once: a later wrong row (impossible now) is not looked at again.
      await (db.update(db.mediaItemsTable)..where((t) => t.id.equals('dl_1700000000401')))
          .write(const MediaItemsTableCompanion(mediaType: Value('video')));
      expect(await engine.repairLibraryKinds(), 0);
      expect(await typeOf('dl_1700000000401'), 'video');
    });

    test('a video saved as a song moves to Videos', () async {
      final video = write('clip.m4a', _mp4(['vide', 'soun']));
      await addMedia('dl_1700000000411', video.path, 'audio');
      expect(await engine.repairLibraryKinds(), 1);
      expect(await typeOf('dl_1700000000411'), 'video');
    });

    // Review finding: "Original audio" on a site with no sound-only file
    // (TikTok, many X, Facebook and Instagram links) saves a file with
    // pictures; the repair moved such songs out of Music (and Liked songs).
    test('a web-link download saved as sound stays in Music, even with a picture track', () async {
      final tiktok = write('dance.mp4', _mp4(['vide', 'soun']));
      await addMedia('dl_x1700000000431', tiktok.path, 'audio', engine: 'extractor', formatSelector: 'ba/b');
      final direct = write('served.m4a', _mp4(['vide', 'soun']));
      await addMedia('dl_1700000000432', direct.path, 'audio');
      expect(await engine.repairLibraryKinds(), 1, reason: 'only the direct-link one moves');
      expect(await typeOf('dl_x1700000000431'), 'audio');
      expect(await typeOf('dl_1700000000432'), 'video');
    });

    test('nothing to repair: the marker is still written, rows untouched', () async {
      final song = write('ok.m4a', _mp4(['soun']));
      await addMedia('dl_1700000000421', song.path, 'audio');
      expect(await engine.repairLibraryKinds(), 0);
      expect(await typeOf('dl_1700000000421'), 'audio');
      expect(File(p.join(tempDir.path, DownloadEngine.kindsCheckedMarker)).existsSync(), isTrue);
    });
  });
}
