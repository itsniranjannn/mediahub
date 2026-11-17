import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../data/repositories/video_engine_impl.dart';
import '../../data/repositories/video_progress_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/video_progress.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/video_engine.dart';
import '../../domain/repositories/video_progress_repository.dart';
import '../music_player/playback_notifier.dart';

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

/// Why a video could not be played, so the screen can show a short plain
/// message instead of the raw player exception.
enum VideoErrorKind {
  /// The phone's decoder (MediaCodec / renderer) could not handle the video:
  /// a busy hardware decoder, memory pressure or an unsupported format.
  decoder,

  /// The file could not be opened: moved, deleted or no permission.
  source,

  /// Anything else.
  other;

  /// The plain message shown under "Unable to play video".
  String get message => switch (this) {
        VideoErrorKind.decoder =>
          "This phone couldn't decode this video. Trying again often helps.",
        VideoErrorKind.source =>
          "The video file couldn't be opened. It may have been moved or deleted.",
        VideoErrorKind.other => 'Something went wrong while starting this video.',
      };
}

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
/// for a missing file.
VideoErrorKind classifyVideoError(String raw) {
  if (_decoderError.hasMatch(raw)) return VideoErrorKind.decoder;
  if (_sourceError.hasMatch(raw)) return VideoErrorKind.source;
  return VideoErrorKind.other;
}

class VideoPlaybackState {
  final MediaItem item;
  final bool isInitialized;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool fitCover;
  final bool isLocked;
  final bool showControls;
  final bool isLandscape;
  final String? errorMessage;

  const VideoPlaybackState({
    required this.item,
    this.isInitialized = false,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.fitCover = false,
    this.isLocked = false,
    this.showControls = true,
    this.isLandscape = false,
    this.errorMessage,
  });

  VideoPlaybackState copyWith({
    MediaItem? item,
    bool? isInitialized,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? fitCover,
    bool? isLocked,
    bool? showControls,
    bool? isLandscape,
    String? errorMessage,
  }) {
    return VideoPlaybackState(
      item: item ?? this.item,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      fitCover: fitCover ?? this.fitCover,
      isLocked: isLocked ?? this.isLocked,
      showControls: showControls ?? this.showControls,
      isLandscape: isLandscape ?? this.isLandscape,
      errorMessage: errorMessage,
    );
  }
}

class VideoPlayerControllerNotifier extends Notifier<VideoPlaybackState> {
  final MediaItem item;

  Timer? _hideControlsTimer;
  Timer? _persistenceTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String?>? _errSub;
  DateTime _lastSavedAt = DateTime.now();
  bool _retrying = false;

  /// Set when a failed attempt flagged the item missing in the library, so a
  /// later attempt that plays (Try again) can put it back.
  bool _markedMissing = false;

  VideoPlayerControllerNotifier(this.item);

  VideoEngine get _engine => ref.read(videoEngineProvider);
  VideoProgressRepository get _progressRepo =>
      ref.read(videoProgressRepositoryProvider);
  LibraryRepository get _libraryRepo => ref.read(libraryRepositoryProvider);

  @override
  VideoPlaybackState build() {
    ref.onDispose(() {
      _cancelPlaybackListeners();
      try {
        WakelockPlus.disable().ignore();
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      } catch (_) {}
    });

    state = VideoPlaybackState(item: item);
    _initPlayer();

    return state;
  }

  /// Stops listening to the current engine and stops the timers.
  void _cancelPlaybackListeners() {
    _hideControlsTimer?.cancel();
    _persistenceTimer?.cancel();
    _posSub?.cancel();
    _playingSub?.cancel();
    _errSub?.cancel();
    _hideControlsTimer = null;
    _persistenceTimer = null;
    _posSub = null;
    _playingSub = null;
    _errSub = null;
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
      debugPrint('[VideoPlayer] Error pausing music playback: $e');
    }

    // Enter immersive mode
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).ignore();

      // Library items know their size; downloaded ones do not (handled after init).
      final width = state.item.width ?? 0;
      final height = state.item.height ?? 0;
      if (width > 0 && height > 0 && width > height) {
        _setOrientation(true);
      }
    } catch (_) {}

    try {
      await _engine.initialize(state.item.uri);
      if (!ref.mounted) return;

      // Auto-rotate from the real video size (works for downloaded files too).
      final size = _engine.videoSize;
      if (size.width > 0 && size.height > 0) {
        _setOrientation(size.width > size.height);
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

      await _engine.play();
      await WakelockPlus.enable();
      if (!ref.mounted) return;

      state = state.copyWith(
        isInitialized: true,
        isPlaying: true,
        duration: _engine.duration,
        position: Duration(milliseconds: targetMs),
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
        state = state.copyWith(isPlaying: playing);
        if (playing) {
          WakelockPlus.enable().ignore();
          _startHideControlsTimer();
        } else {
          WakelockPlus.disable().ignore();
          _saveCurrentProgress();
        }
      });

      _errSub = _engine.errorStream.listen((err) {
        if (err != null) {
          _handleError(err);
        }
      });

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

  void _handleError(String message) {
    if (kDebugMode) debugPrint('_handleError called: $message');
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
    final lower = message.toLowerCase();
    if (lower.contains('file') ||
        lower.contains('not found') ||
        lower.contains('missing') ||
        lower.contains('cannot open')) {
      _markedMissing = true;
      _libraryRepo
          .updateAvailability(state.item.id, MediaAvailability.missing)
          .ignore();
    }
    state = state.copyWith(
      errorMessage: message,
      isInitialized: false,
    );
  }

  /// "Try again" on the error screen: releases the failed player, clears the
  /// error and starts the same item again from where it was (or from the
  /// saved progress). Taps while a retry is running are ignored.
  Future<void> retry() async {
    if (_retrying || state.errorMessage == null) return;
    _retrying = true;
    try {
      final resumeAt = state.position;
      _cancelPlaybackListeners();
      state = VideoPlaybackState(
        item: state.item,
        position: resumeAt,
        speed: state.speed,
        fitCover: state.fitCover,
        isLandscape: state.isLandscape,
      );
      // Free the failed player (and its hardware decoder) before a new one
      // starts, then get a fresh engine: a disposed one cannot be reused.
      // Bounded: a player whose creation failed can wait forever to dispose.
      try {
        await _engine.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
      if (!ref.mounted) return;
      ref.invalidate(videoEngineProvider);
      await _initPlayer(resumeAt: resumeAt);
    } finally {
      _retrying = false;
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (state.isPlaying && !state.isLocked) {
        state = state.copyWith(showControls: false);
      }
    });
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

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  Future<void> seekTo(Duration pos) async {
    await _engine.seekTo(pos);
    state = state.copyWith(position: pos);
    if (state.isPlaying) _startHideControlsTimer();
  }

  Future<void> skipSeconds(int seconds) async {
    final newPos = state.position + Duration(seconds: seconds);
    final Duration clamped;
    if (newPos < Duration.zero) {
      clamped = Duration.zero;
    } else if (newPos > state.duration) {
      clamped = state.duration;
    } else {
      clamped = newPos;
    }
    await seekTo(clamped);
  }

  Future<void> setSpeed(double speed) async {
    await _engine.setPlaybackSpeed(speed);
    state = state.copyWith(speed: speed);
    if (state.isPlaying) _startHideControlsTimer();
  }

  void _setOrientation(bool landscape) {
    try {
      SystemChrome.setPreferredOrientations(landscape
          ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]).ignore();
    } catch (_) {}
    state = state.copyWith(isLandscape: landscape);
  }

  /// Manual rotate button, like other video players.
  void toggleOrientation() {
    _setOrientation(!state.isLandscape);
    if (state.isPlaying) _startHideControlsTimer();
  }

  void toggleFitFill() {
    state = state.copyWith(fitCover: !state.fitCover);
    if (state.isPlaying) _startHideControlsTimer();
  }

  void toggleLock() {
    final nextLock = !state.isLocked;
    state = state.copyWith(isLocked: nextLock, showControls: true);
    if (!nextLock && state.isPlaying) {
      _startHideControlsTimer();
    }
  }

  void onAppBackgrounded() {
    if (state.isPlaying) {
      _engine.pause();
      _saveCurrentProgress();
    }
  }

  Future<void> _saveCurrentProgress() async {
    if (state.duration.inMilliseconds <= 0) return;
    _lastSavedAt = DateTime.now();
    try {
      await _progressRepo.saveProgress(
        VideoProgress(
          mediaId: state.item.id,
          positionMs: state.position.inMilliseconds,
          durationMs: state.duration.inMilliseconds,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {}
  }
}

final videoPlayerControllerProvider =
    NotifierProvider.autoDispose.family<VideoPlayerControllerNotifier, VideoPlaybackState, MediaItem>(
  (arg) => VideoPlayerControllerNotifier(arg),
);
