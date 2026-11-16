import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

  VideoPlayerControllerNotifier(this.item);

  VideoEngine get _engine => ref.read(videoEngineProvider);
  VideoProgressRepository get _progressRepo =>
      ref.read(videoProgressRepositoryProvider);
  LibraryRepository get _libraryRepo => ref.read(libraryRepositoryProvider);

  @override
  VideoPlaybackState build() {
    ref.onDispose(() {
      _hideControlsTimer?.cancel();
      _persistenceTimer?.cancel();
      _posSub?.cancel();
      _playingSub?.cancel();
      _errSub?.cancel();
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

  Future<void> _initPlayer() async {
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

      // Check saved progress
      final savedProgress = await _progressRepo.getProgress(state.item.id);
      int targetMs = 0;
      if (savedProgress != null) {
        targetMs = VideoProgress.calculateResumePosition(
          savedPositionMs: savedProgress.positionMs,
          totalDurationMs: savedProgress.durationMs > 0
              ? savedProgress.durationMs
              : _engine.duration.inMilliseconds,
        );
      }

      if (targetMs > 0) {
        await _engine.seekTo(Duration(milliseconds: targetMs));
      }

      await _engine.play();
      await WakelockPlus.enable();

      state = state.copyWith(
        isInitialized: true,
        isPlaying: true,
        duration: _engine.duration,
        position: Duration(milliseconds: targetMs),
      );

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
      _handleError(e.toString());
    }
  }

  void _handleError(String message) {
    debugPrint('_handleError called: $message');
    final lower = message.toLowerCase();
    if (lower.contains('file') ||
        lower.contains('not found') ||
        lower.contains('missing') ||
        lower.contains('cannot open')) {
      _libraryRepo
          .updateAvailability(state.item.id, MediaAvailability.missing)
          .ignore();
    }
    state = state.copyWith(
      errorMessage: message,
      isInitialized: false,
    );
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
