// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// The equalizer's presets and saved settings, and the Android Auto browse
// tree (Songs, Albums, Playlists, Favourites; a picked song plays its list).
import 'package:audio_service/audio_service.dart' as svc;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/music_player/auto_browse.dart';
import 'package:mediahub/features/music_player/equalizer/audio_effects.dart';

void main() {
  group('equalizer', () {
    test('presets spread over the phone\'s bands and stay in range', () {
      final bass = EqualizerPreset.named('Bass boost')!;
      final five = [for (var i = 0; i < 5; i++) bass.gainFor(i, 5, min: -15, max: 15)];
      expect(five, [6, 4, 0, 0, 0]);
      final ten = [for (var i = 0; i < 10; i++) bass.gainFor(i, 10, min: -15, max: 15)];
      expect(ten.first, 6);
      expect(ten.last, 0);
      expect(ten[1], closeTo(5.11, 0.01));
      expect(bass.gainFor(0, 5, min: -3, max: 3), 3);
      expect(EqualizerPreset.named('Flat')!.gainFor(0, 1, min: -15, max: 15), 0);
    });

    test('custom gains are used only for the same band count', () {
      const s = EqualizerSettings(enabled: true, preset: 'Custom', customGains: [1, 2, 3, 4, 5]);
      expect(s.gainsFor(5, min: -15, max: 15), [1, 2, 3, 4, 5]);
      expect(s.gainsFor(5, min: -2, max: 2), [1, 2, 2, 2, 2]);
      // Another phone (other bands): falls back to Flat.
      expect(s.gainsFor(3, min: -15, max: 15), [0, 0, 0]);
    });

    test('saved and loaded; damaged values are ignored', () async {
      final store = SettingsStore.forTesting();
      await const EqualizerSettings(enabled: true, preset: 'Custom', customGains: [1.5, -2], loudnessDb: 4).save(store);
      final back = EqualizerSettings.load(store);
      expect(back.enabled, isTrue);
      expect(back.preset, 'Custom');
      expect(back.customGains, [1.5, -2]);
      expect(back.loudnessDb, 4);

      await store.setString(EqualizerSettings.presetKey, 'Nonsense');
      await store.setString(EqualizerSettings.loudnessKey, '99');
      await store.setString(EqualizerSettings.customKey, '1,abc,NaN,500');
      final bad = EqualizerSettings.load(store);
      expect(bad.preset, 'Flat');
      expect(bad.loudnessDb, EqualizerSettings.maxLoudnessDb);
      expect(bad.customGains, [1]);
    });

    test('the iPhone gets no equalizer (no audio pipeline)', () {
      PlatformInfo.debugIsAndroid = false;
      PlatformInfo.debugIsIOS = true;
      addTearDown(PlatformInfo.resetForTests);
      expect(AudioEffects.supported, isFalse);
      expect(AudioEffects.instance.pipeline, isNull);
    });
  });

  group('Android Auto browse tree', () {
    late AppDatabase db;
    late LibraryRepositoryImpl repo;
    late AutoBrowseTree tree;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepositoryImpl(db);
      tree = AutoBrowseTree(repo);
      final now = DateTime(2026, 11, 1);
      Future<void> add(String id, String title, {String type = 'audio', bool fav = false, String? album, String avail = 'available', String source = 'device'}) =>
          db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
                id: id,
                uri: 'content://media/external/$type/media/$id',
                mediaType: type,
                title: title,
                artist: const Value('Artist'),
                album: Value(album),
                durationMs: 1000,
                sizeBytes: 1,
                dateAdded: now,
                availability: Value(avail),
                source: Value(source),
                isFavorite: Value(fav),
                favoritedAt: fav ? Value(now) : const Value.absent(),
              ));
      await add('a1', 'Alpha', album: 'Hits', fav: true);
      await add('a2', 'Beta', album: 'Hits');
      await add('a3', 'Gamma (gone)', avail: 'missing', fav: true);
      await add('v1', 'Clip', type: 'video', fav: true);
      final pl = await repo.createPlaylist('Road trip');
      await repo.addSongToPlaylist(pl.id, 'a2');
    });

    tearDown(() => db.close());

    svc.MediaItem session(MediaItem s, String id) => svc.MediaItem(id: id, title: s.title);

    test('root: four folders, none playable', () async {
      final root = await tree.children(svc.AudioService.browsableRootId, session);
      expect(root.map((m) => m.title), ['Songs', 'Albums', 'Playlists', 'Favourites']);
      expect(root.every((m) => m.playable == false), isTrue);
      expect(AutoBrowseTree.rootExtras[svc.AndroidContentStyle.supportedKey], isTrue);
    });

    test('songs and favourites: only playable songs, ids name their list', () async {
      final songs = await tree.children(AutoBrowseTree.songsId, session);
      expect(songs.map((m) => m.id), ['songs|a1', 'songs|a2']);
      final favs = await tree.children(AutoBrowseTree.favouritesId, session);
      expect(favs.map((m) => m.id), ['favourites|a1']);
    });

    test('albums and playlists open into their songs', () async {
      final albums = await tree.children(AutoBrowseTree.albumsId, session);
      final hits = albums.firstWhere((a) => a.title == 'Hits');
      expect(hits.playable, isFalse);
      final inAlbum = await tree.children(hits.id, session);
      expect(inAlbum.map((m) => m.id.split('|').last), unorderedEquals(['a1', 'a2']));
      final playlists = await tree.children(AutoBrowseTree.playlistsId, session);
      expect(playlists.single.title, 'Road trip');
      final inPl = await tree.children(playlists.single.id, session);
      expect(inPl.single.id, '${playlists.single.id}|a2');
      expect((await tree.songsOf(playlists.single.id))!.single.id, 'a2');
    });

    test('split and unknown folders', () async {
      expect(AutoBrowseTree.split('songs|a1'), ('songs', 'a1'));
      expect(AutoBrowseTree.split('playlist:p|1|x'), ('playlist:p', '1|x'));
      expect(AutoBrowseTree.split('a1'), isNull);
      expect(AutoBrowseTree.split('|a1'), isNull);
      expect(await tree.children('nope', session), isEmpty);
      expect(await tree.songsOf('nope'), isNull);
    });
  });
}
