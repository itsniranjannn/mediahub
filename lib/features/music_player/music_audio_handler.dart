// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'auto_browse.dart';
import 'equalizer/audio_effects.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/other_audio_watcher.dart';
import '../../core/platform_info.dart';
import '../../core/utils/play_count_tracker.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../domain/models/playback_state.dart' as domain;
import 'now_playing_art.dart';

/// What an external player (the Online tab's YouTube page) shows in the media
/// notification, on the lock screen and on Bluetooth displays.
@immutable
class ExternalMediaSnapshot {
  const ExternalMediaSnapshot({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.artUri,
    required this.playing,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration,
    this.speed = 1.0,
    this.canSkipNext = false,
    this.pageUrl,
  });

  /// Stable id of what is playing (e.g. `online:<videoId>`).
  final String id;
  final String title;

  /// Channel name.
  final String? artist;

  /// The source's name in the notification's album line and on the mini
  /// player's tag ("YouTube" when null; a local video passes its own).
  final String? album;

  /// https thumbnail.
  final Uri? artUri;
  final bool playing;
  final bool buffering;
  final Duration position;

  /// Null for live streams.
  final Duration? duration;
  final double speed;

  /// The source has a "next" (shows the Next control).
  final bool canSkipNext;

  /// The page it plays on (a YouTube watch page): kept so the controls can
  /// bring the same video back after the process restarts.
  final Uri? pageUrl;

  /// [album], or "YouTube".
  String get albumOrDefault => (album == null || album!.isEmpty) ? 'YouTube' : album!;

  @override
  bool operator ==(Object other) =>
      other is ExternalMediaSnapshot &&
      other.id == id &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.artUri == artUri &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.position == position &&
      other.duration == duration &&
      other.speed == speed &&
      other.canSkipNext == canSkipNext &&
      other.pageUrl == pageUrl;

  @override
  int get hashCode =>
      Object.hash(id, title, artist, album, artUri, playing, buffering, position, duration, speed, canSkipNext, pageUrl);
}

/// The external item (a YouTube video) that last owned the media session,
/// saved so the notification can show it again after the process restarted.
@immutable
class ExternalResumeItem {
  const ExternalResumeItem({
    required this.id,
    required this.pageUrl,
    required this.title,
    this.artist,
    this.album,
    this.artUri,
    this.position = Duration.zero,
    this.duration,
  });

  final String id;
  final Uri pageUrl;
  final String title;
  final String? artist;
  final String? album;
  final Uri? artUri;
  final Duration position;
  final Duration? duration;

  static ExternalResumeItem? fromSnapshot(ExternalMediaSnapshot s) {
    final url = s.pageUrl;
    if (url == null) return null;
    return ExternalResumeItem(
      id: s.id,
      pageUrl: url,
      title: s.title,
      artist: s.artist,
      album: s.album,
      artUri: s.artUri,
      position: s.position,
      duration: s.duration,
    );
  }

  /// The page to open: a watch page gets `t=<seconds>s` (YouTube starts
  /// there); other pages open as they were.
  Uri get resumeUri {
    final secs = position.inSeconds;
    if (secs < 2 || !pageUrl.queryParameters.containsKey('v')) return pageUrl;
    final q = Map<String, String>.of(pageUrl.queryParameters)..['t'] = '${secs}s';
    return pageUrl.replace(queryParameters: q);
  }

  ExternalMediaSnapshot toSnapshot({String? artistLine, bool starting = false}) => ExternalMediaSnapshot(
        id: id,
        title: title,
        artist: artistLine ?? artist,
        album: album,
        artUri: artUri,
        playing: starting,
        buffering: starting,
        position: position,
        duration: duration,
        pageUrl: pageUrl,
      );

  String encode() => jsonEncode({
        'id': id,
        'url': pageUrl.toString(),
        'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (artUri != null) 'art': artUri.toString(),
        'pos': position.inMilliseconds,
        if (duration != null) 'dur': duration!.inMilliseconds,
      });

  /// Null for anything that is not a saved item (missing, corrupt, not https).
  static ExternalResumeItem? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json);
      if (m is! Map) return null;
      final url = Uri.tryParse(m['url'] is String ? m['url'] as String : '');
      final id = m['id'];
      final title = m['title'];
      if (url == null || url.scheme != 'https' || id is! String || title is! String) return null;
      final art = m['art'] is String ? Uri.tryParse(m['art'] as String) : null;
      final pos = m['pos'] is int ? m['pos'] as int : 0;
      final dur = m['dur'] is int ? m['dur'] as int : null;
      return ExternalResumeItem(
        id: id,
        pageUrl: url,
        title: title,
        artist: m['artist'] is String ? m['artist'] as String : null,
        album: m['album'] is String ? m['album'] as String : null,
        artUri: art,
        position: Duration(milliseconds: pos < 0 ? 0 : pos),
        duration: dur == null ? null : Duration(milliseconds: dur),
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the app should do with a restored external item once it is on
/// screen: open the page, and play it when the controls asked for that.
@immutable
class ExternalResumeRequest {
  const ExternalResumeRequest(this.item, {required this.play});
  final ExternalResumeItem item;
  final bool play;
}

/// Stands in for the YouTube page after a process restart: the notification
/// shows the saved video, and its buttons ask for the app to be opened.
class _RestoredExternal implements ExternalPlaybackDelegate {
  _RestoredExternal(this._handler, this.item);
  final MusicAudioHandler _handler;
  final ExternalResumeItem item;

  @override
  Future<void> externalPlay() async => _handler._restoredWants(play: true);
  @override
  Future<void> externalPause() async => _handler._restoredWants(play: false);
  @override
  Future<void> externalSeek(Duration position) async {}
  @override
  Future<void> externalSkipToNext() async => _handler._restoredWants(play: true);
  @override
  Future<void> externalSkipToPrevious() async => _handler._restoredWants(play: true);
  /// Local music or the real page took the session: nothing to hand back
  /// (the queue that starts playing is the player's own); the stand-in is
  /// forgotten so nothing refers to it any more.
  @override
  void onExternalSourceReleased() => _handler._restoredReleased(this);
}

/// Receives the notification / lock screen / headset commands while it is the
/// handler's external source.
abstract class ExternalPlaybackDelegate {
  Future<void> externalPlay();
  Future<void> externalPause();
  Future<void> externalSeek(Duration position);
  Future<void> externalSkipToNext();
  Future<void> externalSkipToPrevious();

  /// The handler went back to local music (local playback started or the
  /// source was replaced). The delegate should stop claiming the session
  /// until its media plays again.
  void onExternalSourceReleased();
}

/// The part of [MusicAudioHandler] an external source talks to.
abstract class ExternalPlaybackHost {
  /// Makes [delegate] the source of the media session: local music pauses,
  /// the notification shows [snapshot] and routes its buttons to [delegate].
  void setExternalSource(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot);

  /// New state of the active external source (ignored for any other delegate).
  void updateExternalMedia(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot);

  /// Hands the session back to local music (no-op unless [delegate] is active).
  void clearExternalSource(ExternalPlaybackDelegate delegate);
}

/// The music engine behind the app's player, the media notification, the lock
/// screen, Bluetooth and the headset buttons.
///
/// ## Next / Previous
///
/// A press is turned into a target index at once, from where the previous
/// presses were heading (Spotify / YT Music behaviour): the notification and
/// the app show the target straight away, and the player seeks once to the
/// newest target instead of loading every song on the way. Presses are
/// "coalesced": each one bumps a generation, the serialized action of an
/// older press finds a newer generation and returns. A Next with nowhere to
/// go (the last track, repeat off) is ignored on the spot and changes
/// nothing, not even the play intent. Every seek waits until the player is
/// done loading (just_audio drops a seek while it loads).
///
/// Queue edits run in the same serialized chain and first apply a pending
/// skip, so an index handed in by the UI always refers to the queue the UI
/// showed.
class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler implements ExternalPlaybackHost {
  final AudioPlayer _player;
  final Future<void> Function(String mediaId)? onRecordPlay;

  /// Called once per track when the player learns a duration that the library
  /// did not know yet (downloaded files are stored with duration 0).
  final Future<void> Function(String mediaId, int durationMs)? onDurationKnown;

  /// Toggles a song's favourite flag (the notification's heart). With
  /// [watchFavorite], the notification shows a Like button for local songs.
  final Future<void> Function(String mediaId)? onToggleFavorite;

  /// The live favourite flag of a song.
  final Stream<bool> Function(String mediaId)? watchFavorite;

  /// The last saved session, for Android's media resumption (the
  /// quick-settings player after the app was closed).
  final Future<domain.PlaybackState?> Function()? loadLastSession;

  /// Whether the phone's media controls last belonged to an external source
  /// (the Online tab), saved across process restarts: read once at start.
  final bool Function()? loadExternalHeld;

  /// Saves [externalHeld] whenever it changes.
  final void Function(bool held)? saveExternalHeld;

  /// Paused this long, the session ends: the foreground service, its wake
  /// lock and the notification go (docs: ONL-8). Off by default (null): a
  /// paused session, local or the Online tab's, keeps its notification and a
  /// working Play button until the user closes it, also after the app was
  /// swiped away from recents. Paused, the service holds no wake lock.
  static const Duration? defaultPausedIdleTimeout = null;
  final Duration? pausedIdleTimeout;

  /// How long a seek waits for the player to finish loading.
  static const Duration loadingWaitTimeout = Duration(seconds: 10);

  /// The sleep timer lowers the volume over this time before it pauses.
  static const Duration sleepFadeDuration = Duration(seconds: 10);
  static const int _sleepFadeSteps = 20;
  final Duration sleepFade;

  final NowPlayingArt _art;

  /// Drops [id]'s cached media-session cover (the song was deleted).
  Future<void> forgetArt(String id) => _art.forget(id);
  final DateTime Function() _clock;

  final Set<String> _durationReported = {};
  late final PlayCountTracker _playCountTracker;
  // ignore: deprecated_member_use
  ConcatenatingAudioSource? _playlistSource;
  List<domain.MediaItem> _originalQueue = [];
  List<domain.MediaItem> _playOrderQueue = [];
  bool _shuffleEnabled = false;
  domain.PlaybackRepeatMode _repeatMode = domain.PlaybackRepeatMode.off;

  List<domain.MediaItem> get originalQueue => List.unmodifiable(_originalQueue);
  List<domain.MediaItem> get playOrderQueue => List.unmodifiable(_playOrderQueue);
  bool get shuffleEnabled => _shuffleEnabled;

  /// The order the player has loaded.
  List<domain.MediaItem> get _domainQueue => _playOrderQueue;

  /// Headphones, earbuds and other personal outputs (not the built-in speaker/earpiece).
  static bool _isPersonalAudioOutput(AudioDevice d) {
    if (!d.isOutput) return false;
    switch (d.type) {
      case AudioDeviceType.wiredHeadset:
      case AudioDeviceType.wiredHeadphones:
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothSco:
      case AudioDeviceType.usbAudio:
        return true;
      default:
        return false;
    }
  }

  /// While the source list is edited in place the player emits transient
  /// indices that do not match the queue yet: ignore them.
  bool _suppressIndexEvents = false;

  UriAudioSource _sourceFor(domain.MediaItem item) {
    final uri = _audioUri(item.uri);
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    final headers = isHttp
        ? const {'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'}
        : null;
    return AudioSource.uri(uri, headers: headers, tag: item.id);
  }

  /// Moves the queue around the currently playing track WITHOUT reloading it, so
  /// toggling shuffle never interrupts the sound. The current item is kept, all
  /// other items are removed and re-inserted in the new order.
  // ignore: deprecated_member_use
  Future<void> _reorderAroundCurrent(ConcatenatingAudioSource src, int curIdx, int newIdx) async {
    _suppressIndexEvents = true;
    try {
      final total = src.length;
      if (curIdx < total - 1) await src.removeRange(curIdx + 1, total);
      if (curIdx > 0) await src.removeRange(0, curIdx);
      final before = _playOrderQueue.sublist(0, newIdx).map(_sourceFor).toList();
      final after = _playOrderQueue.sublist(newIdx + 1).map(_sourceFor).toList();
      if (after.isNotEmpty) await src.insertAll(1, after);
      if (before.isNotEmpty) await src.insertAll(0, before);
    } finally {
      _suppressIndexEvents = false;
    }
  }

  /// Plain file paths (downloaded media) have no scheme: ExoPlayer needs file://.
  static Uri _audioUri(String raw) => raw.contains('://') ? Uri.parse(raw) : Uri.file(raw);

  /// Removes the first element with [id]; keeps duplicates that follow.
  static void _removeFirstById(List<domain.MediaItem> list, String id) {
    final i = list.indexWhere((m) => m.id == id);
    if (i >= 0) list.removeAt(i);
  }

  // Custom notification actions
  static const String actionToggleShuffle = 'action_toggle_shuffle';
  static const String actionCycleRepeat = 'action_cycle_repeat';
  static const String actionToggleFavorite = 'action_toggle_favorite';

  /// Previous restarts the track instead once it has played longer than this
  /// (docs/DESIGN.md 7.17).
  static const Duration restartThreshold = Duration(seconds: 3);

  /// Whether Next has somewhere to go from [index] in a queue of [length]:
  /// everywhere but the last item while repeat is off, where the mini
  /// player, Now Playing and the notification all show it disabled
  /// (docs/DESIGN.md 7.17).
  static bool canSkipNextAt({
    required int index,
    required int length,
    required domain.PlaybackRepeatMode repeatMode,
  }) {
    if (index < 0 || index >= length) return false;
    return index < length - 1 || repeatMode != domain.PlaybackRepeatMode.off;
  }

  /// Whether Next is enabled for the current (or targeted) track.
  bool get canSkipNext =>
      canSkipNextAt(index: _virtualIndex, length: _virtualQueue.length, repeatMode: _repeatMode);

  /// The headset's single button: one press plays / pauses, two skip to the
  /// next track, three to the previous one (Android's media session default,
  /// which audio_service replaces with one call per press). Zero turns the
  /// counting off; iOS counts EarPods presses itself.
  final Duration mediaButtonMultiClickWindow;
  int _mediaButtonClicks = 0;
  Timer? _mediaButtonTimer;

  // Headset auto-resume state
  bool _resumeOnHeadphonesReconnect = true;
  bool get resumeOnHeadphonesReconnect => _resumeOnHeadphonesReconnect;
  void setResumeOnHeadphonesReconnect(bool value) {
    _resumeOnHeadphonesReconnect = value;
  }

  DateTime? _lastNoisyPauseTimestamp;
  bool _userInteractedSinceNoisy = false;
  bool _resumeOnFocusGain = false;
  double _volumeBeforeDuck = 1.0;

  /// iOS: the external source (a video on screen) that was playing when a
  /// call, Siri or an alarm interrupted it, to be resumed when that ends.
  ExternalPlaybackDelegate? _interruptedExternal;

  /// When the external source last went from playing to paused. iOS may
  /// report the video's own pause just before the interruption itself.
  DateTime? _externalStoppedAt;
  static const _interruptionPauseGrace = Duration(seconds: 1);

  /// Audio interruptions (calls, Siri, alarms, other apps): audio_session's
  /// own stream, or the one a test drives.
  final Stream<AudioInterruptionEvent>? _interruptionEvents;

  // --- resume after other apps (Android) -------------------------------------

  /// Watches other apps' playback while the music waits for one to stop
  /// (Android; null elsewhere, and where a test gives none).
  final OtherAudioWatcher? _otherAudio;

  /// Settings → "Resume after other apps", read each time it matters.
  final bool Function() _resumeAfterOtherApps;

  /// Music that another app's sound paused for good (Android never gives the
  /// sound back by itself then) plays again when that app stops, but only
  /// within this time.
  static const Duration otherAppResumeWindow = Duration(minutes: 30);

  /// When the music started waiting for another app to stop (null: no wait).
  DateTime? _otherAppWaitSince;

  /// The other app has been heard playing since the wait began. Until then a
  /// quiet phone means it is still getting ready, not that it stopped.
  bool _otherAppSeenPlaying = false;
  int _otherAppWaitId = 0;
  StreamSubscription<OtherAudioState>? _otherAudioSub;
  Timer? _otherAppWaitTimer;

  /// How long after the music's own pause other apps' playback starts being
  /// watched. The phone lists every app's playing players without saying
  /// whose they are, and the music's own player only stops a moment after
  /// the pause call returns: watched at once, it would count as "another app
  /// playing", and the next quiet moment would start the music again.
  final Duration _otherAppWatchDelay;
  static const Duration defaultOtherAppWatchDelay = Duration(milliseconds: 600);

  /// The music played again by itself, and another app took the sound back
  /// within this time (YouTube's next video, a buffering pause): it then
  /// stays paused, so the two apps never go back and forth.
  static const Duration otherAppRetakeWindow = Duration(minutes: 1);

  /// When the music last played again by itself after another app stopped
  /// (null once the user played since).
  DateTime? _otherAppResumedAt;

  /// The play() caller of that resume.
  static const String _otherAppResumeCaller = 'other_app_stopped';

  /// The music waits for another app to stop playing.
  @visibleForTesting
  bool get waitingForOtherApp => _otherAppWaitSince != null;

  // Single intent flag for playing
  bool _wantPlaying = false;
  bool get wantPlaying => _wantPlaying;

  void _safeStartPlayerPlay(String caller) {
    if (!_wantPlaying) {
      debugPrint('[MusicAudioHandler] _safeStartPlayerPlay skipped: _wantPlaying is false');
      return;
    }
    _player.play().catchError((e) {
      DiagnosticsService.instance.logEvent('player_error', {'source': caller, 'error': e.toString()});
      debugPrint('[MusicAudioHandler] Error in _player.play() from $caller: $e');
    });
  }

  // --- the serialized chain ---------------------------------------------------

  Future<void> _actionChain = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action, [String actionName = 'action']) {
    final completer = Completer<T>();
    _actionChain = _actionChain.then((_) async {
      final sw = Stopwatch()..start();
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        sw.stop();
        if (sw.elapsedMilliseconds >= 400) {
          // Only slow actions are interesting.
          DiagnosticsService.instance.logEvent('lock_held', {
            'action': actionName,
            'durationMs': sw.elapsedMilliseconds,
          });
        }
      }
    });
    return completer.future;
  }

  // --- coalesced skipping -----------------------------------------------------

  /// Bumped by every press and by anything that settles or drops presses.
  int _skipGeneration = 0;

  /// Where the pending presses are heading (an index into [_virtualQueue]),
  /// or null when no skip waits.
  int? _skipTarget;

  /// The reshuffled order a Next past the end (repeat + shuffle) starts;
  /// applied together with [_skipTarget].
  List<domain.MediaItem>? _pendingOrder;

  /// The index an action is loading or seeking to right now.
  int? _anchorIndex;

  /// The index the handler itself last moved the player to. An index event
  /// that differs is the player moving on by itself (a song ended).
  int? _lastRequestedIndex;

  void _anchor(int index) {
    _anchorIndex = index;
    _lastRequestedIndex = index;
    _moveEpoch++;
  }

  /// Bumped whenever the handler moves the player (a load, a skip, a
  /// restore, a stop) and when it deals with a failed song. A failure
  /// report taken before the bump is stale: the player moved on since, or
  /// the same failure reached the handler twice (a load that failed reports
  /// it on the error stream and by throwing).
  int _moveEpoch = 0;

  /// The failure dealt with last: the move epoch right after it, and the
  /// queue position. Pressing play clears it (a new try).
  (int, int)? _handledFailure;

  /// Completes when the pending presses have been applied (or dropped).
  Completer<void>? _batch;
  int _batchPresses = 0;

  /// Queue loads (and restores) asked for that have not started yet. A press
  /// made meanwhile means the new queue: it waits for the load.
  int _pendingLoads = 0;

  /// Runs [press] once the pending load has started, inside the chain but
  /// without awaiting its batch (that would wait on itself).
  Future<void> _afterPendingLoad(Future<void> Function() press) {
    final done = Completer<void>();
    _synchronized(() async {
      press().then((_) {
        if (!done.isCompleted) done.complete();
      }, onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      });
    }, 'press_after_load').catchError((Object _) {});
    return done.future;
  }

  /// The queue as the user sees it: a pending reshuffle, else the loaded order.
  List<domain.MediaItem> get _virtualQueue => _pendingOrder ?? _playOrderQueue;

  /// The index as the user sees it: the pending target, the index being
  /// loaded, else the player's.
  int get _virtualIndex => _skipTarget ?? _anchorIndex ?? (_player.currentIndex ?? -1);

  domain.MediaItem? get _virtualCurrentItem {
    final q = _virtualQueue;
    final i = _virtualIndex;
    return (i >= 0 && i < q.length) ? q[i] : null;
  }

  /// A press is waiting to be applied.
  @visibleForTesting
  bool get hasPendingSkip => _skipTarget != null;

  // --- loading-safe seeks -----------------------------------------------------

  final List<Completer<void>> _loadingWaiters = [];

  void _releaseLoadingWaiters() {
    if (_loadingWaiters.isEmpty) return;
    for (final c in List.of(_loadingWaiters)) {
      if (!c.isCompleted) c.complete();
    }
    _loadingWaiters.clear();
  }

  /// The work in hand is stale: a queue load (or replacing restore) waits behind it, or,
  /// with a [generation], a newer press or edit came in after it was taken.
  bool _superseded([int? generation]) =>
      _pendingReplaces > 0 || (generation != null && generation != _skipGeneration);

  /// Queue loads (and replacing restores) asked for that have not run yet:
  /// they replace whatever an earlier action is waiting to do.
  int _pendingReplaces = 0;

  /// Waits (at most [loadingWaitTimeout]) until the player is not loading:
  /// just_audio ignores a seek while it loads. Gives up at once when the work
  /// is [_superseded] (a slow stream must not hold a tapped song back).
  Future<void> _waitWhileLoading([int? generation]) async {
    if (_player.processingState != ProcessingState.loading || _superseded(generation)) return;
    final done = Completer<void>();
    _loadingWaiters.add(done);
    final poll = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (done.isCompleted) return;
      if (_player.processingState != ProcessingState.loading || _superseded(generation)) done.complete();
    });
    try {
      await done.future.timeout(loadingWaitTimeout, onTimeout: () {
        DiagnosticsService.instance.logEvent('loading_wait_timeout');
      });
    } finally {
      poll.cancel();
      _loadingWaiters.remove(done);
    }
  }

  /// Seeks to [index] at 0:00, waiting out a load first; tries again (twice)
  /// if the player started loading and dropped the seek. Stops as soon as the
  /// seek is [_superseded]: whatever replaced it does its own.
  Future<void> _seekToIndex(int index, [int? generation]) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await _waitWhileLoading(generation);
      if (_superseded(generation)) return;
      await _player.seek(Duration.zero, index: index);
      if ((_player.currentIndex ?? -1) == index || _player.processingState != ProcessingState.loading) return;
    }
  }

  /// Loads the whole [_playOrderQueue] into the player at [index].
  Future<void> _loadSource({required int index, Duration position = Duration.zero}) async {
    final audioSources = _playOrderQueue.map(_sourceFor).toList();
    // just_audio 0.10 has AudioPlayer.setAudioSources / insertAudioSources,
    // but the queue edits below (insert, add, remove, move, the seamless
    // shuffle) work on this playlist object, and so does the test player.
    // ConcatenatingAudioSource is deprecated, not removed, in 0.10.x; move all
    // of them together when a just_audio release drops it.
    // ignore: deprecated_member_use
    _playlistSource = ConcatenatingAudioSource(children: audioSources);
    await _player.setAudioSource(_playlistSource!, initialIndex: index, initialPosition: position);
  }

  int _consecutiveErrorSkips = 0;
  String _lastLoggedPlayerState = '';
  ProcessingState? _lastProcessingState;
  (int, String?)? _lastIndexEvent;

  // Stream controller to broadcast error messages (e.g. unplayable or missing files)
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorEvents => _errorController.stream;

  /// The id of every song that failed to play, once per failure, after the
  /// handler dealt with it (also while paused, when nothing else happens).
  final _failureController = StreamController<String>.broadcast();
  Stream<String> get trackFailures => _failureController.stream;

  /// just_audio's "Connection aborted": a newer load stopped an older one.
  /// Not a failure of any song.
  static const int abortedErrorCode = 10000000;

  void _emitError(String message) {
    if (!_errorController.isClosed) _errorController.add(message);
  }

  final _domainStateController = StreamController<domain.PlaybackState>.broadcast();
  Stream<domain.PlaybackState> get domainStateStream => _domainStateController.stream;

  // --- external source (the Online tab's YouTube page) ----------------------
  ExternalPlaybackDelegate? _external;
  ExternalMediaSnapshot? _externalMedia;
  MediaItem? _externalItem;
  final _externalController = StreamController<ExternalMediaSnapshot?>.broadcast();

  /// True while an external source owns the media session.
  bool get isExternalActive => _external != null;

  /// What the external source last reported (null in local mode).
  ExternalMediaSnapshot? get externalMedia => _externalMedia;

  /// Emits on every external change, and null when the handler is back to local music.
  Stream<ExternalMediaSnapshot?> get externalMediaStream => _externalController.stream;

  /// The last source the user played was an external one (YouTube in the
  /// Online tab) and it went away by itself: paused past its release, its
  /// page frozen or gone, or the whole process restarted in the background.
  /// While true the phone's controls (notification play, a headset click,
  /// media resumption) never start local music on their own; only a local
  /// start made in the app clears it. A play from the controls goes to that
  /// source again if it is still there.
  bool _externalHeld = false;

  /// Where main.dart saves [externalHeld].
  static const String externalHeldPrefKey = 'media_controls_external_held';

  /// Where main.dart saves the last external item (see [ExternalResumeItem]).
  static const String externalResumePrefKey = 'media_controls_external_resume';

  /// The notification's second line while a play waits for the app.
  static const String tapToResumeLine = 'Tap to resume in MediaHub';

  final String? Function()? loadExternalResume;
  final void Function(String? encoded)? saveExternalResume;
  ExternalResumeItem? _lastSavedResume;

  _RestoredExternal? _restored;
  bool _restoredPlayPending = false;
  bool _restoredTaken = false;
  final _restoredRequests = StreamController<void>.broadcast();

  /// The saved video the notification shows after a restart (null once the
  /// app took it, the page itself took over, or local music did).
  ExternalResumeItem? get restoredExternal {
    final r = _restored;
    return r != null && !_restoredTaken && identical(_external, r) ? r.item : null;
  }

  /// The app opened the restored video and its page has not taken the
  /// session yet: a play from the controls goes to that page.
  bool get restoredAwaitingPage {
    final r = _restored;
    return r != null && _restoredTaken && identical(_external, r);
  }

  /// A play (or next) from the controls is waiting for the app to open.
  bool get restoredPlayPending => restoredExternal != null && _restoredPlayPending;

  /// Emits when play (or next) was pressed on the restored item (the app, if
  /// it is on screen, opens the page then).
  Stream<void> get restoredRequests => _restoredRequests.stream;

  /// For the app once on screen: the restored item to open (and whether to
  /// play it); null when there is none. The item stays on the notification
  /// until the page claims the session.
  ExternalResumeRequest? takeRestoredExternal() {
    final r = _restored;
    if (r == null || _restoredTaken || !identical(_external, r)) return null;
    final play = _restoredPlayPending;
    _restoredPlayPending = false;
    _restoredTaken = true; // the page takes it from here
    return ExternalResumeRequest(r.item, play: play);
  }

  /// Android, with no window (the process restarted after the task was
  /// swiped away): the restored video is starting in a page without one
  /// (OnlineHeadlessPlayer). Shown as loading, and playing, right away, so
  /// the media service enters the foreground while the press of Play still
  /// allows it; the page's own reports take over once it plays.
  void showRestoredStarting() {
    final r = _restored;
    if (r == null || !identical(_external, r)) return;
    DiagnosticsService.instance.logEvent('external_restored_starting');
    _applyExternal(r.item.toSnapshot(starting: true));
  }

  /// The page without a window could not start: back to "tap to resume".
  void showRestoredWaiting() {
    final r = _restored;
    if (r == null || !identical(_external, r)) return;
    _applyExternal(r.item.toSnapshot(artistLine: tapToResumeLine));
  }

  void _restoredWants({required bool play}) {
    final r = _restored;
    if (r == null || !identical(_external, r)) return;
    DiagnosticsService.instance.logEvent('play', {'caller': 'system', 'target': 'external_restored', 'play': play});
    _restoredPlayPending = play;
    _applyExternal(r.item.toSnapshot(artistLine: play ? tapToResumeLine : null));
    if (play && !_restoredRequests.isClosed) _restoredRequests.add(null);
  }

  void _restoredReleased(_RestoredExternal r) {
    if (!identical(_restored, r)) return;
    _restored = null;
    _restoredPlayPending = false;
    _restoredTaken = false;
  }

  void _restoreSavedExternal() {
    ExternalResumeItem? item;
    try {
      item = ExternalResumeItem.decode(loadExternalResume?.call());
    } catch (_) {
      item = null;
    }
    if (item == null) return;
    _lastSavedResume = item;
    DiagnosticsService.instance.logEvent('external_source_restored');
    final r = _RestoredExternal(this, item);
    _restored = r;
    setExternalSource(r, item.toSnapshot());
  }

  void _saveResume(ExternalMediaSnapshot s) {
    final r = _restored;
    if (r != null && identical(_external, r)) return; // only a real page's state
    final item = ExternalResumeItem.fromSnapshot(s);
    if (item == null) return;
    final last = _lastSavedResume;
    if (last != null &&
        last.id == item.id &&
        last.title == item.title &&
        last.pageUrl == item.pageUrl &&
        (item.position - last.position).inMilliseconds.abs() < 5000 &&
        s.playing) {
      return;
    }
    _lastSavedResume = item;
    try {
      saveExternalResume?.call(item.encode());
    } catch (e) {
      debugPrint('[MusicAudioHandler] saving the external item failed: $e');
    }
  }
  ExternalPlaybackDelegate? _lastExternal;

  bool get externalHeld => _externalHeld;

  void _setExternalHeld(bool held) {
    if (!held) {
      _lastExternal = null;
      if (_lastSavedResume != null || _externalHeld) {
        _lastSavedResume = null;
        try {
          saveExternalResume?.call(null);
        } catch (_) {}
      }
    }
    if (_externalHeld == held) return;
    _externalHeld = held;
    try {
      saveExternalHeld?.call(held);
    } catch (e) {
      debugPrint('[MusicAudioHandler] saving the media source failed: $e');
    }
  }

  /// A local start the user made in the app: local music owns the controls again.
  void _localChosen() => _setExternalHeld(false);

  /// The Online hand-off loaded its stream here (paused) because the page
  /// lost its window: the phone's controls belong to this player now, also
  /// its Play (no "held" page source left to send it to).
  void takeControlsFromExternal({required String reason}) {
    _localChosen();
    _releaseExternal(reason: reason);
    _broadcastAudioServiceState();
  }

  // --- favourite (the notification's heart) ----------------------------------
  StreamSubscription<bool>? _favoriteSub;
  String? _favoriteFor;
  bool _currentFavorite = false;

  // --- paused-idle stop --------------------------------------------------------
  Timer? _idleStopTimer;
  bool _sessionPlaying = false;

  // --- sleep timer -------------------------------------------------------------
  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;
  bool _sleepEndOfTrack = false;
  Timer? _fadeTimer;
  double? _volumeBeforeFade;
  final _sleepController = StreamController<domain.SleepTimerStatus>.broadcast();
  Duration _lastPosition = Duration.zero;
  int? _lastPositionIndex;

  /// When the handler last moved the position itself. A jump back to the
  /// start within [_ownSeekGrace] of it is that seek, not a repeat-one loop.
  DateTime? _ownSeekAt;
  static const _ownSeekGrace = Duration(seconds: 1);

  void _noteOwnSeek(Duration to) {
    _ownSeekAt = _clock();
    _lastPosition = to;
  }

  MusicAudioHandler({
    AudioPlayer? player,
    this.onRecordPlay,
    this.onDurationKnown,
    this.onToggleFavorite,
    this.watchFavorite,
    this.loadLastSession,
    this.loadExternalHeld,
    this.saveExternalHeld,
    this.loadExternalResume,
    this.saveExternalResume,
    Duration? mediaButtonMultiClickWindow,
    Duration? pausedIdleTimeout,
    Duration? sleepFade,
    NowPlayingArt? art,
    DateTime Function()? clock,
    // Tests drive interruptions here; the app leaves it null and gets
    // audio_session's own stream.
    Stream<AudioInterruptionEvent>? interruptionEvents,
    // Android: other apps' playback, for "Resume after other apps".
    OtherAudioWatcher? otherAudio,
    bool Function()? resumeAfterOtherApps,
    Duration? otherAppWatchDelay,
  })  : _player = player ??
            // just_audio 0.10.6 calls AndroidEqualizer._activate() before load()
            // initializes ExoPlayer's audio session, causing an NPE on Android.
            AudioPlayer(handleInterruptions: false),
        _interruptionEvents = interruptionEvents, // ignore: prefer_initializing_formals
        _otherAudio = otherAudio, // ignore: prefer_initializing_formals
        _resumeAfterOtherApps = resumeAfterOtherApps ?? _always,
        _otherAppWatchDelay = otherAppWatchDelay ?? defaultOtherAppWatchDelay,
        mediaButtonMultiClickWindow = mediaButtonMultiClickWindow ??
            (PlatformInfo.isAndroid ? const Duration(milliseconds: 300) : Duration.zero),
        pausedIdleTimeout = pausedIdleTimeout ?? defaultPausedIdleTimeout,
        sleepFade = sleepFade ?? sleepFadeDuration,
        _art = art ?? NowPlayingArt(),
        _clock = clock ?? DateTime.now {
    _playCountTracker = PlayCountTracker(onCountPlay: (id) async {
      DiagnosticsService.instance.logEvent('track_play_counted', {'id': id});
      if (onRecordPlay != null) {
        await onRecordPlay!(id);
      }
    });
    DiagnosticsService.instance.logEvent('service_start');
    try {
      _externalHeld = loadExternalHeld?.call() ?? false;
    } catch (_) {
      _externalHeld = false;
    }
    _init();
    // The controls belonged to YouTube when the process went away: show that
    // video again (paused) instead of a dead player or local music.
    if (_externalHeld) _restoreSavedExternal();
  }

  static bool _always() => true;

  AudioPlayer get player => _player;
  List<domain.MediaItem> get domainQueue => List.unmodifiable(_domainQueue);
  int get currentIndex => _player.currentIndex ?? -1;
  domain.PlaybackRepeatMode get repeatMode => _repeatMode;

  Future<void> _init() async {
    final injectedInterruptions = _interruptionEvents;
    injectedInterruptions?.listen(_onInterruption);

    // 1. Listen to player events and broadcast AudioService PlaybackState on EVERY change
    _player.playbackEventStream.listen(
      (_) {
        if (_player.processingState != ProcessingState.loading) _releaseLoadingWaiters();
        _broadcastAudioServiceState();
      },
      onError: (Object e, StackTrace st) {
        handlePlaybackError(e, source: 'playback_event');
      },
    );

    // just_audio 0.10.6 reports a song that cannot play (a missing or moved
    // file, one it cannot decode, a refused stream) here only: it is a field
    // of the playback events, never an error on playbackEventStream.
    try {
      _player.errorStream.listen((e) => handlePlaybackError(e), onError: (Object _) {});
    } catch (e) {
      DiagnosticsService.instance.logEvent('player_error_stream_missing');
      debugPrint('[MusicAudioHandler] no player error stream: $e');
    }
    try {
      _player.androidAudioSessionIdStream.listen(
        (id) => AudioEffects.instance.attachSession(id),
        onError: (Object _) {},
      );
    } catch (_) {}

    _player.playerStateStream.listen((state) {
      // Only log real changes: this stream re-emits often and would push the
      // useful events out of the 300-line diagnostics buffer.
      final stateKey = '${state.processingState}/${state.playing}';
      if (stateKey != _lastLoggedPlayerState) {
        _lastLoggedPlayerState = stateKey;
        DiagnosticsService.instance.logEvent('processing_state_change', {
          'state': state.processingState.toString(),
          'playing': state.playing,
        });
      }
      if (state.processingState != ProcessingState.loading) _releaseLoadingWaiters();

      if (state.processingState == ProcessingState.ready && state.playing) {
        _consecutiveErrorSkips = 0;
      }
      _broadcastAudioServiceState();
      // Only the step INTO completed: the stream repeats states, and a second
      // run would advance twice (F15).
      final enteredCompleted = state.processingState == ProcessingState.completed &&
          _lastProcessingState != ProcessingState.completed;
      _lastProcessingState = state.processingState;
      if (enteredCompleted) {
        _synchronized(_handlePlaybackCompleted, 'completed').catchError((Object e) {
          debugPrint('[MusicAudioHandler] completion failed: $e');
        });
      }
      _notifyDomainState();
    });

    _player.currentIndexStream.listen((idx) {
      if (_suppressIndexEvents) return;
      final id = (idx != null && idx >= 0 && idx < _domainQueue.length) ? _domainQueue[idx].id : null;
      final event = (idx ?? -1, id);
      if (event == _lastIndexEvent) return; // the same index again: nothing changed
      final previous = _lastIndexEvent;
      _lastIndexEvent = event;
      if (id != null) {
        _playCountTracker.onTrackChanged(id, Duration(milliseconds: _domainQueue[idx!].durationMs));
      } else {
        _playCountTracker.onTrackChanged(null, Duration.zero);
      }
      // The player moved on by itself (the song ended): "end of song" sleep.
      final natural = previous != null && previous.$2 != null && idx != _lastRequestedIndex && _skipTarget == null;
      _lastRequestedIndex = idx;
      if (natural) _onNaturalTrackEnd();
      _syncCurrentAudioServiceMediaItem();
      _broadcastAudioServiceState();
      _notifyDomainState();
    });

    _player.positionStream.listen((pos) {
      _playCountTracker.onPositionUpdated(pos, isPlaying: _player.playing);
      // Repeat one loops inside the player: a jump from the last seconds back
      // to the start is the song ending.
      // Not a seek the handler made (the user dragging to 0:00, Previous
      // restarting the song) and not a move to another song.
      final index = _player.currentIndex;
      final seekAt = _ownSeekAt;
      final justSeeked = seekAt != null && _clock().difference(seekAt) < _ownSeekGrace;
      if (_sleepEndOfTrack &&
          _repeatMode == domain.PlaybackRepeatMode.one &&
          _anchorIndex == null &&
          !justSeeked &&
          index == _lastPositionIndex) {
        final dur = _player.duration;
        if (dur != null &&
            dur > const Duration(seconds: 3) &&
            _lastPosition > dur - const Duration(milliseconds: 1500) &&
            pos < const Duration(milliseconds: 1500)) {
          _onNaturalTrackEnd();
        }
      }
      _lastPosition = pos;
      _lastPositionIndex = index;
      // Position stream updates are consumed by throttledPositionStreamProvider;
      // Do not broadcast domain state at 5 Hz to save CPU/battery.
    });

    _player.durationStream.listen((dur) {
      if (dur != null && _playCountTracker.currentTrackId != null) {
        _playCountTracker.onTrackChanged(_playCountTracker.currentTrackId, dur);
      }
      _reportLearnedDuration(dur);
      _broadcastAudioServiceState();
      _notifyDomainState();
    });

    // 2. The audio session, after the player's own streams: a song that
    // fails while the session is still being set up (the restore at
    // launch) must not go unseen.
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      if (injectedInterruptions == null) session.interruptionEventStream.listen(_onInterruption);

      session.becomingNoisyEventStream.listen((_) {
        DiagnosticsService.instance.logEvent('becoming_noisy');
        _lastNoisyPauseTimestamp = DateTime.now();
        _userInteractedSinceNoisy = false;
        pause(reason: 'becoming_noisy');
      });

      session.devicesChangedEventStream.listen((event) {
        DiagnosticsService.instance.logEvent('device_changed', {
          'devicesAdded': event.devicesAdded.length,
          'devicesRemoved': event.devicesRemoved.length,
        });

        // Local music only: a YouTube page is resumed from the page or the notification.
        if (_external == null && _resumeOnHeadphonesReconnect && event.devicesAdded.any(_isPersonalAudioOutput)) {
          final now = DateTime.now();
          if (_lastNoisyPauseTimestamp != null && !_userInteractedSinceNoisy) {
            final diff = now.difference(_lastNoisyPauseTimestamp!);
            if (diff.inMinutes < 10) {
              DiagnosticsService.instance.logEvent('headphones_reconnected_autoresume');
              play(caller: 'headphones_reconnect');
            }
          }
        }
      });
    } catch (e) {
      DiagnosticsService.instance.logEvent('audio_session_config_error');
      debugPrint('Error configuring AudioSession: $e');
    }
  }

  // --- audio interruptions (calls, Siri, alarms, other apps) ----------------------

  void _onInterruption(AudioInterruptionEvent event) {
    if (PlatformInfo.isIOS) {
      _onIosInterruption(event);
      return;
    }
    DiagnosticsService.instance.logEvent('audio_focus_change', {
      'begin': event.begin,
      'type': event.type.toString(),
      if (_external != null) 'ignored': 'external_source',
    });
    // The WebView asks for (and reacts to) audio focus on its own. Its own
    // request is what takes focus away from this session when a YouTube
    // video starts, so routing these events to the page would pause the
    // video it just started. Local music is already paused in this mode.
    if (_external != null) {
      _resumeOnFocusGain = false;
      return;
    }

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _volumeBeforeDuck = _player.volume;
          _player.setVolume((_volumeBeforeDuck * 0.5).clamp(0.0, 1.0));
          break;
        case AudioInterruptionType.pause:
          _resumeOnFocusGain = _resumeOnFocusGain || _player.playing;
          pause(reason: _transientLossPauseReason);
          break;
        case AudioInterruptionType.unknown:
          // Another app took the sound for good (it plays music or a video):
          // Android never gives it back by itself, so the music waits for
          // that app to stop instead (Resume after other apps).
          final wasPlaying = _player.playing || _resumeOnFocusGain;
          _resumeOnFocusGain = false;
          final paused = pause(reason: _permanentLossPauseReason);
          if (wasPlaying) _waitForOtherApp(paused);
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _player.setVolume(_volumeBeforeDuck);
          break;
        case AudioInterruptionType.pause:
          if (_resumeOnFocusGain) {
            _resumeOnFocusGain = false;
            play(caller: 'audio_focus_resume');
          }
          break;
        case AudioInterruptionType.unknown:
          _resumeOnFocusGain = false;
          break;
      }
    }
  }

  /// The pause a permanent focus loss makes (it starts the wait, so it must
  /// not end it the way any other pause does).
  static const _permanentLossPauseReason = 'focus_loss_permanent';

  /// The pause a short focus loss makes (it keeps the resume flag).
  static const _transientLossPauseReason = 'focus_loss_transient';

  /// Android: another app took the sound for good while the music played.
  /// Its playback is watched; once it has played and then stopped, the
  /// music plays again (asking for the sound back), within
  /// [otherAppResumeWindow]. A press of play, pause, stop or a skip, a new
  /// queue, a video or the Online tab taking over, a call, or the setting
  /// being off all keep it paused. So does another app taking the sound
  /// again within [otherAppRetakeWindow] of such a resume.
  ///
  /// Watching starts only once the music's own pause ([paused]) is through,
  /// plus [_otherAppWatchDelay]: until then the phone may still list the
  /// music's own player as playing.
  void _waitForOtherApp(Future<void> paused) {
    final watcher = _otherAudio;
    if (watcher == null || !_resumeAfterOtherApps()) return;
    _endOtherAppWait(null); // a fresh wait
    final resumedAt = _otherAppResumedAt;
    final now = _clock();
    if (resumedAt != null && !now.isBefore(resumedAt) && now.difference(resumedAt) < otherAppRetakeWindow) {
      // The other app took the sound back right after the music resumed by
      // itself: it is that app's turn now, and the music stays paused.
      _otherAppResumedAt = null;
      DiagnosticsService.instance.logEvent('other_app_wait_skipped', {'reason': 'taken_again'});
      return;
    }
    final id = ++_otherAppWaitId;
    _otherAppWaitSince = now;
    _otherAppSeenPlaying = false;
    _otherAppWaitTimer = Timer(otherAppResumeWindow, () => _endOtherAppWait('expired'));
    DiagnosticsService.instance.logEvent('other_app_wait_start');
    unawaited(_startWatching(watcher, id, paused));
  }

  Future<void> _startWatching(OtherAudioWatcher watcher, int id, Future<void> paused) async {
    try {
      await paused;
    } catch (_) {
      // The pause itself failed: the watch still starts after the delay.
    }
    if (_otherAppWatchDelay > Duration.zero) await Future<void>.delayed(_otherAppWatchDelay);
    // Ended meanwhile (a press, a new wait, a video taking over).
    if (id != _otherAppWaitId || _otherAppWaitSince == null) return;
    _otherAudioSub = watcher.events.listen(_onOtherAudio, onError: (Object _) {});
    try {
      await watcher.start();
    } catch (e) {
      // No watcher on this phone: the music stays paused, as it always did.
      debugPrint('[MusicAudioHandler] other-app watcher failed: $e');
      if (id == _otherAppWaitId) _endOtherAppWait('unavailable');
    }
  }

  void _onOtherAudio(OtherAudioState s) {
    final since = _otherAppWaitSince;
    if (since == null) return;
    if (s.otherPlaying) {
      if (!_otherAppSeenPlaying) DiagnosticsService.instance.logEvent('other_app_playing');
      _otherAppSeenPlaying = true;
      return;
    }
    // Quiet, but the other app has not played yet: it is still starting.
    if (!_otherAppSeenPlaying) return;
    // A call: the music waits for it to end (the next report says so).
    if (s.inCall) return;
    if (_clock().difference(since) > otherAppResumeWindow) {
      _endOtherAppWait('expired');
      return;
    }
    if (!_resumeAfterOtherApps()) {
      _endOtherAppWait('setting_off');
      return;
    }
    if (_external != null || _player.playing || _playOrderQueue.isEmpty) {
      _endOtherAppWait('taken_over');
      return;
    }
    _endOtherAppWait('resumed');
    _otherAppResumedAt = _clock();
    play(caller: _otherAppResumeCaller);
  }

  /// Ends the wait for another app (if any); [reason] goes to the log.
  void _endOtherAppWait(String? reason) {
    if (_otherAppWaitSince == null) return;
    _otherAppWaitSince = null;
    _otherAppSeenPlaying = false;
    _otherAppWaitTimer?.cancel();
    _otherAppWaitTimer = null;
    _otherAudioSub?.cancel();
    _otherAudioSub = null;
    final watcher = _otherAudio;
    if (watcher != null) {
      Future<void>.sync(watcher.stop).catchError((Object _) {});
    }
    if (reason != null) DiagnosticsService.instance.logEvent('other_app_wait_end', {'reason': reason});
  }

  /// The reason the iOS interruption's own pause gives (it keeps the resume flag).
  static const _interruptionPauseReason = 'interruption';

  /// iOS sends every interruption start (a call, Siri, an alarm) as type
  /// `unknown`, and its end as `pause` when iOS says the app may resume
  /// (shouldResume), else as `unknown` (audio_session's mapping). So the
  /// start never tells a short interruption from a long one: what was
  /// playing is remembered at every start and resumed at an end that may
  /// resume. A play or pause by the user in between clears that.
  ///
  /// Local music (and the Online tab's background hand-off, which plays in
  /// this player) and a video on screen follow this rule. The Online tab's
  /// page is left to WebKit, which handles the page's own interruptions.
  void _onIosInterruption(AudioInterruptionEvent event) {
    final ext = _external;
    final extResumes = ext != null && _resumesAfterInterruption(_externalMedia);
    DiagnosticsService.instance.logEvent('audio_focus_change', {
      'begin': event.begin,
      'type': event.type.toString(),
      if (ext != null && !extResumes) 'ignored': 'external_source',
      if (extResumes) 'target': 'external',
    });

    if (event.type == AudioInterruptionType.duck) {
      // iOS lowers the volume itself and sends no duck; kept for completeness.
      if (ext != null) return;
      if (event.begin) {
        _volumeBeforeDuck = _player.volume;
        _player.setVolume((_volumeBeforeDuck * 0.5).clamp(0.0, 1.0));
      } else {
        _player.setVolume(_volumeBeforeDuck);
      }
      return;
    }

    if (event.begin) {
      if (ext != null) {
        _resumeOnFocusGain = false;
        if (!extResumes) return;
        final media = _externalMedia;
        final stoppedAt = _externalStoppedAt;
        final wasPlaying = (media?.playing ?? false) ||
            (stoppedAt != null && _clock().difference(stoppedAt) <= _interruptionPauseGrace);
        if (wasPlaying) {
          _interruptedExternal = ext;
          _safeDelegateCall(ext.externalPause);
        }
        return;
      }
      _interruptedExternal = null;
      // A second start (Siri during a call) keeps what the first one saw.
      _resumeOnFocusGain = _resumeOnFocusGain || _player.playing;
      _pauseLocalImpl(reason: _interruptionPauseReason);
      return;
    }

    // The end: `pause` when iOS says the app may resume.
    final mayResume = event.type == AudioInterruptionType.pause;
    final interruptedExt = _interruptedExternal;
    final resumeLocal = _resumeOnFocusGain;
    _interruptedExternal = null;
    _resumeOnFocusGain = false;
    if (!mayResume) return;
    if (interruptedExt != null) {
      if (identical(_external, interruptedExt) && !(_externalMedia?.playing ?? false)) {
        DiagnosticsService.instance.logEvent('play', {'caller': 'audio_focus_resume', 'target': 'external'});
        _safeDelegateCall(interruptedExt.externalPlay);
      }
      return;
    }
    if (resumeLocal && _external == null) play(caller: 'audio_focus_resume');
  }

  /// A video on screen is resumed after an interruption; the Online tab's
  /// page (ids `online:...`) is left to WebKit.
  static bool _resumesAfterInterruption(ExternalMediaSnapshot? media) =>
      media != null && !media.id.startsWith('online:');

  /// iOS: the user played or paused, so nothing resumes by itself when an
  /// interruption ends.
  void _clearInterruptionResume() {
    if (!PlatformInfo.isIOS) return;
    _resumeOnFocusGain = false;
    _interruptedExternal = null;
  }

  void _reportLearnedDuration(Duration? dur) {
    if (dur == null || dur <= Duration.zero) return;
    final idx = _player.currentIndex ?? -1;
    if (idx < 0 || idx >= _playOrderQueue.length) return;
    final item = _playOrderQueue[idx];
    if (item.durationMs > 0 || _durationReported.contains(item.id)) return;
    _durationReported.add(item.id);
    final updated = item.copyWith(durationMs: dur.inMilliseconds);
    _playOrderQueue[idx] = updated;
    final oi = _originalQueue.indexWhere((m) => m.id == item.id);
    if (oi >= 0) _originalQueue[oi] = updated;
    _syncCurrentAudioServiceMediaItem();
    final cb = onDurationKnown;
    if (cb != null) {
      cb(item.id, dur.inMilliseconds).catchError((_) {});
    }
  }

  /// The player could not play the song it is on: [error] comes from the
  /// player's error stream, or from a load or skip that failed. The work
  /// runs in the serialized chain, after whatever is running now, and is
  /// dropped when something moved the player in between (a load, a press,
  /// or an earlier report of the same failure).
  void handlePlaybackError(Object error, {String source = 'error_stream'}) {
    if (error is PlayerInterruptedException) return; // a newer load took over
    if (error is PlayerException && error.code == abortedErrorCode) return;
    DiagnosticsService.instance.logEvent('player_error', {
      'source': source,
      if (error is PlayerException) 'code': error.code,
    });
    if (error is PlayerException) {
      // A report about a song the player is no longer on (it arrived after
      // the handler moved on from it): that song was dealt with already.
      final failedAt = error.index;
      final at = _anchorIndex ?? _player.currentIndex;
      if (failedAt != null && at != null && failedAt != at) {
        DiagnosticsService.instance.logEvent('player_error_stale', {'queuePosition': failedAt});
        return;
      }
    }
    final epoch = _moveEpoch;
    _synchronized(() => _onTrackFailed(epoch), 'track_failed').catchError((Object e) {
      debugPrint('[MusicAudioHandler] failure handling failed: $e');
    });
  }

  /// One failure, dealt with once: while playing, one message for a run of
  /// failures, then the next playable song; when nothing in the queue
  /// plays, it stops (paused) instead of trying for ever. While paused (a
  /// restore at launch, a queue loaded without playing) only the failure is
  /// noted: pressing play tries the song again.
  Future<void> _onTrackFailed(int epoch) async {
    if (epoch != _moveEpoch) return; // moved on since, or already dealt with
    // A new queue or a press is on its way: it decides what plays.
    if (_pendingReplaces > 0 || _skipTarget != null) return;
    final q = _domainQueue;
    final idx = _player.currentIndex ?? -1;
    // The same failure reported once more (a load that failed reports it on
    // the error stream and by throwing, in either order) after it stopped
    // the queue: nothing moved since, so there is nothing new to do.
    if (_handledFailure == (epoch, idx)) return;
    _moveEpoch++;
    _handledFailure = (_moveEpoch, idx);
    final item = (idx >= 0 && idx < q.length) ? q[idx] : null;
    DiagnosticsService.instance.logEvent('track_failed', {
      'queuePosition': idx,
      'queueLength': q.length,
      'playing': _wantPlaying,
    });
    if (item != null && !_failureController.isClosed) _failureController.add(item.id);
    if (!_wantPlaying || _external != null) return;

    _consecutiveErrorSkips++;
    if (_consecutiveErrorSkips == 1) _emitError('Can\'t play "${item?.title ?? 'this song'}"');
    if (q.length > 1 && _consecutiveErrorSkips < q.length) {
      await _autoNext('error_skip');
      return;
    }
    // Every song in the queue failed (or it holds only this one).
    if (_consecutiveErrorSkips > 1) _emitError('Can\'t play any song in the queue');
    _consecutiveErrorSkips = 0;
    await _pauseLocalImpl(reason: 'error_loop_guard');
    _notifyDomainState();
  }

  // --- the media session ---------------------------------------------------------

  /// The notification's heart is offered for local songs when the app gave
  /// the callbacks for it.
  bool get _likeAvailable => onToggleFavorite != null && watchFavorite != null && _favoriteFor != null;

  void _broadcastAudioServiceState() {
    // While an external source owns the session, local player events (the
    // pause that handed over, buffering, ...) must not overwrite its state.
    if (_external != null) return;
    final playing = _player.playing;
    final pending = _skipTarget != null;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState] ?? AudioProcessingState.idle;

    // Custom shuffle action icon / label
    final isShuffled = _shuffleEnabled;
    final shuffleAction = MediaControl.custom(
      androidIcon: isShuffled
          ? 'drawable/ic_action_shuffle_on'
          : 'drawable/ic_action_shuffle_off',
      label: isShuffled ? 'Shuffle: On' : 'Shuffle: Off',
      name: actionToggleShuffle,
    );

    // Custom repeat action icon / label
    final String repeatIcon;
    final String repeatLabel;
    switch (_repeatMode) {
      case domain.PlaybackRepeatMode.off:
        repeatIcon = 'drawable/ic_action_repeat_off';
        repeatLabel = 'Repeat: Off';
        break;
      case domain.PlaybackRepeatMode.all:
        repeatIcon = 'drawable/ic_action_repeat_all';
        repeatLabel = 'Repeat: All';
        break;
      case domain.PlaybackRepeatMode.one:
        repeatIcon = 'drawable/ic_action_repeat_one';
        repeatLabel = 'Repeat: One';
        break;
    }
    final repeatAction = MediaControl.custom(
      androidIcon: repeatIcon,
      label: repeatLabel,
      name: actionCycleRepeat,
    );

    final currIdx = _virtualIndex;
    final canNext = canSkipNext;

    final next = playbackState.value.copyWith(
      // Transport first, so the compact (collapsed) notification shows
      // previous, play / pause and next. audio_service counts the compact
      // indices over the standard controls only (like, shuffle and repeat
      // are custom actions, drawn by Android 13+ in their own slots: the
      // first two of them), and with shuffle first the old [1, 2, 3] showed
      // play / pause, next and a slot past the end, never previous. Next is
      // left out of these controls where the app shows it disabled: the last
      // track with repeat off.
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        if (canNext) MediaControl.skipToNext,
        if (_likeAvailable)
          MediaControl.custom(
            androidIcon: _currentFavorite ? 'drawable/ic_action_favorite_on' : 'drawable/ic_action_favorite_off',
            label: _currentFavorite ? 'Remove from Favourites' : 'Add to Favourites',
            name: actionToggleFavorite,
          ),
        shuffleAction,
        repeatAction,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
        MediaAction.setSpeed,
        MediaAction.skipToPrevious,
        // Always advertised, even where the controls above leave Next out:
        // Android 13+ draws the shade and lock-screen controls from these
        // session actions and, with no ACTION_SKIP_TO_NEXT (audio_service
        // cannot reserve the slot), moves the first custom action into
        // Next's place, where a reach for Next would toggle something else.
        // At the end of the queue a Next from there is ignored
        // (skipToNext), like the app's disabled button.
        MediaAction.skipToNext,
        MediaAction.skipToQueueItem,
        MediaAction.playFromMediaId,
        MediaAction.prepareFromMediaId,
      },
      androidCompactActionIndices: canNext ? const [0, 1, 2] : const [0, 1],
      // Lock screen, Bluetooth (AVRCP), Wear OS and Android Auto read the
      // modes from the session itself.
      repeatMode: switch (_repeatMode) {
        domain.PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
        domain.PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
        domain.PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: _shuffleEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      processingState: processingState,
      playing: playing,
      // A skip on its way: the target starts at 0:00 (the old song's time
      // would show under the new title for a moment).
      updatePosition: pending ? Duration.zero : _player.position,
      bufferedPosition: pending ? Duration.zero : _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: currIdx >= 0 ? currIdx : null,
    );
    if (!_sameSessionState(playbackState.value, next)) {
      playbackState.add(next);
    }
    _onSessionPlaying(playing);
  }

  /// The same state apart from its time stamp: sending it again would only
  /// make the system redraw the notification.
  static bool _sameSessionState(PlaybackState a, PlaybackState b) =>
      a.processingState == b.processingState &&
      a.playing == b.playing &&
      listEquals(a.controls, b.controls) &&
      listEquals(a.controls.map((c) => c.customAction?.name).toList(),
          b.controls.map((c) => c.customAction?.name).toList()) &&
      listEquals(a.androidCompactActionIndices, b.androidCompactActionIndices) &&
      setEquals(a.systemActions, b.systemActions) &&
      a.updatePosition == b.updatePosition &&
      a.bufferedPosition == b.bufferedPosition &&
      a.speed == b.speed &&
      a.errorCode == b.errorCode &&
      a.errorMessage == b.errorMessage &&
      a.repeatMode == b.repeatMode &&
      a.shuffleMode == b.shuffleMode &&
      a.captioningEnabled == b.captioningEnabled &&
      a.queueIndex == b.queueIndex;

  List<domain.MediaItem>? _queueSnapshot;
  List<domain.MediaItem>? _originalSnapshot;

  /// An unmodifiable copy of [source], the previous one when nothing in it
  /// changed: the app's state keeps the same list, so screens that select
  /// the queue do not rebuild on every player event.
  static List<domain.MediaItem> _snapshot(List<domain.MediaItem> source, List<domain.MediaItem>? previous) {
    if (previous != null && previous.length == source.length) {
      var same = true;
      for (var i = 0; i < source.length; i++) {
        if (!identical(previous[i], source[i])) {
          same = false;
          break;
        }
      }
      if (same) return previous;
    }
    return List.unmodifiable(source);
  }

  domain.PlaybackState _buildDomainState() {
    final q = _virtualQueue;
    final idx = _virtualIndex;
    final currentItem = (idx >= 0 && idx < q.length) ? q[idx] : null;
    // While a skip is on its way (or loading) the player still reports the
    // old song's time and length.
    final settling = _skipTarget != null || _anchorIndex != null;
    return domain.PlaybackState(
      currentItemId: currentItem?.id,
      queue: _queueSnapshot = _snapshot(q, _queueSnapshot),
      originalQueue: _originalSnapshot = _snapshot(_originalQueue, _originalSnapshot),
      queueIndex: idx,
      position: settling ? Duration.zero : _player.position,
      duration: settling
          ? Duration(milliseconds: currentItem?.durationMs ?? 0)
          : (_player.duration ?? Duration.zero),
      isPlaying: _player.playing,
      repeatMode: _repeatMode,
      shuffle: _shuffleEnabled,
      speed: _player.speed,
      updatedAt: DateTime.now(),
    );
  }

  void _notifyDomainState() {
    if (_domainStateController.isClosed) return;
    _domainStateController.add(_buildDomainState());
  }

  domain.PlaybackState getCurrentDomainState() => _buildDomainState();

  MediaItem _sessionItem(domain.MediaItem item, Uri? artUri) => MediaItem(
        id: item.id,
        album: item.album ?? '',
        title: item.title,
        artist: item.artist,
        duration: Duration(milliseconds: item.durationMs),
        // Never the audio file URI itself: an image the system can open
        // (download thumbnail, online thumbnail, or the cached cover).
        artUri: artUri,
      );

  /// Sends [item] unless the notification already shows exactly that.
  void _emitMediaItem(MediaItem? item) {
    final last = mediaItem.value;
    if (item == null) {
      if (last != null) mediaItem.add(null);
      return;
    }
    if (last != null &&
        last.id == item.id &&
        last.title == item.title &&
        last.artist == item.artist &&
        last.album == item.album &&
        last.duration == item.duration &&
        last.artUri == item.artUri) {
      return;
    }
    mediaItem.add(item);
  }

  void _syncAudioServiceQueue() {
    final q = _virtualQueue;
    final idx = _virtualIndex;
    queue.add([for (final item in q) _sessionItem(item, _art.peek(item))]);
    // Only the current and the next song are looked up.
    if (idx >= 0 && idx < q.length) {
      _resolveArt(q[idx]);
      if (q.length > 1) _resolveArt(q[(idx + 1) % q.length]);
    }
  }

  void _syncCurrentAudioServiceMediaItem() {
    if (_external != null) return; // the external source's item stays on show
    final item = _virtualCurrentItem;
    _followFavorite(item);
    if (item == null) {
      _emitMediaItem(null);
      return;
    }
    _emitMediaItem(_sessionItem(item, _art.peek(item)));
    _resolveArt(item);
    final q = _virtualQueue;
    if (q.length > 1) _resolveArt(q[(_virtualIndex + 1) % q.length]);
  }

  /// Looks up [item]'s cover for the session and sends it once found, if the
  /// item is still on show (or next in line).
  void _resolveArt(domain.MediaItem item) {
    if (_art.peek(item) != null) return;
    _art.resolve(item).then((uri) {
      if (uri == null || _external != null) return;
      final q = _virtualQueue;
      final idx = _virtualIndex;
      if (idx < 0 || idx >= q.length) return;
      if (q[idx].id == item.id) _syncCurrentAudioServiceMediaItem();
      final isNext = q.length > 1 && q[(idx + 1) % q.length].id == item.id;
      if ((q[idx].id == item.id || isNext) && q.length <= 500) {
        queue.add([for (final m in q) _sessionItem(m, _art.peek(m))]);
      }
    });
  }

  // --- favourite ------------------------------------------------------------------

  void _followFavorite(domain.MediaItem? item) {
    final watch = watchFavorite;
    if (watch == null || onToggleFavorite == null) return;
    final id = (item == null || item.source == 'online') ? null : item.id;
    if (id == _favoriteFor) return;
    _favoriteSub?.cancel();
    _favoriteSub = null;
    _favoriteFor = id;
    _currentFavorite = item?.isFavorite ?? false;
    if (id == null) return;
    try {
      _favoriteSub = watch(id).listen((fav) {
        if (_favoriteFor != id || fav == _currentFavorite) return;
        _currentFavorite = fav;
        _broadcastAudioServiceState();
      }, onError: (Object _) {});
    } catch (_) {
      // no live flag: the heart keeps the queued snapshot
    }
  }

  // --- restore / load -------------------------------------------------------------

  /// Brings back the last session (paused). Does nothing when a queue is
  /// already loaded (media resumption got there first, or the user started
  /// something while the database was read), unless [replace] is set: then
  /// [restored] takes the place of whatever is loaded (the iOS Online
  /// hand-off giving the user's own queue back after its YouTube stream).
  Future<void> restoreSession(domain.PlaybackState restored, {bool replace = false}) {
    _pendingLoads++;
    if (replace) {
      _endOtherAppWait('new_queue');
      _skipGeneration++;
      _pendingReplaces++;
      _releaseLoadingWaiters();
    }
    return _synchronized(() {
      _pendingLoads--;
      if (replace) _pendingReplaces--;
      return _restoreSessionImpl(restored, replace: replace);
    }, 'restoreSession');
  }

  Future<void> _restoreSessionImpl(domain.PlaybackState restored, {bool replace = false}) async {
    if (!replace && _playOrderQueue.isNotEmpty) return;
    _dropPendingSkip();
    if (replace) {
      _wantPlaying = false;
      if (_player.playing) await _player.pause();
    }
    _consecutiveErrorSkips = 0;
    _originalQueue = List.from(restored.originalQueue.isNotEmpty ? restored.originalQueue : restored.queue);
    _playOrderQueue = List.from(restored.queue);
    _shuffleEnabled = restored.shuffle;
    _repeatMode = restored.repeatMode;
    await _player.setSpeed(restored.speed);

    if (_domainQueue.isNotEmpty) {
      final initialIdx = (restored.queueIndex >= 0 && restored.queueIndex < _domainQueue.length)
          ? restored.queueIndex
          : 0;
      _anchor(initialIdx);
      _syncAudioServiceQueue();
      try {
        await _loadSource(index: initialIdx, position: restored.position);
        _applyLoopMode();
      } catch (e) {
        DiagnosticsService.instance.logEvent('player_error', {'source': 'restore_session'});
        debugPrint('Failed to set source on restore: $e');
      } finally {
        _anchorIndex = null;
      }
    } else {
      _syncAudioServiceQueue();
    }
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  /// Restores the last session when nothing is loaded (media resumption: the
  /// system's player calls play / prepare after the app was closed).
  Future<void> _ensureRestored() async {
    if (_playOrderQueue.isNotEmpty || _external != null) return;
    final load = loadLastSession;
    if (load == null) return;
    domain.PlaybackState? saved;
    try {
      saved = await load();
    } catch (_) {
      return;
    }
    if (saved == null || saved.queue.isEmpty) return;
    await restoreSession(saved);
  }

  Future<void> loadQueue(
    List<domain.MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) {
    _userInteractedSinceNoisy = true;
    _endOtherAppWait('new_queue');
    // Presses made before this load meant the old queue: drop them now, so
    // none of them seeks the old source first.
    _skipGeneration++;
    // Starting local music hands the session back from YouTube (which pauses).
    if (autoPlay && items.isNotEmpty) {
      _localChosen();
      _releaseExternal(reason: 'local_queue');
    }
    _pendingLoads++;
    // A skip or seek waiting on a slow load stands down now (it meant the old
    // queue), so the new one starts at once.
    _pendingReplaces++;
    _releaseLoadingWaiters();
    return _synchronized(() {
      _pendingLoads--;
      _pendingReplaces--;
      return _loadQueueImpl(items, startIndex: startIndex, autoPlay: autoPlay, shuffle: shuffle);
    }, 'loadQueue');
  }

  Future<void> _loadQueueImpl(
    List<domain.MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) async {
    _dropPendingSkip();
    if (items.isEmpty) {
      await _stopLocalImpl(reason: 'empty_queue_load');
      _originalQueue = [];
      _playOrderQueue = [];
      _shuffleEnabled = false;
      _syncAudioServiceQueue();
      if (_external == null) _emitMediaItem(null);
      _broadcastAudioServiceState();
      _notifyDomainState();
      return;
    }
    if (autoPlay) _releaseExternal(reason: 'local_queue');

    _originalQueue = List.from(items);
    _shuffleEnabled = shuffle;
    final safeStart = (startIndex >= 0 && startIndex < items.length) ? startIndex : 0;

    if (shuffle) {
      // Start at startIndex as first item, shuffle the rest
      final startItem = items[safeStart];
      final remaining = List<domain.MediaItem>.from(items)..removeAt(safeStart);
      _fisherYatesShuffle(remaining);
      _playOrderQueue = [startItem, ...remaining];
    } else {
      _playOrderQueue = List.from(items);
    }
    final initialIndex = shuffle ? 0 : safeStart;

    _consecutiveErrorSkips = 0; // a new queue: a new run of failures
    _anchor(initialIndex);
    _syncAudioServiceQueue();
    _syncCurrentAudioServiceMediaItem();
    Object? loadError;
    try {
      await _loadSource(index: initialIndex);
      _applyLoopMode();
    } catch (e) {
      // A newer load stopping this one is not the song's fault.
      if (e is! PlayerInterruptedException) loadError = e;
      debugPrint('Error setting queue source: $e');
    } finally {
      _anchorIndex = null;
    }

    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();

    if (autoPlay) {
      _wantPlaying = true;
      // A song that failed to load is not started again here: the failure
      // moves on to the next playable song.
      if (loadError == null) _safeStartPlayerPlay('load_queue');
      _broadcastAudioServiceState();
    }
    if (loadError != null) {
      _applyLoopMode();
      // Usually on the error stream too: the same failure reported twice is
      // dealt with once.
      handlePlaybackError(loadError, source: 'load_queue');
    }
  }

  String _formatCaller() {
    return 'in_app';
  }

  // --- external source -----------------------------------------------------

  @override
  void setExternalSource(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    final previous = _external;
    if (previous != null && !identical(previous, delegate)) {
      _safeDelegateCall(previous.onExternalSourceReleased);
    }
    if (!identical(previous, delegate)) {
      _externalStoppedAt = null;
      _interruptedExternal = null;
    }
    // A video or the Online tab took over: the music no longer waits for
    // another app.
    _endOtherAppWait('taken_over');
    _external = delegate;
    _lastExternal = delegate;
    _setExternalHeld(true);
    if (previous == null) {
      DiagnosticsService.instance.logEvent('external_source_start');
      // Local music pauses (it stays queued and resumes from its own controls).
      _wantPlaying = false;
      _resumeOnFocusGain = false;
      _stopSleepFade(restoreVolume: true);
      if (_player.playing) {
        _player.pause().catchError((Object e) {
          debugPrint('[MusicAudioHandler] pause for external source failed: $e');
        });
      }
      _notifyDomainState();
    }
    _externalItem = null; // force the notification item out once for the new source
    _applyExternal(snapshot, force: true);
  }

  @override
  void updateExternalMedia(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    if (!identical(_external, delegate)) return;
    _applyExternal(snapshot);
  }

  @override
  void clearExternalSource(ExternalPlaybackDelegate delegate) {
    if (!identical(_external, delegate)) return;
    _leaveExternal();
  }

  /// Local playback is starting: YouTube pauses and the session returns to local music.
  void _releaseExternal({required String reason}) {
    final d = _external;
    if (d == null) return;
    DiagnosticsService.instance.logEvent('external_source_released', {'reason': reason});
    _leaveExternal();
    _safeDelegateCall(d.externalPause);
    _safeDelegateCall(d.onExternalSourceReleased);
  }

  void _leaveExternal() {
    if (_external == null) return;
    _external = null;
    _externalMedia = null;
    _externalItem = null;
    _externalStoppedAt = null;
    _interruptedExternal = null;
    _externalController.add(null);
    DiagnosticsService.instance.logEvent('external_source_end');
    // Back to the local queue (paused), or to nothing (idle: the service stops).
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
  }

  void _safeDelegateCall(Object? Function() call) {
    try {
      final r = call();
      if (r is Future) {
        r.catchError((Object e) {
          debugPrint('[MusicAudioHandler] external source call failed: $e');
        });
      }
    } catch (e) {
      debugPrint('[MusicAudioHandler] external source call failed: $e');
    }
  }

  void _applyExternal(ExternalMediaSnapshot s, {bool force = false}) {
    _saveResume(s);
    final previous = _externalMedia;
    _externalMedia = s;
    if (previous != null && previous.id == s.id && previous.playing && !s.playing) _externalStoppedAt = _clock();
    // Started again during an interruption (by the user): not ours to resume.
    if (s.playing && previous != null && !previous.playing) _interruptedExternal = null;

    final item = MediaItem(
      id: s.id,
      title: s.title.isEmpty ? s.albumOrDefault : s.title,
      artist: (s.artist == null || s.artist!.isEmpty) ? null : s.artist,
      album: s.albumOrDefault,
      duration: s.duration,
      artUri: s.artUri,
    );
    // The notification reloads metadata (and its artwork) on every item, so
    // only send it when something visible changed, not on every tick.
    final last = _externalItem;
    if (force ||
        last == null ||
        last.id != item.id ||
        last.title != item.title ||
        last.artist != item.artist ||
        last.album != item.album ||
        last.artUri != item.artUri ||
        last.duration != item.duration) {
      _externalItem = item;
      mediaItem.add(item);
    }

    if (force || previous == null || _externalStateChanged(previous, s)) {
      final controls = [
        MediaControl.skipToPrevious,
        if (s.playing) MediaControl.pause else MediaControl.play,
        if (s.canSkipNext) MediaControl.skipToNext,
      ];
      playbackState.add(PlaybackState(
        controls: controls,
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToPrevious,
          if (s.canSkipNext) MediaAction.skipToNext,
        },
        // Same compact layout as local music: previous, play/pause, next.
        androidCompactActionIndices: List<int>.generate(controls.length, (i) => i),
        processingState: s.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
        playing: s.playing,
        updatePosition: s.position,
        bufferedPosition: s.position,
        speed: s.speed,
        repeatMode: AudioServiceRepeatMode.none,
        shuffleMode: AudioServiceShuffleMode.none,
      ));
    }
    _externalController.add(s);
    _onSessionPlaying(s.playing);
    // "End of song" for a video: the page moved on to another one.
    if (_sleepEndOfTrack && previous != null && previous.id != s.id && s.playing) {
      _onNaturalTrackEnd();
    }
  }

  /// True when the system's own extrapolation (position + speed x elapsed)
  /// would show something wrong: play state, controls, speed, length, or a jump.
  static bool _externalStateChanged(ExternalMediaSnapshot a, ExternalMediaSnapshot b) {
    if (a.playing != b.playing ||
        a.buffering != b.buffering ||
        a.canSkipNext != b.canSkipNext ||
        a.speed != b.speed ||
        a.duration != b.duration ||
        a.id != b.id) {
      return true;
    }
    // Ticks arrive about once a second; anything else is a seek.
    final drift = (b.position - a.position).inMilliseconds.abs();
    return drift > 2500 || (!b.playing && drift > 0);
  }

  // No audio focus is asked for the Online tab's page: Android's WebView
  // holds it itself (Chromium's AudioFocusDelegate, in the app's process).
  // Asking for it here as well took it from the WebView, which then paused
  // the video on every Play (seen on the emulator: onAudioFocusChange(-1)
  // to AudioFocusDelegate every few seconds after a swipe-away).

  /// Swiped away from recents: nothing stops. The service is a started
  /// foreground service (stopWithTask="false"), the engine and the Online
  /// page live on in it, and the notification keeps working.
  @override
  Future<void> onTaskRemoved() async {
    DiagnosticsService.instance.logEvent('task_removed', {
      'target': _external != null ? 'external' : 'local',
      'playing': playbackState.value.playing,
    });
  }

  // --- paused-idle stop (ONL-8) ----------------------------------------------------

  /// The foreground service stays up while paused (androidStopForegroundOnPause
  /// is false). Only when [pausedIdleTimeout] is set (it is off by default)
  /// does a long pause end the session, local or external.
  void _onSessionPlaying(bool playing) {
    if (playing) {
      _sessionPlaying = true;
      _idleStopTimer?.cancel();
      _idleStopTimer = null;
    } else if (_sessionPlaying) {
      _sessionPlaying = false;
      _idleStopTimer?.cancel();
      _idleStopTimer = null;
      final idle = pausedIdleTimeout;
      if (idle == null) return;
      _idleStopTimer = Timer(idle, () {
        _idleStopTimer = null;
        DiagnosticsService.instance.logEvent('paused_idle_stop', {'minutes': idle.inMinutes});
        stop(reason: 'paused_idle').catchError((Object e) {
          debugPrint('[MusicAudioHandler] idle stop failed: $e');
        });
      });
    }
  }

  /// True while the session waits out [pausedIdleTimeout].
  @visibleForTesting
  bool get idleStopArmed => _idleStopTimer != null;

  // --- sleep timer (F9) --------------------------------------------------------------

  /// The sleep timer right now.
  domain.SleepTimerStatus get sleepTimer {
    final endsAt = _sleepEndsAt;
    if (endsAt == null && !_sleepEndOfTrack && _fadeTimer == null) return domain.SleepTimerStatus.off;
    Duration? remaining;
    if (endsAt != null) {
      final left = endsAt.difference(_clock());
      remaining = left.isNegative ? Duration.zero : left;
    }
    return domain.SleepTimerStatus(
      endsAt: endsAt,
      remaining: remaining,
      endOfTrack: _sleepEndOfTrack,
      fading: _fadeTimer != null,
    );
  }

  /// Emits whenever the sleep timer is set, changes or ends.
  Stream<domain.SleepTimerStatus> get sleepTimerStream => _sleepController.stream;

  void _emitSleep() {
    if (!_sleepController.isClosed) _sleepController.add(sleepTimer);
  }

  /// Pauses everything (local music or the YouTube page) after [duration],
  /// fading the music out over its last [sleepFade].
  void setSleepTimer(Duration duration) {
    _clearSleep(restoreVolume: true);
    if (duration <= Duration.zero) {
      _emitSleep();
      return;
    }
    _sleepEndsAt = _clock().add(duration);
    final fadeStartsIn = duration > sleepFade ? duration - sleepFade : Duration.zero;
    _sleepTimer = Timer(fadeStartsIn, _startSleepFade);
    DiagnosticsService.instance.logEvent('sleep_timer_set', {'minutes': duration.inMinutes});
    _emitSleep();
  }

  /// Pauses when the song that is playing ends.
  void setSleepTimerAtEndOfTrack() {
    _clearSleep(restoreVolume: true);
    _sleepEndOfTrack = true;
    DiagnosticsService.instance.logEvent('sleep_timer_set', {'mode': 'end_of_track'});
    _emitSleep();
  }

  void cancelSleepTimer() {
    final wasActive = sleepTimer.isActive;
    _clearSleep(restoreVolume: true);
    if (wasActive) DiagnosticsService.instance.logEvent('sleep_timer_cancelled');
    _emitSleep();
  }

  void _clearSleep({required bool restoreVolume}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
    _sleepEndOfTrack = false;
    _stopSleepFade(restoreVolume: restoreVolume);
  }

  void _stopSleepFade({required bool restoreVolume}) {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final volume = _volumeBeforeFade;
    _volumeBeforeFade = null;
    if (restoreVolume && volume != null) {
      _player.setVolume(volume).catchError((Object _) {});
    }
  }

  void _startSleepFade() {
    _sleepTimer = null;
    if (_external != null || !_player.playing) {
      // YouTube (its own volume) or nothing playing: pause when the time is up.
      final endsAt = _sleepEndsAt;
      final left = endsAt == null ? Duration.zero : endsAt.difference(_clock());
      if (left > Duration.zero) {
        _sleepTimer = Timer(left, _finishSleep);
      } else {
        _finishSleep();
      }
      return;
    }
    final start = _player.volume;
    _volumeBeforeFade = start;
    var step = 0;
    _fadeTimer = Timer.periodic(sleepFade ~/ _sleepFadeSteps, (timer) {
      step++;
      if (step >= _sleepFadeSteps) {
        timer.cancel();
        _finishSleep();
        return;
      }
      _player.setVolume(start * (1 - step / _sleepFadeSteps)).catchError((Object _) {});
    });
    _emitSleep();
  }

  void _finishSleep() {
    final volume = _volumeBeforeFade;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _volumeBeforeFade = null;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
    _sleepEndOfTrack = false;
    DiagnosticsService.instance.logEvent('sleep_timer_fired');
    _emitSleep();
    pause(reason: 'sleep').whenComplete(() {
      if (volume != null) _player.setVolume(volume).catchError((Object _) {});
    }).catchError((Object _) {});
  }

  /// A song ended by itself. With "end of song" set, playback pauses here.
  void _onNaturalTrackEnd() {
    if (!_sleepEndOfTrack) return;
    _sleepEndOfTrack = false;
    DiagnosticsService.instance.logEvent('sleep_timer_fired', {'mode': 'end_of_track'});
    _emitSleep();
    if (_external != null) {
      pause(reason: 'sleep');
      return;
    }
    _wantPlaying = false;
    // The next song waits at its start.
    _pauseLocalImpl(reason: 'sleep').then((_) => _player.seek(Duration.zero)).catchError((Object _) {});
  }

  // --- transport: system entry points route to the external source -------

  /// In-app "play" for the local queue (Music, Now Playing, local mini player).
  Future<void> playLocal() {
    _localChosen();
    _releaseExternal(reason: 'local_play');
    return _playLocalImpl(caller: 'in_app');
  }

  /// In-app "pause" for the local queue.
  Future<void> pauseLocal() => _pauseLocalImpl();

  /// Gives up on a song that is still loading (a stream that never
  /// answers): the player stops loading, so it cannot start later on its
  /// own. Local music stays paused and the media session is left alone.
  Future<void> cancelLoading() async {
    if (_player.processingState != ProcessingState.loading) return;
    DiagnosticsService.instance.logEvent('loading_cancelled');
    _wantPlaying = false;
    _moveEpoch++;
    await _player.stop();
  }

  /// In-app seek in the local track.
  Future<void> seekLocal(Duration position) => _seekLocalImpl(position);

  /// In-app "next" for the local queue (starts local playback).
  Future<void> skipToNextLocal() {
    _localChosen();
    _releaseExternal(reason: 'local_next');
    return _requestNext();
  }

  /// In-app "previous" for the local queue (starts local playback).
  Future<void> skipToPreviousLocal() {
    _localChosen();
    _releaseExternal(reason: 'local_previous');
    return _requestPrevious();
  }

  /// A headset, Bluetooth or notification media button. Next and previous
  /// act at once (and do what the app's own buttons do: Next is ignored on
  /// the last track with repeat off). The play / pause button counts presses
  /// within [mediaButtonMultiClickWindow]: one toggles, two skip to the next
  /// track, three to the previous one.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    DiagnosticsService.instance.logEvent('media_button', {'button': button.name});
    switch (button) {
      case MediaButton.next:
        return skipToNext();
      case MediaButton.previous:
        return skipToPrevious();
      case MediaButton.media:
        if (mediaButtonMultiClickWindow <= Duration.zero) return _togglePlayPauseFromButton();
        _mediaButtonTimer?.cancel();
        _mediaButtonClicks++;
        if (_mediaButtonClicks >= 3) return _flushMediaButtonClicks();
        _mediaButtonTimer = Timer(mediaButtonMultiClickWindow, () {
          _flushMediaButtonClicks();
        });
    }
  }

  Future<void> _flushMediaButtonClicks() {
    _mediaButtonTimer?.cancel();
    _mediaButtonTimer = null;
    final clicks = _mediaButtonClicks;
    _mediaButtonClicks = 0;
    if (clicks >= 3) return skipToPrevious();
    if (clicks == 2) return skipToNext();
    return _togglePlayPauseFromButton();
  }

  Future<void> _togglePlayPauseFromButton() =>
      playbackState.value.playing ? pause(reason: 'media_button') : play(caller: 'media_button');

  @override
  Future<void> play({String? caller}) async {
    final ext = _external;
    if (ext != null) {
      DiagnosticsService.instance.logEvent('play', {'caller': caller ?? 'system', 'target': 'external'});
      _clearInterruptionResume();
      return ext.externalPlay();
    }
    if (_externalHeld) {
      // The controls belong to YouTube, which went quiet: ask it to play
      // again (if its page is still there), never start local music instead.
      DiagnosticsService.instance.logEvent('play', {'caller': caller ?? 'system', 'target': 'external_held'});
      final last = _lastExternal;
      if (last != null) _safeDelegateCall(last.externalPlay);
      return;
    }
    // Media resumption: the system's player after the app was closed.
    if (_playOrderQueue.isEmpty) await _ensureRestored();
    return _playLocalImpl(caller: caller);
  }

  @override
  Future<void> prepare() => _ensureRestored();

  @override
  Future<void> prepareFromMediaId(String mediaId, [Map<String, dynamic>? extras]) => _ensureRestored();

  /// Android Auto / MediaBrowser clients browse the library through this
  /// (set in main.dart); null: only the "recent" root is answered.
  AutoBrowseTree? browse;

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    // A song picked in a browsed list (Android Auto): that list plays from it.
    final picked = AutoBrowseTree.split(mediaId);
    final tree = browse;
    if (picked != null && tree != null) {
      final songs = await tree.songsOf(picked.$1);
      final index = songs?.indexWhere((s) => s.id == picked.$2) ?? -1;
      if (songs != null && index >= 0) {
        DiagnosticsService.instance.logEvent('play', {'caller': 'browse', 'list': picked.$1.split(':').first});
        return loadQueue(songs, startIndex: index, autoPlay: true, shuffle: _shuffleEnabled);
      }
    }
    if (_external == null) await _ensureRestored();
    final q = _virtualQueue;
    final index = q.indexWhere((m) => m.id == mediaId);
    if (index >= 0 && index != _virtualIndex) {
      return skipToQueueItem(index, expectedId: mediaId);
    }
    return play(caller: 'play_from_media_id');
  }

  /// The quick-settings player asks for the "recent" root after the app was
  /// closed: the current (or last saved) song, with its cover.
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId != AudioService.recentRootId) {
      final tree = browse;
      if (tree == null) return const [];
      try {
        return await tree.children(
          parentMediaId,
          (song, browseId) => _sessionItem(song, _art.peek(song)).copyWith(id: browseId),
        );
      } catch (e) {
        DiagnosticsService.instance.logEvent('browse_failed', {'type': e.runtimeType.toString()});
        return const [];
      }
    }
    // The last thing played was YouTube: no local song to offer.
    if (_externalHeld) return const [];
    domain.MediaItem? item = _virtualCurrentItem;
    if (item == null && loadLastSession != null) {
      try {
        item = (await loadLastSession!())?.currentItem;
      } catch (_) {
        item = null;
      }
    }
    if (item == null) return const [];
    Uri? art;
    try {
      art = await _art.resolve(item).timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {
      art = null;
    }
    return [_sessionItem(item, art)];
  }

  Future<void> _playLocalImpl({String? caller}) async {
    _userInteractedSinceNoisy = true;
    _handledFailure = null; // a failure from here on is a new one
    _clearInterruptionResume();
    if (caller != _otherAppResumeCaller && caller != 'audio_focus_resume') {
      // A play of the user's own: the next app taking the sound starts a
      // fresh wait, and a short interruption under way no longer resumes.
      _otherAppResumedAt = null;
      if (!PlatformInfo.isIOS) _resumeOnFocusGain = false;
    }
    _endOtherAppWait('play');
    _wantPlaying = true;
    if (_fadeTimer != null) cancelSleepTimer(); // pressing play during the fade keeps the music
    final callSource = caller ?? _formatCaller();
    DiagnosticsService.instance.logEvent('play', {'caller': callSource});
    debugPrint('[MusicAudioHandler] play() called by: $callSource');

    // If completed or at end with repeat off, reset to track start
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }

    _safeStartPlayerPlay(callSource);
    _broadcastAudioServiceState();
  }

  @override
  Future<void> pause({String? reason}) {
    final ext = _external;
    if (ext != null) {
      DiagnosticsService.instance.logEvent('pause', {'reason': reason ?? 'user', 'target': 'external'});
      _clearInterruptionResume();
      return ext.externalPause();
    }
    return _pauseLocalImpl(reason: reason);
  }

  Future<void> _pauseLocalImpl({String? reason}) async {
    if (reason != _interruptionPauseReason) _clearInterruptionResume();
    // Android: a pause of any other kind (the user, the sleep timer, unplugged
    // headphones) during a short interruption keeps the music paused when
    // that interruption ends.
    if (!PlatformInfo.isIOS && reason != _transientLossPauseReason) _resumeOnFocusGain = false;
    if (reason != _permanentLossPauseReason) _endOtherAppWait('pause');
    _wantPlaying = false;
    if (reason != 'sleep' && _fadeTimer != null) cancelSleepTimer();
    final stopReason = reason ?? 'user';
    DiagnosticsService.instance.logEvent('pause', {'reason': stopReason});
    debugPrint('[MusicAudioHandler] pause(reason: $stopReason)');
    await _player.pause();
    _broadcastAudioServiceState();
  }

  @override
  Future<void> stop({String? reason}) async {
    final ext = _external;
    if (ext != null) {
      // Stop from the notification: YouTube pauses and the session ends.
      DiagnosticsService.instance.logEvent('stop', {'reason': reason ?? 'user', 'target': 'external'});
      _leaveExternal();
      _safeDelegateCall(ext.externalPause);
      _safeDelegateCall(ext.onExternalSourceReleased);
    }
    await _stopLocalImpl(reason: reason);
  }

  Future<void> _stopLocalImpl({String? reason}) async {
    _wantPlaying = false;
    _endOtherAppWait('stop');
    _moveEpoch++; // a failure reported before the stop is over with it
    _idleStopTimer?.cancel();
    _idleStopTimer = null;
    _sessionPlaying = false;
    // The session is over: a sleep timer left running would keep its chip
    // counting and later fade a stopped player.
    if (sleepTimer.isActive) {
      _clearSleep(restoreVolume: true);
      _emitSleep();
    }
    final stopReason = reason ?? 'user';
    DiagnosticsService.instance.logEvent('stop', {'reason': stopReason});
    debugPrint('[MusicAudioHandler] stop(reason: $stopReason)');
    await _player.stop();
    await super.stop();
    _broadcastAudioServiceState();
  }

  @override
  Future<void> seek(Duration position) {
    final ext = _external;
    if (ext != null) return ext.externalSeek(position);
    return _seekLocalImpl(position);
  }

  /// A seek in the song on show: after any pending skip (it is that song's
  /// time), and never while the player loads (it would be dropped).
  Future<void> _seekLocalImpl(Duration position) {
    _userInteractedSinceNoisy = true;
    DiagnosticsService.instance.logEvent('seek');
    debugPrint('[MusicAudioHandler] seek($position) called by: ${_formatCaller()}');
    return _synchronized(() async {
      await _applyPendingSkip();
      await _waitWhileLoading();
      _noteOwnSeek(position);
      await _player.seek(position);
      _noteOwnSeek(position);
      _broadcastAudioServiceState();
    }, 'seek');
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  void _applyLoopMode() {
    switch (_repeatMode) {
      case domain.PlaybackRepeatMode.off:
        _player.setLoopMode(LoopMode.off);
        break;
      case domain.PlaybackRepeatMode.all:
        _player.setLoopMode(LoopMode.all);
        break;
      case domain.PlaybackRepeatMode.one:
        _player.setLoopMode(LoopMode.one);
        break;
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        _repeatMode = domain.PlaybackRepeatMode.off;
        break;
      case AudioServiceRepeatMode.one:
        _repeatMode = domain.PlaybackRepeatMode.one;
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        _repeatMode = domain.PlaybackRepeatMode.all;
        break;
    }
    _applyLoopMode();
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  void cycleRepeatMode() {
    _userInteractedSinceNoisy = true;
    switch (_repeatMode) {
      case domain.PlaybackRepeatMode.off:
        _repeatMode = domain.PlaybackRepeatMode.all;
        break;
      case domain.PlaybackRepeatMode.all:
        _repeatMode = domain.PlaybackRepeatMode.one;
        break;
      case domain.PlaybackRepeatMode.one:
        _repeatMode = domain.PlaybackRepeatMode.off;
        break;
    }
    _applyLoopMode();
    DiagnosticsService.instance.logEvent('repeat_mode_changed', {'mode': _repeatMode.name});
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = (shuffleMode == AudioServiceShuffleMode.all || shuffleMode == AudioServiceShuffleMode.group);
    if (enable != _shuffleEnabled) {
      await toggleShuffle();
    }
  }

  void _fisherYatesShuffle<T>(List<T> list, [int startIndex = 0]) {
    final random = math.Random();
    for (int i = list.length - 1; i > startIndex; i--) {
      final j = startIndex + random.nextInt(i - startIndex + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  Future<void> toggleShuffle() async {
    _userInteractedSinceNoisy = true;
    return _synchronized(() async {
      await _applyPendingSkip();
      final nextVal = !_shuffleEnabled;
      _shuffleEnabled = nextVal;
      final currentPos = _player.position;
      final currIdx = _player.currentIndex ?? 0;
      domain.MediaItem? currentItem;
      if (currIdx >= 0 && currIdx < _playOrderQueue.length) {
        currentItem = _playOrderQueue[currIdx];
      }

      if (_shuffleEnabled) {
        // Shuffle ON: current track stays first, the rest is Fisher-Yates shuffled
        if (currentItem != null) {
          final remaining = List<domain.MediaItem>.from(_originalQueue);
          _removeFirstById(remaining, currentItem.id);
          _fisherYatesShuffle(remaining);
          _playOrderQueue = [currentItem, ...remaining];
        } else {
          _playOrderQueue = List.from(_originalQueue);
          _fisherYatesShuffle(_playOrderQueue);
        }
      } else {
        // Shuffle OFF: restore original order, keep current track playing
        _playOrderQueue = List.from(_originalQueue);
      }

      int newIndex = 0;
      if (currentItem != null) {
        newIndex = _playOrderQueue.indexWhere((item) => item.id == currentItem!.id);
        if (newIndex == -1) newIndex = 0;
      }

      _anchor(newIndex);
      try {
        final src = _playlistSource;
        if (src != null && currentItem != null && src.length == _playOrderQueue.length) {
          // Seamless: the playing track keeps playing, only its neighbours change.
          await _reorderAroundCurrent(src, currIdx, newIndex);
          // The player moves its own index along; this only fires if it did not.
          if ((_player.currentIndex ?? -1) != newIndex) {
            await _waitWhileLoading();
            await _player.seek(currentPos, index: newIndex);
          }
        } else {
          await _loadSource(index: newIndex, position: currentPos);
        }
      } finally {
        _anchorIndex = null;
      }

      DiagnosticsService.instance.logEvent('shuffle_mode_changed', {
        'enabled': _shuffleEnabled,
        'trackId': currentItem?.id,
        'queuePosition': newIndex,
      });

      _syncAudioServiceQueue();
      _syncCurrentAudioServiceMediaItem();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'toggleShuffle');
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (_external != null) return; // shuffle / repeat / like are not shown for YouTube
    if (name == actionToggleShuffle) {
      toggleShuffle();
    } else if (name == actionCycleRepeat) {
      cycleRepeatMode();
    } else if (name == actionToggleFavorite) {
      final id = _favoriteFor;
      final toggle = onToggleFavorite;
      if (id == null || toggle == null) return;
      // Shown at once; the live flag confirms it.
      _currentFavorite = !_currentFavorite;
      _broadcastAudioServiceState();
      DiagnosticsService.instance.logEvent('favorite_from_notification', {'id': id});
      try {
        await toggle(id);
      } catch (_) {
        _currentFavorite = !_currentFavorite;
        _broadcastAudioServiceState();
      }
    }
  }

  // --- next / previous / queue item: coalesced presses ---------------------------

  @override
  Future<void> skipToNext() {
    final ext = _external;
    if (ext != null) return ext.externalSkipToNext();
    if (_externalHeld) return _heldSkip(next: true);
    return _requestNext();
  }

  @override
  Future<void> skipToPrevious() {
    final ext = _external;
    if (ext != null) return ext.externalSkipToPrevious();
    if (_externalHeld) return _heldSkip(next: false);
    return _requestPrevious();
  }

  /// Next / previous from the phone's controls while they still belong to a
  /// source that went quiet: that source's, never a local track change.
  Future<void> _heldSkip({required bool next}) async {
    DiagnosticsService.instance.logEvent(next ? 'skip_next' : 'skip_previous', {'target': 'external_held'});
    final last = _lastExternal;
    if (last == null) return;
    _safeDelegateCall(next ? last.externalSkipToNext : last.externalSkipToPrevious);
  }

  /// A track picked from the queue (the app's queue sheet, or a car / watch
  /// queue view) plays, like a tapped song row. Local music takes the session
  /// back from YouTube first, as every other local start does. With
  /// [expectedId] (the queue sheet passes it) a row that moved since it was
  /// drawn is found by its id; one that is gone is ignored.
  @override
  Future<void> skipToQueueItem(int index, {String? expectedId}) {
    _userInteractedSinceNoisy = true;
    _localChosen(); // a song picked from the queue is a local choice
    if (_pendingLoads > 0) return _afterPendingLoad(() => skipToQueueItem(index, expectedId: expectedId));
    final q = _virtualQueue;
    var target = index;
    if (expectedId != null && (target < 0 || target >= q.length || q[target].id != expectedId)) {
      target = _nearestIndexOf(q, expectedId, index);
      if (target < 0) {
        DiagnosticsService.instance.logEvent('skip_ignored', {'action': 'skipToQueueItem', 'reason': 'id_gone'});
        return Future.value();
      }
    }
    if (target < 0 || target >= q.length) return Future.value();
    _releaseExternal(reason: 'local_queue_item');
    return _requestSkip(target, action: 'skipToQueueItem');
  }

  /// The occurrence of [id] in [list] closest to [hint], or -1.
  static int _nearestIndexOf(List<domain.MediaItem> list, String id, int hint) {
    var best = -1;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id != id) continue;
      if (best < 0 || (i - hint).abs() < (best - hint).abs()) best = i;
    }
    return best;
  }

  /// Next, from where the pending presses are heading. The neighbours come
  /// from the handler's own play order, not from the player's `hasNext` /
  /// `seekToNext`: with repeat one the player loops the current item, so
  /// those only restarted the same track.
  Future<void> _requestNext() {
    _userInteractedSinceNoisy = true;
    if (_pendingLoads > 0) return _afterPendingLoad(_requestNext);
    final q = _virtualQueue;
    if (q.isEmpty) return _batch?.future ?? Future.value();
    final from = _virtualIndex;
    final last = q.length - 1;
    if (from >= 0 && from < last) {
      return _requestSkip(from + 1, action: 'skipToNext');
    }
    if (_repeatMode == domain.PlaybackRepeatMode.off) {
      // Disabled: the last track with repeat off has no next. Nothing
      // changes, not even the play intent: a paused track stays paused.
      DiagnosticsService.instance.logEvent('skip_ignored', {'action': 'skipToNext', 'reason': 'queue_end'});
      return _batch?.future ?? Future.value();
    }
    if (_shuffleEnabled && _originalQueue.length > 1) {
      // Reshuffle at wrap: the new round does not start with the track that just played.
      final lastPlayed = (from >= 0 && from < q.length) ? q[from] : null;
      return _requestSkip(0, order: _reshuffled(avoidFirst: lastPlayed), action: 'skipToNext');
    }
    return _requestSkip(0, action: 'skipToNext');
  }

  List<domain.MediaItem> _reshuffled({domain.MediaItem? avoidFirst}) {
    final reshuffled = List<domain.MediaItem>.from(_originalQueue);
    _fisherYatesShuffle(reshuffled);
    if (avoidFirst != null && reshuffled.length > 1 && reshuffled.first.id == avoidFirst.id) {
      final temp = reshuffled[0];
      reshuffled[0] = reshuffled[1];
      reshuffled[1] = temp;
    }
    return reshuffled;
  }

  /// Previous: past the first seconds it restarts the track (DESIGN.md 7.17),
  /// judged by the position at the first press of a run of presses; the
  /// presses after it go back one track each.
  Future<void> _requestPrevious() {
    _userInteractedSinceNoisy = true;
    if (_pendingLoads > 0) return _afterPendingLoad(_requestPrevious);
    final q = _virtualQueue;
    if (q.isEmpty) return _batch?.future ?? Future.value();
    final from = _virtualIndex;
    final settling = _skipTarget != null || _anchorIndex != null;
    final position = settling ? Duration.zero : _player.position;
    final last = q.length - 1;
    final int target;
    if (position > restartThreshold && from >= 0 && from <= last) {
      target = from; // restart
    } else if (from > 0 && from <= last) {
      target = from - 1;
    } else if (_repeatMode != domain.PlaybackRepeatMode.off && last > 0) {
      // At the start of the queue with repeat on: round to the last item.
      target = last;
    } else {
      // At the start with repeat off: the first track starts again.
      target = (from >= 0 && from <= last) ? from : 0;
    }
    return _requestSkip(target, action: 'skipToPrevious');
  }

  /// Records a press heading for [target] (in [_virtualQueue], or in [order]
  /// when given) and shows it at once; the serialized action seeks once to
  /// the newest target. Skipping starts playing (Spotify).
  Future<void> _requestSkip(int target, {List<domain.MediaItem>? order, required String action}) {
    _wantPlaying = true;
    _endOtherAppWait('skip');
    final firstPress = _skipTarget == null;
    if (firstPress) {
      DiagnosticsService.instance.logEvent('skip_start', {
        'action': action,
        'caller': _formatCaller(),
        'beforeTrackId': _virtualCurrentItem?.id,
        'beforeQueuePosition': _virtualIndex,
      });
    }
    if (order != null) _pendingOrder = order;
    _skipTarget = target;
    _batchPresses++;
    final batch = _batch ??= Completer<void>();
    final generation = ++_skipGeneration;

    // The target shows everywhere right away.
    if (order != null) _syncAudioServiceQueue();
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();

    _synchronized(() async {
      if (generation != _skipGeneration) return; // a newer press or a queue edit took over
      await _applyPendingSkip();
    }, action).catchError((Object e) {
      debugPrint('[MusicAudioHandler] $action failed: $e');
    });
    return batch.future;
  }

  /// Drops presses that meant a queue which is being replaced.
  void _dropPendingSkip() {
    _skipGeneration++;
    _skipTarget = null;
    _pendingOrder = null;
    _batchPresses = 0;
    final batch = _batch;
    _batch = null;
    if (batch != null && !batch.isCompleted) batch.complete();
  }

  /// Applies the pending presses: one seek (or, past the end with shuffle, one
  /// reload in the new order), then play if wanted. Runs inside the chain.
  Future<void> _applyPendingSkip() async {
    final target = _skipTarget;
    if (target == null) return;
    final order = _pendingOrder;
    final batch = _batch;
    final presses = _batchPresses;
    _skipTarget = null;
    _pendingOrder = null;
    _batch = null;
    _batchPresses = 0;
    _anchor(target);
    _consecutiveErrorSkips = 0; // the user moved on: a new run of failures
    // A newer press or a queue load from here on takes over: this one stops
    // waiting and leaves the seek (and the play) to it.
    final generation = _skipGeneration;
    Object? failure;
    try {
      if (order != null) {
        _playOrderQueue = order;
        _syncAudioServiceQueue(); // F7: the session queue follows the new order
        // The new order must reach the player even when a newer press came
        // in (its target is in that order); only a queue load replaces it.
        await _waitWhileLoading();
        if (!_superseded()) await _loadSource(index: target);
      } else if (target == (_player.currentIndex ?? -1)) {
        // Previous within the first seconds of a track, or presses that
        // came back to where they started: the track restarts.
        await _waitWhileLoading(generation);
        if (!_superseded(generation)) {
          _noteOwnSeek(Duration.zero);
          await _player.seek(Duration.zero);
          _noteOwnSeek(Duration.zero);
        }
      } else {
        await _seekToIndex(target, generation);
      }
    } catch (e) {
      failure = e;
      debugPrint('Error while skipping: $e');
    } finally {
      _anchorIndex = null;
    }

    final afterIdx = _player.currentIndex ?? -1;
    DiagnosticsService.instance.logEvent('skip_complete', {
      'afterTrackId': (afterIdx >= 0 && afterIdx < _domainQueue.length) ? _domainQueue[afterIdx].id : null,
      'afterQueuePosition': afterIdx,
      'presses': presses,
    });

    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();

    if (failure != null) {
      // Dealt with like any failed song (once, even when the error stream
      // reported it too): the message, then the next playable song.
      handlePlaybackError(failure, source: 'skip');
    } else if (_skipTarget == null && _wantPlaying && !_superseded()) {
      // Only once the presses have settled (a newer one plays when it lands).
      _safeStartPlayerPlay('skip');
    }
    if (batch != null && !batch.isCompleted) batch.complete();
  }

  /// Next without a press (a song that could not play): the queue stops
  /// paused at its start after the last track with repeat off. A press
  /// waiting in the meantime wins. Runs inside the chain.
  Future<void> _autoNext(String reason) async {
    if (_skipTarget != null) {
      await _applyPendingSkip();
      return;
    }
    final q = _playOrderQueue;
    if (q.isEmpty) return;
    final idx = _player.currentIndex ?? -1;
    final last = q.length - 1;
    Object? failure;
    try {
      if (idx >= 0 && idx < last) {
        _wantPlaying = true;
        _anchor(idx + 1);
        await _seekToIndex(idx + 1);
      } else if (_repeatMode != domain.PlaybackRepeatMode.off) {
        _wantPlaying = true;
        _anchor(0);
        if (_shuffleEnabled && _originalQueue.length > 1) {
          _playOrderQueue = _reshuffled(avoidFirst: (idx >= 0 && idx <= last) ? q[idx] : null);
          _syncAudioServiceQueue();
          await _loadSource(index: 0);
        } else {
          await _seekToIndex(0);
        }
      } else {
        // Repeat off -> stop at last track and show paused state at start of queue
        _wantPlaying = false;
        _consecutiveErrorSkips = 0;
        DiagnosticsService.instance.logEvent('queue_ended', {'action': 'paused_at_start', 'reason': reason});
        _lastRequestedIndex = 0;
        await _player.pause();
        await _waitWhileLoading();
        await _player.seek(Duration.zero, index: 0);
      }
    } catch (e) {
      failure = e;
      debugPrint('Error in $reason: $e');
    } finally {
      _anchorIndex = null;
    }
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();
    if (failure != null) {
      handlePlaybackError(failure, source: reason); // the song it moved to failed too
    } else if (_wantPlaying) {
      _safeStartPlayerPlay(reason);
    }
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_skipTarget != null) {
      // The user already moved on.
      await _applyPendingSkip();
      return;
    }
    final sleepNow = _sleepEndOfTrack;
    if (sleepNow) _onNaturalTrackEnd();
    final idx = _player.currentIndex ?? -1;
    if (_repeatMode == domain.PlaybackRepeatMode.one && !sleepNow) {
      await _waitWhileLoading();
      await _player.seek(Duration.zero);
      _wantPlaying = true;
      _safeStartPlayerPlay('repeat_one_completed');
    } else if (idx >= 0 && idx < _domainQueue.length - 1) {
      _anchor(idx + 1);
      try {
        await _seekToIndex(idx + 1);
      } finally {
        _anchorIndex = null;
      }
      if (!sleepNow) {
        _wantPlaying = true;
        _safeStartPlayerPlay('completed_next');
      }
      _syncCurrentAudioServiceMediaItem();
      _broadcastAudioServiceState();
      _notifyDomainState();
    } else if (_repeatMode == domain.PlaybackRepeatMode.all && !sleepNow) {
      _lastRequestedIndex = 0;
      await _seekToIndex(0);
      _wantPlaying = true;
      _safeStartPlayerPlay('repeat_all_restart');
      _syncCurrentAudioServiceMediaItem();
      _broadcastAudioServiceState();
      _notifyDomainState();
    } else {
      // Repeat off -> show paused state at start of queue, not silent stop
      _wantPlaying = false;
      DiagnosticsService.instance.logEvent('queue_ended', {'action': 'completed_paused_at_start'});
      _lastRequestedIndex = 0;
      await _player.pause();
      await _waitWhileLoading();
      await _player.seek(Duration.zero, index: 0);
      _syncCurrentAudioServiceMediaItem();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }
  }

  // --- queue edits ------------------------------------------------------------------
  // Each runs in the chain and first applies a pending skip: the indexes the
  // UI hands in refer to the queue it showed, which includes those presses.

  Future<void> playNext(domain.MediaItem item) => playNextAll([item]);

  /// [items] play right after the current song, in this order.
  Future<void> playNextAll(List<domain.MediaItem> items) {
    _userInteractedSinceNoisy = true;
    if (items.isEmpty) return Future.value();
    return _synchronized(() async {
      await _applyPendingSkip();
      if (_domainQueue.isEmpty) {
        await _loadQueueImpl(items);
        return;
      }
      final currIdx = _player.currentIndex ?? 0;
      final insertIndex = currIdx + 1;
      _playOrderQueue.insertAll(insertIndex, items);
      // Keep the original (un-shuffled) order in step, duplicates included.
      final currentItem = currIdx < _playOrderQueue.length ? _playOrderQueue[currIdx] : null;
      final origIdx = currentItem == null ? -1 : _originalQueue.indexWhere((m) => m.id == currentItem.id);
      if (origIdx >= 0) {
        _originalQueue.insertAll(origIdx + 1, items);
      } else {
        _originalQueue.addAll(items);
      }
      if (_playlistSource != null) {
        await _playlistSource!.insertAll(insertIndex, items.map(_sourceFor).toList());
      } else {
        await _loadSource(index: currIdx, position: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'playNext');
  }

  Future<void> addToQueue(domain.MediaItem item) => addAllToQueue([item]);

  /// [items] go to the end of the queue.
  Future<void> addAllToQueue(List<domain.MediaItem> items) {
    _userInteractedSinceNoisy = true;
    if (items.isEmpty) return Future.value();
    return _synchronized(() async {
      await _applyPendingSkip();
      if (_domainQueue.isEmpty) {
        await _loadQueueImpl(items);
        return;
      }
      final currIdx = _player.currentIndex ?? 0;
      _playOrderQueue.addAll(items);
      _originalQueue.addAll(items);
      if (_playlistSource != null) {
        await _playlistSource!.addAll(items.map(_sourceFor).toList());
      } else {
        await _loadSource(index: currIdx, position: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'addToQueue');
  }

  @override
  Future<void> removeQueueItemAt(int index, {String? expectedId}) {
    _userInteractedSinceNoisy = true;
    if (expectedId == null && (index < 0 || index >= _virtualQueue.length)) return Future.value();

    return _synchronized(() async {
      await _applyPendingSkip();
      var at = index;
      if (expectedId != null && (at < 0 || at >= _domainQueue.length || _domainQueue[at].id != expectedId)) {
        at = _nearestIndexOf(_domainQueue, expectedId, index);
      }
      if (at < 0 || at >= _domainQueue.length) return;
      await _removeAtImpl(at);
    }, 'removeQueueItemAt');
  }

  /// Takes every copy of [mediaId] out of the queue (a deleted file). When it
  /// is the current song, the next one takes its place. No-op when absent.
  Future<void> removeFromQueueById(String mediaId) {
    return _synchronized(() async {
      await _applyPendingSkip();
      for (var i = _domainQueue.length - 1; i >= 0; i--) {
        if (_domainQueue[i].id == mediaId) await _removeAtImpl(i);
      }
    }, 'removeFromQueueById');
  }

  Future<void> _removeAtImpl(int index) async {
    final currIdx = _player.currentIndex ?? 0;
    final isRemovingCurrent = (index == currIdx);
    final removedItem = _playOrderQueue.removeAt(index);
    if (!_shuffleEnabled && index < _originalQueue.length && _originalQueue[index].id == removedItem.id) {
      _originalQueue.removeAt(index); // both lists are index-aligned when not shuffled
    } else {
      _removeFirstById(_originalQueue, removedItem.id);
    }

    if (_domainQueue.isEmpty) {
      await _player.stop();
      _playlistSource = null;
      if (_external == null) _emitMediaItem(null);
    } else {
      int newIdx = currIdx;
      if (index < currIdx) {
        newIdx = currIdx - 1;
      } else if (isRemovingCurrent && newIdx >= _domainQueue.length) {
        newIdx = _domainQueue.length - 1;
      }
      _anchor(newIdx);
      try {
        if (_playlistSource != null && _playlistSource!.length > index) {
          await _playlistSource!.removeAt(index);
          if (isRemovingCurrent) {
            // When removing current item, reload next track from Duration.zero
            await _waitWhileLoading();
            await _player.seek(Duration.zero);
          }
        } else {
          await _loadSource(
            index: newIdx,
            position: isRemovingCurrent ? Duration.zero : _player.position,
          );
        }
      } finally {
        _anchorIndex = null;
      }
    }

    _syncAudioServiceQueue();
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex, {String? expectedId}) {
    _userInteractedSinceNoisy = true;
    final length = _virtualQueue.length;
    if (expectedId == null && (oldIndex < 0 || oldIndex >= length || newIndex < 0 || newIndex >= length)) {
      return Future.value();
    }

    return _synchronized(() async {
      await _applyPendingSkip();
      var from = oldIndex;
      if (expectedId != null && (from < 0 || from >= _domainQueue.length || _domainQueue[from].id != expectedId)) {
        from = _nearestIndexOf(_domainQueue, expectedId, oldIndex);
      }
      if (from < 0 || from >= _domainQueue.length || newIndex < 0 || newIndex >= _domainQueue.length) return;
      final item = _playOrderQueue.removeAt(from);
      _playOrderQueue.insert(newIndex, item);

      if (!_shuffleEnabled) {
        final origItem = _originalQueue.removeAt(from);
        _originalQueue.insert(newIndex, origItem);
      }

      final currIdx = _player.currentIndex ?? 0;
      int updatedIdx = currIdx;
      if (currIdx == from) {
        updatedIdx = newIndex;
      } else if (currIdx > from && currIdx <= newIndex) {
        updatedIdx = currIdx - 1;
      } else if (currIdx < from && currIdx >= newIndex) {
        updatedIdx = currIdx + 1;
      }
      _anchor(updatedIdx);
      try {
        if (_playlistSource != null && _playlistSource!.length > from) {
          await _playlistSource!.move(from, newIndex);
        } else {
          await _loadSource(index: updatedIdx, position: _player.position);
        }
      } finally {
        _anchorIndex = null;
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'reorderQueue');
  }

  Future<void> dispose() async {
    DiagnosticsService.instance.logEvent('service_stop');
    _external = null;
    _endOtherAppWait(null);
    _mediaButtonTimer?.cancel();
    _idleStopTimer?.cancel();
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();
    _favoriteSub?.cancel();
    _releaseLoadingWaiters();
    final batch = _batch;
    if (batch != null && !batch.isCompleted) batch.complete();
    await _player.dispose();
    await _errorController.close();
    await _failureController.close();
    await _domainStateController.close();
    await _externalController.close();
    await _sleepController.close();
  }
}
