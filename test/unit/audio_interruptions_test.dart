// Calls, Siri, alarms and other apps' sound (audio interruptions), as the
// phones send them through audio_session:
// - Android: another app's music or video takes the sound for good (begin
//   'unknown', and no end ever comes). "Resume after other apps" waits for
//   that app to stop, then plays again. Short losses (begin / end 'pause')
//   work as they always did.
// - iOS: every start is 'unknown' and an end that may resume is 'pause'
//   (shouldResume). What played is resumed then, unless the user pressed
//   play or pause meanwhile; the Online page is left to WebKit.
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform/other_audio_watcher.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';

import 'fake_audio_player.dart';

domain.MediaItem _song(int i) => domain.MediaItem(
      id: 's$i',
      uri: 'file:///music/s$i.mp3',
      mediaType: domain.MediaType.audio,
      title: 'Song $i',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

List<domain.MediaItem> _songs(int n) => [for (var i = 0; i < n; i++) _song(i)];

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class _Watcher implements OtherAudioWatcher {
  final _events = StreamController<OtherAudioState>.broadcast();
  int starts = 0;
  int stops = 0;
  bool failStart = false;

  @override
  Stream<OtherAudioState> get events => _events.stream;

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('no watcher');
  }

  @override
  Future<void> stop() async => stops++;

  void otherApp({required bool playing, bool inCall = false}) =>
      _events.add(OtherAudioState(otherPlaying: playing, inCall: inCall));
}

/// just_audio's pause returns before the phone's own player has stopped: until
/// [hold] completes, this player still says it plays.
class _SlowPausePlayer extends FakeAudioPlayer {
  Completer<void>? hold;

  @override
  Future<void> pause() async {
    final h = hold;
    if (h != null) await h.future;
    return super.pause();
  }
}

/// Android's playback list as the watcher sees it at start: every app's
/// playing players, MediaHub's own among them, with no owner on them.
class _SelfSeeingWatcher extends _Watcher {
  _SelfSeeingWatcher(this.player);
  final FakeAudioPlayer player;

  @override
  Future<void> start() async {
    await super.start();
    otherApp(playing: player.playing);
  }
}

class _Delegate implements ExternalPlaybackDelegate {
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

ExternalMediaSnapshot _snapshot(String id, {required bool playing}) =>
    ExternalMediaSnapshot(id: id, title: 'A video', playing: playing);

final _otherAppTakesOver = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
final _shortLossBegins = AudioInterruptionEvent(true, AudioInterruptionType.pause);
final _shortLossEnds = AudioInterruptionEvent(false, AudioInterruptionType.pause);
// iOS: a call, Siri or an alarm.
final _iosBegins = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
final _iosEndsMayResume = AudioInterruptionEvent(false, AudioInterruptionType.pause);
final _iosEndsNoResume = AudioInterruptionEvent(false, AudioInterruptionType.unknown);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late FakeAudioPlayer player;
  late StreamController<AudioInterruptionEvent> interruptions;
  late _Watcher watcher;
  late MusicAudioHandler handler;
  late DateTime now;
  var resumeSetting = true;

  MusicAudioHandler makeHandler() => MusicAudioHandler(
        player: player,
        art: NowPlayingArt(cacheDirectory: () async => null),
        interruptionEvents: interruptions.stream,
        otherAudio: watcher,
        resumeAfterOtherApps: () => resumeSetting,
        clock: () => now,
        // The settle time after the music's own pause has its own tests below.
        otherAppWatchDelay: Duration.zero,
      );

  setUp(() {
    now = DateTime(2026, 11, 19, 20);
    resumeSetting = true;
    player = FakeAudioPlayer();
    interruptions = StreamController<AudioInterruptionEvent>.broadcast();
    watcher = _Watcher();
    handler = makeHandler();
  });

  tearDown(() async {
    PlatformInfo.resetForTests();
    await handler.dispose();
    await interruptions.close();
  });

  Future<void> playing() async {
    await handler.loadQueue(_songs(3), autoPlay: true);
    await _settle();
    expect(player.playing, isTrue);
  }

  Future<void> send(AudioInterruptionEvent e) async {
    interruptions.add(e);
    await _settle();
  }

  group('Android: Resume after other apps', () {
    test('another app plays: the music pauses, then plays again once that app stops', () async {
      await playing();
      await send(_otherAppTakesOver);
      expect(player.playing, isFalse);
      expect(watcher.starts, 1, reason: 'other apps are only watched while the music waits');
      expect(handler.waitingForOtherApp, isTrue);

      watcher.otherApp(playing: true);
      await _settle();
      expect(player.playing, isFalse, reason: 'still the other app\'s turn');

      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isTrue);
      expect(handler.wantPlaying, isTrue);
      expect(handler.waitingForOtherApp, isFalse);
      expect(watcher.stops, 1, reason: 'the watch ends with the wait');
    });

    test('quiet before the other app ever played is not its end (it is still starting)', () async {
      await playing();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isFalse);
      expect(handler.waitingForOtherApp, isTrue);

      watcher.otherApp(playing: true);
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isTrue);
    });

    for (final press in ['play', 'pause', 'next', 'stop', 'a new song']) {
      test('the user pressed $press meanwhile: nothing plays by itself later', () async {
        await playing();
        await send(_otherAppTakesOver);
        watcher.otherApp(playing: true);
        await _settle();

        switch (press) {
          case 'play':
            await handler.playLocal();
          case 'pause':
            await handler.pause();
          case 'next':
            await handler.skipToNext();
          case 'stop':
            await handler.stop();
          case 'a new song':
            await handler.loadQueue(_songs(2), autoPlay: false);
        }
        await _settle();
        expect(handler.waitingForOtherApp, isFalse);
        expect(watcher.stops, 1);
        if (press != 'play' && press != 'next') {
          final calls = player.playCalls;
          watcher.otherApp(playing: false);
          await _settle();
          expect(player.playing, isFalse);
          expect(player.playCalls, calls);
        }
      });
    }

    test('not during a call: it waits for the call to end', () async {
      await playing();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: true);
      watcher.otherApp(playing: false, inCall: true);
      await _settle();
      expect(player.playing, isFalse);
      expect(handler.waitingForOtherApp, isTrue);

      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isTrue);
    });

    test('not after 30 minutes', () async {
      await playing();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: true);
      await _settle();
      now = now.add(MusicAudioHandler.otherAppResumeWindow + const Duration(minutes: 1));
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isFalse);
      expect(handler.waitingForOtherApp, isFalse);
      expect(watcher.stops, 1);
    });

    test('not with the setting off (from the start, or turned off while it waits)', () async {
      resumeSetting = false;
      await playing();
      await send(_otherAppTakesOver);
      expect(watcher.starts, 0, reason: 'nothing is watched with the setting off');
      expect(handler.waitingForOtherApp, isFalse);

      resumeSetting = true;
      await handler.playLocal();
      await _settle();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: true);
      await _settle();
      resumeSetting = false;
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isFalse);
      expect(handler.waitingForOtherApp, isFalse);
    });

    test('not when a video or the Online tab took over meanwhile', () async {
      await playing();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: true);
      await _settle();
      final video = _Delegate();
      handler.setExternalSource(video, _snapshot('video:v1', playing: true));
      await _settle();
      expect(handler.waitingForOtherApp, isFalse);

      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isFalse, reason: 'the music stays paused');
      expect(video.calls, isNot(contains('play')));
    });

    test('music already paused when the other app came: nothing resumes later', () async {
      await playing();
      await handler.pause();
      await _settle();
      await send(_otherAppTakesOver);
      expect(watcher.starts, 0);
      expect(handler.waitingForOtherApp, isFalse);
    });

    test('a phone without the watcher keeps the music paused, as before', () async {
      watcher.failStart = true;
      await playing();
      await send(_otherAppTakesOver);
      expect(player.playing, isFalse);
      expect(handler.waitingForOtherApp, isFalse);
    });

    test('a short loss (a notification, a navigation prompt) works as before', () async {
      await playing();
      await send(_shortLossBegins);
      expect(player.playing, isFalse);
      await send(_shortLossEnds);
      expect(player.playing, isTrue);
      expect(watcher.starts, 0, reason: 'only a loss for good starts a wait');
    });

    test('Android: an end of type pause after a loss for good does not resume (unchanged)', () async {
      await playing();
      await send(_otherAppTakesOver);
      resumeSetting = false; // only the old rule is left to act
      await send(_shortLossEnds);
      expect(player.playing, isFalse);
    });

    // Review finding: watched before its own player had stopped, the music
    // saw itself as "another app playing" and started again at the next
    // quiet moment, though no other app ever played (a slow YouTube start, a
    // voice recorder that takes the sound and plays nothing).
    test('its own player, still sounding as the pause goes through, is never taken for another app', () async {
      final slow = _SlowPausePlayer();
      final selfSeeing = _SelfSeeingWatcher(slow);
      final h = MusicAudioHandler(
        player: slow,
        art: NowPlayingArt(cacheDirectory: () async => null),
        interruptionEvents: interruptions.stream,
        otherAudio: selfSeeing,
        resumeAfterOtherApps: () => true,
        clock: () => now,
        otherAppWatchDelay: const Duration(milliseconds: 1000),
      );
      addTearDown(h.dispose);
      await h.loadQueue(_songs(3), autoPlay: true);
      await _settle();
      expect(slow.playing, isTrue);

      slow.hold = Completer<void>();
      await send(_otherAppTakesOver);
      expect(h.waitingForOtherApp, isTrue);
      expect(selfSeeing.starts, 0, reason: 'nothing is watched until the music itself has stopped');

      slow.hold!.complete();
      await _settle();
      expect(slow.playing, isFalse);
      expect(selfSeeing.starts, 0, reason: 'and the phone has had a moment to see that');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      await _settle();
      expect(selfSeeing.starts, 1);

      // The other app takes the sound but has not played yet: quiet.
      selfSeeing.otherApp(playing: false);
      await _settle();
      expect(slow.playing, isFalse, reason: 'no other app was ever heard playing');
      expect(h.waitingForOtherApp, isTrue);

      // It plays, then stops: now the music comes back.
      selfSeeing.otherApp(playing: true);
      selfSeeing.otherApp(playing: false);
      await _settle();
      expect(slow.playing, isTrue);
    });

    test('a press while the music\'s own pause goes through ends the wait before any watching', () async {
      final slow = _SlowPausePlayer();
      final h = MusicAudioHandler(
        player: slow,
        art: NowPlayingArt(cacheDirectory: () async => null),
        interruptionEvents: interruptions.stream,
        otherAudio: watcher,
        resumeAfterOtherApps: () => true,
        clock: () => now,
        otherAppWatchDelay: const Duration(milliseconds: 50),
      );
      addTearDown(h.dispose);
      await h.loadQueue(_songs(3), autoPlay: true);
      await _settle();
      slow.hold = Completer<void>();
      await send(_otherAppTakesOver);
      slow.hold!.complete();
      slow.hold = null;
      await h.pause();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _settle();
      expect(h.waitingForOtherApp, isFalse);
      expect(watcher.starts, 0);
    });

    // Review finding: YouTube's next video, or a buffering pause longer than
    // the quiet time, took the sound back each time the music resumed.
    test('another app taking the sound right after the music came back: it stays paused this time', () async {
      await playing();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: true);
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isTrue, reason: 'the first stop resumes');

      now = now.add(const Duration(seconds: 20));
      await send(_otherAppTakesOver);
      expect(player.playing, isFalse);
      expect(handler.waitingForOtherApp, isFalse, reason: 'its turn now: no second wait');
      expect(watcher.starts, 1);
      watcher.otherApp(playing: true);
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isFalse);
    });

    test('a minute later, or after the user pressed play, a new loss waits again', () async {
      await playing();
      await send(_otherAppTakesOver);
      watcher.otherApp(playing: true);
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isTrue);

      now = now.add(MusicAudioHandler.otherAppRetakeWindow + const Duration(seconds: 1));
      await send(_otherAppTakesOver);
      expect(handler.waitingForOtherApp, isTrue);
      watcher.otherApp(playing: true);
      watcher.otherApp(playing: false);
      await _settle();
      expect(player.playing, isTrue);

      // Resumed by itself again; the user then presses pause and play.
      now = now.add(const Duration(seconds: 5));
      await handler.pause();
      await handler.playLocal();
      await _settle();
      await send(_otherAppTakesOver);
      expect(handler.waitingForOtherApp, isTrue, reason: 'the user\'s own play starts things afresh');
    });

    // Review finding: a pause during a short interruption did not clear its
    // resume flag on Android.
    test('play, then pause, during a short interruption: it stays paused when that ends', () async {
      await playing();
      await send(_shortLossBegins);
      await handler.playLocal();
      await handler.pause();
      await _settle();
      await send(_shortLossEnds);
      expect(player.playing, isFalse);
      expect(handler.wantPlaying, isFalse);
    });

    test('paused by the user during a short interruption, a loss for good starts no wait', () async {
      await playing();
      await send(_shortLossBegins);
      await handler.pause();
      await _settle();
      await send(_otherAppTakesOver);
      expect(handler.waitingForOtherApp, isFalse);
      expect(watcher.starts, 0);
    });
  });

  group('iOS: calls, Siri and alarms', () {
    setUp(() => PlatformInfo.debugIsIOS = true);

    test('a call that ends with "may resume": the music plays again', () async {
      await playing();
      await send(_iosBegins);
      expect(player.playing, isFalse);
      await send(_iosEndsMayResume);
      expect(player.playing, isTrue);
      expect(watcher.starts, 0, reason: 'iOS needs no watcher: it says when to resume');
    });

    test('a call that ends without "may resume": the music stays paused', () async {
      await playing();
      await send(_iosBegins);
      await send(_iosEndsNoResume);
      expect(player.playing, isFalse);
    });

    test('paused or played by the user during the call: nothing resumes by itself', () async {
      await playing();
      await send(_iosBegins);
      await handler.pause(); // e.g. from Control Center
      await _settle();
      await send(_iosEndsMayResume);
      expect(player.playing, isFalse);
    });

    test('paused before the call: it stays paused after it', () async {
      await playing();
      await handler.pause();
      await _settle();
      await send(_iosBegins);
      await send(_iosEndsMayResume);
      expect(player.playing, isFalse);
    });

    test('Siri during a call: one resume at the end', () async {
      await playing();
      await send(_iosBegins);
      await send(_iosBegins);
      await send(_iosEndsMayResume);
      expect(player.playing, isTrue);
    });

    test('the Online hand-off item follows the music rule', () async {
      final stream = _song(9).copyWith(id: 'yt_dQw4w9WgXcQ', uri: 'https://rr1---sn.googlevideo.com/x', source: 'online');
      await handler.loadQueue([stream], autoPlay: true);
      await _settle();
      await send(_iosBegins);
      expect(player.playing, isFalse);
      await send(_iosEndsMayResume);
      expect(player.playing, isTrue);
    });

    test('a video on screen is paused and resumed through its own controls', () async {
      final video = _Delegate();
      handler.setExternalSource(video, _snapshot('video:v1', playing: true));
      await _settle();
      await send(_iosBegins);
      expect(video.calls, contains('pause'));
      handler.updateExternalMedia(video, _snapshot('video:v1', playing: false));
      await send(_iosEndsMayResume);
      expect(video.calls.last, 'play');
    });

    test('a video that iOS paused just before the call started still resumes', () async {
      final video = _Delegate();
      handler.setExternalSource(video, _snapshot('video:v1', playing: true));
      handler.updateExternalMedia(video, _snapshot('video:v1', playing: false));
      await _settle();
      await send(_iosBegins);
      await send(_iosEndsMayResume);
      expect(video.calls, contains('play'));
    });

    test('a video the user paused long before the call stays paused', () async {
      final video = _Delegate();
      handler.setExternalSource(video, _snapshot('video:v1', playing: true));
      handler.updateExternalMedia(video, _snapshot('video:v1', playing: false));
      await _settle();
      now = now.add(const Duration(seconds: 30));
      await send(_iosBegins);
      await send(_iosEndsMayResume);
      expect(video.calls, isNot(contains('play')));
    });

    test('the Online page is left to WebKit', () async {
      final page = _Delegate();
      handler.setExternalSource(page, _snapshot('online:dQw4w9WgXcQ', playing: true));
      await _settle();
      await send(_iosBegins);
      handler.updateExternalMedia(page, _snapshot('online:dQw4w9WgXcQ', playing: false));
      await send(_iosEndsMayResume);
      expect(page.calls, isNot(contains('play')));
      expect(page.calls, isNot(contains('pause')));
    });
  });
}
