import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/features/music_player/music_audio_handler.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class FakeAudioSource extends Fake implements AudioSource {}

domain.MediaItem _createTestItem(String id, String title) {
  return domain.MediaItem(
    id: id,
    uri: 'file:///path/to/$id.mp3',
    mediaType: domain.MediaType.audio,
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 180000,
    sizeBytes: 1024,
    dateAdded: DateTime(2026, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(FakeAudioSource());
    registerFallbackValue(LoopMode.off);
  });

  group('MusicAudioHandler unit tests', () {
    late MockAudioPlayer mockPlayer;
    late MusicAudioHandler handler;
    final item1 = _createTestItem('1', 'Song 1');
    final item2 = _createTestItem('2', 'Song 2');
    final item3 = _createTestItem('3', 'Song 3');
    int fakeCurrentIndex = 0;
    late StreamController<PlaybackEvent> playbackEventController;

    setUp(() {
      fakeCurrentIndex = 0;
      mockPlayer = MockAudioPlayer();
      playbackEventController = StreamController<PlaybackEvent>.broadcast();
      when(() => mockPlayer.playbackEventStream).thenAnswer((_) => playbackEventController.stream);
      when(() => mockPlayer.playerStateStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.currentIndexStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.positionStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.durationStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.playing).thenReturn(false);
      when(() => mockPlayer.processingState).thenReturn(ProcessingState.ready);
      when(() => mockPlayer.position).thenReturn(Duration.zero);
      when(() => mockPlayer.bufferedPosition).thenReturn(Duration.zero);
      when(() => mockPlayer.speed).thenReturn(1.0);
      when(() => mockPlayer.duration).thenReturn(const Duration(milliseconds: 180000));
      when(() => mockPlayer.currentIndex).thenAnswer((_) => fakeCurrentIndex);
      when(() => mockPlayer.shuffleModeEnabled).thenReturn(false);
      when(() => mockPlayer.hasNext).thenAnswer((_) => fakeCurrentIndex < 2);
      when(() => mockPlayer.hasPrevious).thenAnswer((_) => fakeCurrentIndex > 0);

      when(() => mockPlayer.setAudioSources(any(), initialIndex: any(named: 'initialIndex'), initialPosition: any(named: 'initialPosition')))
          .thenAnswer((invocation) async {
            fakeCurrentIndex = invocation.namedArguments[#initialIndex] ?? 0;
            return const Duration(milliseconds: 180000);
          });
      when(() => mockPlayer.setAudioSource(any(), initialIndex: any(named: 'initialIndex'), initialPosition: any(named: 'initialPosition'), preload: any(named: 'preload')))
          .thenAnswer((invocation) async {
            fakeCurrentIndex = invocation.namedArguments[#initialIndex] ?? 0;
            return const Duration(milliseconds: 180000);
          });
      when(() => mockPlayer.setShuffleModeEnabled(any())).thenAnswer((_) async {});
      when(() => mockPlayer.setLoopMode(any())).thenAnswer((_) async {});
      when(() => mockPlayer.seekToNext()).thenAnswer((_) async {
        fakeCurrentIndex++;
      });
      when(() => mockPlayer.seekToPrevious()).thenAnswer((_) async {
        fakeCurrentIndex--;
      });
      when(() => mockPlayer.play()).thenAnswer((_) async {});
      when(() => mockPlayer.pause()).thenAnswer((_) async {});
      when(() => mockPlayer.seek(any(), index: any(named: 'index'))).thenAnswer((invocation) async {
        if (invocation.namedArguments[#index] != null) {
          fakeCurrentIndex = invocation.namedArguments[#index];
        }
      });
      when(() => mockPlayer.dispose()).thenAnswer((_) async {});

      handler = MusicAudioHandler(player: mockPlayer);
    });

    tearDown(() async {
      await handler.dispose();
    });

    test('skipToNext advances currentIndex and broadcasts updated PlaybackState with controls', () async {
      await handler.loadQueue([item1, item2, item3], startIndex: 0, autoPlay: false);

      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, '1');

      // Call skipToNext
      await handler.skipToNext();

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, '2');

      final state = handler.playbackState.value;
      expect(state.queueIndex, 1);
      expect(state.systemActions, contains(MediaAction.skipToNext));
      expect(state.systemActions, contains(MediaAction.skipToPrevious));
      expect(state.androidCompactActionIndices, [1, 2, 3]);
    });

    test('skipToPrevious decrements currentIndex and updates broadcast state', () async {
      await handler.loadQueue([item1, item2, item3], startIndex: 1, autoPlay: false);

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, '2');

      // Call skipToPrevious
      await handler.skipToPrevious();

      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, '1');

      final state = handler.playbackState.value;
      expect(state.queueIndex, 0);
      expect(state.systemActions, contains(MediaAction.skipToPrevious));
      expect(state.systemActions, contains(MediaAction.skipToNext));
    });

    test('skipToNext at queue end with repeat off pauses and resets to start of queue', () async {
      await handler.loadQueue([item1, item2, item3], startIndex: 2, autoPlay: false);
      expect(handler.currentIndex, 2);

      await handler.skipToNext();

      // Should pause and reset to start of queue (index 0)
      verify(() => mockPlayer.pause()).called(1);
      verify(() => mockPlayer.seek(Duration.zero, index: 0)).called(1);
    });

    test('skipToNext at queue end with repeat all loops to index 0 and plays', () async {
      await handler.loadQueue([item1, item2, item3], startIndex: 2, autoPlay: false);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);

      await handler.skipToNext();

      verify(() => mockPlayer.seek(Duration.zero, index: 0)).called(1);
      verify(() => mockPlayer.play()).called(1);
    });

    test('rapid skipToNext calls are serialized and advance in order', () async {
      // 12 tracks to test 10 rapid skips
      final items = List.generate(12, (i) => _createTestItem('$i', 'Song $i'));
      when(() => mockPlayer.hasNext).thenAnswer((_) => fakeCurrentIndex < 11);
      await handler.loadQueue(items, startIndex: 0, autoPlay: false);
      expect(handler.currentIndex, 0);

      // Fire 10 rapid skips concurrently without awaiting each
      final futures = List.generate(10, (_) => handler.skipToNext());
      await Future.wait(futures);

      expect(fakeCurrentIndex, 10);
      expect(handler.currentIndex, 10);
      expect(handler.mediaItem.value?.id, '10');
    });

    test('resume-on-reconnect rule toggles and updates handler state', () {
      expect(handler.resumeOnHeadphonesReconnect, isFalse);
      handler.setResumeOnHeadphonesReconnect(true);
      expect(handler.resumeOnHeadphonesReconnect, isTrue);
    });

    test('queue of 3 unplayable files with repeat all stops paused instead of looping', () async {
      final items = [item1, item2, item3];
      when(() => mockPlayer.hasNext).thenReturn(true);
      await handler.loadQueue(items, startIndex: 0, autoPlay: false);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);

      final stopCompleter = Completer<bool>();
      handler.errorEvents.listen((event) {
        if (event.contains('Playback stopped: consecutive playback errors reached queue limit')) {
          if (!stopCompleter.isCompleted) stopCompleter.complete(true);
        }
      });

      // Directly trigger 3 playback errors on the handler
      handler.handlePlaybackError(Exception('File 1 unplayable'));
      handler.handlePlaybackError(Exception('File 2 unplayable'));
      handler.handlePlaybackError(Exception('File 3 unplayable'));

      final stopEmitted = await stopCompleter.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => false,
      );

      expect(stopEmitted, isTrue);
      verify(() => mockPlayer.pause()).called(greaterThanOrEqualTo(1));
    });

    test('rapid skipToNext calls advance promptly when play() only completes on pause', () async {
      final items = [item1, item2, item3];
      final playCompleter = Completer<void>();
      when(() => mockPlayer.play()).thenAnswer((_) => playCompleter.future);
      when(() => mockPlayer.hasNext).thenAnswer((_) => fakeCurrentIndex < 2);

      await handler.loadQueue(items, startIndex: 0, autoPlay: false);

      // Fire 2 rapid skips
      final skip1 = handler.skipToNext();
      final skip2 = handler.skipToNext();
      await Future.wait([skip1, skip2]);

      expect(fakeCurrentIndex, 2);
      expect(handler.currentIndex, 2);

      // Complete play to avoid lingering future
      playCompleter.complete();
    });

    test('pause during a skip leaves player paused', () async {
      final items = [item1, item2, item3];
      when(() => mockPlayer.hasNext).thenAnswer((_) => fakeCurrentIndex < 2);
      await handler.loadQueue(items, startIndex: 0, autoPlay: false);

      // Start skip and immediately pause
      final skipFuture = handler.skipToNext();
      await handler.pause();
      await skipFuture;

      expect(handler.playbackState.value.playing, isFalse);
    });

    test('toggleShuffle preserves track and position, and toggle off restores original order', () async {
      final items = [item1, item2, item3];
      when(() => mockPlayer.position).thenReturn(const Duration(seconds: 45));
      when(() => mockPlayer.seek(any(), index: any(named: 'index'))).thenAnswer((invocation) async {
        fakeCurrentIndex = invocation.namedArguments[#index] ?? 0;
      });

      await handler.loadQueue(items, startIndex: 1, autoPlay: false);
      expect(handler.originalQueue.map((e) => e.id).toList(), ['1', '2', '3']);

      // Toggle Shuffle ON: item 2 ('2') should stay first
      await handler.toggleShuffle();
      expect(handler.shuffleEnabled, isTrue);
      expect(handler.playOrderQueue.first.id, '2');
      expect(handler.playOrderQueue.length, 3);
      expect(handler.currentIndex, 0);

      // Toggle Shuffle OFF: original order restored, item 2 is playing
      await handler.toggleShuffle();
      expect(handler.shuffleEnabled, isFalse);
      expect(handler.playOrderQueue.map((e) => e.id).toList(), ['1', '2', '3']);
      expect(handler.currentIndex, 1);
    });

    test('50 skips on a queue of 10 with shuffle on never repeats a track inside a cycle', () async {
      final items = List.generate(10, (i) => _createTestItem('$i', 'Track $i'));
      when(() => mockPlayer.seekToNext()).thenAnswer((_) async {
        fakeCurrentIndex++;
      });
      when(() => mockPlayer.hasNext).thenAnswer((_) => fakeCurrentIndex < handler.domainQueue.length - 1);
      when(() => mockPlayer.seek(any(), index: any(named: 'index'))).thenAnswer((invocation) async {
        fakeCurrentIndex = invocation.namedArguments[#index] ?? 0;
      });

      await handler.loadQueue(items, startIndex: 0, autoPlay: false);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.toggleShuffle();

      final visitedTrackIdsInCycle = <String>[];
      String? lastTrackOfPreviousCycle;

      for (int i = 0; i < 50; i++) {
        final currentTrackId = handler.domainQueue[fakeCurrentIndex].id;
        
        // If this is the start of a new cycle (every 10 tracks)
        if (visitedTrackIdsInCycle.length == 10) {
          visitedTrackIdsInCycle.clear();
          // Repeat-all wrap must not repeat the last track
          expect(currentTrackId, isNot(equals(lastTrackOfPreviousCycle)));
        }

        // Inside a single cycle, tracks must not repeat
        expect(visitedTrackIdsInCycle.contains(currentTrackId), isFalse,
            reason: 'Track $currentTrackId was repeated within the same cycle');
        visitedTrackIdsInCycle.add(currentTrackId);

        if (visitedTrackIdsInCycle.length == 10) {
          lastTrackOfPreviousCycle = currentTrackId;
        }

        await handler.skipToNext();
      }
    });

    test('queue edits under shuffle update both original and play order lists', () async {
      final items = [item1, item2, item3];
      when(() => mockPlayer.seek(any(), index: any(named: 'index'))).thenAnswer((invocation) async {
        fakeCurrentIndex = invocation.namedArguments[#index] ?? 0;
      });

      await handler.loadQueue(items, startIndex: 0, autoPlay: false);
      await handler.toggleShuffle();

      final item4 = _createTestItem('4', 'Track 4');
      await handler.addToQueue(item4);

      expect(handler.originalQueue.any((m) => m.id == '4'), isTrue);
      expect(handler.playOrderQueue.any((m) => m.id == '4'), isTrue);

      // Remove item 4
      final idx4 = handler.playOrderQueue.indexWhere((m) => m.id == '4');
      await handler.removeQueueItemAt(idx4);

      expect(handler.originalQueue.any((m) => m.id == '4'), isFalse);
      expect(handler.playOrderQueue.any((m) => m.id == '4'), isFalse);
    });
  });
}
