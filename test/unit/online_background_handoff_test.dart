import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/online/online_background_handoff.dart';
import 'package:mediahub/features/online/online_bridge_protocol.dart';
import 'package:mediahub/features/online/online_media_session.dart';

const _watch = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ';
const _m4a = 'https://rr1.googlevideo.com/videoplayback?itag=140&id=a';
const _webm = 'https://rr1.googlevideo.com/videoplayback?itag=251&id=a';

class _Host implements ExternalPlaybackHost {
  ExternalPlaybackDelegate? active;

  @override
  void setExternalSource(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) => active = delegate;

  @override
  void updateExternalMedia(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {}

  @override
  void clearExternalSource(ExternalPlaybackDelegate delegate) {
    if (identical(active, delegate)) active = null;
  }

  /// What the music handler does when local playback starts.
  void localPlaybackStarts() {
    final d = active;
    active = null;
    d?.externalPause();
    d?.onExternalSourceReleased();
  }
}

class _Player implements HandoffPlayer {
  _Player(this.host);
  final _Host host;
  final List<String> log = [];
  domain.PlaybackState? local;
  domain.MediaItem? item;
  domain.PlaybackState? restored;
  @override
  HandoffPlayerState current = const HandoffPlayerState();

  @override
  domain.PlaybackState? captureLocal() => local;

  /// The next this many tries fail the way the real player reports a
  /// refused stream: the item is loaded but does not play.
  int failNext = 0;

  @override
  Future<void> playAlone(domain.MediaItem item, Duration position, {bool play = true}) async {
    log.add('play ${item.id} @${position.inMilliseconds}');
    this.item = item;
    if (failNext > 0) {
      failNext--;
      current = HandoffPlayerState(itemId: item.id, position: position);
      throw const HandoffPlaybackException('failed');
    }
    host.localPlaybackStarts();
    current = HandoffPlayerState(itemId: item.id, position: position, playing: play);
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    current = HandoffPlayerState(itemId: current.itemId, position: current.position, playing: false);
  }

  @override
  Future<void> restoreLocal(domain.PlaybackState? saved) async {
    log.add('restore ${saved?.queue.length ?? 0}');
    restored = saved;
  }

  @override
  Future<void> restoreSettings() async => log.add('settings');
}

OnlineStreams _streams() => const OnlineStreams(
      audio: [
        OnlineStream(url: _webm, kind: OnlineStreamKind.audio, label: '160 kbps', container: 'webm', sizeBytes: 1, bitrateKbps: 160),
        OnlineStream(url: _m4a, kind: OnlineStreamKind.audio, label: '128 kbps', container: 'mp4', sizeBytes: 1, bitrateKbps: 128),
      ],
      video: [],
    );

OnlineMediaState _state(OnlineMediaStatus status, {double pos = 42, String event = 'timeupdate'}) => OnlineMediaState(
      status: status,
      position: Duration(milliseconds: (pos * 1000).round()),
      duration: const Duration(minutes: 3, seconds: 33),
      title: 'Never Gonna Give You Up',
      artist: 'Rick Astley',
      artworkUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      pageUrl: Uri.parse(_watch),
      event: event,
    );

domain.MediaItem _song(String id) => domain.MediaItem(
      id: id,
      uri: '/music/$id.mp3',
      mediaType: domain.MediaType.audio,
      title: id,
      durationMs: 1000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('onlineHandoffEnabled', () {
    test('Android never hands the page to the music player (the WebView plays on after a swipe-away)', () {
      expect(onlineHandoffEnabled(isIOS: false, backgroundPlay: true), isFalse);
      expect(onlineHandoffEnabled(isIOS: false, backgroundPlay: false), isFalse);
    });

    test('iOS hands off only with Background play on', () {
      expect(onlineHandoffEnabled(isIOS: true, backgroundPlay: true), isTrue);
      expect(onlineHandoffEnabled(isIOS: true, backgroundPlay: false), isFalse);
    });
  });

  late _Host host;
  late OnlineMediaSession session;
  late _Player player;
  late List<BridgeCommand> sent;
  late int resolves;
  late bool enabled;
  late Future<OnlineStreams> Function(String id) resolver;
  late DateTime now;
  late OnlineBackgroundHandoff handoff;

  OnlineBackgroundHandoff build() => OnlineBackgroundHandoff(
        session: session,
        player: player,
        resolveStreams: (id) {
          resolves++;
          return resolver(id);
        },
        enabled: () => enabled,
        clock: () => now,
      );

  setUp(() {
    now = DateTime(2026, 11, 18, 9);
    host = _Host();
    session = OnlineMediaSession(host: host, clock: () => now, resumeBackgroundInterruptions: true);
    sent = [];
    session.attachSender((c) async {
      sent.add(c);
      return true;
    });
    player = _Player(host);
    resolves = 0;
    enabled = true;
    resolver = (id) async => _streams();
    handoff = build();
  });

  tearDown(() {
    handoff.dispose();
    session.dispose();
  });

  void push(OnlineMediaState s) => session.handleMessage(BridgeMediaMessage(s));

  void lifecycle(AppLifecycleState s) {
    handoff.lifecycleChanged(s);
    session.appLifecycleChanged(s);
  }

  void lock() {
    lifecycle(AppLifecycleState.inactive);
    lifecycle(AppLifecycleState.hidden);
    lifecycle(AppLifecycleState.paused);
  }

  void unlock() {
    lifecycle(AppLifecycleState.hidden);
    lifecycle(AppLifecycleState.inactive);
    lifecycle(AppLifecycleState.resumed);
  }

  test('locking the phone hands the playing video to the native player, from the same spot', () async {
    player.local = domain.PlaybackState(queue: [_song('a'), _song('b')], queueIndex: 1, updatedAt: DateTime(2026));
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    // WebKit pauses the page as the app leaves: the hand-off holds it there.
    push(_state(OnlineMediaStatus.paused, event: 'pause', pos: 42.3));
    await _settle();

    expect(handoff.isHandedOff, isTrue);
    final item = player.item!;
    expect(item.id, 'yt_dQw4w9WgXcQ');
    expect(item.source, 'online', reason: 'never saved by the music player');
    expect(item.uri, _m4a, reason: 'AAC in mp4: iOS cannot play WebM / Opus');
    expect(item.title, 'Never Gonna Give You Up');
    expect(item.artist, 'Rick Astley');
    expect(item.artworkPath, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(item.durationMs, 213000);
    expect(player.log, ['play yt_dQw4w9WgXcQ @42300']);
    expect(sent, contains(const BridgeCommand.pause()));
    expect(sent, isNot(contains(const BridgeCommand.play())), reason: 'the page is held paused');
    expect(session.holdPage, isTrue);
  });

  test('unlocking gives it back: the page jumps to the native spot and plays; local music comes back', () async {
    player.local = domain.PlaybackState(queue: [_song('a'), _song('b')], queueIndex: 1, updatedAt: DateTime(2026));
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    await _settle();
    expect(handoff.isHandedOff, isTrue);
    // Ten minutes of native playing later.
    player.current = const HandoffPlayerState(itemId: 'yt_dQw4w9WgXcQ', position: Duration(seconds: 160), playing: true);
    sent.clear();

    unlock();
    await _settle();
    expect(sent, [BridgeCommand.seekTo(const Duration(seconds: 160)), const BridgeCommand.play()]);
    expect(player.log.sublist(1), ['pause', 'restore 2']);
    expect(player.restored!.queueIndex, 1);
    expect(handoff.isHandedOff, isFalse);
    expect(session.holdPage, isFalse);

    // The page's play claims the notification again at once.
    push(_state(OnlineMediaStatus.playing, event: 'play', pos: 160));
    expect(host.active, same(session));
  });

  test('paused on the lock screen: the page gets the spot but stays paused', () async {
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    await _settle();
    player.current = const HandoffPlayerState(itemId: 'yt_dQw4w9WgXcQ', position: Duration(seconds: 70));
    sent.clear();
    unlock();
    await _settle();
    expect(sent, [BridgeCommand.seekTo(const Duration(seconds: 70))]);
    expect(player.log.last, 'restore 0', reason: 'no local queue before: the player is cleared');
  });

  test('the music player moved on meanwhile: the page and that music are left alone', () async {
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    await _settle();
    player.current = const HandoffPlayerState(itemId: 'local_song', position: Duration(seconds: 5), playing: true);
    sent.clear();
    unlock();
    await _settle();
    expect(sent, isEmpty);
    expect(player.log, ['play yt_dQw4w9WgXcQ @42000', 'settings'], reason: 'only the user\'s repeat mode comes back');
  });

  test('back before the stream was ready: nothing native starts, and the page plays on', () async {
    final stream = Completer<OnlineStreams>();
    resolver = (id) => stream.future;
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    await _settle();
    expect(handoff.isResolving, isTrue);
    sent.clear();
    unlock();
    await _settle();
    expect(sent, [const BridgeCommand.play()], reason: 'what WebKit interrupted is undone');
    stream.complete(_streams());
    await _settle();
    expect(player.log, isEmpty);
    expect(handoff.isHandedOff, isFalse);
    expect(session.holdPage, isFalse);
  });

  test('no stream iOS can play: the page is asked to play on instead', () async {
    resolver = (id) async => const OnlineStreams(
          audio: [OnlineStream(url: _webm, kind: OnlineStreamKind.audio, label: '', container: 'webm', sizeBytes: 1)],
          video: [],
        );
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    await _settle();
    expect(player.log, isEmpty);
    expect(sent.last, const BridgeCommand.play());
    expect(session.holdPage, isFalse);
  });

  test('a lookup error also falls back to the page', () async {
    resolver = (id) async => throw const OnlineException('offline');
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    await _settle();
    expect(player.log, isEmpty);
    expect(sent.last, const BridgeCommand.play());
  });

  test('the stream is refused: one more try with a newly looked-up link, which plays', () async {
    var lookups = 0;
    resolver = (id) async {
      lookups++;
      return OnlineStreams(audio: [
        OnlineStream(url: '$_m4a&n=$lookups', kind: OnlineStreamKind.audio, label: '', container: 'mp4', sizeBytes: 1),
      ], video: const []);
    };
    player.failNext = 1;
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    await _settle();

    expect(resolves, 2, reason: 'the cached link is dropped and looked up again');
    expect(player.log, ['play yt_dQw4w9WgXcQ @42000', 'play yt_dQw4w9WgXcQ @42000']);
    expect(player.item!.uri, '$_m4a&n=2');
    expect(handoff.isHandedOff, isTrue);
    expect(sent, isNot(contains(const BridgeCommand.play())), reason: 'the page stays held');
    expect(session.holdPage, isTrue);
  });

  test('both tries fail: the page is asked to play on, and the user\'s queue comes back', () async {
    player.local = domain.PlaybackState(queue: [_song('a'), _song('b')], queueIndex: 1, updatedAt: DateTime(2026));
    player.failNext = 2;
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    await _settle();

    expect(player.log, ['play yt_dQw4w9WgXcQ @42000', 'play yt_dQw4w9WgXcQ @42000', 'restore 2']);
    expect(player.restored!.queueIndex, 1);
    expect(handoff.isHandedOff, isFalse);
    expect(sent.last, const BridgeCommand.play(), reason: 'last try: the page itself (WebKit may allow it)');
    expect(session.holdPage, isFalse);

    // Back in the app later: nothing is given back twice.
    player.log.clear();
    unlock();
    await _settle();
    expect(player.log, isEmpty);
  });

  test('no new link for the second try: the page plays on at once', () async {
    var lookups = 0;
    resolver = (id) async {
      lookups++;
      if (lookups > 1) throw const OnlineException('offline');
      return _streams();
    };
    player.failNext = 1;
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    await _settle();
    expect(player.log, ['play yt_dQw4w9WgXcQ @42000', 'restore 0']);
    expect(sent.last, const BridgeCommand.play());
  });

  test('nothing happens when off (Android, or Background play off), paused, or not a video', () async {
    enabled = false;
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    await _settle();
    expect(resolves, 0);
    unlock();

    enabled = true;
    push(_state(OnlineMediaStatus.paused, event: 'pause'));
    now = now.add(const Duration(minutes: 1));
    lock();
    await _settle();
    expect(resolves, 0, reason: 'the user had paused it');
    expect(player.log, isEmpty);
  });

  test('the browser\'s own picture-in-picture keeps playing: no hand-off', () async {
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    session.handleMessage(const BridgePipMessage(true));
    lock();
    await _settle();
    expect(resolves, 0);
  });

  test('after an Auto PiP request it waits for the page, then hands off only without PiP', () {
    fakeAsync((async) {
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      handoff.pipRequested();
      lock();
      async.flushMicrotasks();
      expect(resolves, 0, reason: 'waiting for the page to answer');
      session.handleMessage(const BridgePipMessage(true));
      async.elapse(const Duration(seconds: 1));
      expect(resolves, 0, reason: 'it went into picture-in-picture');
    });
    fakeAsync((async) {
      final h = build();
      session.handleMessage(const BridgePipMessage(false));
      unlock();
      h.lifecycleChanged(AppLifecycleState.resumed);
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      h.pipRequested();
      h.lifecycleChanged(AppLifecycleState.inactive);
      h.lifecycleChanged(AppLifecycleState.hidden);
      async.elapse(const Duration(seconds: 1));
      expect(h.isResolving || h.isHandedOff, isTrue, reason: 'no PiP after all');
      h.dispose();
    });
  });

  test('the stream is fetched ahead while the video plays, so leaving does not wait for it', () async {
    handoff.prefetch('dQw4w9WgXcQ');
    handoff.prefetch('dQw4w9WgXcQ');
    await _settle();
    expect(resolves, 1);
    resolver = (id) => Completer<OnlineStreams>().future; // the network is gone now
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    await _settle();
    expect(handoff.isHandedOff, isTrue);
    expect(resolves, 1);
  });

  test('a prefetched link older than 4 hours is fetched again', () async {
    handoff.prefetch('dQw4w9WgXcQ');
    await _settle();
    now = now.add(const Duration(hours: 4, minutes: 1));
    push(_state(OnlineMediaStatus.playing, event: 'play'));
    lock();
    await _settle();
    expect(resolves, 2);
    expect(handoff.isHandedOff, isTrue);
  });

  test('prefetch does nothing when off or for a bad id', () async {
    enabled = false;
    handoff.prefetch('dQw4w9WgXcQ');
    enabled = true;
    handoff.prefetch('not-an-id');
    handoff.prefetch(null);
    await _settle();
    expect(resolves, 0);
  });

  group('Android: swiped away from recents (proactive)', () {
    late bool detachedOn;
    OnlineBackgroundHandoff buildAndroid() => OnlineBackgroundHandoff(
          session: session,
          player: player,
          resolveStreams: (id) {
            resolves++;
            return resolver(id);
          },
          enabled: () => false,
          detachedEnabled: () => detachedOn,
          clock: () => now,
        );

    void swipeAway() {
      lifecycle(AppLifecycleState.inactive);
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.paused);
      lifecycle(AppLifecycleState.detached);
    }

    setUp(() {
      handoff.dispose();
      detachedOn = true;
      handoff = buildAndroid();
    });

    test('a playing video moves to the native player at once, without waiting for the browser to pause it', () async {
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      // Going home prefetches the stream.
      lifecycle(AppLifecycleState.inactive);
      lifecycle(AppLifecycleState.hidden);
      await _settle();
      expect(resolves, 1);
      lifecycle(AppLifecycleState.paused);
      lifecycle(AppLifecycleState.detached);
      await _settle();
      expect(handoff.isHandedOff, isTrue);
      expect(player.current.playing, isTrue);
      expect(player.log.first, startsWith('play yt_dQw4w9WgXcQ @42'));
      expect(resolves, 1, reason: 'the prefetched link is used');
      // The page is paused only after the native player plays: one source.
      expect(sent.where((c) => c.kind == BridgeCommandKind.pause), isNotEmpty);
      expect(session.holdPage, isTrue);
    });

    test('a paused video is loaded natively, paused, so the notification Play goes to it', () async {
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      push(_state(OnlineMediaStatus.paused, event: 'pause'));
      swipeAway();
      await _settle();
      expect(handoff.isHandedOff, isTrue);
      expect(player.current.playing, isFalse);
      expect(player.current.itemId, 'yt_dQw4w9WgXcQ');
      expect(session.isActive, isFalse, reason: 'Play from the controls goes to the native player');
    });

    test('a second detached play while handed off reports success without a new hand-off', () async {
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      swipeAway();
      await _settle();
      final plays = player.log.where((l) => l.startsWith('play')).length;
      expect(await handoff.startDetachedPlay(), isTrue);
      expect(player.log.where((l) => l.startsWith('play')).length, plays);
    });

    test('reopening hands back once: native pauses first, then the page seeks and plays', () async {
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      swipeAway();
      await _settle();
      sent.clear();
      player.log.clear();
      lifecycle(AppLifecycleState.resumed);
      await _settle();
      expect(handoff.isHandedOff, isFalse);
      expect(player.log.first, 'pause');
      expect(sent.map((c) => c.kind), containsAllInOrder([BridgeCommandKind.seekTo, BridgeCommandKind.play]));
    });

    test('a paused hand-off given back: the page keeps the controls (the media service stays)', () async {
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      push(_state(OnlineMediaStatus.paused, event: 'pause'));
      swipeAway();
      await _settle();
      expect(session.isActive, isFalse);
      lifecycle(AppLifecycleState.resumed);
      await _settle();
      expect(handoff.isHandedOff, isFalse);
      expect(session.isActive, isTrue);
    });

    test('no stream: the notification stays with the page and nothing is handed off', () async {
      resolver = (id) async => throw Exception('blocked');
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      swipeAway();
      await _settle();
      expect(handoff.isHandedOff, isFalse);
      expect(session.isActive, isTrue);
    });

    test('a refused link (403) is looked up again through the next YouTube clients', () async {
      final variants = <int>[];
      handoff.dispose();
      handoff = OnlineBackgroundHandoff(
        session: session,
        player: player,
        resolveStreams: (id) async {
          variants.add(0);
          return _streams();
        },
        resolveStreamsVariant: (id, v) async {
          variants.add(v);
          return _streams();
        },
        enabled: () => false,
        detachedEnabled: () => true,
        clock: () => now,
      );
      player.failNext = 2;
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      swipeAway();
      await _settle();
      await _settle();
      expect(variants, [0, 1, 2]);
      expect(handoff.isHandedOff, isTrue);
    });

    test('a link the stream server refuses is skipped before anything plays', () async {
      final variants = <int>[];
      handoff.dispose();
      handoff = OnlineBackgroundHandoff(
        session: session,
        player: player,
        resolveStreams: (id) async {
          variants.add(0);
          return _streams();
        },
        resolveStreamsVariant: (id, v) async {
          variants.add(v);
          return _streams();
        },
        verifyStream: (url) async => variants.length > 1,
        enabled: () => false,
        detachedEnabled: () => true,
        clock: () => now,
      );
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      swipeAway();
      await _settle();
      await _settle();
      expect(variants, [0, 1]);
      expect(player.log.where((l) => l.startsWith('play')), hasLength(1));
      expect(handoff.isHandedOff, isTrue);
    });

    test('Background play off: nothing happens on a swipe-away', () async {
      detachedOn = false;
      push(_state(OnlineMediaStatus.playing, event: 'play'));
      swipeAway();
      await _settle();
      expect(handoff.isHandedOff, isFalse);
      expect(player.log, isEmpty);
    });
  });

  group('pickHandoffStream', () {
    test('AAC audio in mp4, highest bitrate first', () {
      const s = OnlineStreams(
        audio: [
          OnlineStream(url: 'https://a/1', kind: OnlineStreamKind.audio, label: '', container: 'mp4', sizeBytes: 1, bitrateKbps: 48),
          OnlineStream(url: 'https://a/2', kind: OnlineStreamKind.audio, label: '', container: 'webm', sizeBytes: 1, bitrateKbps: 160),
          OnlineStream(url: 'https://a/3', kind: OnlineStreamKind.audio, label: '', container: 'mp4', sizeBytes: 1, bitrateKbps: 128),
        ],
        video: [],
      );
      expect(pickHandoffStream(s)!.url, 'https://a/3');
    });

    test('else the smallest mp4 video with sound; never WebM', () {
      const s = OnlineStreams(
        audio: [OnlineStream(url: 'https://a/w', kind: OnlineStreamKind.audio, label: '', container: 'webm', sizeBytes: 1)],
        video: [
          OnlineStream(url: 'https://v/720', kind: OnlineStreamKind.video, label: '', container: 'mp4', sizeBytes: 1, height: 720),
          OnlineStream(url: 'https://v/360', kind: OnlineStreamKind.video, label: '', container: 'mp4', sizeBytes: 1, height: 360),
          OnlineStream(url: 'https://v/w', kind: OnlineStreamKind.video, label: '', container: 'webm', sizeBytes: 1, height: 144),
        ],
      );
      expect(pickHandoffStream(s)!.url, 'https://v/360');
      expect(pickHandoffStream(const OnlineStreams(audio: [], video: [])), isNull);
    });
  });
}
