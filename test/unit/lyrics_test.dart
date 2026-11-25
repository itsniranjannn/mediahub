// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// Lyrics: the LRC parser, the embedded tag reader (ID3 USLT, FLAC Vorbis,
// MP4 ©lyr), the lookup order (.lrc, file, LRCLIB) and LRCLIB's request
// and host allowlist.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/music_player/lyrics/embedded_lyrics_reader.dart';
import 'package:mediahub/features/music_player/lyrics/lyrics.dart';
import 'package:mediahub/features/music_player/lyrics/lyrics_repository.dart';
import 'package:path/path.dart' as p;

import 'save_to_phone_test.dart' show FakePhoneMedia;

MediaItem _item(String uri, {String title = 'Resham Firiri', String id = 'dl_1'}) => MediaItem(
      id: id,
      uri: uri,
      mediaType: MediaType.audio,
      title: title,
      artist: 'Bipana Thapa',
      album: 'Lok Geet',
      durationMs: 201400,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      source: 'download',
    );

class _FakeLrclib extends LrclibClient {
  _FakeLrclib(this.answer);
  final String? answer;
  int calls = 0;

  @override
  Future<String?> fetch(MediaItem item) async {
    calls++;
    return answer;
  }
}

Uint8List _syncsafe(int n) =>
    Uint8List.fromList([(n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f]);

Uint8List _be32(int n) => Uint8List.fromList([(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]);

Uint8List _le32(int n) => Uint8List.fromList([n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]);

/// An ID3v2.4 tag with one UTF-8 USLT frame, then a few "audio" bytes.
Uint8List _id3WithLyrics(String text) {
  final frameBody = BytesBuilder()
    ..addByte(3) // UTF-8
    ..add(ascii.encode('eng'))
    ..add(utf8.encode('desc'))
    ..addByte(0)
    ..add(utf8.encode(text));
  final body = frameBody.takeBytes();
  final frame = BytesBuilder()
    ..add(ascii.encode('TIT2'))
    ..add(_syncsafe(3))
    ..add([0, 0])
    ..add([3, 0x41, 0x42])
    ..add(ascii.encode('USLT'))
    ..add(_syncsafe(body.length))
    ..add([0, 0])
    ..add(body);
  final frames = frame.takeBytes();
  return (BytesBuilder()
        ..add(ascii.encode('ID3'))
        ..add([4, 0, 0])
        ..add(_syncsafe(frames.length))
        ..add(frames)
        ..add(List.filled(32, 0xff)))
      .takeBytes();
}

Uint8List _flacWithLyrics(String text) {
  final vendor = utf8.encode('test');
  final entry = utf8.encode('LYRICS=$text');
  final title = utf8.encode('TITLE=x');
  final block = (BytesBuilder()
        ..add(_le32(vendor.length))
        ..add(vendor)
        ..add(_le32(2))
        ..add(_le32(title.length))
        ..add(title)
        ..add(_le32(entry.length))
        ..add(entry))
      .takeBytes();
  return (BytesBuilder()
        ..add(ascii.encode('fLaC'))
        // STREAMINFO (type 0, 34 bytes)
        ..add([0, 0, 0, 34])
        ..add(List.filled(34, 0))
        // VORBIS_COMMENT, last block
        ..add([0x80 | 4, (block.length >> 16) & 0xff, (block.length >> 8) & 0xff, block.length & 0xff])
        ..add(block))
      .takeBytes();
}

Uint8List _box(String type, List<int> payload) =>
    (BytesBuilder()..add(_be32(payload.length + 8))..add(latin1.encode(type))..add(payload)).takeBytes();

Uint8List _mp4WithLyrics(String text) {
  final data = _box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(text)]);
  final lyr = _box('©lyr', data);
  final ilst = _box('ilst', lyr);
  final meta = _box('meta', [0, 0, 0, 0, ...ilst]);
  final udta = _box('udta', meta);
  final moov = _box('moov', [..._box('mvhd', List.filled(8, 0)), ...udta]);
  return (BytesBuilder()..add(_box('ftyp', ascii.encode('M4A mp42')))..add(_box('mdat', [1, 2, 3]))..add(moov))
      .takeBytes();
}

void main() {
  group('LRC', () {
    test('timed lines, several stamps on one line, sorted', () {
      final l = Lyrics.parse(
        '[ar:Bipana]\n[ti:Resham]\n[00:12.50]Resham firiri\n[00:05.00][00:20]Udera jaula\n\n',
        source: LyricsSource.sidecar,
      )!;
      expect(l.isSynced, isTrue);
      expect(l.lines, [
        const LyricsLine(Duration(seconds: 5), 'Udera jaula'),
        const LyricsLine(Duration(milliseconds: 12500), 'Resham firiri'),
        const LyricsLine(Duration(seconds: 20), 'Udera jaula'),
      ]);
      expect(l.lineAt(Duration.zero), -1);
      expect(l.lineAt(const Duration(seconds: 13)), 1);
      expect(l.lineAt(const Duration(minutes: 9)), 2);
    });

    test('offset moves the lines, three-digit fractions read as ms', () {
      final l = Lyrics.parse('[offset:+500]\n[01:00.250]a\n[00:00.10]b', source: LyricsSource.online)!;
      expect(l.lines.map((e) => e.time), [Duration.zero, const Duration(milliseconds: 59750)]);
    });

    test('plain text stays plain', () {
      final l = Lyrics.parse('First line\r\nSecond line\n', source: LyricsSource.embedded)!;
      expect(l.isSynced, isFalse);
      expect(l.lines.map((e) => e.text), ['First line', 'Second line']);
      expect(l.lineAt(const Duration(seconds: 3)), -1);
    });

    test('nothing to show: null', () {
      expect(Lyrics.parse('', source: LyricsSource.sidecar), isNull);
      expect(Lyrics.parse('[ar:x]\n[ti:y]', source: LyricsSource.sidecar), isNull);
    });
  });

  group('embedded', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('lyrics'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<String?> readOf(String name, Uint8List bytes) {
      final f = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
      return const EmbeddedLyricsReader().read(f.path);
    }

    test('ID3 USLT (UTF-8, Devanagari)', () async {
      expect(await readOf('a.mp3', _id3WithLyrics('रेशम फिरिरी\nline 2')), 'रेशम फिरिरी\nline 2');
    });

    test('FLAC LYRICS comment', () async {
      expect(await readOf('a.flac', _flacWithLyrics('[00:01.00]hi')), '[00:01.00]hi');
    });

    test('MP4 ©lyr', () async {
      expect(await readOf('a.m4a', _mp4WithLyrics('plain words')), 'plain words');
    });

    test('damaged or unknown files give null', () async {
      expect(await readOf('x.mp3', Uint8List.fromList([0x49, 0x44, 0x33, 4, 0, 0, 0x7f, 0x7f, 0x7f, 0x7f, 1, 2])),
          isNull);
      expect(await readOf('y.bin', Uint8List.fromList(List.filled(40, 7))), isNull);
      expect(await const EmbeddedLyricsReader().read(p.join(dir.path, 'missing.mp3')), isNull);
    });
  });

  group('lookup', () {
    late Directory dir;
    late Directory cache;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('lyrics_lookup');
      cache = Directory(p.join(dir.path, 'cache'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    LyricsRepository repo(_FakeLrclib lrclib, {bool online = true}) => LyricsRepository(
          phoneMedia: FakePhoneMedia(),
          lrclib: lrclib,
          onlineEnabled: () => online,
          cacheDir: () async => cache,
        );

    test('a .lrc next to the file wins over the tag and LRCLIB', () async {
      final song = File(p.join(dir.path, 'song.mp3'))..writeAsBytesSync(_id3WithLyrics('from tag'));
      File(p.join(dir.path, 'song.lrc')).writeAsStringSync('[00:01.00]from lrc');
      final lrclib = _FakeLrclib('[00:01.00]online');
      final l = (await repo(lrclib).find(_item(song.path)))!;
      expect(l.source, LyricsSource.sidecar);
      expect(l.lines.single.text, 'from lrc');
      expect(lrclib.calls, 0);
    });

    test('the tag before LRCLIB', () async {
      final song = File(p.join(dir.path, 'song.mp3'))..writeAsBytesSync(_id3WithLyrics('from tag'));
      final lrclib = _FakeLrclib('online');
      final l = (await repo(lrclib).find(_item(song.path)))!;
      expect(l.source, LyricsSource.embedded);
      expect(lrclib.calls, 0);
    });

    test('LRCLIB only when turned on; its answer is kept and asked once', () async {
      final song = File(p.join(dir.path, 'plain.mp3'))..writeAsBytesSync([1, 2, 3]);
      final off = _FakeLrclib('[00:02.00]online');
      expect(await repo(off, online: false).find(_item(song.path)), isNull);
      expect(off.calls, 0);

      final on = _FakeLrclib('[00:02.00]online');
      final r = repo(on);
      final l = (await r.find(_item(song.path)))!;
      expect(l.source, LyricsSource.online);
      expect(l.isSynced, isTrue);
      expect((await r.find(_item(song.path)))!.lines.single.text, 'online');
      expect(on.calls, 1);
      // Kept on the phone: shown even with the switch off later.
      expect((await repo(_FakeLrclib(null), online: false).find(_item(song.path))), isNotNull);
    });

    test('LRCLIB without an answer is not asked again this session', () async {
      final song = File(p.join(dir.path, 'plain.mp3'))..writeAsBytesSync([1, 2, 3]);
      final none = _FakeLrclib(null);
      final r = repo(none);
      expect(await r.find(_item(song.path)), isNull);
      expect(await r.find(_item(song.path)), isNull);
      expect(none.calls, 1);
    });

    test('the online cache keeps only the newest files', () async {
      cache.createSync(recursive: true);
      for (var i = 0; i < 6; i++) {
        File(p.join(cache.path, 'f$i.lrc'))
          ..writeAsStringSync('x')
          ..setLastModifiedSync(DateTime(2026, 1, 1 + i));
      }
      File(p.join(cache.path, 'keep.txt')).writeAsStringSync('not lyrics');
      final r = repo(_FakeLrclib(null));
      expect(await r.pruneCache(keep: 4), 2);
      final left = cache.listSync().map((e) => p.basename(e.path)).toSet();
      expect(left, {'f2.lrc', 'f3.lrc', 'f4.lrc', 'f5.lrc', 'keep.txt'});
      expect(LyricsRepository.maxCachedLyrics, 500);
    });

    test('forget deletes the cached online lyrics of a song', () async {
      final song = File(p.join(dir.path, 'plain.mp3'))..writeAsBytesSync([1, 2, 3]);
      final r = repo(_FakeLrclib('[00:02.00]online'));
      await r.find(_item(song.path));
      expect(cache.listSync().whereType<File>(), hasLength(1));
      await r.forget(_item(song.path));
      expect(cache.listSync().whereType<File>(), isEmpty);
      await r.forget(_item(song.path)); // nothing there: no throw
    });

    test('Online items are never looked up', () async {
      final lrclib = _FakeLrclib('x');
      final item = MediaItem(
        id: 'yt_abc',
        uri: 'https://www.youtube.com/watch?v=abc',
        mediaType: MediaType.video,
        title: 'x',
        durationMs: 0,
        sizeBytes: 0,
        dateAdded: DateTime(2026),
        source: 'online',
      );
      expect(await repo(lrclib).find(item), isNull);
      expect(lrclib.calls, 0);
    });
  });

  group('LRCLIB', () {
    test('request: https lrclib.net /api/get with the song details', () {
      final uri = LrclibClient.requestFor(_item('/x.mp3'))!;
      expect(uri.scheme, 'https');
      expect(uri.host, 'lrclib.net');
      expect(uri.path, '/api/get');
      expect(uri.queryParameters, {
        'track_name': 'Resham Firiri',
        'artist_name': 'Bipana Thapa',
        'album_name': 'Lok Geet',
        'duration': '201',
      });
      expect(LrclibClient.requestFor(_item('/x.mp3', title: 'Unknown Title')), isNull);
    });

    test('an answer from another host (a redirect) is refused', () async {
      final client = LrclibClient(http: _RedirectingClient());
      expect(await client.fetch(_item('/x.mp3')), isNull);
    });

    test('synced lyrics are preferred over plain', () async {
      final client = LrclibClient(http: _AnsweringClient('{"plainLyrics":"p","syncedLyrics":"[00:01.00]s"}'));
      expect(await client.fetch(_item('/x.mp3')), '[00:01.00]s');
      final plain = LrclibClient(http: _AnsweringClient('{"plainLyrics":"p","syncedLyrics":null}'));
      expect(await plain.fetch(_item('/x.mp3')), 'p');
    });

    test('cleanTitle strips YouTube/video suffixes and ignores Unknown artist', () {
      expect(
        LrclibClient.cleanTitle('"Safarnama" Video Song | Tamasha | Ranbir Kapoor'),
        'Safarnama',
      );
      expect(
        LrclibClient.cleanTitle("'AGAR TUM SAATH HO' Full VIDEO song (Official)"),
        'AGAR TUM SAATH HO',
      );
      final req = LrclibClient.requestFor(MediaItem(
        id: 'id',
        uri: '/x.mp3',
        mediaType: MediaType.audio,
        title: 'DHUN',
        artist: 'Unknown artist',
        durationMs: 180000,
        sizeBytes: 1,
        dateAdded: DateTime(2026),
      ))!;
      expect(req.queryParameters.containsKey('artist_name'), isFalse);
    });

    test('falls back to /api/search when /api/get returns 404', () async {
      final client = LrclibClient(http: _SearchFallbackClient());
      final item = _item('/x.mp3', title: '"Safarnama" Video Song | Tamasha');
      expect(await client.fetch(item), '[00:10.00]safarnama');
    });
  });
}

class _SearchFallbackClient extends SafeHttpClient {
  @override
  Future<SafeHttpResponse> request(Uri initialUri,
      {String method = 'GET', Map<String, String>? headers, List<int>? body, int? maxBodySize = 1024 * 1024}) async {
    if (initialUri.path == '/api/get') {
      return SafeHttpResponse(
        statusCode: 404,
        reasonPhrase: 'Not Found',
        headers: _Headers(),
        bodyBytes: Uint8List(0),
        finalUri: initialUri,
      );
    }
    return SafeHttpResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      headers: _Headers(),
      bodyBytes: Uint8List.fromList(utf8.encode(
        '[{"duration":201,"plainLyrics":"p","syncedLyrics":"[00:10.00]safarnama"}]',
      )),
      finalUri: initialUri,
    );
  }
}

class _AnsweringClient extends SafeHttpClient {
  _AnsweringClient(this.body);
  final String body;

  @override
  Future<SafeHttpResponse> request(Uri initialUri,
          {String method = 'GET', Map<String, String>? headers, List<int>? body, int? maxBodySize = 1024 * 1024}) async =>
      SafeHttpResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: _Headers(),
        bodyBytes: Uint8List.fromList(utf8.encode(this.body)),
        finalUri: initialUri,
      );
}

class _RedirectingClient extends SafeHttpClient {
  @override
  Future<SafeHttpResponse> request(Uri initialUri,
          {String method = 'GET', Map<String, String>? headers, List<int>? body, int? maxBodySize = 1024 * 1024}) async =>
      SafeHttpResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: _Headers(),
        bodyBytes: Uint8List.fromList(utf8.encode('{"syncedLyrics":"[00:01.00]evil"}')),
        finalUri: Uri.https('evil.example', '/api/get'),
      );
}

class _Headers extends Mock implements HttpHeaders {}
