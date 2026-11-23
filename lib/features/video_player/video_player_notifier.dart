import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../data/repositories/video_engine_impl.dart';
import '../../data/repositories/video_progress_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/video_progress.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/video_engine.dart';
import '../../domain/repositories/video_progress_repository.dart';
import '../music_player/music_audio_handler.dart';
import '../music_player/playback_notifier.dart';
import 'video_queue.dart';

final videoProgressRepositoryProvider = Provider<VideoProgressRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return VideoProgressRepositoryImpl(db);
});

final videoEngineProvider = Provider.autoDispose<VideoEngine>((ref) {
  final engine = OfficialVideoEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});

final allVideoProgressStreamProvider = StreamProvider<List<VideoProgress>>((ref) {
  final repo = ref.watch(videoProgressRepositoryProvider);
  return repo.watchAllProgress();
});

/// Where a video's notification, lock-screen and headset controls go: the
/// music handler's external-source slot. Null when there is no handler
/// (tests); the video then simply has no media session.
final videoMediaHostProvider = Provider<ExternalPlaybackHost?>((ref) {
  // The phone's media session exists on the phones only (audio_service).
  if (!PlatformInfo.isAndroid && !PlatformInfo.isIOS) return null;
  try {
    return ref.watch(audioHandlerProvider);
  } catch (_) {
    return null;
  }
});

/// Hands a video over to the music player ("audio only"): loads [item] as
/// a queue of one, seeks to [position] and plays. Throws when the music
/// player is not available.
typedef AudioHandoff = Future<void> Function(MediaItem item, Duration position);

final videoAudioHandoffProvider = Provider<AudioHandoff>((ref) {
  return (item, position) async {
    final playback = ref.read(playbackNotifierProvider.notifier);
    await playback.loadQueue([item], autoPlay: false, shuffle: playback.shuffleMode);
    if (position > Duration.zero) await playback.seek(position);
    await playback.play();
  };
});

/// Why a video could not be played, so the screen can show a short plain
/// message instead of the raw player exception.
enum VideoErrorKind {
  /// The phone's decoder (MediaCodec / renderer) could not handle the video:
  /// a busy hardware decoder, memory pressure or an unsupported format.
  decoder,

  /// The file could not be opened: moved, deleted or no permission.
  source,

  /// iOS: AVFoundation cannot read this kind of file at all (an .mkv, .webm
  /// or .avi, say). Trying again never helps, and the file is still there.
  unsupportedFormat,

  /// Anything else.
  other;

  /// The plain message shown under "Unable to play video".
  String get message => switch (this) {
        VideoErrorKind.decoder =>
          "This phone couldn't decode this video. Trying again often helps.",
        VideoErrorKind.source =>
          "The video file couldn't be opened. It may have been moved or deleted.",
        VideoErrorKind.unsupportedFormat => "This iPhone can't play this video format.",
        VideoErrorKind.other => 'Something went wrong while starting this video.',
      };
}

// iOS (video_player_avfoundation): "Failed to load video: Cannot Open: This
// media format is not supported." (AVErrorFileFormatNotRecognized, -11828) or
// "... Cannot Open: This media may be damaged." (AVErrorFailedToParse,
// -11829); the codes appear when an underlying error is printed.
final RegExp _iosUnsupportedFormat = RegExp(
  r'format is not supported|media may be damaged|failed to load video: cannot open|-1182[89](?!\d)',
  caseSensitive: false,
);

// "format" but not "information"; "decod" covers decode / decoder / decoding.
final RegExp _decoderError = RegExp(
  r'mediacodec|renderer|decod|codec|(?<!in)format',
  caseSensitive: false,
);

// "\bfile" so "FileNotFoundException" and "/x/file.mp4" count but "profile" does not.
final RegExp _sourceError = RegExp(
  r'not ?found|no such file|enoent|missing|permission|denied|not permitted|'
  r"eacces|securityexception|source error|datasource|cannot open|can't open|"
  r"could not open|couldn't open|unable to open|\bfile",
  caseSensitive: false,
);

/// Sorts a raw player error ([VideoPlaybackState.errorMessage]) into a
/// [VideoErrorKind]. Decoder words are checked first: a decoder failure may
/// also mention the source or the file, so it would otherwise be mistaken
/// for a missing file. On iOS, AVFoundation's "this format cannot be read"
/// wording comes before both (it says "format" and "Cannot Open").
/// [isIOS] defaults to the platform the app runs on.
VideoErrorKind classifyVideoError(String raw, {bool? isIOS}) {
  if ((isIOS ?? PlatformInfo.isIOS) && _iosUnsupportedFormat.hasMatch(raw)) {
    return VideoErrorKind.unsupportedFormat;
  }
  if (_decoderError.hasMatch(raw)) return VideoErrorKind.decoder;
  if (_sourceError.hasMatch(raw)) return VideoErrorKind.source;
  return VideoErrorKind.other;
}

/// How the player turns with the phone.
enum OrientationMode {
  /// Follows the phone (portrait or either landscape), and so the phone's
  /// own rotation lock.
  auto,

  /// Either landscape side only.
  landscape,

  /// Upright portrait only.
  portrait;

  OrientationMode get next => switch (this) {
        OrientationMode.auto => OrientationMode.landscape,
        OrientationMode.landscape => OrientationMode.portrait,
        OrientationMode.portrait => OrientationMode.auto,
      };

  /// The toast after a change.
  String get label => switch (this) {
        OrientationMode.auto => 'Auto-rotate',
        OrientationMode.landscape => 'Landscape locked',
        OrientationMode.portrait => 'Portrait locked',
      };

  List<DeviceOrientation> get orientations => switch (this) {
        OrientationMode.auto => const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        OrientationMode.landscape => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        OrientationMode.portrait => const [DeviceOrientation.portraitUp],
      };
}

/// How the picture fills the screen.
enum VideoFit {
  /// The whole picture, with bars.
  fit,

  /// Fills the screen, cropping the edges.
  fill,

  /// Fills the screen, ignoring the aspect ratio.
  stretch,

  /// One video pixel per screen pixel.
  original;

  VideoFit get next => VideoFit.values[(index + 1) % VideoFit.values.length];

  String get label => switch (this) {
        VideoFit.fit => 'Fit to screen',
        VideoFit.fill => 'Fill screen',
        VideoFit.stretch => 'Stretch',
        VideoFit.original => 'Original size',
      };

  BoxFit get boxFit => switch (this) {
        VideoFit.fit => BoxFit.contain,
        VideoFit.fill => BoxFit.cover,
        VideoFit.stretch => BoxFit.fill,
        VideoFit.original => BoxFit.none,
      };
}

/// The subtitle file next to a downloaded video (`name.srt` or `name.vtt`
/// for `name.mp4`), or null. Only local files have neighbours: phone media
/// (content://) and streams have none.
String? sidecarSubtitlePath(String uri, {bool Function(String path)? exists}) {
  final String path;
  if (uri.startsWith('file://')) {
    path = Uri.parse(uri).toFilePath();
  } else if (!uri.contains('://') && uri.isNotEmpty) {
    path = uri;
  } else {
    return null;
  }
  final check = exists ?? (p) => File(p).existsSync();
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  final base = dot > slash ? path.substring(0, dot) : path;
  for (final ext in const ['.srt', '.vtt', '.SRT', '.VTT']) {
    final candidate = '$base$ext';
    try {
      if (check(candidate)) return candidate;
    } catch (_) {}
  }
  return null;
}

const Object _keep = Object();

class VideoPlaybackState {
  final MediaItem item;
  final bool isInitialized;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;
  final VideoFit fit;
  final bool isLocked;
  final bool showControls;
  final OrientationMode orientationMode;
  final String? errorMessage;

  /// Playback reached the end (cleared by a play or a seek).
  final bool isCompleted;

  /// Where [item] is in the queue, and how long the queue is.
  final int queueIndex;
  final int queueLength;

  /// Seconds left before the next video starts by itself; null when no
  /// countdown runs.
  final int? upNextSeconds;

  /// A sidecar .srt / .vtt was found and loaded.
  final bool subtitlesAvailable;
  final bool subtitlesOn;

  /// The subtitle line for now ('' when none).
  final String caption;

  /// The video has more than one audio track.
  final bool hasAudioTracks;

  /// Volume boost in percent of full volume (100 = off).
  final int boostPercent;

  /// The phone accepts the boost (Android with LoudnessEnhancer).
  final bool boostSupported;

  const VideoPlaybackState({
    required this.item,
    this.isInitialized = false,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.fit = VideoFit.fit,
    this.isLocked = false,
    this.showControls = true,
    this.orientationMode = OrientationMode.auto,
    this.errorMessage,
    this.isCompleted = false,
    this.queueIndex = 0,
    this.queueLength = 1,
    this.upNextSeconds,
    this.subtitlesAvailable = false,
    this.subtitlesOn = true,
    this.caption = '',
    this.hasAudioTracks = false,
    this.boostPercent = 100,
    this.boostSupported = false,
  });

  bool get hasNext => queueIndex < queueLength - 1;
  bool get hasPrevious => queueIndex > 0;

  /// The picture is locked to landscape.
  bool get isLandscape => orientationMode == OrientationMode.landscape;

  /// Copies with changes. [errorMessage] is cleared unless given (a new
  /// state means the player is working again).
  VideoPlaybackState copyWith({
    MediaItem? item,
    bool? isInitialized,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? speed,
    VideoFit? fit,
    bool? isLocked,
    bool? showControls,
    OrientationMode? orientationMode,
    String? errorMessage,
    bool? isCompleted,
    int? queueIndex,
    int? queueLength,
    Object? upNextSeconds = _keep,
    bool? subtitlesAvailable,
    bool? subtitlesOn,
    String? caption,
    bool? hasAudioTracks,
    int? boostPercent,
    bool? boostSupported,
  }) {
    return VideoPlaybackState(
      item: item ?? this.item,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      fit: fit ?? this.fit,
      isLocked: isLocked ?? this.isLocked,
      showControls: showControls ?? this.showControls,
      orientationMode: orientationMode ?? this.orientationMode,
      errorMessage: errorMessage,
      isCompleted: isCompleted ?? this.isCompleted,
      queueIndex: queueIndex ?? this.queueIndex,
      queueLength: queueLength ?? this.queueLength,
      upNextSeconds: identical(upNextSeconds, _keep) ? this.upNextSeconds : upNextSeconds as int?,
      subtitlesAvailable: subtitlesAvailable ?? this.subtitlesAvailable,
      subtitlesOn: subtitlesOn ?? this.subtitlesOn,
      caption: caption ?? this.caption,
      hasAudioTracks: hasAudioTracks ?? this.hasAudioTracks,
      boostPercent: boostPercent ?? this.boostPercent,
      boostSupported: boostSupported ?? this.boostSupported,
    );
  }
}

class VideoPlayerControllerNotifier extends Notifier<VideoPlaybackState> {
  final MediaItem item;

  /// How long the controls stay after the last touch.
  static const Duration hideControlsAfter = Duration(seconds: 3);

  /// The "Up next" countdown at the end of a video.
  static const int upNextCountdownSeconds = 5;

  /// A seek while paused is saved after this pause (so scrubbing writes once).
  static const Duration pausedSeekSaveDelay = Duration(milliseconds: 600);

  /// Taps of a double-tap burst within this window add up.
  static const Duration skipBurstWindow = Duration(milliseconds: 900);

  Timer? _hideControlsTimer;
  Timer? _persistenceTimer;
  Timer? _seekSaveTimer;
  Timer? _upNextTimer;

  /// The viewer tapped Cancel on Up next for this video: a later "ended"
  /// signal (the player reporting the end again, a stand-in engine stopping
  /// at the end) must not start the countdown again. Cleared by Replay, a
  /// seek away from the end and the next video.
  bool _upNextDismissed = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String?>? _errSub;
  StreamSubscription<void>? _completedSub;
  StreamSubscription<String>? _captionSub;
  DateTime _lastSavedAt = DateTime.now();
  bool _retrying = false;
  bool _switching = false;
  int _holds = 0;

  /// The viewer picked an orientation: later videos in the queue keep it
  /// (otherwise each video starts by its own shape).
  bool _orientationChosen = false;

  /// The last position saved for each item, so the same position is not
  /// written twice (Back, then the provider's own dispose).
  final Map<String, int> _savedPositions = {};

  /// Where the last skip asked to go, while a double-tap burst runs: the
  /// next skip adds to it even before the player has caught up.
  Duration? _skipTarget;
  DateTime? _skipAt;

  VideoQueue _queue;
  VideoProgressRepository? _repo;
  _VideoMediaSession? _session;

  /// Set when a failed attempt flagged the item missing in the library, so a
  /// later attempt that plays (Try again) can put it back.
  bool _markedMissing = false;

  /// When each item last had its quiet second try after a decoder error.
  final Map<String, DateTime> _autoRetriedAt = {};

  /// A decoder error is retried once by itself per item within this window:
  /// a busy or glitching hardware decoder (seen on the emulator right after
  /// switching videos) usually works the second time, so the error screen
  /// only shows when that fails too, or for a second failure soon after.
  static const Duration autoRetryWindow = Duration(seconds: 30);

  /// What the viewer last asked for: play, or a pause (also backgrounding and
  /// the end of the video). A quiet retry starts playback again only when they
  /// wanted it; the player's own "stopped" report is no guide, because a
  /// failing decoder sends one just before its error.
  bool _viewerWantsPlay = true;

  /// Back or "Audio only" is closing the screen: no quiet retry then.
  bool _closing = false;

  VideoPlayerControllerNotifier(this.item) : _queue = VideoQueue.single(item);

  VideoEngine get _engine => ref.read(videoEngineProvider);
  VideoProgressRepository get _progressRepo {
    final cached = _repo;
    if (cached != null) return cached;
    final repo = ref.read(videoProgressRepositoryProvider);
    _repo = repo;
    return repo;
  }

  LibraryRepository get _libraryRepo => ref.read(libraryRepositoryProvider);

  /// The queue being played (a queue of one unless the Videos tab gave one).
  VideoQueue get queue => _queue;

  bool get hasNextVideo => _queue.hasNext;
  bool get hasPreviousVideo => _queue.hasPrevious;

  /// The platform player's id, for the volume boost; null when unknown.
  int? get _platformPlayerId {
    final engine = _engine;
    return engine is VideoEngineExtras ? (engine as VideoEngineExtras).platformPlayerId : null;
  }

  @override
  VideoPlaybackState build() {
    _repo = ref.read(videoProgressRepositoryProvider);
    try {
      final host = ref.read(videoMediaHostProvider);
      if (host != null) _session = _VideoMediaSession(this, host);
    } catch (_) {}

    ref.onDispose(() {
      // The last word on progress, whoever closes the player (Back, a route
      // replaced, the app shutting down): uses only what is cached here.
      _saveLast();
      _cancelPlaybackListeners();
      _seekSaveTimer?.cancel();
      _upNextTimer?.cancel();
      _session?.clear();
      DeviceControls.releaseVideoBoost();
      restoreSystemUi();
    });

    state = VideoPlaybackState(item: item, boostSupported: DeviceControls.boostAvailable);
    _initPlayer();

    return state;
  }

  /// Gives the phone back its normal orientation and bars: the app's own
  /// default (no lock), never a forced portrait. Also called from the
  /// screen's pop, so the list underneath is not laid out in landscape first.
  static void restoreSystemUi() {
    try {
      WakelockPlus.disable().ignore();
    } catch (_) {}
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
      SystemChrome.setPreferredOrientations(const []).ignore();
    } catch (_) {}
  }

  /// Uses the queue the screen was opened with ([queue.current] must be
  /// this player's item).
  ///
  /// Safe to call from a widget's initState: the state only takes the queue
  /// when the player starts (or, if it already plays, right after the
  /// current build), as providers must not change while widgets build.
  void attachQueue(VideoQueue queue) {
    if (queue.isEmpty || queue.current.id != state.item.id) return;
    _queue = queue;
    if (!state.isInitialized) return;
    scheduleMicrotask(() {
      if (!ref.mounted) return;
      state = state.copyWith(
        queueIndex: _queue.index,
        queueLength: _queue.items.length,
        errorMessage: state.errorMessage,
      );
      _session?.update(state);
    });
  }

  /// Stops listening to the current engine and stops the timers.
  void _cancelPlaybackListeners() {
    _hideControlsTimer?.cancel();
    _persistenceTimer?.cancel();
    _posSub?.cancel();
    _playingSub?.cancel();
    _errSub?.cancel();
    _completedSub?.cancel();
    _captionSub?.cancel();
    _hideControlsTimer = null;
    _persistenceTimer = null;
    _posSub = null;
    _playingSub = null;
    _errSub = null;
    _completedSub = null;
    _captionSub = null;
  }

  /// [resumeAt] (set by [retry]) is used instead of the saved progress.
  Future<void> _initPlayer({Duration resumeAt = Duration.zero}) async {
    // 1. Explicitly pause music audio handler & request audio focus
    try {
      debugPrint('[VideoPlayer] Starting video, paused music playback');
      await ref.read(audioHandlerProvider).pause();
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      // No music player (tests, a failed start): nothing to pause.
      debugPrint('[VideoPlayer] Could not pause music playback (${e.runtimeType})');
    }
    if (!ref.mounted) return;

    // Enter immersive mode
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).ignore();
    } catch (_) {}
    // Library items know their size; downloaded ones do not (handled after init).
    final width = state.item.width ?? 0;
    final height = state.item.height ?? 0;
    if (state.orientationMode == OrientationMode.auto && width > 0 && height > 0 && width > height) {
      // A wide video starts in landscape, as in other players.
      setOrientationMode(OrientationMode.landscape);
    } else {
      _applyOrientation(state.orientationMode);
    }

    try {
      await _engine.initialize(state.item.uri);
      if (!ref.mounted) return;

      // Learned from the real video size (works for downloaded files too).
      final size = _engine.videoSize;
      if (state.orientationMode == OrientationMode.auto &&
          size.width > 0 &&
          size.height > 0 &&
          size.width > size.height) {
        setOrientationMode(OrientationMode.landscape);
      }

      // Downloaded files are stored with an unknown duration: remember it.
      final learned = _engine.duration;
      if (state.item.durationMs == 0 && learned > Duration.zero) {
        final repo = _libraryRepo;
        if (repo is LibraryRepositoryImpl) {
          repo.updateDurationIfUnknown(state.item.id, learned.inMilliseconds).ignore();
        }
      }

      int targetMs = 0;
      if (resumeAt > Duration.zero) {
        // Retrying after a failure: carry on where the failed attempt was.
        targetMs = VideoProgress.calculateResumePosition(
          savedPositionMs: resumeAt.inMilliseconds,
          totalDurationMs: _engine.duration.inMilliseconds,
        );
      } else {
        // Check saved progress
        final savedProgress = await _progressRepo.getProgress(state.item.id);
        if (!ref.mounted) return;
        if (savedProgress != null) {
          targetMs = VideoProgress.calculateResumePosition(
            savedPositionMs: savedProgress.positionMs,
            totalDurationMs: savedProgress.durationMs > 0
                ? savedProgress.durationMs
                : _engine.duration.inMilliseconds,
          );
        }
      }

      if (targetMs > 0) {
        await _engine.seekTo(Duration(milliseconds: targetMs));
      }
      // A retry keeps the speed the viewer picked (a new player starts at 1x).
      if (state.speed != 1.0) {
        await _engine.setPlaybackSpeed(state.speed);
      }

      _viewerWantsPlay = true;
      await _engine.play();
      await WakelockPlus.enable();
      if (!ref.mounted) return;

      state = state.copyWith(
        isInitialized: true,
        isPlaying: true,
        isCompleted: false,
        duration: _engine.duration,
        position: Duration(milliseconds: targetMs),
        queueIndex: _queue.index,
        queueLength: _queue.items.length,
      );

      // An earlier attempt in this session marked the item missing, but it
      // plays now: without this it would stay "Missing" in Videos (and refuse
      // to open) until the next library scan.
      if (_markedMissing) {
        _markedMissing = false;
        _libraryRepo
            .updateAvailability(state.item.id, MediaAvailability.available)
            .ignore();
      }

      _startHideControlsTimer();

      // Listen to streams
      _posSub = _engine.positionStream.listen((pos) {
        state = state.copyWith(position: pos);
      });

      _playingSub = _engine.isPlayingStream.listen((playing) {
        if (playing == state.isPlaying) return;
        state = state.copyWith(isPlaying: playing, isCompleted: playing ? false : null);
        _session?.update(state);
        if (playing) {
          WakelockPlus.enable().ignore();
          _startHideControlsTimer();
        } else {
          WakelockPlus.disable().ignore();
          _saveCurrentProgress();
          // Stand-in engines without a completion event: stopped at the end.
          final d = state.duration;
          if (d > Duration.zero && state.position >= d - const Duration(milliseconds: 300)) {
            _onCompleted();
          }
        }
      });

      _errSub = _engine.errorStream.listen((err) {
        if (err != null) {
          _handleError(err);
        }
      });

      if (_engine case final VideoEngineExtras extras) {
        _completedSub = extras.completedStream.listen((_) => _onCompleted());
        _captionSub = extras.captionStream.listen((text) {
          if (text != state.caption) state = state.copyWith(caption: text);
        });
        _loadExtras(extras);
      }

      // A boost chosen for the previous video carries over to this one.
      if (state.boostPercent > 100) setBoost(state.boostPercent);

      _session?.update(state);

      // Throttle write timer every ~10s while playing
      _persistenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (state.isPlaying &&
            DateTime.now().difference(_lastSavedAt).inSeconds >= 9) {
          _saveCurrentProgress();
        }
      });
    } catch (e) {
      if (!ref.mounted) return;
      _handleError(e.toString());
    }
  }

  /// Sidecar subtitles and the audio-track list, after the video started.
  Future<void> _loadExtras(VideoEngineExtras extras) async {
    final itemId = state.item.id;
    final subtitlePath = sidecarSubtitlePath(state.item.uri);
    if (subtitlePath != null) {
      final ok = await extras.setSubtitleFile(subtitlePath);
      if (!ref.mounted || state.item.id != itemId) return;
      if (ok) {
        state = state.copyWith(subtitlesAvailable: true);
        if (!state.subtitlesOn) await extras.setSubtitleFile(null);
      }
    }
    final tracks = await extras.getAudioTracks();
    if (!ref.mounted || state.item.id != itemId) return;
    if (tracks.length > 1) state = state.copyWith(hasAudioTracks: true);
  }

  /// True (and noted) when this decoder error gets a quiet retry first.
  bool _takeQuietRetry(String message) {
    if (_retrying || _closing || !ref.mounted) return false;
    // Paused, backgrounded or finished: a retry would start playing by itself.
    if (!_viewerWantsPlay || state.isCompleted) return false;
    if (classifyVideoError(message) != VideoErrorKind.decoder) return false;
    final id = state.item.id;
    final now = DateTime.now();
    final last = _autoRetriedAt[id];
    if (last != null && now.difference(last) < autoRetryWindow) return false;
    _autoRetriedAt[id] = now;
    return true;
  }

  void _handleError(String message) {
    if (kDebugMode) debugPrint('_handleError called: $message');
    if (state.errorMessage == null && _takeQuietRetry(message)) {
      DiagnosticsService.instance.logEvent('video_player_auto_retry', {
        'kind': VideoErrorKind.decoder.name,
        'error': message,
      });
      if (state.isInitialized) _saveCurrentProgress();
      _upNextTimer?.cancel();
      // From where the video was; the loading circle shows meanwhile.
      unawaited(_retryFrom(state.position));
      return;
    }
    if (state.errorMessage == null) {
      // The raw text never reaches the screen; the diagnostics log keeps it
      // (links and storage paths are redacted there).
      DiagnosticsService.instance.logEvent('video_player_error', {
        'kind': classifyVideoError(message).name,
        'error': message,
      });
      // Remember how far the viewer got before the failed player goes quiet.
      if (state.isInitialized) _saveCurrentProgress();
    }
    // The failed player is finished: its position / playing updates would
    // otherwise rebuild the state and wipe the error (copyWith clears it).
    _cancelPlaybackListeners();
    _upNextTimer?.cancel();
    final lower = message.toLowerCase();
    // A format the phone cannot read is not a missing file, although iOS
    // words it "Cannot Open".
    final unreadable = classifyVideoError(message) == VideoErrorKind.unsupportedFormat;
    if (!unreadable &&
        (lower.contains('file') ||
            lower.contains('not found') ||
            lower.contains('missing') ||
            lower.contains('cannot open'))) {
      _markedMissing = true;
      _libraryRepo
          .updateAvailability(state.item.id, MediaAvailability.missing)
          .ignore();
    }
    state = state.copyWith(
      errorMessage: message,
      isInitialized: false,
      upNextSeconds: null,
    );
    _session?.clear();
  }

  /// A fresh state for [newItem] that keeps the viewer's choices.
  VideoPlaybackState _freshState(MediaItem newItem, {Duration position = Duration.zero, int? queueIndex}) {
    final sameItem = newItem.id == state.item.id;
    return VideoPlaybackState(
      item: newItem,
      position: position,
      speed: state.speed,
      fit: state.fit,
      orientationMode: sameItem || _orientationChosen ? state.orientationMode : OrientationMode.auto,
      subtitlesOn: state.subtitlesOn,
      boostPercent: state.boostPercent,
      boostSupported: state.boostSupported,
      queueIndex: queueIndex ?? _queue.index,
      queueLength: _queue.items.length,
    );
  }

  /// Frees the current player (and its hardware decoder) and gets a fresh
  /// engine: a disposed one cannot be reused. Bounded: a player whose
  /// creation failed can wait forever to dispose.
  Future<bool> _replaceEngine() async {
    try {
      await _engine.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (!ref.mounted) return false;
    ref.invalidate(videoEngineProvider);
    return true;
  }

  /// "Try again" on the error screen: releases the failed player, clears the
  /// error and starts the same item again from where it was (or from the
  /// saved progress). Taps while a retry is running are ignored.
  Future<void> retry() async {
    if (_retrying || state.errorMessage == null) return;
    await _retryFrom(state.position);
  }

  /// Releases the current player and starts the same item at [resumeAt]
  /// (zero: its saved progress). A failure while this runs shows the error
  /// screen; it is never retried quietly again.
  Future<void> _retryFrom(Duration resumeAt) async {
    if (_retrying || !ref.mounted) return;
    _retrying = true;
    try {
      _cancelPlaybackListeners();
      state = _freshState(state.item, position: resumeAt);
      if (!await _replaceEngine() || _closing) return;
      await _initPlayer(resumeAt: resumeAt);
    } finally {
      _retrying = false;
    }
  }

  /// The screen is going away (Back): nothing may start playing again.
  void markClosing() => _closing = true;

  /// Plays queue item [index]: saves where this video was, releases its
  /// player and starts the other one (from its own saved position).
  Future<void> playIndex(int index) async {
    if (_switching || _retrying) return;
    if (index < 0 || index >= _queue.items.length || index == _queue.index) return;
    _switching = true;
    try {
      _upNextTimer?.cancel();
      _upNextDismissed = false;
      // Stop listening to the old player first: an error from it while the
      // save below runs must not start a retry next to this switch.
      _cancelPlaybackListeners();
      if (state.isInitialized) await saveProgressNow();
      _queue = _queue.moveTo(index);
      final next = _queue.current;
      DeviceControls.releaseVideoBoost();
      state = _freshState(next, queueIndex: index);
      if (!await _replaceEngine()) return;
      await _initPlayer();
    } finally {
      _switching = false;
    }
  }

  Future<void> playNext() => playIndex(_queue.index + 1);
  Future<void> playPrevious() => playIndex(_queue.index - 1);

  /// The video reached its end: controls back with a Replay button and, if
  /// the queue has more, the "Up next" countdown.
  void _onCompleted() {
    if (!ref.mounted || state.isCompleted || state.errorMessage != null) return;
    _viewerWantsPlay = false;
    _hideControlsTimer?.cancel();
    state = state.copyWith(
      isCompleted: true,
      isPlaying: false,
      showControls: true,
      position: state.duration > Duration.zero ? state.duration : state.position,
    );
    _session?.update(state);
    if (state.hasNext && !_upNextDismissed) _startUpNext();
  }

  void _startUpNext() {
    _upNextTimer?.cancel();
    state = state.copyWith(upNextSeconds: upNextCountdownSeconds);
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (state.upNextSeconds ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        state = state.copyWith(upNextSeconds: null);
        playNext();
      } else {
        state = state.copyWith(upNextSeconds: left);
      }
    });
  }

  /// "Cancel" on the Up next card: stay on this video; the next one does
  /// not start, not even when the player reports the end once more.
  void cancelUpNext() {
    _upNextDismissed = true;
    _stopUpNext();
  }

  void _stopUpNext() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    if (state.upNextSeconds != null) state = state.copyWith(upNextSeconds: null);
  }

  /// The Replay button at the end.
  Future<void> replay() async {
    _stopUpNext();
    _upNextDismissed = false;
    _viewerWantsPlay = true;
    await seekTo(Duration.zero);
    await _engine.play();
  }

  // --- the controls overlay ---------------------------------------------------

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_holds > 0) return;
    _hideControlsTimer = Timer(hideControlsAfter, () {
      if (_holds > 0 || state.isCompleted) return;
      // Locked: only the lock icon shows; it fades even while paused.
      if (state.isLocked || state.isPlaying) {
        state = state.copyWith(showControls: false);
      }
    });
  }

  /// Keeps the controls up while the user is busy with them (dragging the
  /// scrubber or the volume, an open menu). Pair with [releaseControls].
  void holdControls() {
    _holds++;
    _hideControlsTimer?.cancel();
    if (!state.showControls) state = state.copyWith(showControls: true);
  }

  /// Ends a [holdControls]; the last release starts the 3 s hide timer again.
  void releaseControls() {
    if (_holds > 0) _holds--;
    if (_holds == 0 && (state.isPlaying || state.isLocked)) _startHideControlsTimer();
  }

  /// Shows the controls (or, locked, just the lock icon) for a while.
  void showControlsNow() {
    if (!state.showControls) state = state.copyWith(showControls: true);
    _startHideControlsTimer();
  }

  void toggleControls() {
    if (state.isLocked) {
      state = state.copyWith(showControls: !state.showControls);
      if (state.showControls) _startHideControlsTimer();
      return;
    }
    final nextShow = !state.showControls;
    state = state.copyWith(showControls: nextShow);
    if (nextShow && state.isPlaying) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  // --- transport --------------------------------------------------------------

  Future<void> togglePlayPause() async {
    if (state.isCompleted) return replay();
    if (state.isPlaying) {
      _viewerWantsPlay = false;
      await _engine.pause();
    } else {
      _viewerWantsPlay = true;
      await _engine.play();
    }
  }

  Future<void> play() async {
    if (state.isCompleted) return replay();
    _viewerWantsPlay = true;
    if (!state.isPlaying) await _engine.play();
  }

  Future<void> pause() async {
    _viewerWantsPlay = false;
    if (state.isPlaying) await _engine.pause();
  }

  Future<void> seekTo(Duration pos) async {
    final clamped = _clampToDuration(pos);
    await _engine.seekTo(clamped);
    if (!ref.mounted) return;
    final leavesEnd = state.isCompleted && clamped < state.duration;
    if (leavesEnd) {
      _stopUpNext();
      _upNextDismissed = false;
    }
    state = state.copyWith(position: clamped, isCompleted: leavesEnd ? false : null);
    _session?.update(state);
    if (state.isPlaying) {
      _startHideControlsTimer();
    } else {
      // Paused: playing again would save, closing might not; save soon.
      _seekSaveTimer?.cancel();
      _seekSaveTimer = Timer(pausedSeekSaveDelay, () {
        if (ref.mounted) _saveCurrentProgress();
      });
    }
  }

  Duration _clampToDuration(Duration pos) {
    if (pos < Duration.zero) return Duration.zero;
    if (state.duration > Duration.zero && pos > state.duration) return state.duration;
    return pos;
  }

  /// Skips [seconds] forward (negative: back). Repeated skips within
  /// [skipBurstWindow] add up from the last requested position, so fast taps
  /// never lose a step to a position update that has not arrived yet.
  Future<Duration> skipSeconds(int seconds) async {
    final now = DateTime.now();
    final burst = _skipTarget != null && _skipAt != null && now.difference(_skipAt!) < skipBurstWindow;
    final from = burst ? _skipTarget! : state.position;
    final target = _clampToDuration(from + Duration(seconds: seconds));
    _skipTarget = target;
    _skipAt = now;
    await seekTo(target);
    return target;
  }

  Future<void> setSpeed(double speed) async {
    await _engine.setPlaybackSpeed(speed);
    state = state.copyWith(speed: speed);
    _session?.update(state);
    if (state.isPlaying) _startHideControlsTimer();
  }

  // --- orientation and fit -----------------------------------------------------

  void _applyOrientation(OrientationMode mode) {
    try {
      SystemChrome.setPreferredOrientations(mode.orientations).ignore();
    } catch (_) {}
  }

  void setOrientationMode(OrientationMode mode) {
    _applyOrientation(mode);
    state = state.copyWith(orientationMode: mode, errorMessage: state.errorMessage);
  }

  /// The rotate button: Auto, Landscape lock, Portrait lock, Auto...
  OrientationMode cycleOrientation() {
    _orientationChosen = true;
    final next = state.orientationMode.next;
    setOrientationMode(next);
    if (state.isPlaying) _startHideControlsTimer();
    return next;
  }

  void setFit(VideoFit fit) {
    if (fit == state.fit) return;
    state = state.copyWith(fit: fit);
    if (state.isPlaying) _startHideControlsTimer();
  }

  /// The fit button: Fit, Fill, Stretch, Original, Fit...
  VideoFit cycleFit() {
    final next = state.fit.next;
    setFit(next);
    return next;
  }

  void toggleLock() {
    final nextLock = !state.isLocked;
    state = state.copyWith(isLocked: nextLock, showControls: true);
    if (state.isPlaying || nextLock) _startHideControlsTimer();
  }

  // --- subtitles and audio tracks ------------------------------------------------

  Future<void> toggleSubtitles() async {
    if (!state.subtitlesAvailable) return;
    if (_engine case final VideoEngineExtras extras) {
      final on = !state.subtitlesOn;
      state = state.copyWith(subtitlesOn: on, caption: on ? null : '');
      final path = on ? sidecarSubtitlePath(state.item.uri) : null;
      await extras.setSubtitleFile(path);
    }
  }

  Future<List<VideoAudioTrackInfo>> audioTracks() async {
    if (_engine case final VideoEngineExtras extras) return extras.getAudioTracks();
    return const [];
  }

  Future<void> selectAudioTrack(String id) async {
    if (_engine case final VideoEngineExtras extras) await extras.selectAudioTrack(id);
  }

  // --- volume boost -------------------------------------------------------------

  /// Sets the video's volume boost (100 = off, up to
  /// [DeviceControls.maxBoostPercent]). Returns false, and turns the boost
  /// off for this session, when the phone cannot boost.
  Future<bool> setBoost(int percent) async {
    final p = percent.clamp(100, DeviceControls.maxBoostPercent);
    if (!state.boostSupported) {
      if (state.boostPercent != 100) state = state.copyWith(boostPercent: 100);
      return p == 100;
    }
    final previous = state.boostPercent;
    state = state.copyWith(boostPercent: p, errorMessage: state.errorMessage);
    final id = _platformPlayerId;
    if (p == 100 && previous == 100) return true;
    final ok = id != null && await DeviceControls.setVideoBoost(playerId: id, percent: p);
    if (!ref.mounted) return ok;
    if (!ok && p > 100) {
      DiagnosticsService.instance.logEvent('video_boost_unavailable');
      state = state.copyWith(boostPercent: 100, boostSupported: false, errorMessage: state.errorMessage);
    }
    return ok;
  }

  // --- leaving and handing over ------------------------------------------------------

  void onAppBackgrounded() {
    _viewerWantsPlay = false;
    if (state.isPlaying) {
      _engine.pause();
      _saveCurrentProgress();
    }
  }

  /// Saves where the video is now, playing or paused (Back, a switch to
  /// another video, audio only).
  Future<void> saveProgressNow() async {
    _seekSaveTimer?.cancel();
    await _saveCurrentProgress();
  }

  /// "Audio only": the music player carries on from here (screen off,
  /// other apps) and this player stops. The screen pops afterwards. Returns
  /// false when the music player could not take over.
  Future<bool> continueAsAudio() async {
    if (!state.isInitialized) return false;
    _closing = true; // no quiet retry may start the video while the music takes over
    _viewerWantsPlay = false;
    final position = state.position;
    final current = state.item;
    await saveProgressNow();
    cancelUpNext();
    try {
      await _engine.pause();
    } catch (_) {}
    // Hand the media session back before the music player claims it.
    _session?.clear();
    try {
      final handoff = ref.read(videoAudioHandoffProvider);
      await handoff(current, position);
      DiagnosticsService.instance.logEvent('video_audio_only');
      return true;
    } catch (e) {
      debugPrint('[VideoPlayer] audio only failed: $e');
      _closing = false; // the screen stays
      return false;
    }
  }

  Future<void> _saveCurrentProgress() async {
    final s = state;
    await _writeProgress(s.item.id, s.position, s.duration);
  }

  /// From onDispose: no `state` reads that could throw, no new work.
  void _saveLast() {
    try {
      final s = state;
      _writeProgress(s.item.id, s.position, s.duration).ignore();
    } catch (_) {}
  }

  Future<void> _writeProgress(String mediaId, Duration position, Duration duration) async {
    if (duration.inMilliseconds <= 0) return;
    final positionMs = position.inMilliseconds;
    if (_savedPositions[mediaId] == positionMs) return;
    _savedPositions[mediaId] = positionMs;
    _lastSavedAt = DateTime.now();
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.saveProgress(
        VideoProgress(
          mediaId: mediaId,
          positionMs: positionMs,
          durationMs: duration.inMilliseconds,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Try again next time.
      if (_savedPositions[mediaId] == positionMs) _savedPositions.remove(mediaId);
    }
  }
}

/// The video in the phone's media session while it is on screen: the
/// notification, lock screen, Bluetooth and headset buttons control it
/// (through the music handler's external-source slot), and local music
/// stays paused.
class _VideoMediaSession implements ExternalPlaybackDelegate {
  _VideoMediaSession(this.notifier, this.host);

  final VideoPlayerControllerNotifier notifier;
  final ExternalPlaybackHost host;
  bool _active = false;

  ExternalMediaSnapshot snapshotOf(VideoPlaybackState s) {
    final art = s.item.artworkPath;
    return ExternalMediaSnapshot(
      id: 'video:${s.item.id}',
      title: videoDisplayTitle(s.item.title),
      // Shown under the title in the notification (YouTube items say 'YouTube').
      album: 'Video',
      artUri: art == null || art.isEmpty
          ? null
          : (art.startsWith('http://') || art.startsWith('https://') ? Uri.tryParse(art) : Uri.file(art)),
      playing: s.isPlaying,
      position: s.position,
      duration: s.duration > Duration.zero ? s.duration : null,
      speed: s.speed,
      canSkipNext: s.hasNext,
    );
  }

  /// New state of the video; claims the session once it plays.
  void update(VideoPlaybackState s) {
    if (!s.isInitialized || s.errorMessage != null) return;
    try {
      if (!_active) {
        if (!s.isPlaying) return;
        _active = true;
        host.setExternalSource(this, snapshotOf(s));
      } else {
        host.updateExternalMedia(this, snapshotOf(s));
      }
    } catch (e) {
      debugPrint('[VideoPlayer] media session update failed: $e');
    }
  }

  void clear() {
    if (!_active) return;
    _active = false;
    try {
      host.clearExternalSource(this);
    } catch (_) {}
  }

  @override
  Future<void> externalPlay() => notifier.play();

  @override
  Future<void> externalPause() => notifier.pause();

  @override
  Future<void> externalSeek(Duration position) => notifier.seekTo(position);

  /// Next video, or 10 s on when there is none.
  @override
  Future<void> externalSkipToNext() async {
    if (notifier.hasNextVideo) {
      await notifier.playNext();
    } else {
      await notifier.skipSeconds(10);
    }
  }

  /// Previous video, or 10 s back when there is none.
  @override
  Future<void> externalSkipToPrevious() async {
    if (notifier.hasPreviousVideo) {
      await notifier.playPrevious();
    } else {
      await notifier.skipSeconds(-10);
    }
  }

  @override
  void onExternalSourceReleased() {
    _active = false;
  }
}

final videoPlayerControllerProvider =
    NotifierProvider.autoDispose.family<VideoPlayerControllerNotifier, VideoPlaybackState, MediaItem>(
  (arg) => VideoPlayerControllerNotifier(arg),
);
