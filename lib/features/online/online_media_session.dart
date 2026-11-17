import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
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
///   and Bluetooth show the video and control it.
/// - Paused for [pausedRelease] (or no video at all for [idleRelease]) hands
///   the session back to local music.
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
    this.pausedRelease = const Duration(minutes: 10),
    this.idleRelease = const Duration(seconds: 15),
    this.staleAfter = const Duration(seconds: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The audio handler (or a fake in tests).
  final ExternalPlaybackHost host;
  final DateTime Function() _clock;
  final Duration pausedRelease;
  final Duration idleRelease;
  final Duration staleAfter;

  /// A "play" event this long after local music took over is the user
  /// pressing play in the page again, not a tick still on its way.
  static const Duration resumeGrace = Duration(milliseconds: 1500);

  BridgeCommandSender? _sender;
  bool _active = false;
  bool _suppressed = false;
  DateTime? _releasedAt;
  Timer? _releaseTimer;
  Timer? _staleTimer;
  bool _staleAsked = false;
  bool _disposed = false;

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
      case BridgeReadyMessage(:final pageUrl):
        documentReplaced(pageUrl);
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
    media.value = s;
    if (s.isPlaying) {
      _cancelRelease();
      if (!_active) {
        if (_suppressed) {
          final releasedAt = _releasedAt;
          final userPressedPlay = s.event == 'play' &&
              releasedAt != null &&
              _clock().difference(releasedAt) >= resumeGrace;
          if (!userPressedPlay) return;
        }
        // Only a video page claims the session (not a preview on the home feed).
        if (!isYouTubeVideoPage(s.pageUrl)) return;
        _suppressed = false;
        _active = true;
        DiagnosticsService.instance.logEvent('online_media_session_claimed');
        host.setExternalSource(this, snapshotOf(s));
        _watchTicks();
        return;
      }
      host.updateExternalMedia(this, snapshotOf(s));
      _watchTicks();
      return;
    }
    // Paused, ended, buffering-stopped or no video: a later play is a real one.
    _suppressed = false;
    _stopTickWatch();
    if (!_active) return;
    host.updateExternalMedia(this, snapshotOf(s));
    _scheduleRelease(s.status == OnlineMediaStatus.none ? idleRelease : pausedRelease);
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
      host.clearExternalSource(this);
    });
  }

  void _cancelRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  /// What the notification shows for [s].
  static ExternalMediaSnapshot snapshotOf(OnlineMediaState s) {
    final id = s.videoId;
    final art = s.artworkUrl;
    return ExternalMediaSnapshot(
      id: id != null ? 'online:$id' : 'online:${s.pageUrl?.path ?? ''}',
      title: s.title.isNotEmpty ? s.title : addressLabel(url: s.pageUrl),
      artist: s.artist.isEmpty ? null : s.artist,
      artUri: art == null ? null : Uri.tryParse(art),
      playing: s.isPlaying,
      buffering: s.status == OnlineMediaStatus.buffering,
      position: s.position,
      duration: s.duration,
      speed: s.rate,
      canSkipNext: s.hasNext,
    );
  }

  // --- ExternalPlaybackDelegate: the notification's buttons --------------

  @override
  Future<void> externalPlay() => send(const BridgeCommand.play());

  @override
  Future<void> externalPause() => send(const BridgeCommand.pause());

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
    if (_active) {
      _active = false;
      host.clearExternalSource(this);
    }
  }

  void dispose() {
    if (_disposed) return;
    detachPage();
    _disposed = true;
    media.dispose();
    browserPipActive.dispose();
  }
}

/// One session for the app's lifetime (the WebView lives in a kept-alive tab).
final onlineMediaSessionProvider = Provider<OnlineMediaSession>((ref) {
  final session = OnlineMediaSession(host: ref.watch(audioHandlerProvider));
  ref.onDispose(session.dispose);
  return session;
});
