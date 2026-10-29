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
    // 1. Pause any background music playback via AudioSession
    try {
      AudioSession.instance.then((session) => session.setActive(true)).ignore();
    } catch (_) {}

    // Enter immersive mode
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).ignore();

      // Check video orientation to auto-rotate
      final width = state.item.width ?? 0;
      final height = state.item.height ?? 0;
      if (width > 0 && height > 0 && width > height) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]).ignore();
      }
    } catch (_) {}

    try {
      await _engine.initialize(state.item.uri);

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
