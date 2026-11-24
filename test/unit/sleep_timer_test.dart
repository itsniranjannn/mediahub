import 'package:audio_service/audio_service.dart' show AudioProcessingState, AudioServiceRepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart';
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

import 'fake_audio_player.dart';

domain.MediaItem _song(int i) => domain.MediaItem(
      id: 's$i',
      uri: 'content://media/external/audio/media/$i',
      mediaType: domain.MediaType.audio,
      title: 'Song $i',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

class _NoSavedSession implements PlaybackRepository {
  @override
  Future<PlaybackState?> loadLastPlaybackState() async => null;
  @override
  Future<void> savePlaybackState(PlaybackState state) async {}
}

class _Page implements ExternalPlaybackDelegate {
  final List<String> calls = [];
  @override
  Future<void> externalPlay() async => calls.add('play');
  @override
  Future<void> externalPause() async => calls.add('pause');
  @override
  Future<void> externalSeek(Duration position) async => calls.add('seek');
  @override
  Future<void> externalSkipToNext() async => calls.add('next');
  @override
  Future<void> externalSkipToPrevious() async => calls.add('previous');
  @override
  void onExternalSourceReleased() => calls.add('released');
}

ExternalMediaSnapshot _video({String id = 'online:a', bool playing = true}) =>
    ExternalMediaSnapshot(id: id, title: 'Video', playing: playing, duration: const Duration(minutes: 4));

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Waits until [done] holds, at most [maxMs]: real timers run late on a busy
/// machine (the full suite runs files side by side).
Future<void> _until(bool Function() done, {int maxMs = 3000}) async {
  for (var waited = 0; waited < maxMs && !done(); waited += 10) {
    await _wait(10);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late FakeAudioPlayer player;
  late MusicAudioHandler handler;

  Future<void> start({
    Duration fade = const Duration(milliseconds: 200),
    Duration idle = const Duration(minutes: 30),
    bool play = true,
  }) async {
    player = FakeAudioPlayer();
    handler = MusicAudioHandler(
      player: player,
      sleepFade: fade,
      pausedIdleTimeout: idle,
      art: NowPlayingArt(cacheDirectory: () async => null),
    );
    await handler.loadQueue([_song(0), _song(1), _song(2)], autoPlay: play);
    await _wait(5);
  }

  tearDown(() async => handler.dispose());

  group('F9 sleep timer', () {
    test('counts down, fades the music out, pauses and gives the volume back', () async {
      await start(fade: const Duration(milliseconds: 600));
      final seen = <SleepTimerStatus>[];
      final sub = handler.sleepTimerStream.listen(seen.add);
      handler.setSleepTimer(const Duration(milliseconds: 1500));
      final set = handler.sleepTimer;
      expect(set.isActive, isTrue);
      expect(set.endsAt, isNotNull);
      expect(set.remaining!.inMilliseconds, inInclusiveRange(1400, 1500));

      await _wait(200);
      expect(player.volume, 1.0, reason: 'not fading yet (fade is the last 600 ms)');
      expect(player.playing, isTrue);

      await _until(() => player.volume < 1.0);
      expect(player.volume, lessThan(1.0), reason: 'fading');
      expect(handler.sleepTimer.fading, isTrue);
      expect(player.playing, isTrue, reason: 'still playing while it fades');

      await _until(() => !player.playing && player.volume == 1.0);
      expect(player.playing, isFalse, reason: 'paused when the time is up');
      expect(player.volume, 1.0, reason: 'the next play is at full volume');
      expect(handler.sleepTimer.isActive, isFalse);
      expect(handler.wantPlaying, isFalse);
      final faded = player.volumes.where((v) => v < 1.0).toList();
      expect(faded.length, greaterThan(5));
      for (var i = 1; i < faded.length; i++) {
        expect(faded[i], lessThanOrEqualTo(faded[i - 1]), reason: 'always going down');
      }
      expect(seen.last.isActive, isFalse);
      await sub.cancel();
    });

    test('turning it off during the fade keeps the music, at full volume', () async {
      await start(fade: const Duration(seconds: 2));
      handler.setSleepTimer(const Duration(milliseconds: 2100));
      await _until(() => player.volume < 1.0);
      expect(player.volume, lessThan(1.0));
      handler.cancelSleepTimer();
      await _wait(5);
      expect(player.volume, 1.0);
      await _wait(250);
      expect(player.playing, isTrue);
      expect(handler.sleepTimer, SleepTimerStatus.off);
    });

    test('pressing play during the fade keeps the music too', () async {
      await start(fade: const Duration(seconds: 2));
      handler.setSleepTimer(const Duration(milliseconds: 2100));
      await _until(() => player.volume < 1.0);
      await handler.play();
      await _wait(250);
      expect(player.playing, isTrue);
      expect(player.volume, 1.0);
      expect(handler.sleepTimer.isActive, isFalse);
    });

    test('a new time replaces the old one', () async {
      await start();
      handler.setSleepTimer(const Duration(milliseconds: 250));
      handler.setSleepTimer(const Duration(seconds: 30));
      await _wait(400);
      expect(player.playing, isTrue);
      expect(handler.sleepTimer.remaining!.inSeconds, inInclusiveRange(28, 30));
    });

    test('end of song: pauses when the song ends by itself, at the start of the next', () async {
      await start();
      handler.setSleepTimerAtEndOfTrack();
      expect(handler.sleepTimer.endOfTrack, isTrue);
      // A skip is not the song ending.
      await handler.skipToNext();
      await _wait(10);
      expect(player.playing, isTrue);
      expect(handler.sleepTimer.endOfTrack, isTrue);

      player.finishTrack(); // s1 ends, s2 starts
      await _wait(20);
      expect(player.playing, isFalse);
      expect(handler.currentIndex, 2);
      expect(player.position, Duration.zero);
      expect(handler.sleepTimer.isActive, isFalse);
    });

    test('end of song with repeat one: the loop back to the start counts as the end', () async {
      await start();
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      handler.setSleepTimerAtEndOfTrack();
      player.finishTrack(); // loops: position jumps from the end to the start
      await _wait(20);
      expect(player.playing, isFalse);
    });

    test('end of song with repeat one: a seek back to 0:00, a restart or a skip is not the end (review)',
        () async {
      await start();
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      handler.setSleepTimerAtEndOfTrack();

      // The user drags the bar from the last seconds back to the start.
      player.fakePosition = const Duration(minutes: 2, seconds: 59);
      await _wait(5);
      await handler.seek(Duration.zero);
      player.fakePosition = const Duration(milliseconds: 200);
      await _wait(20);
      expect(player.playing, isTrue, reason: 'a seek is not the song ending');
      expect(handler.sleepTimer.endOfTrack, isTrue, reason: 'still armed');

      // Previous after 3 s restarts the song.
      player.fakePosition = const Duration(minutes: 2, seconds: 59);
      await _wait(5);
      await handler.skipToPrevious();
      await _wait(10);
      player.fakePosition = const Duration(milliseconds: 100);
      await _wait(20);
      expect(player.playing, isTrue, reason: 'a restart is not the song ending');
      expect(handler.sleepTimer.endOfTrack, isTrue);

      // Next from the last seconds moves to another song.
      player.fakePosition = const Duration(minutes: 2, seconds: 59);
      await _wait(5);
      await handler.skipToNext();
      await _wait(10);
      player.fakePosition = const Duration(milliseconds: 100);
      await _wait(20);
      expect(handler.currentIndex, 1);
      expect(player.playing, isTrue, reason: 'a skip is not the song ending');
      expect(handler.sleepTimer.endOfTrack, isTrue);

      // The player's own loop still counts once the seeks are past.
      await _wait(1100);
      player.finishTrack();
      await _wait(20);
      expect(player.playing, isFalse);
      expect(handler.sleepTimer.isActive, isFalse);
    });

    test('stopping the session ends the sleep timer (notification Stop, idle stop, empty queue)', () async {
      await start();
      final seen = <SleepTimerStatus>[];
      final sub = handler.sleepTimerStream.listen(seen.add);
      handler.setSleepTimer(const Duration(minutes: 15));
      await handler.stop();
      await _wait(5);
      expect(handler.sleepTimer.isActive, isFalse, reason: 'the chip must not keep counting on a stopped session');
      expect(seen.last.isActive, isFalse);

      await handler.loadQueue([_song(0), _song(1)]);
      await _wait(5);
      handler.setSleepTimerAtEndOfTrack();
      await handler.loadQueue(const []);
      await _wait(5);
      expect(handler.sleepTimer.isActive, isFalse);
      await sub.cancel();
    });

    test('the timer pauses the Online tab\'s video too', () async {
      await start(play: false);
      final page = _Page();
      handler.setExternalSource(page, _video());
      handler.setSleepTimer(const Duration(milliseconds: 150));
      await _until(() => page.calls.contains('pause'));
      expect(page.calls, contains('pause'));
      expect(handler.sleepTimer.isActive, isFalse);
    });

    test('end of song for a video: the page moving on to another video', () async {
      await start(play: false);
      final page = _Page();
      handler.setExternalSource(page, _video());
      handler.setSleepTimerAtEndOfTrack();
      handler.updateExternalMedia(page, _video(id: 'online:b'));
      await _wait(5);
      expect(page.calls, ['pause']);
    });

    test('the provider follows the handler (and is off without one)', () async {
      await start();
      final container = ProviderContainer(overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        playbackRepositoryProvider.overrideWithValue(_NoSavedSession()),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(sleepTimerProvider, (_, _) {});
      expect(container.read(sleepTimerProvider).isActive, isFalse);
      container.read(playbackNotifierProvider.notifier).setSleepTimer(const Duration(minutes: 15));
      await _wait(5);
      expect(container.read(sleepTimerProvider).remaining!.inSeconds, inInclusiveRange(890, 900));
      container.read(playbackNotifierProvider.notifier).setSleepTimerAtEndOfTrack();
      await _wait(5);
      expect(container.read(sleepTimerProvider).endOfTrack, isTrue);
      container.read(playbackNotifierProvider.notifier).cancelSleepTimer();
      await _wait(5);
      expect(container.read(sleepTimerProvider), SleepTimerStatus.off);
      sub.close();

      final bare = ProviderContainer();
      addTearDown(bare.dispose);
      expect(bare.read(sleepTimerProvider), SleepTimerStatus.off);
    });
  });

  group('ONL-8 paused-idle stop', () {
    test('local: after the idle time paused, the session ends (service, wake lock, notification)', () async {
      await start(idle: const Duration(milliseconds: 600));
      await handler.pause();
      expect(handler.idleStopArmed, isTrue);
      await _wait(150);
      expect(player.stopCalls, 0);
      await _until(() => handler.playbackState.value.processingState == AudioProcessingState.idle);
      expect(player.stopCalls, 1);
      expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
      expect(handler.idleStopArmed, isFalse);
      // The queue stays: play brings it back.
      expect(handler.playOrderQueue, hasLength(3));
    });

    test('playing again within the idle time keeps the session', () async {
      await start(idle: const Duration(milliseconds: 600));
      await handler.pause();
      await _wait(150);
      await handler.play();
      await _wait(5);
      expect(handler.idleStopArmed, isFalse);
      await _wait(700);
      expect(player.stopCalls, 0);
    });

    test('never armed before anything played (nothing to keep alive)', () async {
      await start(idle: const Duration(milliseconds: 50), play: false);
      expect(handler.idleStopArmed, isFalse);
      await _wait(100);
      expect(player.stopCalls, 0);
    });

    test('a paused YouTube video ends the session the same way', () async {
      await start(idle: const Duration(milliseconds: 150), play: false);
      final page = _Page();
      handler.setExternalSource(page, _video());
      handler.updateExternalMedia(page, _video(playing: false));
      await _until(() => page.calls.contains('released'));
      expect(page.calls, ['pause', 'released']);
      expect(handler.isExternalActive, isFalse);
    });

    test('off by default: a paused session keeps its notification until the user closes it', () async {
      expect(MusicAudioHandler.defaultPausedIdleTimeout, isNull);
      player = FakeAudioPlayer();
      handler = MusicAudioHandler(player: player, art: NowPlayingArt(cacheDirectory: () async => null));
      await handler.loadQueue([_song(0), _song(1)], autoPlay: true);
      await _wait(5);
      await handler.pause();
      expect(handler.idleStopArmed, isFalse);
      await _wait(50);
      expect(player.stopCalls, 0);
      expect(handler.playbackState.value.processingState, isNot(AudioProcessingState.idle));
    });
  });
}
