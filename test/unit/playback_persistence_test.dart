import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/playback_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

void main() {
  group('PlaybackState persistence and mapping test', () {
    late AppDatabase db;
    late PlaybackRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = PlaybackRepositoryImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('savePlaybackState and loadLastPlaybackState restores state accurately in paused mode', () async {
      final item = MediaItem(
        id: 'track_123',
        uri: 'file:///storage/emulated/0/Music/track.mp3',
        mediaType: MediaType.audio,
        title: 'Song Title',
        artist: 'Song Artist',
        album: 'Song Album',
        durationMs: 215000,
        sizeBytes: 4096000,
        dateAdded: DateTime(2026, 2, 1, 10, 0),
      );

      await db.into(db.mediaItemsTable).insert(
        MediaItemsTableCompanion.insert(
          id: item.id,
          uri: item.uri,
          mediaType: item.mediaType.name,
          title: item.title,
          artist: Value(item.artist),
          album: Value(item.album),
          durationMs: item.durationMs,
          sizeBytes: item.sizeBytes,
          dateAdded: item.dateAdded,
        ),
      );

      final stateToSave = PlaybackState(
        currentItemId: 'track_123',
        queue: [item],
        queueIndex: 0,
        position: const Duration(seconds: 42),
        duration: const Duration(milliseconds: 215000),
        isPlaying: true, // Playing before saving
        repeatMode: PlaybackRepeatMode.all,
        shuffle: true,
        speed: 1.25,
        updatedAt: DateTime.now(),
      );

      await repo.savePlaybackState(stateToSave);

      final loadedState = await repo.loadLastPlaybackState();
      expect(loadedState, isNotNull);
      expect(loadedState!.currentItemId, 'track_123');
      expect(loadedState.queue.length, 1);
      expect(loadedState.queue.first.title, 'Song Title');
      expect(loadedState.queue.first.artist, 'Song Artist');
      expect(loadedState.queueIndex, 0);
      expect(loadedState.position, const Duration(seconds: 42));
      expect(loadedState.duration, const Duration(milliseconds: 215000));
      // Must restore in a paused state
      expect(loadedState.isPlaying, isFalse);
      expect(loadedState.repeatMode, PlaybackRepeatMode.all);
      expect(loadedState.shuffle, isTrue);
      expect(loadedState.speed, 1.25);
    });
  });

  group('online (Explore) items are never persisted', () {
    MediaItem local(String id, {int durationMs = 1000, String source = 'device'}) => MediaItem(
          id: id,
          uri: 'file:///storage/emulated/0/Music/$id.mp3',
          mediaType: MediaType.audio,
          title: 'Local $id',
          durationMs: durationMs,
          sizeBytes: 1,
          dateAdded: DateTime(2026, 1, 1),
          source: source,
        );
    MediaItem online(String id) => MediaItem(
          id: 'yt_$id',
          uri: 'https://rr3---sn-a5mekn7s.googlevideo.com/videoplayback?id=$id&ip=203.0.113.9&expire=1',
          mediaType: MediaType.audio,
          title: 'Online $id',
          durationMs: 5000,
          sizeBytes: 0,
          dateAdded: DateTime(2026, 1, 1),
          source: 'online',
        );

    PlaybackState stateOf(List<MediaItem> queue, int index,
        {List<MediaItem>? original, Duration position = const Duration(seconds: 30)}) {
      return PlaybackState(
        currentItemId: index >= 0 && index < queue.length ? queue[index].id : null,
        queue: queue,
        originalQueue: original ?? queue,
        queueIndex: index,
        position: position,
        duration: const Duration(seconds: 200),
        repeatMode: PlaybackRepeatMode.all,
        shuffle: true,
        speed: 1.5,
        updatedAt: DateTime(2026, 1, 1),
      );
    }

    List<String> ids(List<MediaItem> items) => items.map((m) => m.id).toList();

    test('a queue without online items is persisted unchanged', () {
      final s = stateOf([local('a'), local('b', source: 'download')], 1);
      expect(identical(PlaybackNotifier.withoutOnlineItems(s), s), isTrue);
    });

    test('online items are dropped and the index follows the current item', () {
      final a = local('a'), b = local('b'), c = local('c');
      final s = stateOf([online('1'), a, online('2'), b, c], 3); // current: b
      final out = PlaybackNotifier.withoutOnlineItems(s);

      expect(ids(out.queue), ['a', 'b', 'c']);
      expect(ids(out.originalQueue), ['a', 'b', 'c']);
      expect(out.queueIndex, 1);
      expect(out.currentItemId, 'b');
      expect(out.currentItem, b);
      // Position, settings: as they were.
      expect(out.position, const Duration(seconds: 30));
      expect(out.duration, const Duration(seconds: 200));
      expect(out.repeatMode, PlaybackRepeatMode.all);
      expect(out.shuffle, isTrue);
      expect(out.speed, 1.5);
    });

    test('the original (unshuffled) order is filtered on its own', () {
      final a = local('a'), b = local('b');
      final o = online('1');
      final s = stateOf([b, o, a], 2, original: [a, o, b]); // shuffled play order
      final out = PlaybackNotifier.withoutOnlineItems(s);
      expect(ids(out.queue), ['b', 'a']);
      expect(ids(out.originalQueue), ['a', 'b']);
      expect(out.queueIndex, 1);
      expect(out.currentItemId, 'a');
    });

    test('an online current item hands over to the next local item, from the start', () {
      final s = stateOf([local('a'), online('1'), online('2'), local('b', durationMs: 7000), local('c')], 1);
      final out = PlaybackNotifier.withoutOnlineItems(s);
      expect(ids(out.queue), ['a', 'b', 'c']);
      expect(out.queueIndex, 1);
      expect(out.currentItemId, 'b');
      expect(out.position, Duration.zero, reason: 'the old position belonged to the online item');
      expect(out.duration, const Duration(milliseconds: 7000));
    });

    test('an online current item at the end falls back to the last local item', () {
      final s = stateOf([local('a'), local('b', durationMs: 4000), online('1')], 2);
      final out = PlaybackNotifier.withoutOnlineItems(s);
      expect(ids(out.queue), ['a', 'b']);
      expect(out.queueIndex, 1);
      expect(out.currentItemId, 'b');
      expect(out.position, Duration.zero);
      expect(out.duration, const Duration(milliseconds: 4000));
    });

    test('an all-online queue is persisted as an empty session', () {
      final s = stateOf([online('1'), online('2')], 0);
      final out = PlaybackNotifier.withoutOnlineItems(s);
      expect(out.queue, isEmpty);
      expect(out.originalQueue, isEmpty);
      expect(out.queueIndex, -1);
      expect(out.currentItemId, isNull);
      expect(out.position, Duration.zero);
    });

    test('no current item: the index stays "none" or is clamped into the queue', () {
      final none = PlaybackNotifier.withoutOnlineItems(stateOf([online('1'), local('a')], -1));
      expect(ids(none.queue), ['a']);
      expect(none.queueIndex, -1);

      final outOfRange = PlaybackNotifier.withoutOnlineItems(
          stateOf([online('1'), local('a'), local('b')], 7));
      expect(ids(outOfRange.queue), ['a', 'b']);
      expect(outOfRange.queueIndex, 1);
    });

    group('round trip through the database', () {
      late AppDatabase db;
      late PlaybackRepositoryImpl repo;

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
        repo = PlaybackRepositoryImpl(db);
      });

      tearDown(() async {
        await db.close();
      });

      Future<void> insert(MediaItem item) => db.into(db.mediaItemsTable).insert(
            MediaItemsTableCompanion.insert(
              id: item.id,
              uri: item.uri,
              mediaType: item.mediaType.name,
              title: item.title,
              durationMs: item.durationMs,
              sizeBytes: item.sizeBytes,
              dateAdded: item.dateAdded,
            ),
          );

      test('the saved row holds no online ids or stream URLs and restores the right item',
          () async {
        final a = local('a'), b = local('b');
        await insert(a);
        await insert(b);

        final s = stateOf([a, online('1'), b, online('2')], 2); // current: b
        await repo.savePlaybackState(PlaybackNotifier.withoutOnlineItems(s));

        final row = await db.select(db.playbackStatesTable).getSingle();
        expect(row.queueJson, isNot(contains('yt_')));
        expect(row.queueJson, isNot(contains('googlevideo')));
        expect(row.currentItemId, 'b');

        final loaded = await repo.loadLastPlaybackState();
        expect(loaded, isNotNull);
        expect(ids(loaded!.queue), ['a', 'b']);
        expect(loaded.queueIndex, 1);
        expect(loaded.currentItem?.id, 'b', reason: 'the index matches the restored queue');
        expect(loaded.position, const Duration(seconds: 30));
      });

      test('an online-only session saves an empty queue, so nothing is restored', () async {
        await repo.savePlaybackState(
            PlaybackNotifier.withoutOnlineItems(stateOf([online('1')], 0)));

        final row = await db.select(db.playbackStatesTable).getSingle();
        expect(row.currentItemId, isNull);
        expect(row.queueJson, isNot(contains('yt_')));

        final loaded = await repo.loadLastPlaybackState();
        expect(loaded!.queue, isEmpty, reason: 'PlaybackNotifier only restores a non-empty queue');
      });

      /// A row as an older version (or a since-deleted file) left it: ids the
      /// repository cannot resolve are dropped from the restored queue.
      Future<PlaybackState> restore(List<String> queueIds, int index, String? currentId,
          {Duration position = const Duration(minutes: 25)}) async {
        await db.into(db.playbackStatesTable).insert(PlaybackStatesTableCompanion.insert(
              currentItemId: Value(currentId),
              queueJson: jsonEncode({'queue': queueIds}),
              queueIndex: Value(index),
              positionMs: Value(position.inMilliseconds),
              durationMs: const Value(200000),
              updatedAt: DateTime(2026, 1, 1),
            ));
        final loaded = await repo.loadLastPlaybackState();
        // What PlaybackNotifier does before restoring the session.
        return PlaybackNotifier.alignIndexWithCurrentItem(
            PlaybackNotifier.withoutOnlineItems(loaded!));
      }

      test('an old row with a yt_ id restores the saved item, not its neighbour', () async {
        await insert(local('a'));
        await insert(local('b'));

        final s = await restore(['yt_1', 'a', 'b'], 2, 'b');
        expect(ids(s.queue), ['a', 'b']);
        expect(s.queueIndex, 1, reason: 'index 2 is out of range in the shorter queue');
        expect(s.currentItem?.id, 'b');
        expect(s.currentItemId, 'b');
        expect(s.position, const Duration(minutes: 25), reason: 'still the same item');
      });

      test('a saved online current item starts the first local item from 0:00', () async {
        await insert(local('a', durationMs: 3000));

        final s = await restore(['yt_1', 'a'], 0, 'yt_1');
        expect(ids(s.queue), ['a']);
        expect(s.queueIndex, 0);
        expect(s.currentItemId, isNull);
        expect(s.position, Duration.zero, reason: "25:00 was the online item's position");
        expect(s.duration, const Duration(milliseconds: 3000));
      });

      test('a current file deleted since the save does not hand its position on', () async {
        await insert(local('a'));
        await insert(local('b'));

        final s = await restore(['a', 'gone', 'b'], 1, 'gone');
        expect(ids(s.queue), ['a', 'b']);
        expect(s.queueIndex, 0);
        expect(s.currentItemId, isNull);
        expect(s.position, Duration.zero);
      });
    });
  });

  group('alignIndexWithCurrentItem', () {
    MediaItem item(String id) => MediaItem(
          id: id,
          uri: 'file:///storage/emulated/0/Music/$id.mp3',
          mediaType: MediaType.audio,
          title: id,
          durationMs: 1000,
          sizeBytes: 1,
          dateAdded: DateTime(2026, 1, 1),
        );
    PlaybackState state(List<String> queue, int index, String? currentId) => PlaybackState(
          currentItemId: currentId,
          queue: queue.map(item).toList(),
          queueIndex: index,
          position: const Duration(seconds: 30),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('a matching index (or no current item) is left alone', () {
      final matching = state(['a', 'b'], 1, 'b');
      expect(identical(PlaybackNotifier.alignIndexWithCurrentItem(matching), matching), isTrue);
      final none = state(['a', 'b'], 5, null);
      expect(identical(PlaybackNotifier.alignIndexWithCurrentItem(none), none), isTrue);
    });

    test('a shifted index moves to the current item and keeps the position', () {
      final out = PlaybackNotifier.alignIndexWithCurrentItem(state(['a', 'b', 'c'], 0, 'c'));
      expect(out.queueIndex, 2);
      expect(out.currentItemId, 'c');
      expect(out.position, const Duration(seconds: 30));
    });

    test('an empty queue ends up with nothing selected', () {
      final out = PlaybackNotifier.alignIndexWithCurrentItem(state([], 0, 'x'));
      expect(out.queueIndex, -1);
      expect(out.currentItemId, isNull);
      expect(out.position, Duration.zero);
    });
  });
}

