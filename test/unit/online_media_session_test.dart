import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/online/online_bridge_protocol.dart';
import 'package:mediahub/features/online/online_media_session.dart';

class FakeHost implements ExternalPlaybackHost {
  final List<String> log = [];
  ExternalPlaybackDelegate? active;
  ExternalMediaSnapshot? last;

  @override
  void setExternalSource(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    log.add('set');
    active = delegate;
    last = snapshot;
  }

  @override
  void updateExternalMedia(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    if (!identical(active, delegate)) return;
    log.add('update');
    last = snapshot;
  }

  @override
  void clearExternalSource(ExternalPlaybackDelegate delegate) {
    if (!identical(active, delegate)) return;
    log.add('clear');
    active = null;
  }

  /// What the handler does when local music starts.
  void localMusicStarts() {
    final d = active;
    active = null;
    log.add('local');
    d?.externalPause();
    d?.onExternalSourceReleased();
  }
}

OnlineMediaState state(
  OnlineMediaStatus status, {
  String url = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
  double pos = 10,
  String event = 'timeupdate',
  bool hasNext = true,
  String title = 'Video',
  bool byPage = false,
  bool bySystem = false,
}) =>
    OnlineMediaState(
      status: status,
      position: Duration(milliseconds: (pos * 1000).round()),
      duration: const Duration(minutes: 3),
      title: title,
      artist: 'Channel',
      artworkUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      hasNext: hasNext,
      pageUrl: Uri.parse(url),
      event: event,
      pausedByPage: byPage,
      pausedBySystemControls: bySystem,
    );

void main() {
  late FakeHost host;
  late OnlineMediaSession session;
  late List<BridgeCommand> sent;
  DateTime now = DateTime(2026, 11, 17, 12);

  setUp(() {
    host = FakeHost();
    sent = [];
    now = DateTime(2026, 11, 17, 12);
    session = OnlineMediaSession(host: host, clock: () => now);
    session.attachSender((c) async {
      sent.add(c);
      return true;
    });
  });

  tearDown(() => session.dispose());

  void push(OnlineMediaState s) => session.handleMessage(BridgeMediaMessage(s));

  test('a playing video claims the session with its metadata', () {
    push(state(OnlineMediaStatus.playing, event: 'play'));
    expect(host.log, ['set']);
    expect(session.isActive, isTrue);
    final snap = host.last!;
    expect(snap.id, 'online:dQw4w9WgXcQ');
    expect(snap.title, 'Video');
    expect(snap.artist, 'Channel');
    expect(snap.artUri.toString(), 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(snap.playing, isTrue);
    expect(snap.canSkipNext, isTrue);
    expect(snap.duration, const Duration(minutes: 3));
    push(state(OnlineMediaStatus.playing, pos: 11));
    expect(host.log, ['set', 'update']);
  });

  // Block ads: while the bridge skips an ad it reports the video itself as
  // loading (event 'ad', the video's own title and position); see
  // test/js/youtube_bridge_test.js for the page side.
  test('an ad being skipped keeps the notification on the video and never counts as a pause', () {
    push(state(OnlineMediaStatus.playing, event: 'play', pos: 60, title: 'Song'));
    push(state(OnlineMediaStatus.buffering, event: 'ad', pos: 60, title: 'Song'));
    expect(host.last!.title, 'Song');
    expect(host.last!.playing, isTrue, reason: 'loading, not stopped');
    expect(host.last!.buffering, isTrue);
    expect(host.last!.position, const Duration(seconds: 60));
    // Even screen off, with an ad paused at its end: no automatic resume, no hand-back.
    session.appLifecycleChanged(AppLifecycleState.paused);
    push(state(OnlineMediaStatus.paused, event: 'ad', pos: 60, title: 'Song', byPage: true));
    expect(sent, isEmpty);
    push(state(OnlineMediaStatus.playing, event: 'adend', pos: 60, title: 'Song'));
    expect(session.isActive, isTrue);
    expect(host.log, ['set', 'update', 'update', 'update']);
  });

  test('a paused page, or a moment of sound on another page, does not claim it', () {
    push(state(OnlineMediaStatus.paused));
    push(state(OnlineMediaStatus.playing, url: 'https://m.youtube.com/'));
    expect(host.log, isEmpty);
    expect(session.isActive, isFalse);
    expect(session.media.value?.status, OnlineMediaStatus.playing, reason: 'the state is still tracked');
  });

  test('sound that keeps playing on any YouTube page claims it after 3 s (YouTube Music, a trailer)', () {
    const music = 'https://music.youtube.com/';
    push(state(OnlineMediaStatus.playing, url: music, event: 'play'));
    now = now.add(const Duration(seconds: 2));
    push(state(OnlineMediaStatus.playing, url: music));
    expect(host.log, isEmpty, reason: 'a short preview never takes the notification');
    now = now.add(const Duration(seconds: 1));
    push(state(OnlineMediaStatus.playing, url: music));
    expect(host.log, ['set']);
    expect(session.isActive, isTrue);
  });

  test('a pause restarts the 3 s count on a non-video page', () {
    const channel = 'https://m.youtube.com/@channel';
    push(state(OnlineMediaStatus.playing, url: channel, event: 'play'));
    now = now.add(const Duration(seconds: 2));
    push(state(OnlineMediaStatus.paused, url: channel, event: 'pause'));
    now = now.add(const Duration(seconds: 2));
    push(state(OnlineMediaStatus.playing, url: channel, event: 'play'));
    now = now.add(const Duration(seconds: 2));
    push(state(OnlineMediaStatus.playing, url: channel));
    expect(host.log, isEmpty);
    now = now.add(const Duration(seconds: 1));
    push(state(OnlineMediaStatus.playing, url: channel));
    expect(host.log, ['set']);
  });

  test('notification buttons become bridge commands', () async {
    push(state(OnlineMediaStatus.playing, event: 'play'));
    await host.active!.externalPause();
    await host.active!.externalPlay();
    await host.active!.externalSeek(const Duration(seconds: 42));
    await host.active!.externalSkipToNext();
    await host.active!.externalSkipToPrevious();
    expect(sent, [
      const BridgeCommand.pause(),
      const BridgeCommand.play(),
      BridgeCommand.seekTo(const Duration(seconds: 42)),
      const BridgeCommand.next(),
      const BridgeCommand.previous(),
    ]);
  });

  test('without a page the commands are dropped quietly', () async {
    session.attachSender(null);
    expect(await session.send(const BridgeCommand.play()), isFalse);
  });

  /// A playing page reports about once a second; this plays it for [d].
  void playFor(FakeAsync async, Duration d) {
    for (var s = 1; s <= d.inSeconds; s++) {
      async.elapse(const Duration(seconds: 1));
      push(state(OnlineMediaStatus.playing, pos: s.toDouble()));
    }
  }

  test('paused for 30 minutes hands the session back; playing again cancels that', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      push(state(OnlineMediaStatus.paused, event: 'pause'));
      // The lock screen keeps a paused video's controls for as long as the
      // music player keeps a paused song's (30 minutes), not 10.
      async.elapse(const Duration(minutes: 29));
      expect(host.log.contains('clear'), isFalse);
      push(state(OnlineMediaStatus.playing, event: 'play'));
      playFor(async, const Duration(minutes: 30));
      expect(host.log.contains('clear'), isFalse, reason: 'still playing');
      expect(sent, isNot(contains(const BridgeCommand.requestState())), reason: 'the ticks kept coming');
      push(state(OnlineMediaStatus.paused, event: 'pause'));
      async.elapse(const Duration(minutes: 29, seconds: 59));
      expect(host.log.contains('clear'), isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(host.log.last, 'clear');
      expect(session.isActive, isFalse);
    });
  });

  test('no video at all (left the watch page) hands it back soon', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      push(state(OnlineMediaStatus.none, url: 'https://m.youtube.com/', event: 'emptied'));
      async.elapse(const Duration(seconds: 16));
      expect(host.log.last, 'clear');
    });
  });

  test('a new document ends the old video: not playing, handed back soon', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      expect(host.last!.playing, isTrue);
      // Our search, Clear site data, a reload or YouTube's own full load:
      // the new document's bridge says "ready"; its feed previews are muted,
      // so no media message follows.
      session.handleMessage(BridgeReadyMessage(Uri.parse('https://m.youtube.com/results?search_query=x')));
      expect(host.last!.playing, isFalse, reason: 'the notification stops saying "playing"');
      expect(session.media.value!.status, OnlineMediaStatus.none);
      expect(session.media.value!.isPlaying, isFalse);
      async.elapse(const Duration(seconds: 16));
      expect(host.log.last, 'clear');
      expect(session.isActive, isFalse);
    });
  });

  test('a new document that plays keeps the session', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      session.handleMessage(BridgeReadyMessage(Uri.parse('https://m.youtube.com/watch?v=dQw4w9WgXcQ')));
      async.elapse(const Duration(seconds: 2));
      push(state(OnlineMediaStatus.playing, event: 'play', pos: 0));
      playFor(async, const Duration(seconds: 30));
      expect(host.log.contains('clear'), isFalse);
      expect(host.last!.playing, isTrue);
    });
  });

  test('"ready" before anything played changes nothing', () {
    session.handleMessage(BridgeReadyMessage(Uri.parse('https://m.youtube.com/')));
    expect(session.media.value, isNull);
    expect(host.log, isEmpty);
  });

  test('a playing page that goes quiet is asked once, then shown paused', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      async.elapse(const Duration(seconds: 5));
      expect(sent, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(sent, [const BridgeCommand.requestState()]);
      expect(host.last!.playing, isTrue, reason: 'not yet: the page may still answer');
      async.elapse(const Duration(seconds: 6));
      expect(host.last!.playing, isFalse);
      expect(session.media.value!.status, OnlineMediaStatus.paused);
      expect(session.media.value!.event, 'stale');
      expect(session.isActive, isTrue, reason: 'paused, so the notification can resume it');
      async.elapse(const Duration(minutes: 30, seconds: 1));
      expect(host.log.last, 'clear');
    });
  });

  test('a quiet page that answers the state request keeps playing', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      async.elapse(const Duration(seconds: 6));
      expect(sent, [const BridgeCommand.requestState()]);
      push(state(OnlineMediaStatus.buffering, event: 'request'));
      async.elapse(const Duration(seconds: 5));
      expect(host.last!.playing, isTrue);
      async.elapse(const Duration(seconds: 1));
      expect(sent, [const BridgeCommand.requestState(), const BridgeCommand.requestState()]);
      playFor(async, const Duration(seconds: 20));
      expect(host.last!.playing, isTrue);
      expect(host.log.contains('clear'), isFalse);
    });
  });

  test('local music taking over: in-flight ticks do not grab the session back', () {
    push(state(OnlineMediaStatus.playing, event: 'play'));
    host.localMusicStarts();
    expect(sent.last, const BridgeCommand.pause(), reason: 'YouTube was asked to pause');
    expect(session.isActive, isFalse);
    // A tick that was already on its way.
    push(state(OnlineMediaStatus.playing, pos: 12));
    expect(host.log.where((e) => e == 'set').length, 1);
    // A 'play' event right away is the same in-flight state.
    push(state(OnlineMediaStatus.playing, event: 'play'));
    expect(host.log.where((e) => e == 'set').length, 1);
    // The user presses play in the page a little later: claimed again.
    now = now.add(const Duration(seconds: 3));
    push(state(OnlineMediaStatus.playing, event: 'play'));
    expect(host.log.where((e) => e == 'set').length, 2);
  });

  test('after the page reports the pause, the next play claims again', () {
    push(state(OnlineMediaStatus.playing, event: 'play'));
    host.localMusicStarts();
    push(state(OnlineMediaStatus.paused, event: 'pause'));
    push(state(OnlineMediaStatus.playing, event: 'timeupdate'));
    expect(host.log.where((e) => e == 'set').length, 2);
  });

  test('detaching the page (WebView gone) clears the session', () {
    push(state(OnlineMediaStatus.playing, event: 'play'));
    session.detachPage();
    expect(host.log.last, 'clear');
    expect(session.hasSender, isFalse);
  });

  test('the browser PiP flag follows the page', () {
    session.handleMessage(const BridgePipMessage(true));
    expect(session.browserPipActive.value, isTrue);
    session.handleMessage(const BridgePipMessage(false));
    expect(session.browserPipActive.value, isFalse);
  });

  test('snapshot falls back to the page for a title and no next', () {
    final snap = OnlineMediaSession.snapshotOf(state(OnlineMediaStatus.buffering, title: '', hasNext: false));
    expect(snap.title, 'm.youtube.com');
    expect(snap.buffering, isTrue);
    expect(snap.playing, isTrue);
    expect(snap.canSkipNext, isFalse);
  });

  group('headphones unplugged (ONL-6)', () {
    late StreamController<void> noisy;
    late OnlineMediaSession s2;
    late List<BridgeCommand> sent2;

    setUp(() {
      noisy = StreamController<void>.broadcast();
      sent2 = [];
      s2 = OnlineMediaSession(host: host, clock: () => now, becomingNoisy: () => noisy.stream);
      s2.attachSender((c) async {
        sent2.add(c);
        return true;
      });
    });

    tearDown(() async {
      s2.dispose();
      await noisy.close();
    });

    test('pauses the video while the page owns the session, and only then', () async {
      expect(noisy.hasListener, isFalse, reason: 'nothing to pause yet');
      s2.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      expect(noisy.hasListener, isTrue);
      noisy.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(sent2, [const BridgeCommand.pause()]);
    });

    test('the watch ends when the session is handed back', () async {
      s2.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      host.localMusicStarts();
      expect(noisy.hasListener, isFalse, reason: 'local music has its own unplug pause');
      s2.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.paused, event: 'pause')));
      s2.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      expect(noisy.hasListener, isTrue, reason: 'claimed again');
      s2.detachPage();
      expect(noisy.hasListener, isFalse);
    });
  });

  group('keeping a background listen going (ONL-2, ONL-1)', () {
    void leave(OnlineMediaSession s) {
      s.appLifecycleChanged(AppLifecycleState.inactive);
      s.appLifecycleChanged(AppLifecycleState.hidden);
      s.appLifecycleChanged(AppLifecycleState.paused);
    }

    test('screen off: a pause the page made by itself is undone once', () {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      now = now.add(const Duration(minutes: 50));
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, [const BridgeCommand.play()]);
    });

    test('never while the app is on screen: the user sees the prompt', () {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, isEmpty);
    });

    test('never with Background play off', () {
      session.backgroundPlay = false;
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, isEmpty);
    });

    test('never a pause from the notification, a headset or the lock screen', () async {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      now = now.add(const Duration(minutes: 5));
      await host.active!.externalPause(); // the notification's pause
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, [const BridgeCommand.pause()], reason: 'commanded: not undone');

      push(state(OnlineMediaStatus.playing, event: 'play'));
      now = now.add(const Duration(minutes: 5));
      push(state(OnlineMediaStatus.paused, event: 'pause', bySystem: true));
      expect(sent, [const BridgeCommand.pause()], reason: 'the iOS lock screen: the user');
    });

    test('a pause that is not the page\'s own (audio focus, a call) is left alone on Android', () {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      push(state(OnlineMediaStatus.paused, event: 'pause'));
      expect(sent, isEmpty);
    });

    test('at most once a minute, so it can never fight the page', () {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      push(state(OnlineMediaStatus.playing, event: 'play'));
      now = now.add(const Duration(seconds: 10));
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, [const BridgeCommand.play()]);
      push(state(OnlineMediaStatus.playing, event: 'play'));
      now = now.add(const Duration(minutes: 2));
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, [const BridgeCommand.play(), const BridgeCommand.play()]);
    });

    test('not while the iOS hand-off holds the page paused', () {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      session.holdPage = true;
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, isEmpty);
    });

    test('iOS: a pause as the app leaves (WebKit) is undone once; later ones are not', () {
      final ios = OnlineMediaSession(host: FakeHost(), clock: () => now, resumeBackgroundInterruptions: true);
      final iosSent = <BridgeCommand>[];
      ios.attachSender((c) async {
        iosSent.add(c);
        return true;
      });
      addTearDown(ios.dispose);
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      leave(ios);
      now = now.add(const Duration(milliseconds: 600));
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.paused, event: 'pause')));
      expect(iosSent, [const BridgeCommand.play()]);

      // The page plays again; a pause minutes later is the user's (or the
      // end of a video) and stays.
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      now = now.add(const Duration(minutes: 3));
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.paused, event: 'pause')));
      expect(iosSent, [const BridgeCommand.play()]);
    });

    test('iOS: a pause just before the app finished leaving counts too', () {
      final ios = OnlineMediaSession(host: FakeHost(), clock: () => now, resumeBackgroundInterruptions: true);
      final iosSent = <BridgeCommand>[];
      ios.attachSender((c) async {
        iosSent.add(c);
        return true;
      });
      addTearDown(ios.dispose);
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      ios.appLifecycleChanged(AppLifecycleState.inactive);
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.paused, event: 'pause')));
      expect(iosSent, isEmpty, reason: 'inactive alone is not leaving');
      now = now.add(const Duration(milliseconds: 400));
      ios.appLifecycleChanged(AppLifecycleState.hidden);
      expect(iosSent, [const BridgeCommand.play()]);
    });

    test('iOS: a pause long before leaving (the user paused, then locked) stays', () {
      final ios = OnlineMediaSession(host: FakeHost(), clock: () => now, resumeBackgroundInterruptions: true);
      final iosSent = <BridgeCommand>[];
      ios.attachSender((c) async {
        iosSent.add(c);
        return true;
      });
      addTearDown(ios.dispose);
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.playing, event: 'play')));
      ios.handleMessage(BridgeMediaMessage(state(OnlineMediaStatus.paused, event: 'pause')));
      now = now.add(const Duration(seconds: 20));
      leave(ios);
      expect(iosSent, isEmpty);
    });

    test('coming back to the app ends it', () {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      leave(session);
      session.appLifecycleChanged(AppLifecycleState.resumed);
      expect(session.appInForeground, isTrue);
      push(state(OnlineMediaStatus.paused, event: 'pause', byPage: true));
      expect(sent, isEmpty);
    });
  });

  test('estimated position moves on with the clock while playing, and holds while paused', () {
    push(state(OnlineMediaStatus.playing, event: 'play', pos: 30));
    now = now.add(const Duration(milliseconds: 1500));
    expect(session.estimatedPosition(), const Duration(milliseconds: 31500));
    push(state(OnlineMediaStatus.paused, event: 'pause', pos: 31.8));
    now = now.add(const Duration(seconds: 10));
    expect(session.estimatedPosition(), const Duration(milliseconds: 31800));
  });

  test('expectPagePlay: the page reclaims at once after a hand-back', () {
    push(state(OnlineMediaStatus.playing, event: 'play'));
    host.localMusicStarts();
    session.expectPagePlay();
    push(state(OnlineMediaStatus.playing, event: 'play'));
    expect(host.log.where((e) => e == 'set').length, 2);
  });

  group('play from the controls after MediaHub was swiped away', () {
    test('a page that does not start without a window: the notification says so, opening the app plays', () {
      fakeAsync((async) {
        push(state(OnlineMediaStatus.playing, event: 'play'));
        push(state(OnlineMediaStatus.paused, event: 'pause'));
        session.appLifecycleChanged(AppLifecycleState.detached);
        sent.clear();
        host.active!.externalPlay();
        async.flushMicrotasks();
        expect(sent, [const BridgeCommand.play()]);
        async.elapse(const Duration(seconds: 3));
        expect(session.playWaitsForWindow, isTrue);
        expect(host.last!.artist, OnlineMediaSession.tapToResumeLine);
        expect(host.active, same(session), reason: 'the notification stays on the video, never local music');
        sent.clear();
        session.appLifecycleChanged(AppLifecycleState.resumed);
        expect(sent, [const BridgeCommand.play()]);
        expect(session.playWaitsForWindow, isFalse);
        push(state(OnlineMediaStatus.playing, event: 'play'));
        expect(host.last!.artist, 'Channel');
      });
    });

    test('a page that plays without a window needs nothing more', () {
      fakeAsync((async) {
        push(state(OnlineMediaStatus.playing, event: 'play'));
        push(state(OnlineMediaStatus.paused, event: 'pause'));
        session.appLifecycleChanged(AppLifecycleState.detached);
        host.active!.externalPlay();
        async.flushMicrotasks();
        push(state(OnlineMediaStatus.playing, event: 'play'));
        async.elapse(const Duration(seconds: 5));
        expect(session.playWaitsForWindow, isFalse);
        expect(host.last!.artist, 'Channel');
        sent.clear();
        session.appLifecycleChanged(AppLifecycleState.resumed);
        expect(sent, isNot(contains(const BridgeCommand.play())));
      });
    });

    test('a pause from the controls cancels the waiting play', () {
      fakeAsync((async) {
        push(state(OnlineMediaStatus.playing, event: 'play'));
        push(state(OnlineMediaStatus.paused, event: 'pause'));
        session.appLifecycleChanged(AppLifecycleState.detached);
        host.active!.externalPlay();
        async.elapse(const Duration(seconds: 3));
        host.active!.externalPause();
        async.flushMicrotasks();
        expect(session.playWaitsForWindow, isFalse);
        expect(host.last!.artist, 'Channel');
        sent.clear();
        session.appLifecycleChanged(AppLifecycleState.resumed);
        expect(sent, isNot(contains(const BridgeCommand.play())));
      });
    });

    test('with the app on screen a play is just a play', () {
      fakeAsync((async) {
        push(state(OnlineMediaStatus.playing, event: 'play'));
        push(state(OnlineMediaStatus.paused, event: 'pause'));
        host.active!.externalPlay();
        async.elapse(const Duration(seconds: 5));
        expect(session.playWaitsForWindow, isFalse);
      });
    });
  });
}
