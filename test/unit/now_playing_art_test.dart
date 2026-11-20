import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';

import 'fake_audio_player.dart';

MediaItem _song(int n, {String? artworkPath, String? uri}) => MediaItem(
      id: 'song_$n',
      uri: uri ?? 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: 'Song $n',
      artist: 'Artist',
      durationMs: 200000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      artworkPath: artworkPath,
    );

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 0xFF, 0xD9]);
const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late Directory cache;
  late Map<String, Uint8List?> embedded;
  late List<String> lookups;

  NowPlayingArt resolver() => NowPlayingArt(
        cacheDirectory: () async => cache,
        embeddedArt: (uri) async {
          lookups.add(uri);
          return embedded[uri];
        },
      );

  setUp(() {
    cache = Directory.systemTemp.createTempSync('np_art_test');
    embedded = {};
    lookups = [];
    ArtworkService.instance.clearCache();
  });

  tearDown(() {
    try {
      cache.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the cover the media session can open', () {
    test('F1: a phone (content://) song ends with a file:// cover holding its art', () async {
      final song = _song(1);
      embedded[song.uri] = _jpeg;
      final art = resolver();
      expect(art.peek(song), isNull, reason: 'nothing known before the lookup');

      final uri = await art.resolve(song);
      expect(uri, isNotNull);
      expect(uri!.scheme, 'file');
      expect(File(uri.toFilePath()).readAsBytesSync(), _jpeg);
      expect(uri.toFilePath(), contains('${Platform.pathSeparator}${NowPlayingArt.folderName}${Platform.pathSeparator}'));
      expect(art.peek(song), uri, reason: 'known at once afterwards');

      // Written once: a new resolver (app restart) finds the file.
      final again = await resolver().resolve(song);
      expect(again, uri);
      expect(lookups, [song.uri], reason: 'the cover was read once');
    });

    test('F1: a song without a cover gets its Bijuli placeholder as a PNG, shared per gradient', () async {
      final art = resolver();
      final a = _song(1);
      // Another song with the same placeholder gradient.
      final twin = List.generate(400, (i) => _song(100 + i)).firstWhere((s) =>
          ArtworkPlaceholder.paletteIndexFor(s.uri) == ArtworkPlaceholder.paletteIndexFor(a.uri));
      final uriA = await art.resolve(a);
      final uriB = await art.resolve(twin);
      expect(uriA, isNotNull);
      expect(uriA!.scheme, 'file');
      final bytes = File(uriA.toFilePath()).readAsBytesSync();
      expect(bytes.take(8), _pngSignature);
      expect(bytes.length, greaterThan(1000), reason: 'a real 512 px picture');
      expect(uriB, uriA, reason: 'one file per palette gradient');
    });

    test('a rescan (clearNegativeCache) looks for a real cover again', () async {
      final art = resolver();
      final song = _song(7);
      final placeholder = await art.resolve(song);
      expect(placeholder!.path, contains('placeholder_'));
      embedded[song.uri] = _jpeg; // the file got a cover since
      expect(art.peek(song), placeholder, reason: 'still the remembered answer');
      ArtworkService.instance.clearNegativeCache();
      expect(art.peek(song), isNull);
      final cover = await art.resolve(song);
      expect(cover!.path, isNot(contains('placeholder_')));
      expect(File(cover.toFilePath()).readAsBytesSync(), _jpeg);
    });

    test('downloads and online songs keep their own picture, without a lookup', () async {
      final art = resolver();
      final online = _song(2, artworkPath: 'https://i.ytimg.com/vi/x/hqdefault.jpg');
      final download = _song(3, artworkPath: '/data/user/0/app/files/thumbs/3.jpg');
      expect(art.peek(online).toString(), 'https://i.ytimg.com/vi/x/hqdefault.jpg');
      expect(art.peek(download), Uri.file('/data/user/0/app/files/thumbs/3.jpg'));
      expect(await art.resolve(online), art.peek(online));
      expect(lookups, isEmpty);
    });

    test('no cache folder: no cover, no error', () async {
      final art = NowPlayingArt(cacheDirectory: () async => null, embeddedArt: (_) async => _jpeg);
      expect(await art.resolve(_song(1)), isNull);
    });

    test('file names are safe and unique per id', () {
      final a = NowPlayingArt.fileNameFor('content://media/external/audio/media/12');
      final b = NowPlayingArt.fileNameFor('content:__media_external_audio_media_12');
      expect(a, matches(RegExp(r'^[A-Za-z0-9._-]+\.jpg$')));
      expect(a, isNot(b), reason: 'the hash keeps ids that sanitise alike apart');
      expect(NowPlayingArt.fileNameFor('x' * 500).length, lessThan(100));
    });
  });

  group('the handler sends it to the notification', () {
    test('F1: the current song (and the next) carry a file:// cover in the session', () async {
      final songs = [_song(1), _song(2), _song(3)];
      embedded[songs[0].uri] = _jpeg;
      final player = FakeAudioPlayer();
      final handler = MusicAudioHandler(player: player, art: resolver());
      addTearDown(handler.dispose);

      await handler.loadQueue(songs, autoPlay: false);
      // Shown at once (no cover yet), then again with the cover.
      for (var i = 0; i < 20 && handler.mediaItem.value?.artUri == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final item = handler.mediaItem.value!;
      expect(item.id, 'song_1');
      expect(item.artUri, isNotNull, reason: 'artUri was null for phone songs');
      expect(item.artUri!.scheme, 'file');
      expect(File(item.artUri!.toFilePath()).readAsBytesSync(), _jpeg);

      // The next song is looked up ahead, so a skip shows its cover at once.
      for (var i = 0; i < 20 && handler.queue.value[1].artUri == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(handler.queue.value[0].artUri, item.artUri);
      expect(handler.queue.value[1].artUri, isNotNull, reason: 'the next song: its placeholder');
      expect(handler.queue.value[2].artUri, isNull, reason: 'only the current and the next are looked up');

      await handler.skipToNext();
      expect(handler.mediaItem.value!.id, 'song_2');
      expect(handler.mediaItem.value!.artUri, isNotNull, reason: 'known before the skip');
      expect(handler.mediaItem.value!.artUri!.path, contains('placeholder_'));
    });
  });
}
