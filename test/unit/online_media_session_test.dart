import 'package:fake_async/fake_async.dart';
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

  test('a paused page, or one that is not a video page, does not claim it', () {
    push(state(OnlineMediaStatus.paused));
    push(state(OnlineMediaStatus.playing, url: 'https://m.youtube.com/'));
    expect(host.log, isEmpty);
    expect(session.isActive, isFalse);
    expect(session.media.value?.status, OnlineMediaStatus.playing, reason: 'the state is still tracked');
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

  test('paused for long hands the session back; playing again cancels that', () {
    fakeAsync((async) {
      push(state(OnlineMediaStatus.playing, event: 'play'));
      push(state(OnlineMediaStatus.paused, event: 'pause'));
      async.elapse(const Duration(minutes: 9));
      expect(host.log.contains('clear'), isFalse);
      push(state(OnlineMediaStatus.playing, event: 'play'));
      playFor(async, const Duration(minutes: 30));
      expect(host.log.contains('clear'), isFalse, reason: 'still playing');
      expect(sent, isNot(contains(const BridgeCommand.requestState())), reason: 'the ticks kept coming');
      push(state(OnlineMediaStatus.paused, event: 'pause'));
      async.elapse(const Duration(minutes: 10, seconds: 1));
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
      async.elapse(const Duration(minutes: 10, seconds: 1));
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
}
