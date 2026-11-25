// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io' show HttpClient, HttpHeaders, HttpStatus;

import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform_info.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../domain/models/playback_state.dart' as domain;
import '../explore/online_models.dart';
import '../explore/online_source.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/personal_tools_notifier.dart';
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

  /// Plays [item] alone, from [position], and returns once it really plays.
  /// Throws (a [HandoffPlaybackException]) when the stream is refused or
  /// does not start in time; nothing plays then.
  ///
  /// With [play] false the item is only loaded, paused at [position] (ready
  /// for a Play from the phone's controls); it returns once it is loaded.
  Future<void> playAlone(domain.MediaItem item, Duration position, {bool play = true});

  HandoffPlayerState get current;

  Future<void> pause();

  /// Puts [saved] back, paused where it was (null: an empty player), with
  /// the user's own settings (repeat).
  Future<void> restoreLocal(domain.PlaybackState? saved);

  /// Puts only the user's own settings back (repeat): other music took over
  /// the player meanwhile and stays.
  Future<void> restoreSettings();
}

/// The hand-off's stream did not play.
class HandoffPlaybackException implements Exception {
  const HandoffPlaybackException(this.reason);
  final String reason;

  @override
  String toString() => 'HandoffPlaybackException: $reason';
}

/// The real music player: [PlaybackNotifier] for playing (so the item goes
/// through the same queue, notification and lock screen as any song), and
/// the handler's own session restore for putting the local queue back.
class MusicHandoffPlayer implements HandoffPlayer {
  MusicHandoffPlayer(this._ref, {this.startTimeout = defaultStartTimeout});

  final Ref _ref;

  /// How long the stream gets to load and start playing. Short: iOS gives an
  /// app that left the screen only seconds, and a failure still has to leave
  /// time for the second try and for the page to play on. Android allows more
  /// buffering time for ExoPlayer.
  static const Duration defaultStartTimeout = Duration(seconds: 4);
  static const Duration defaultAndroidStartTimeout = Duration(seconds: 12);
  final Duration startTimeout;

  /// The user's repeat mode while the hand-off plays with repeat off.
  domain.PlaybackRepeatMode? _repeatBefore;

  MusicAudioHandler get _handler => _ref.read(audioHandlerProvider);
  PlaybackNotifier get _playback => _ref.read(playbackNotifierProvider.notifier);

  @override
  domain.PlaybackState? captureLocal() {
    final s = _handler.getCurrentDomainState();
    return s.queue.isEmpty ? null : s;
  }

  @override
  Future<void> playAlone(domain.MediaItem item, Duration position, {bool play = true}) async {
    final handler = _handler;
    bool onItem() => handler.getCurrentDomainState().currentItemId == item.id;
    final failed = Completer<void>();
    final started = Completer<void>();
    void check() {
      final p = handler.player;
      if (!started.isCompleted && p.playing && p.processingState == ProcessingState.ready && onItem()) {
        started.complete();
      }
    }

    // The player's own reports (its error stream, a load that failed).
    final failures = handler.trackFailures.listen((id) {
      if (id == item.id && !failed.isCompleted) failed.complete();
    });
    StreamSubscription<PlayerState>? states;
    // Set once the time is up: the steps still under way must not start
    // the stream after that (the page has been asked to play on).
    var gaveUp = false;
    try {
      await () async {
        // The one video plays once: with the user's repeat one, its sound
        // would loop for good with the screen off. Their mode comes back
        // with their queue.
        _repeatBefore ??= handler.repeatMode;
        if (handler.repeatMode != domain.PlaybackRepeatMode.off) {
          await handler.setRepeatMode(AudioServiceRepeatMode.none);
        }
        await _playback.loadQueue([item], autoPlay: false);
        if (failed.isCompleted || !onItem() || handler.player.processingState == ProcessingState.idle) {
          throw const HandoffPlaybackException('not_loaded');
        }
        if (position > Duration.zero) await _playback.seek(position);
        if (gaveUp) throw const HandoffPlaybackException('too_late');
        if (!play) {
          // Loaded and paused: the notification's Play must start it, not
          // go to the page (which cannot play without a window).
          handler.takeControlsFromExternal(reason: 'native_handoff');
          return;
        }
        states = handler.player.playerStateStream.listen((_) => check());
        // Local playback starting hands the media session over from the page
        // (which is told to pause).
        await _playback.play();
        check();
        await Future.any<void>([
          started.future,
          failed.future.then<void>((_) => throw const HandoffPlaybackException('failed')),
        ]);
      }().timeout(startTimeout);
    } catch (e) {
      // Nothing may start late, once the page has been asked to play on.
      gaveUp = true;
      try {
        await handler.cancelLoading();
        if (onItem()) await _playback.pause();
      } catch (_) {}
      DiagnosticsService.instance.logEvent('online_handoff_play_failed', {
        'reason': e is HandoffPlaybackException
            ? e.reason
            : (e is TimeoutException ? 'timeout' : e.runtimeType.toString()),
      });
      if (e is HandoffPlaybackException) rethrow;
      throw HandoffPlaybackException(e is TimeoutException ? 'timeout' : e.runtimeType.toString());
    } finally {
      await failures.cancel();
      await states?.cancel();
    }
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
      await restoreSettings();
      return;
    }
    // The hand-off's stream item is still loaded: a plain restore would see
    // a queue and leave it there, so this one replaces it. It brings back
    // the repeat mode saved with the queue.
    _repeatBefore = null;
    await _handler.restoreSession(saved.copyWith(isPlaying: false), replace: true);
  }

  @override
  Future<void> restoreSettings() async {
    final repeat = _repeatBefore;
    _repeatBefore = null;
    if (repeat == null || _handler.repeatMode == repeat) return;
    await _handler.setRepeatMode(switch (repeat) {
      domain.PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
      domain.PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
      domain.PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
    });
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

  final audio = streams.audio.where(isMp4).toList()..sort((a, b) => (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0));
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
    bool Function()? detachedEnabled,
    DateTime Function()? clock,
    this.streamLifetime = const Duration(hours: 4),
    this.pipSettle = const Duration(milliseconds: 700),
    this.fixtureLocalStreams = false,
    Future<OnlineStreams> Function(String videoId, int variant)? resolveStreamsVariant,
    Future<bool> Function(Uri url)? verifyStream,
  }) : _resolveVariant = resolveStreamsVariant,
       _verifyStream = verifyStream, // ignore: prefer_initializing_formals
       _resolveStreams = resolveStreams, // ignore: prefer_initializing_formals
       _enabled = enabled, // ignore: prefer_initializing_formals
       _detachedEnabled = detachedEnabled ?? enabled,
       _clock = clock ?? DateTime.now;

  final OnlineMediaSession session;
  final HandoffPlayer player;
  final Future<OnlineStreams> Function(String videoId) _resolveStreams;

  /// Another YouTube client's streams for a retry (null: [_resolveStreams] only).
  final Future<OnlineStreams> Function(String videoId, int variant)? _resolveVariant;

  /// Checks that the stream server accepts a link (null: not checked).
  final Future<bool> Function(Uri url)? _verifyStream;

  /// Which client the next lookup of a video uses (raised after a refused link).
  final Map<String, int> _variant = {};

  /// How many client variants a refused stream is retried with.
  static const int maxVariants = 6;
  final bool Function() _enabled;

  /// Whether a play the page cannot start without a window may be played
  /// natively ([startDetachedPlay]); defaults to [_enabled].
  final bool Function() _detachedEnabled;
  final DateTime Function() _clock;

  /// Stream links stop working after some hours: older ones are resolved again.
  final Duration streamLifetime;

  /// After an automatic picture-in-picture request, how long to wait for the
  /// page to say whether it went into picture-in-picture.
  final Duration pipSettle;

  /// Debug fixture builds: a stream served by the local fixture server
  /// (http://127.0.0.1) is accepted too.
  final bool fixtureLocalStreams;

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
      case AppLifecycleState.detached:
        if (state == AppLifecycleState.detached) _onDetached();
        // Have the stream ready in case the task is swiped away next.
        if (!_left && !_enabled() && (session.media.value?.isPlaying ?? false)) prefetch(session.media.value?.videoId);
        if (_left) return;
        _left = true;
        _onLeft();
      case AppLifecycleState.resumed:
        _left = false;
        _playingWhenInactive = false;
        _pipTimer?.cancel();
        _pipTimer = null;
        unawaited(_onReturned());
    }
  }

  /// Android: the Activity is gone (swiped away from recents, or destroyed).
  /// The WebView has no window now and Chromium pauses its video within
  /// milliseconds, so a playing video moves to the native player at once,
  /// without waiting for that pause.
  void _onDetached() {
    String? skip;
    final s = session.media.value;
    if (_disposed) {
      skip = 'disposed';
    } else if (_enabled() || !_detachedEnabled()) {
      skip = 'off';
    } else if (_phase != _Phase.idle) {
      skip = 'busy_${_phase.name}';
    } else if (session.browserPipActive.value) {
      skip = 'browser_pip';
    } else if (s == null || s.videoId == null) {
      skip = 'no_video';
    } else if (!session.isActive) {
      skip = 'not_session';
    }
    if (skip != null) {
      if (!_disposed) DiagnosticsService.instance.logEvent('online_handoff_proactive_skipped', {'why': skip});
      return;
    }
    final playing = (s!.isPlaying || _playingWhenInactive) && !session.pausePending;
    DiagnosticsService.instance.logEvent('online_handoff_proactive', {'playing': playing});
    // Paused: the native player is loaded, paused, at the page's position, so
    // the notification's Play (which the page cannot honour without a window)
    // goes straight to it.
    unawaited(startDetachedPlay(proactive: true, play: playing));
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
    if (session.browserPipActive.value || DeviceControls.inPip.value) return; // picture-in-picture plays on
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

  Future<void> _start(int generation, String videoId, {bool pauseFirst = true, bool play = true}) async {
    String? url;
    // Two tries: a lookup fails now and then (a slow or refused request).
    for (var attempt = 0; attempt < 2 && url == null; attempt++) {
      if (attempt > 0) {
        if (generation != _generation || _phase != _Phase.resolving) return;
        DiagnosticsService.instance.logEvent('online_handoff_resolve_retry');
      }
      try {
        url = await _streamUrl(videoId);
      } catch (e) {
        url = null;
      }
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
    // Paused on purpose (and not to be resumed: holdPage). A proactive
    // hand-off keeps the page going until the native player really plays.
    if (pauseFirst) await session.send(const BridgeCommand.pause());
    if (generation != _generation) return; // back meanwhile: the page was told to play on
    _saved = player.captureLocal();
    var played = await _tryPlay(item, position, play: play);
    // Stream links expire, they only work from the network they were made
    // on (a cached one breaks after a move from Wi-Fi to mobile data), and
    // some clients' links are refused (HTTP 403): new links, through the
    // next YouTube client each time.
    for (var retry = 1; !played && generation == _generation && retry < maxVariants; retry++) {
      DiagnosticsService.instance.logEvent('online_handoff_retry', {'retry': retry});
      _cache.remove(videoId);
      if (_resolveVariant != null) _variant[videoId] = ((_variant[videoId] ?? 0) + 1) % maxVariants;
      String? fresh;
      try {
        fresh = await _streamUrl(videoId);
      } catch (_) {
        fresh = null;
      }
      if (fresh == null || generation != _generation) {
        if (_resolveVariant == null) break;
        continue;
      }
      played = await _tryPlay(item.copyWith(uri: fresh), position, play: play);
      if (_resolveVariant == null) break;
    }
    if (!played) {
      final saved = _saved;
      _saved = null;
      if (!play) {
        // Only getting ready (the video was paused): the page keeps the
        // session, and a later Play takes the page's own retry path.
        _phase = _Phase.idle;
        session.holdPage = false;
        DiagnosticsService.instance.logEvent('online_handoff_prepare_failed');
        try {
          if (player.current.itemId == item.id) {
            await player.restoreLocal(saved);
          } else {
            await player.restoreSettings();
          }
        } catch (_) {}
        return;
      }
      // The page first (iOS gives a backgrounded app only seconds), then the
      // user's own queue comes back, paused, unless other music took over.
      if (generation == _generation) _fail('play_failed');
      try {
        if (player.current.itemId == item.id) {
          if (saved == null && !_enabled()) {
            // Android: an empty queue would turn the session idle and stop
            // the service (and, with no Activity, the engine). Paused instead.
            await player.pause();
          } else {
            await player.restoreLocal(saved);
          }
        } else {
          await player.restoreSettings();
        }
      } catch (e) {
        debugPrint('[Online] hand-off restore failed: $e');
      }
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
    // Only one audio source: the page stops now that the native player plays.
    if (!pauseFirst) await session.send(const BridgeCommand.pause());
    // Loaded paused: the phone's Play must reach the native player.
    if (!play) session.yieldToNative();
    DiagnosticsService.instance.logEvent('online_handoff_native');
  }

  /// True once [item] really plays natively.
  Future<bool> _tryPlay(domain.MediaItem item, Duration position, {bool play = true}) async {
    try {
      await player.playAlone(item, position, play: play);
      return true;
    } catch (e) {
      debugPrint('[Online] hand-off playback failed: $e');
      return false;
    }
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
      // The music player moved on to something else meanwhile: leave it be
      // (only the user's repeat mode comes back).
      DiagnosticsService.instance.logEvent('online_handoff_back', {'synced': false});
      try {
        await player.restoreSettings();
      } catch (_) {}
      return;
    }
    if (now.itemId == ours) {
      if (session.hasSender) {
        // Native first, so the two never play at once; then the user's own
        // queue (or an empty player) comes back, before the page plays and
        // claims the controls: emptying the player afterwards would end the
        // media session under the playing page.
        try {
          await player.pause();
          await player.restoreLocal(saved);
        } catch (e) {
          debugPrint('[Online] hand-off restore failed: $e');
        }
        await session.send(BridgeCommand.seekTo(now.position));
        if (now.playing) {
          session.expectPagePlay();
          await session.send(const BridgeCommand.play());
        } else if (saved == null) {
          // A paused video: the page keeps the controls, so the notification
          // and the media service stay.
          session.claimPaused();
        }
        DiagnosticsService.instance.logEvent('online_handoff_back', {'synced': true});
        return;
      } else {
        // App was swiped away and reopened: WebView hasn't loaded the page yet.
        // Handover once the page is ready so music continues playing seamlessly!
        session.handoverOnNextPage(
          position: now.position,
          play: now.playing,
          onHandover: () async {
            try {
              await player.pause();
              await player.restoreLocal(saved);
            } catch (e) {
              debugPrint('[Online] hand-off restore failed: $e');
            }
          },
        );
        DiagnosticsService.instance.logEvent('online_handoff_back', {'synced': true, 'waiting_bridge': true});
        return;
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

  /// Starts native stream playback when the phone's controls are pressed while
  /// the app is detached (swiped away from recents).
  Future<bool> startDetachedPlay({bool proactive = false, bool play = true}) async {
    if (_disposed || !_detachedEnabled()) {
      DiagnosticsService.instance.logEvent('online_detached_play_skipped', {'why': _disposed ? 'disposed' : 'off'});
      return false;
    }
    // Already handed off (the proactive switch, or a play under way).
    if (_phase == _Phase.native) return true;
    if (_phase == _Phase.resolving) return false;
    final s = session.media.value;
    final videoId = s?.videoId;
    if (videoId == null || !isValidYouTubeVideoId(videoId)) {
      DiagnosticsService.instance.logEvent('online_detached_play_skipped', {'why': 'no_video'});
      return false;
    }
    _left = true;
    _leftPlaying = play;
    session.holdPage = true;
    _phase = _Phase.resolving;
    final generation = ++_generation;
    await _start(generation, videoId, pauseFirst: !proactive || !play, play: play);
    return _phase == _Phase.native;
  }

  // --- stream links ----------------------------------------------------------

  /// Resolves [videoId]'s stream ahead of time, so leaving the app does not
  /// have to wait for the network (iOS gives a backgrounded app only seconds).
  /// The Online screen calls it while a video plays with Background play on.
  void prefetch(String? videoId) {
    if (_disposed || videoId == null || !isValidYouTubeVideoId(videoId)) return;
    if (!_enabled() && !_detachedEnabled()) return;
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
        Object? lastError;
        final resolveVariant = _resolveVariant;
        // Without other clients: one lookup. With them: each client in turn
        // until one gives a link the stream server accepts (checked with a
        // 2-byte request when [_verifyStream] is set), so a link that would
        // be refused (HTTP 403) is never what the hand-off starts with.
        final last = resolveVariant == null ? (_variant[videoId] ?? 0) : maxVariants - 1;
        for (var variant = _variant[videoId] ?? 0; variant <= last; variant++) {
          OnlineStreams streams;
          try {
            streams = (variant > 0 && resolveVariant != null)
                ? await resolveVariant(videoId, variant)
                : await _resolveStreams(videoId);
          } catch (e) {
            lastError = e;
            _logResolveFailure(e, variant);
            continue;
          }
          final pick = pickHandoffStream(streams);
          final uri = pick == null ? null : Uri.tryParse(pick.url);
          if (uri == null ||
              !(uri.scheme == 'https' || (fixtureLocalStreams && uri.scheme == 'http' && uri.host == '127.0.0.1'))) {
            continue;
          }
          final verify = _verifyStream;
          if (verify != null && !await verify(uri)) {
            DiagnosticsService.instance.logEvent('online_stream_refused', {'variant': variant});
            continue;
          }
          _variant[videoId] = variant;
          if (_cache.length >= 3) _cache.remove(_cache.keys.first);
          _cache[videoId] = _CachedStream(pick!.url, _clock());
          if (variant > 0) DiagnosticsService.instance.logEvent('online_stream_resolved', {'variant': variant});
          return pick.url;
        }
        _failedAt[videoId] = _clock();
        if (lastError != null) throw lastError;
        return null;
      } finally {
        _pending.remove(videoId);
      }
    }();
    _pending[videoId] = future;
    return future;
  }

  void _logResolveFailure(Object e, int variant) {
    final text = '$e';
    DiagnosticsService.instance.logEvent('online_stream_resolve_failed', {
      'variant': variant,
      'error': text.length > 160 ? text.substring(0, 160) : text,
    });
    debugPrint('[Online] stream lookup failed (variant $variant): $e');
  }

  void dispose() {
    _disposed = true;
    _pipTimer?.cancel();
    _generation++;
  }
}

const bool _fixtureMedia = !kReleaseMode && bool.fromEnvironment('MEDIAHUB_ONLINE_FIXTURE');

/// [videoId]'s audio-only links from yt-dlp (Android's extractor).
Future<OnlineStreams> extractorHandoffStreams(ExtractorBackend backend, String videoId) async {
  final info = await backend.getInfo('https://www.youtube.com/watch?v=$videoId');
  return OnlineStreams(audio: [
    for (final f in info.formats)
      if (f.isAudioOnly && f.url != null)
        OnlineStream(
          url: f.url!,
          kind: OnlineStreamKind.audio,
          label: '${f.abr.round()} kbps',
          container: f.ext,
          sizeBytes: f.filesize,
          bitrateKbps: f.abr.round(),
        ),
  ], video: const []);
}

/// Whether the stream server serves [url] (a 2-byte request): links from
/// some YouTube clients are refused (HTTP 403) and would never play.
Future<bool> verifyHandoffStream(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.getUrl(url).timeout(const Duration(seconds: 8));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
    final response = await request.close().timeout(const Duration(seconds: 8));
    await response.drain<void>().catchError((Object _) {});
    return response.statusCode == HttpStatus.ok || response.statusCode == HttpStatus.partialContent;
  } catch (_) {
    // Unknown (a slow network): let the player try it.
    return true;
  } finally {
    client.close(force: true);
  }
}

/// Whether the native hand-off may run: iOS only, with Background play on.
///
/// Android never hands the page's video to the music player. Its WebView
/// keeps playing with the screen off and after the task is swiped away from
/// recents (the Flutter engine, and the page in it, live on in the
/// mediaPlayback foreground service). The hand-off there paused a playing
/// video to re-fetch it as an audio stream, and when that stream would not
/// play (an expired or refused link) it put back an empty music queue, which
/// turned the session idle: audio_service then stopped its service, the
/// notification went away and, with no Activity left, the engine with it.
bool onlineHandoffEnabled({required bool isIOS, required bool backgroundPlay}) => isIOS && backgroundPlay;

/// One hand-off for the app's lifetime, next to the media session.
final onlineBackgroundHandoffProvider = Provider<OnlineBackgroundHandoff>((ref) {
  final session = ref.watch(onlineMediaSessionProvider);
  final handoff = OnlineBackgroundHandoff(
    session: session,
    player: MusicHandoffPlayer(
      ref,
      startTimeout: PlatformInfo.isIOS
          ? MusicHandoffPlayer.defaultStartTimeout
          : MusicHandoffPlayer.defaultAndroidStartTimeout,
    ),
    resolveStreams: (videoId) => ref.read(onlineSourceProvider).streams(videoId),
    // Android: the first retry asks yt-dlp (the extractor downloads use),
    // whose clients' links the stream server accepts where youtube_explode's
    // are often refused (HTTP 403); then youtube_explode's other clients.
    resolveStreamsVariant: (videoId, variant) {
      if (PlatformInfo.isAndroid && variant == 1 && !_fixtureMedia) {
        return extractorHandoffStreams(ref.read(extractorBackendProvider), videoId);
      }
      final v = PlatformInfo.isAndroid && variant > 1 ? variant - 1 : variant;
      return ref.read(onlineSourceProvider).streams(videoId, variant: v);
    },
    verifyStream: PlatformInfo.isAndroid ? verifyHandoffStream : null,
    enabled: () =>
        onlineHandoffEnabled(isIOS: PlatformInfo.isIOS, backgroundPlay: ref.read(onlineBackgroundPlayProvider)),
    // Both platforms: a play the page cannot start without a window. On
    // Android, once the task is swiped away the WebView has no window and
    // Chromium will not start a hidden <video> (it pauses again at once), so
    // the page is retried first (OnlineMediaSession.externalPlay) and then the
    // video plays as an audio stream in the music player.
    detachedEnabled: () => ref.read(onlineBackgroundPlayProvider),
    fixtureLocalStreams: _fixtureMedia,
  );
  session.onDetachedPlay = handoff.startDetachedPlay;
  session.onDetachedPrefetch = handoff.prefetch;
  ref.onDispose(() {
    if (identical(session.onDetachedPlay, handoff.startDetachedPlay)) {
      session.onDetachedPlay = null;
    }
    handoff.dispose();
  });
  return handoff;
});
