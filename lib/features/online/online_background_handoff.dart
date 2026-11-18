import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform_info.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../domain/models/playback_state.dart' as domain;
import '../explore/online_models.dart';
import '../explore/online_source.dart';
import '../music_player/music_audio_handler.dart';
import '../music_player/playback_notifier.dart';
import 'online_bridge_protocol.dart';
import 'online_media_session.dart';
import 'online_settings.dart';
import 'youtube_urls.dart';

/// What the music player is doing, as far as the hand-off cares.
@immutable
class HandoffPlayerState {
  const HandoffPlayerState({this.itemId, this.position = Duration.zero, this.playing = false});

  final String? itemId;
  final Duration position;
  final bool playing;
}

/// The part of the music player the hand-off drives (a fake in tests).
abstract class HandoffPlayer {
  /// The local queue as it is now, to put back afterwards (null when empty).
  domain.PlaybackState? captureLocal();

  /// Plays [item] alone, from [position].
  Future<void> playAlone(domain.MediaItem item, Duration position);

  HandoffPlayerState get current;

  Future<void> pause();

  /// Puts [saved] back, paused where it was (null: an empty player).
  Future<void> restoreLocal(domain.PlaybackState? saved);
}

/// The real music player: [PlaybackNotifier] for playing (so the item goes
/// through the same queue, notification and lock screen as any song), and
/// the handler's own session restore for putting the local queue back.
class MusicHandoffPlayer implements HandoffPlayer {
  MusicHandoffPlayer(this._ref);

  final Ref _ref;

  MusicAudioHandler get _handler => _ref.read(audioHandlerProvider);
  PlaybackNotifier get _playback => _ref.read(playbackNotifierProvider.notifier);

  @override
  domain.PlaybackState? captureLocal() {
    final s = _handler.getCurrentDomainState();
    return s.queue.isEmpty ? null : s;
  }

  @override
  Future<void> playAlone(domain.MediaItem item, Duration position) async {
    await _playback.loadQueue([item], autoPlay: false);
    if (position > Duration.zero) await _playback.seek(position);
    // Local playback starting hands the media session over from the page
    // (which is told to pause).
    await _playback.play();
  }

  @override
  HandoffPlayerState get current {
    final s = _handler.getCurrentDomainState();
    return HandoffPlayerState(itemId: s.currentItemId, position: s.position, playing: s.isPlaying);
  }

  @override
  Future<void> pause() => _playback.pause();

  @override
  Future<void> restoreLocal(domain.PlaybackState? saved) async {
    if (saved == null || saved.queue.isEmpty) {
      await _playback.loadQueue(const [], autoPlay: false);
      return;
    }
    // The hand-off's stream item is still loaded: a plain restore would see
    // a queue and leave it there, so this one replaces it.
    await _handler.restoreSession(saved.copyWith(isPlaying: false), replace: true);
  }
}

/// The audio stream iOS can play natively for a hand-off: AAC audio in an
/// mp4 container (the highest bitrate), else the smallest mp4 video with
/// sound. WebM / Opus is not playable by iOS's player, so never chosen.
OnlineStream? pickHandoffStream(OnlineStreams streams) {
  bool isMp4(OnlineStream s) {
    final c = s.container.toLowerCase();
    return c == 'mp4' || c == 'm4a';
  }

  final audio = streams.audio.where(isMp4).toList()
    ..sort((a, b) => (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0));
  if (audio.isNotEmpty) return audio.first;
  final video = streams.video.where(isMp4).toList()..sort((a, b) => (a.height ?? 0).compareTo(b.height ?? 0));
  return video.isEmpty ? null : video.first;
}

class _CachedStream {
  const _CachedStream(this.url, this.at);
  final String url;
  final DateTime at;
}

enum _Phase { idle, resolving, native }

/// iOS: keeps a YouTube listen going when the phone locks or the app leaves
/// the screen (WebKit pauses a web page's video audio there; only
/// picture-in-picture keeps it).
///
/// With Background play on and a video playing (and not in the browser's
/// picture-in-picture), leaving the app hands the video to the music player:
/// its audio-only stream (resolved ahead of time while the video plays, or
/// right then) plays natively from the page's position, so the lock screen,
/// Control Center and Bluetooth keep working, and the page is paused. On the
/// way back the page is moved to the native position and resumed (if the
/// native player was still playing), the native player pauses, and the
/// local music queue that was there before is put back, paused.
///
/// Online items are never saved by the music player (expiring stream URLs),
/// so the hand-off leaves nothing behind across restarts.
class OnlineBackgroundHandoff {
  OnlineBackgroundHandoff({
    required this.session,
    required this.player,
    required Future<OnlineStreams> Function(String videoId) resolveStreams,
    required bool Function() enabled,
    DateTime Function()? clock,
    this.streamLifetime = const Duration(hours: 4),
    this.pipSettle = const Duration(milliseconds: 700),
  })  : _resolveStreams = resolveStreams, // ignore: prefer_initializing_formals
        _enabled = enabled, // ignore: prefer_initializing_formals
        _clock = clock ?? DateTime.now;

  final OnlineMediaSession session;
  final HandoffPlayer player;
  final Future<OnlineStreams> Function(String videoId) _resolveStreams;
  final bool Function() _enabled;
  final DateTime Function() _clock;

  /// Stream links stop working after some hours: older ones are resolved again.
  final Duration streamLifetime;

  /// After an automatic picture-in-picture request, how long to wait for the
  /// page to say whether it went into picture-in-picture.
  final Duration pipSettle;

  /// Prefetch failures are not retried sooner than this.
  static const Duration prefetchRetry = Duration(minutes: 2);

  _Phase _phase = _Phase.idle;
  int _generation = 0;
  bool _left = false;
  bool _playingWhenInactive = false;
  bool _leftPlaying = false;
  DateTime? _pipRequestedAt;
  Timer? _pipTimer;
  String? _itemId;
  domain.PlaybackState? _saved;
  bool _disposed = false;

  final Map<String, _CachedStream> _cache = {};
  final Map<String, Future<String?>> _pending = {};
  final Map<String, DateTime> _failedAt = {};

  /// The native player has the video (tests and diagnostics).
  bool get isHandedOff => _phase == _Phase.native;
  bool get isResolving => _phase == _Phase.resolving;

  /// The Online screen asked the page for picture-in-picture as the app went
  /// inactive (iOS Auto PiP).
  void pipRequested() {
    _pipRequestedAt = _clock();
  }

  /// Called by the Online screen on every lifecycle change, before the
  /// media session hears of it.
  void lifecycleChanged(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.inactive:
        if (!_left) _playingWhenInactive = session.media.value?.isPlaying ?? false;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_left) return;
        _left = true;
        _onLeft();
      case AppLifecycleState.resumed:
        _left = false;
        _playingWhenInactive = false;
        _pipTimer?.cancel();
        _pipTimer = null;
        unawaited(_onReturned());
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onLeft() {
    if (_phase != _Phase.idle || !_enabled()) return;
    final requested = _pipRequestedAt;
    if (requested != null && _clock().difference(requested) < const Duration(seconds: 2)) {
      // The page may be going into its own picture-in-picture, which keeps it
      // playing: wait for its answer.
      _pipTimer?.cancel();
      _pipTimer = Timer(pipSettle, () {
        _pipTimer = null;
        if (_left) _decide();
      });
      return;
    }
    _decide();
  }

  void _decide() {
    if (_phase != _Phase.idle || _disposed || !_enabled()) return;
    if (session.browserPipActive.value) return; // picture-in-picture plays on
    final s = session.media.value;
    final videoId = s?.videoId;
    if (s == null || videoId == null || !session.isActive) return;
    // Playing as the app left (WebKit may already have paused it since).
    final playing = s.isPlaying || _playingWhenInactive;
    if (!playing) return;
    _leftPlaying = true;
    session.holdPage = true;
    _phase = _Phase.resolving;
    final generation = ++_generation;
    DiagnosticsService.instance.logEvent('online_handoff_start');
    unawaited(_start(generation, videoId));
  }

  Future<void> _start(int generation, String videoId) async {
    String? url;
    try {
      url = await _streamUrl(videoId);
    } catch (e) {
      url = null;
    }
    if (generation != _generation || _phase != _Phase.resolving) return; // back already
    final s = session.media.value;
    if (url == null || s == null || s.videoId != videoId) {
      _fail('no_stream');
      return;
    }
    final position = session.estimatedPosition() ?? s.position;
    final item = domain.MediaItem(
      id: 'yt_$videoId',
      uri: url,
      mediaType: domain.MediaType.audio,
      title: s.title.isNotEmpty ? s.title : addressLabel(url: s.pageUrl),
      artist: s.artist.isEmpty ? null : s.artist,
      album: 'YouTube',
      durationMs: s.duration?.inMilliseconds ?? 0,
      sizeBytes: 0,
      dateAdded: _clock(),
      source: 'online',
      artworkPath: s.artworkUrl ?? youTubeThumbnailFor(videoId),
    );
    // Paused on purpose (and not to be resumed: holdPage).
    await session.send(const BridgeCommand.pause());
    if (generation != _generation) return; // back meanwhile: the page was told to play on
    _saved = player.captureLocal();
    try {
      await player.playAlone(item, position);
    } catch (e) {
      debugPrint('[Online] hand-off playback failed: $e');
      if (generation == _generation) _fail('play_failed');
      return;
    }
    _itemId = item.id;
    if (generation != _generation) {
      // The app came back while the player was starting: give it back now.
      _phase = _Phase.native;
      await _giveBack();
      return;
    }
    _phase = _Phase.native;
    DiagnosticsService.instance.logEvent('online_handoff_native');
  }

  void _fail(String reason) {
    DiagnosticsService.instance.logEvent('online_handoff_failed', {'reason': reason});
    _phase = _Phase.idle;
    session.holdPage = false;
    _saved = null;
    // Last try: ask the page to play on (WebKit may allow it).
    if (_left && _leftPlaying && !(session.media.value?.isPlaying ?? false)) {
      session.expectPagePlay();
      session.send(const BridgeCommand.play());
    }
  }

  Future<void> _onReturned() async {
    switch (_phase) {
      case _Phase.idle:
        _leftPlaying = false;
        return;
      case _Phase.resolving:
        // Back before the stream was ready: the page carries on as it was.
        _generation++;
        _phase = _Phase.idle;
        session.holdPage = false;
        if (_leftPlaying && !(session.media.value?.isPlaying ?? false)) {
          session.expectPagePlay();
          session.send(const BridgeCommand.play());
        }
        _leftPlaying = false;
        DiagnosticsService.instance.logEvent('online_handoff_cancelled');
      case _Phase.native:
        await _giveBack();
    }
  }

  /// The native player gives the video back to the page.
  Future<void> _giveBack() async {
    final now = player.current;
    final ours = _itemId;
    final saved = _saved;
    _phase = _Phase.idle;
    _itemId = null;
    _saved = null;
    _leftPlaying = false;
    session.holdPage = false;
    if (now.itemId != null && now.itemId != ours) {
      // The music player moved on to something else meanwhile: leave it be.
      DiagnosticsService.instance.logEvent('online_handoff_back', {'synced': false});
      return;
    }
    if (now.itemId == ours) {
      await session.send(BridgeCommand.seekTo(now.position));
      if (now.playing) {
        session.expectPagePlay();
        await session.send(const BridgeCommand.play());
      }
    }
    try {
      await player.pause();
      await player.restoreLocal(saved);
    } catch (e) {
      debugPrint('[Online] hand-off restore failed: $e');
    }
    DiagnosticsService.instance.logEvent('online_handoff_back', {'synced': now.itemId == ours});
  }

  // --- stream links ----------------------------------------------------------

  /// Resolves [videoId]'s stream ahead of time, so leaving the app does not
  /// have to wait for the network (iOS gives a backgrounded app only seconds).
  /// The Online screen calls it while a video plays with Background play on.
  void prefetch(String? videoId) {
    if (_disposed || videoId == null || !isValidYouTubeVideoId(videoId) || !_enabled()) return;
    if (_fresh(videoId) != null || _pending.containsKey(videoId)) return;
    final failed = _failedAt[videoId];
    if (failed != null && _clock().difference(failed) < prefetchRetry) return;
    unawaited(_streamUrl(videoId).catchError((Object _) => null));
  }

  String? _fresh(String videoId) {
    final c = _cache[videoId];
    if (c == null) return null;
    if (_clock().difference(c.at) >= streamLifetime) {
      _cache.remove(videoId);
      return null;
    }
    return c.url;
  }

  Future<String?> _streamUrl(String videoId) {
    final cached = _fresh(videoId);
    if (cached != null) return Future.value(cached);
    final pending = _pending[videoId];
    if (pending != null) return pending;
    final future = () async {
      try {
        final streams = await _resolveStreams(videoId);
        final pick = pickHandoffStream(streams);
        final uri = pick == null ? null : Uri.tryParse(pick.url);
        if (uri == null || uri.scheme != 'https') {
          _failedAt[videoId] = _clock();
          return null;
        }
        if (_cache.length >= 3) _cache.remove(_cache.keys.first);
        _cache[videoId] = _CachedStream(pick!.url, _clock());
        return pick.url;
      } catch (e) {
        _failedAt[videoId] = _clock();
        rethrow;
      } finally {
        _pending.remove(videoId);
      }
    }();
    _pending[videoId] = future;
    return future;
  }

  void dispose() {
    _disposed = true;
    _pipTimer?.cancel();
    _generation++;
  }
}

/// One hand-off for the app's lifetime, next to the media session.
final onlineBackgroundHandoffProvider = Provider<OnlineBackgroundHandoff>((ref) {
  final handoff = OnlineBackgroundHandoff(
    session: ref.watch(onlineMediaSessionProvider),
    player: MusicHandoffPlayer(ref),
    resolveStreams: (videoId) => ref.read(onlineSourceProvider).streams(videoId),
    enabled: () => PlatformInfo.isIOS && ref.read(onlineBackgroundPlayProvider),
  );
  ref.onDispose(handoff.dispose);
  return handoff;
});
