import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' show PlaybackRepeatMode;
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
    // just_audio 0.10.6 reports a song that cannot play here only.
    late StreamController<PlayerException> errorController;

    setUp(() {
      fakeCurrentIndex = 0;
      mockPlayer = MockAudioPlayer();
      playbackEventController = StreamController<PlaybackEvent>.broadcast();
      errorController = StreamController<PlayerException>.broadcast();
      when(() => mockPlayer.playbackEventStream).thenAnswer((_) => playbackEventController.stream);
      when(() => mockPlayer.errorStream).thenAnswer((_) => errorController.stream);
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
      expect(state.androidCompactActionIndices, [0, 1, 2]);
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

    // DESIGN.md 7.17: Next is disabled on the last track with repeat off, in
    // the app and in the notification alike. It used to pause and jump back
    // to the first track instead.
    test('skipToNext on the last track with repeat off does nothing (Next is disabled)', () async {
      await handler.loadQueue([item1, item2, item3], startIndex: 2, autoPlay: false);
      expect(handler.currentIndex, 2);
      expect(handler.canSkipNext, isFalse);

      await handler.skipToNext();
      await handler.click(MediaButton.next); // a headset's Next button

      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, '3');
      verifyNever(() => mockPlayer.pause());
      verifyNever(() => mockPlayer.seek(any(), index: 0));
      verifyNever(() => mockPlayer.play());
    });

    test('a track that cannot play on the last item still stops the queue at its start', () async {
      final messages = <String>[];
      handler.errorEvents.listen(messages.add);
      await handler.loadQueue([item1, item2, item3], startIndex: 2, autoPlay: true);

      errorController.add(PlayerException(1, 'Last file unplayable', 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      verify(() => mockPlayer.pause()).called(1);
      verify(() => mockPlayer.seek(Duration.zero, index: 0)).called(1);
      expect(messages, ['Can\'t play "Song 3"']);
      expect(handler.wantPlaying, isFalse);
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

    test('resume-on-reconnect rule is on by default and can be switched off and on', () {
      expect(handler.resumeOnHeadphonesReconnect, isTrue);
      handler.setResumeOnHeadphonesReconnect(false);
      expect(handler.resumeOnHeadphonesReconnect, isFalse);
      handler.setResumeOnHeadphonesReconnect(true);
      expect(handler.resumeOnHeadphonesReconnect, isTrue);
    });

    test('queue of 3 unplayable files with repeat all stops paused instead of looping', () async {
      final items = [item1, item2, item3];
      when(() => mockPlayer.hasNext).thenReturn(true);
      await handler.loadQueue(items, startIndex: 0, autoPlay: true);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);

      final messages = <String>[];
      handler.errorEvents.listen(messages.add);

      // Each song fails once the handler has moved on to it, as the player
      // reports it: on its error stream.
      for (var i = 0; i < 3; i++) {
        expect(fakeCurrentIndex, i, reason: 'the handler moved on to song ${i + 1}');
        errorController.add(PlayerException(1, 'File ${i + 1} unplayable', i));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // One message for the run, one when it gives up; no fourth try.
      expect(messages, ['Can\'t play "Song 1"', 'Can\'t play any song in the queue']);
      expect(fakeCurrentIndex, 2);
      expect(handler.wantPlaying, isFalse);
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

    test('the same song queued twice keeps both copies through shuffle on/off and removing one', () async {
      await handler.loadQueue([item1, item2], startIndex: 0, autoPlay: false);
      await handler.addToQueue(item1);
      expect(handler.playOrderQueue.map((e) => e.id).toList(), ['1', '2', '1']);

      await handler.toggleShuffle();
      expect(handler.playOrderQueue.length, 3);
      await handler.toggleShuffle();
      expect(handler.playOrderQueue.map((e) => e.id).toList(), ['1', '2', '1']);

      await handler.removeQueueItemAt(2);
      expect(handler.playOrderQueue.map((e) => e.id).toList(), ['1', '2']);
      expect(handler.originalQueue.map((e) => e.id).toList(), ['1', '2']);
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
        // F7: the media session's queue (Android Auto, Wear, the lock
        // screen's queue) follows the reshuffle at the wrap.
        expect(handler.queue.value.map((m) => m.id).toList(), handler.playOrderQueue.map((m) => m.id).toList(),
            reason: 'skip $i: session queue in play order');
        expect(handler.playbackState.value.queueIndex, handler.currentIndex);
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

    // --- the playback basics (docs/DESIGN.md 7.17) ---------------------------

    group('notification, lock screen and Bluetooth', () {
      List<MediaAction> actions(PlaybackState s) => s.controls.map((c) => c.action).toList();
      List<String?> customNames(PlaybackState s) => s.controls.map((c) => c.customAction?.name).toList();

      test('previous, play / pause and next come first, so the compact view shows exactly those', () async {
        await handler.loadQueue([item1, item2, item3], startIndex: 1, autoPlay: false);
        final s = handler.playbackState.value;
        expect(actions(s).take(3), [MediaAction.skipToPrevious, MediaAction.play, MediaAction.skipToNext]);
        // Shuffle and repeat are custom actions after the transport: they
        // never shift the compact indices (audio_service counts those over
        // the standard controls only).
        expect(customNames(s).skip(3), [MusicAudioHandler.actionToggleShuffle, MusicAudioHandler.actionCycleRepeat]);
        expect(s.androidCompactActionIndices, [0, 1, 2]);
        final standard = s.controls.where((c) => c.customAction == null).toList();
        for (final i in s.androidCompactActionIndices!) {
          expect(i, lessThan(standard.length), reason: 'every compact index names a standard control');
        }
        expect(standard.map((c) => c.action), [MediaAction.skipToPrevious, MediaAction.play, MediaAction.skipToNext]);
        expect(s.systemActions, containsAll([MediaAction.skipToPrevious, MediaAction.skipToNext, MediaAction.seek]));
      });

      test('on the last track with repeat off Next leaves the notification controls, not the session',
          () async {
        await handler.loadQueue([item1, item2, item3], startIndex: 2, autoPlay: false);
        final s = handler.playbackState.value;
        expect(actions(s), isNot(contains(MediaAction.skipToNext)));
        expect(s.androidCompactActionIndices, [0, 1]);
        // The session keeps ACTION_SKIP_TO_NEXT, so Android 13+ keeps Next's
        // slot instead of moving Shuffle (the first custom action) into it.
        expect(s.systemActions, containsAll([MediaAction.skipToPrevious, MediaAction.skipToNext]));
        expect(customNames(s).whereType<String>(),
            [MusicAudioHandler.actionToggleShuffle, MusicAudioHandler.actionCycleRepeat]);
        // A Next from the shade, lock screen or Bluetooth there does nothing.
        await handler.skipToNext();
        expect(handler.currentIndex, 2);
        verifyNever(() => mockPlayer.seek(any(), index: 0));

        // Repeat on: Next is back (it wraps to the start).
        await handler.setRepeatMode(AudioServiceRepeatMode.all);
        final repeating = handler.playbackState.value;
        expect(actions(repeating).take(3), [MediaAction.skipToPrevious, MediaAction.play, MediaAction.skipToNext]);
        expect(repeating.systemActions, contains(MediaAction.skipToNext));
        expect(repeating.androidCompactActionIndices, [0, 1, 2]);
        expect(handler.canSkipNext, isTrue);
      });

      test('moving off the last track brings Next back', () async {
        await handler.loadQueue([item1, item2, item3], startIndex: 2, autoPlay: false);
        await handler.skipToPrevious();
        expect(handler.currentIndex, 1);
        expect(actions(handler.playbackState.value), contains(MediaAction.skipToNext));
      });

      test('the play control follows the player, the pause control while playing', () async {
        var playingNow = false;
        when(() => mockPlayer.playing).thenAnswer((_) => playingNow);
        when(() => mockPlayer.play()).thenAnswer((_) async => playingNow = true);
        when(() => mockPlayer.pause()).thenAnswer((_) async => playingNow = false);
        await handler.loadQueue([item1, item2], autoPlay: true);
        expect(actions(handler.playbackState.value)[1], MediaAction.pause);
        await handler.pause();
        expect(actions(handler.playbackState.value)[1], MediaAction.play);
      });

      test('shuffle and repeat show in the session state and on their custom actions', () async {
        await handler.loadQueue([item1, item2, item3], autoPlay: false);
        var s = handler.playbackState.value;
        expect(s.shuffleMode, AudioServiceShuffleMode.none);
        expect(s.repeatMode, AudioServiceRepeatMode.none);
        expect(s.controls[3].label, 'Shuffle: Off');
        expect(s.controls[4].label, 'Repeat: Off');

        await handler.toggleShuffle();
        handler.cycleRepeatMode();
        s = handler.playbackState.value;
        expect(s.shuffleMode, AudioServiceShuffleMode.all);
        expect(s.repeatMode, AudioServiceRepeatMode.all);
        expect(s.controls[3].label, 'Shuffle: On');
        expect(s.controls[4].label, 'Repeat: All');
        expect(s.controls[4].androidIcon, 'drawable/ic_action_repeat_all');

        handler.cycleRepeatMode();
        expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.one);
        expect(handler.playbackState.value.controls[4].label, 'Repeat: One');

        // From the lock screen / a car: the system's own shuffle and repeat.
        await handler.setShuffleMode(AudioServiceShuffleMode.none);
        await handler.setRepeatMode(AudioServiceRepeatMode.none);
        s = handler.playbackState.value;
        expect(handler.shuffleEnabled, isFalse);
        expect(handler.repeatMode.name, 'off');
        expect(s.shuffleMode, AudioServiceShuffleMode.none);
        expect(s.repeatMode, AudioServiceRepeatMode.none);
      });

      test('the notification shuffle / repeat buttons change the modes', () async {
        await handler.loadQueue([item1, item2, item3], autoPlay: false);
        await handler.customAction(MusicAudioHandler.actionCycleRepeat);
        expect(handler.repeatMode.name, 'all');
        await handler.customAction(MusicAudioHandler.actionToggleShuffle);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(handler.shuffleEnabled, isTrue);
      });
    });

    group('previous', () {
      test('past 3 s it restarts the track', () async {
        await handler.loadQueue([item1, item2, item3], startIndex: 1, autoPlay: false);
        when(() => mockPlayer.position).thenReturn(const Duration(seconds: 10));

        await handler.skipToPrevious();

        expect(handler.currentIndex, 1);
        verify(() => mockPlayer.seek(Duration.zero)).called(1);
        verifyNever(() => mockPlayer.seek(any(), index: 0));
      });

      test('in the first 3 s it goes to the previous track', () async {
        await handler.loadQueue([item1, item2, item3], startIndex: 1, autoPlay: false);
        when(() => mockPlayer.position).thenReturn(const Duration(seconds: 3));

        await handler.skipToPrevious();

        expect(handler.currentIndex, 0);
        expect(handler.mediaItem.value?.id, '1');
      });

      test('on the first track it restarts it with repeat off, and goes to the last with repeat on', () async {
        await handler.loadQueue([item1, item2, item3], startIndex: 0, autoPlay: false);
        await handler.skipToPrevious();
        expect(handler.currentIndex, 0);
        verify(() => mockPlayer.seek(Duration.zero)).called(1);

        await handler.setRepeatMode(AudioServiceRepeatMode.all);
        await handler.skipToPrevious();
        expect(handler.currentIndex, 2);
      });

      test('skipping starts playback, like Next', () async {
        await handler.loadQueue([item1, item2], startIndex: 1, autoPlay: false);
        await handler.skipToPrevious();
        verify(() => mockPlayer.play()).called(1);
      });
    });

    test('with repeat one, Next and Previous still move between tracks', () async {
      // just_audio loops the current item under LoopMode.one, so its own
      // hasNext / seekToNext only restarted the same song.
      when(() => mockPlayer.hasNext).thenReturn(true);
      when(() => mockPlayer.hasPrevious).thenReturn(true);
      when(() => mockPlayer.seekToNext()).thenAnswer((_) async {});
      when(() => mockPlayer.seekToPrevious()).thenAnswer((_) async {});
      await handler.loadQueue([item1, item2, item3], startIndex: 1, autoPlay: false);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      verify(() => mockPlayer.setLoopMode(LoopMode.one)).called(1);

      await handler.skipToNext();
      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, '3');

      // The last track: Next stays enabled with repeat on and wraps.
      expect(handler.canSkipNext, isTrue);
      await handler.skipToNext();
      expect(handler.currentIndex, 0);

      await handler.skipToPrevious();
      expect(handler.currentIndex, 2);
      verifyNever(() => mockPlayer.seekToNext());
      verifyNever(() => mockPlayer.seekToPrevious());
    });

    test('picking a track in the queue plays it (it used to jump there and stay paused)', () async {
      await handler.loadQueue([item1, item2, item3], autoPlay: false);
      verifyNever(() => mockPlayer.play());

      await handler.skipToQueueItem(2);

      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, '3');
      expect(handler.wantPlaying, isTrue);
      verify(() => mockPlayer.play()).called(1);
    });

    test('canSkipNextAt: only the last item with repeat off has no next', () {
      bool at(int index, int length, String mode) => MusicAudioHandler.canSkipNextAt(
            index: index,
            length: length,
            repeatMode: PlaybackRepeatMode.values.byName(mode),
          );
      expect(at(0, 3, 'off'), isTrue);
      expect(at(1, 3, 'off'), isTrue);
      expect(at(2, 3, 'off'), isFalse);
      expect(at(2, 3, 'all'), isTrue);
      expect(at(2, 3, 'one'), isTrue);
      expect(at(0, 1, 'off'), isFalse);
      expect(at(0, 1, 'all'), isTrue);
      expect(at(-1, 3, 'all'), isFalse, reason: 'nothing loaded');
      expect(at(0, 0, 'all'), isFalse);
    });

    group('headset buttons', () {
      test('Bluetooth next / previous and the play / pause button act at once', () async {
        var playingNow = false;
        when(() => mockPlayer.playing).thenAnswer((_) => playingNow);
        when(() => mockPlayer.play()).thenAnswer((_) async => playingNow = true);
        when(() => mockPlayer.pause()).thenAnswer((_) async => playingNow = false);
        expect(handler.mediaButtonMultiClickWindow, Duration.zero, reason: 'not Android: no press counting');
        await handler.loadQueue([item1, item2, item3], autoPlay: false);

        await handler.click(MediaButton.media);
        expect(playingNow, isTrue);
        await handler.click(MediaButton.next);
        expect(handler.currentIndex, 1);
        await handler.click(MediaButton.previous);
        expect(handler.currentIndex, 0);
        await handler.click(MediaButton.media);
        expect(playingNow, isFalse);
        expect(handler.wantPlaying, isFalse);
      });

      test('a single-button headset: one press toggles, two skip next, three go back', () async {
        var playingNow = false;
        when(() => mockPlayer.playing).thenAnswer((_) => playingNow);
        when(() => mockPlayer.play()).thenAnswer((_) async => playingNow = true);
        when(() => mockPlayer.pause()).thenAnswer((_) async => playingNow = false);
        final counting = MusicAudioHandler(
          player: mockPlayer,
          mediaButtonMultiClickWindow: const Duration(milliseconds: 40),
        );
        addTearDown(counting.dispose);
        await counting.loadQueue([item1, item2, item3], startIndex: 1, autoPlay: false);
        Future<void> wait() => Future<void>.delayed(const Duration(milliseconds: 90));

        await counting.click(MediaButton.media);
        expect(playingNow, isFalse, reason: 'waits for a second press');
        await wait();
        expect(playingNow, isTrue);

        await counting.click(MediaButton.media);
        await counting.click(MediaButton.media);
        await wait();
        expect(counting.currentIndex, 2);
        expect(playingNow, isTrue, reason: 'a skip, not pause + play');

        await counting.click(MediaButton.media);
        await counting.click(MediaButton.media);
        await counting.click(MediaButton.media);
        await wait();
        expect(counting.currentIndex, 1);

        await counting.click(MediaButton.media);
        await wait();
        expect(playingNow, isFalse);
      });
    });
  });
}
