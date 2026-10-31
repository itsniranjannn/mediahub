import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/playback_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart';

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
}

