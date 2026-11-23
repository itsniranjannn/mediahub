import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform_info.dart';
import '../music_player/music_audio_handler.dart';
import '../music_player/playback_notifier.dart';
import 'online_bridge_protocol.dart';
import 'youtube_urls.dart';

/// Sends one command to the page; resolves to whether the page had the bridge.
typedef BridgeCommandSender = Future<bool> Function(BridgeCommand command);

/// Connects the YouTube page to the phone's media session.
///
/// - While the page's video plays it becomes the [MusicAudioHandler]'s
///   external source: local music pauses and the notification, lock screen
///   and Bluetooth show the video and control it. A watch, Shorts or live
///   page claims it at once; any other YouTube page (YouTube Music's player,
///   a channel's autoplaying trailer with sound) after [claimAfter] of
///   unmuted playing, so a short preview never takes the notification.
/// - Paused for [pausedRelease] (or no video at all for [idleRelease]) hands
///   the session back to local music.
/// - While it owns the session, unplugging headphones (or a Bluetooth
///   headset going away) pauses the video, as in every media app.
/// - With Background play on and the app not on screen, a pause the page
///   made by itself (YouTube's "Continue watching?" stop) is undone once;
///   on iOS so is a pause that arrives as the app leaves the screen (WebKit
///   interrupting the page). Never a pause the user made, one MediaHub
///   commanded, or one from the phone's own controls.
/// - Starting local music hands it back at once (YouTube pauses); ticks that
///   were already on the way are then ignored until the page reports a real
///   stop or the user presses play in the page again.
/// - A new document (a full page load: our search, Clear site data, a reload
///   or YouTube's own) takes the old video with it, so the session stops
///   saying "playing" and is handed back soon unless the new page plays.
/// - A playing page reports about once a second. If it goes quiet for
///   [staleAfter], it is asked for its state once; still nothing after
///   another [staleAfter] (the page was frozen or went away without a last
///   word), the video is shown as paused and the paused release runs.
class OnlineMediaSession implements ExternalPlaybackDelegate {
  OnlineMediaSession({
    required this.host,
    this.pausedRelease = const Duration(minutes: 30),
    this.idleRelease = const Duration(seconds: 15),
    this.staleAfter = const Duration(seconds: 6),
    this.claimAfter = const Duration(seconds: 3),
    this.playCheckAfter = const Duration(seconds: 3),
    this.resumeBackgroundInterruptions = false,
    Stream<void> Function()? becomingNoisy,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _becomingNoisy = becomingNoisy; // ignore: prefer_initializing_formals

  /// The audio handler (or a fake in tests).
  final ExternalPlaybackHost host;
  final DateTime Function() _clock;

  /// How long a paused video keeps the notification (the music player's own
  /// paused-idle stop is also 30 minutes).
  final Duration pausedRelease;
  final Duration idleRelease;
  final Duration staleAfter;

  /// Unmuted playing this long on a YouTube page that is not a video page
  /// claims the session.
  final Duration claimAfter;

  /// How long a play from the phone's controls gets to start the page's
  /// video while MediaHub has no window (swiped away from recents).
  final Duration playCheckAfter;

  /// The notification's second line while a play is waiting for the app's
  /// window: the page could not start without it, and a tap on the
  /// notification opens MediaHub, which then plays.
  static const String tapToResumeLine = 'Tap to resume in MediaHub';

  /// iOS: WebKit pauses the page's video as the app leaves the screen. A
  /// pause within [backgroundInterruptWindow] of that is undone once.
  final bool resumeBackgroundInterruptions;

  /// Headphones unplugged (DeviceControls.watchBecomingNoisy('online')).
  final Stream<void> Function()? _becomingNoisy;

  /// A "play" event this long after local music took over is the user
  /// pressing play in the page again, not a tick still on its way.
  static const Duration resumeGrace = Duration(milliseconds: 1500);

  /// A pause this close to the app leaving the screen counts as WebKit's.
  static const Duration backgroundInterruptWindow = Duration(milliseconds: 1500);

  /// A pause within this of MediaHub's own pause command is that command.
  static const Duration commandedPauseWindow = Duration(seconds: 3);

  /// At most one automatic resume per this period, so the page and MediaHub
  /// can never fight over play and pause.
  static const Duration autoResumeCooldown = Duration(seconds: 60);

  BridgeCommandSender? _sender;
  bool _active = false;
  bool _suppressed = false;
  DateTime? _releasedAt;
  Timer? _releaseTimer;
  Timer? _staleTimer;
  bool _staleAsked = false;
  bool _disposed = false;
  DateTime? _playingSince;
  DateTime? _lastStateAt;
  StreamSubscription<void>? _noisySub;

  bool _appInForeground = true;

  /// The Flutter view has no Activity (the task was swiped away; the engine
  /// and this page live on in the audio service's process).
  bool _detached = false;

  /// A play from the phone's controls that the page could not carry out
  /// without a window: done as soon as the app is back on screen.
  bool _playWaitsForWindow = false;
  Timer? _playCheckTimer;
  DateTime? _backgroundedAt;
  DateTime? _lastCommandedPauseAt;
  DateTime? _lastAutoResumeAt;

  /// The last pause that came straight after playing, and when it came.
  OnlineMediaState? _lastPause;
  DateTime? _lastPauseAt;

  /// "Background play" (the Online screen keeps it in step with the setting).
  bool backgroundPlay = true;

  /// True while the iOS background hand-off plays the video natively: the
  /// page is paused on purpose and must not be resumed.
  bool holdPage = false;

  /// Latest validated state of the page's main video (null before any).
  final ValueNotifier<OnlineMediaState?> media = ValueNotifier<OnlineMediaState?>(null);

  /// The video is in the browser's own picture-in-picture (iOS).
  final ValueNotifier<bool> browserPipActive = ValueNotifier<bool>(false);

  /// True while the page owns the phone's media session.
  bool get isActive => _active;

  /// Set by the Online screen once its WebView exists (null when it goes away).
  void attachSender(BridgeCommandSender? sender) {
    _sender = sender;
  }

  bool get hasSender => _sender != null;

  Future<bool> send(BridgeCommand command) async {
    final sender = _sender;
    if (sender == null || _disposed) return false;
    if (command.kind == BridgeCommandKind.pause) _lastCommandedPauseAt = _clock();
    try {
      return await sender(command);
    } catch (e) {
      debugPrint('[Online] bridge command ${command.kind.name} failed: $e');
      return false;
    }
  }

  void handleMessage(BridgeMessage message) {
    if (_disposed) return;
    switch (message) {
      case BridgeMediaMessage(:final state):
        _onState(state);
      case BridgePipMessage(:final active):
        browserPipActive.value = active;
      case BridgeFullscreenMessage():
        break; // the Online screen's toolbar and orientation, not the media session
      case BridgeReadyMessage(:final pageUrl):
        documentReplaced(pageUrl);
        if (_playOnNextPage) {
          _playOnNextPage = false;
          DiagnosticsService.instance.logEvent('online_play_restored_page');
          send(const BridgeCommand.play());
        }
    }
  }

  /// The page loaded a new document (the bridge says "ready" once per
  /// document, before anything in it plays): whatever the old document was
  /// playing is gone. Reported as "no video", which hands the session back
  /// after [idleRelease] unless the new page starts playing first.
  void documentReplaced(Uri? pageUrl) {
    if (_disposed || media.value == null) return;
    _onState(OnlineMediaState(status: OnlineMediaStatus.none, pageUrl: pageUrl, event: 'document'));
  }

  void _onState(OnlineMediaState s) {
    if (s.isPlaying && _playWaitsForWindow) {
      _playWaitsForWindow = false; // it started after all
      _playCheckTimer?.cancel();
    }
    final previous = media.value;
    final now = _clock();
    media.value = s;
    _lastStateAt = now;
    if (s.isPlaying) {
      _playingSince ??= now;
      _cancelRelease();
      if (!_active) {
        if (_suppressed) {
          final releasedAt = _releasedAt;
          final userPressedPlay = s.event == 'play' &&
              releasedAt != null &&
              now.difference(releasedAt) >= resumeGrace;
          if (!userPressedPlay) return;
        }
        if (!_mayClaim(s, now)) return;
        _suppressed = false;
        _active = true;
        DiagnosticsService.instance.logEvent('online_media_session_claimed');
        host.setExternalSource(this, snapshotOf(s));
        _listenForNoisy();
        _watchTicks();
        return;
      }
      host.updateExternalMedia(this, snapshotOf(s));
      _watchTicks();
      return;
    }
    // Paused, ended, buffering-stopped or no video: a later play is a real one.
    _playingSince = null;
    _suppressed = false;
    _stopTickWatch();
    if (!_active) return;
    host.updateExternalMedia(this, snapshotOf(s));
    _scheduleRelease(s.status == OnlineMediaStatus.none ? idleRelease : pausedRelease);
    if (s.status == OnlineMediaStatus.paused && s.event == 'pause' && (previous?.isPlaying ?? false)) {
      _lastPause = s;
      _lastPauseAt = now;
      _maybeAutoResume(onPause: true);
    }
  }

  /// A watch, Shorts or live page claims at once; any other YouTube page
  /// (YouTube Music's player, an autoplaying trailer with sound) once it has
  /// played unmuted for [claimAfter], so a short preview never takes over.
  /// (Picture-in-picture keeps the watch-page rule: see the Online screen.)
  bool _mayClaim(OnlineMediaState s, DateTime now) {
    if (isYouTubeVideoPage(s.pageUrl)) return true;
    final url = s.pageUrl;
    if (url == null || !isYouTubePage(url)) return false;
    final since = _playingSince;
    return since != null && now.difference(since) >= claimAfter;
  }

  // --- keeping a background listen going -----------------------------------

  /// The app's lifecycle, from the Online screen.
  void appLifecycleChanged(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        _backgroundedAt = null;
        _detached = false;
        if (_playWaitsForWindow) {
          _playWaitsForWindow = false;
          _playCheckTimer?.cancel();
          DiagnosticsService.instance.logEvent('online_play_after_window');
          send(const BridgeCommand.play());
        }
      case AppLifecycleState.inactive:
        // Android picture-in-picture, a system dialog, iOS Control Center:
        // not on screen for the page's purposes, but not left either.
        _appInForeground = false;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appInForeground = false;
        if (state == AppLifecycleState.detached) _detached = true;
        if (_backgroundedAt == null) {
          _backgroundedAt = _clock();
          // A pause that came just before the app finished leaving counts too.
          _maybeAutoResume(onPause: false);
        }
    }
  }

  bool get appInForeground => _appInForeground;

  void _maybeAutoResume({required bool onPause}) {
    final pause = _lastPause;
    final pausedAt = _lastPauseAt;
    if (pause == null || pausedAt == null || !_active || holdPage) return;
    if (!backgroundPlay || _appInForeground) return;
    // Anything reported since (a play, another pause) settles it.
    if (!identical(media.value, pause)) return;
    if (pause.pausedBySystemControls) return; // the user, on the lock screen
    final commanded = _lastCommandedPauseAt;
    if (commanded != null && pausedAt.difference(commanded).abs() < commandedPauseWindow) return;
    final now = _clock();
    final last = _lastAutoResumeAt;
    if (last != null && now.difference(last) < autoResumeCooldown) return;

    String? reason;
    if (onPause && pause.pausedByPage) {
      reason = 'page_idle_pause';
    } else if (resumeBackgroundInterruptions) {
      final left = _backgroundedAt;
      if (left != null && pausedAt.difference(left).abs() <= backgroundInterruptWindow) {
        reason = 'background_interruption';
      }
    }
    if (reason == null) return;
    _lastAutoResumeAt = now;
    _lastPause = null;
    DiagnosticsService.instance.logEvent('online_auto_resume', {'reason': reason});
    send(const BridgeCommand.play());
  }

  /// The hand-off is giving the video back to the page, which will play it:
  /// its next "play" claims the session again at once.
  void expectPagePlay() {
    _suppressed = false;
  }

  /// Where the page's video is now: the last report plus the time since,
  /// while it plays (reports come about once a second).
  Duration? estimatedPosition() {
    final s = media.value;
    if (s == null) return null;
    final at = _lastStateAt;
    if (s.status != OnlineMediaStatus.playing || at == null) return s.position;
    final elapsed = _clock().difference(at);
    var ms = s.position.inMilliseconds + (elapsed.inMilliseconds * s.rate).round();
    final d = s.duration;
    if (d != null && ms > d.inMilliseconds) ms = d.inMilliseconds;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  void _listenForNoisy() {
    final watch = _becomingNoisy;
    if (watch == null || _noisySub != null) return;
    try {
      _noisySub = watch().listen((_) {
        if (!_active || _disposed) return;
        DiagnosticsService.instance.logEvent('online_becoming_noisy');
        send(const BridgeCommand.pause());
      });
    } catch (e) {
      debugPrint('[Online] headphone watch failed: $e');
    }
  }

  void _stopNoisy() {
    _noisySub?.cancel();
    _noisySub = null;
  }

  /// (Re)starts the wait for the playing page's next report.
  void _watchTicks() {
    _staleTimer?.cancel();
    _staleAsked = false;
    _staleTimer = Timer(staleAfter, _onTicksStopped);
  }

  void _stopTickWatch() {
    _staleTimer?.cancel();
    _staleTimer = null;
    _staleAsked = false;
  }

  void _onTicksStopped() {
    _staleTimer = null;
    final last = media.value;
    if (!_active || _disposed || last == null || !last.isPlaying) return;
    if (!_staleAsked) {
      // A live page answers at once, and its answer restarts the watch.
      _staleAsked = true;
      send(const BridgeCommand.requestState());
      _staleTimer = Timer(staleAfter, _onTicksStopped);
      return;
    }
    DiagnosticsService.instance.logEvent('online_media_session_stale');
    _onState(last.withStatus(OnlineMediaStatus.paused, event: 'stale'));
  }

  void _scheduleRelease(Duration after) {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(after, () {
      if (!_active || _disposed) return;
      DiagnosticsService.instance.logEvent('online_media_session_released', {'reason': 'idle'});
      _active = false;
      _stopNoisy();
      host.clearExternalSource(this);
    });
  }

  void _cancelRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  /// What the notification shows for [s].
  static ExternalMediaSnapshot snapshotOf(OnlineMediaState s, {bool waitingForWindow = false}) {
    final id = s.videoId;
    final art = s.artworkUrl;
    return ExternalMediaSnapshot(
      id: id != null ? 'online:$id' : 'online:${s.pageUrl?.path ?? ''}',
      title: s.title.isNotEmpty ? s.title : addressLabel(url: s.pageUrl),
      artist: waitingForWindow ? tapToResumeLine : (s.artist.isEmpty ? null : s.artist),
      artUri: art == null ? null : Uri.tryParse(art),
      playing: s.isPlaying,
      buffering: s.status == OnlineMediaStatus.buffering,
      position: s.position,
      duration: s.duration,
      speed: s.rate,
      canSkipNext: s.hasNext,
      pageUrl: s.pageUrl,
    );
  }

  // --- ExternalPlaybackDelegate: the notification's buttons --------------

  @override
  Future<void> externalPlay() async {
    final sent = await send(const BridgeCommand.play());
    if (!_detached || _disposed) return;
    // No window: some WebViews (Samsung, Android 13) will not start a video
    // in a page that lost its window. Check, and if it did not start, say
    // so in the notification and play once MediaHub is opened.
    _playCheckTimer?.cancel();
    if (!sent) {
      _waitForWindow();
      return;
    }
    _playCheckTimer = Timer(playCheckAfter, () {
      if (_disposed || !_detached || (media.value?.isPlaying ?? false)) return;
      _waitForWindow();
    });
  }

  void _waitForWindow() {
    _playWaitsForWindow = true;
    DiagnosticsService.instance.logEvent('online_play_waits_for_window');
    final s = media.value;
    if (s == null || !_active) return;
    host.updateExternalMedia(this, snapshotOf(s, waitingForWindow: true));
  }

  /// The app opened a video the notification brought back after a restart,
  /// and the controls had asked for it to play: the next page plays once its
  /// bridge is ready.
  void playOnNextPage() => _playOnNextPage = true;
  bool _playOnNextPage = false;

  /// A play is waiting for MediaHub to be opened (see [externalPlay]).
  bool get playWaitsForWindow => _playWaitsForWindow;

  @override
  Future<void> externalPause() {
    if (_playWaitsForWindow) {
      _playWaitsForWindow = false;
      _playCheckTimer?.cancel();
      final st = media.value;
      if (st != null && _active) host.updateExternalMedia(this, snapshotOf(st));
    }
    return send(const BridgeCommand.pause());
  }

  @override
  Future<void> externalSeek(Duration position) => send(BridgeCommand.seekTo(position));

  @override
  Future<void> externalSkipToNext() => send(const BridgeCommand.next());

  @override
  Future<void> externalSkipToPrevious() => send(const BridgeCommand.previous());

  @override
  void onExternalSourceReleased() {
    _cancelRelease();
    _stopTickWatch();
    _stopNoisy();
    if (!_active) return;
    _active = false;
    _suppressed = true;
    _releasedAt = _clock();
  }

  /// The WebView went away (or was recreated): hand the session back.
  void detachPage() {
    _sender = null;
    _cancelRelease();
    _stopTickWatch();
    _stopNoisy();
    _playingSince = null;
    if (_active) {
      _active = false;
      host.clearExternalSource(this);
    }
  }

  void dispose() {
    if (_disposed) return;
    _playCheckTimer?.cancel();
    detachPage();
    _disposed = true;
    media.dispose();
    browserPipActive.dispose();
  }
}

/// One session for the app's lifetime (the WebView lives in a kept-alive tab).
final onlineMediaSessionProvider = Provider<OnlineMediaSession>((ref) {
  final session = OnlineMediaSession(
    host: ref.watch(audioHandlerProvider),
    resumeBackgroundInterruptions: PlatformInfo.isIOS,
    becomingNoisy: () => DeviceControls.watchBecomingNoisy(DeviceControls.pipOwnerOnline),
  );
  ref.onDispose(session.dispose);
  return session;
});
