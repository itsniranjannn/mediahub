import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/playback_repository_impl.dart';
import '../../domain/models/media_item.dart' as domain_models;
import '../../domain/models/playback_state.dart' as domain;
import '../../domain/repositories/playback_repository.dart';
import 'music_audio_handler.dart';

// Database provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// Playback repository provider
final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PlaybackRepositoryImpl(db);
});

// AudioHandler singleton provider
final audioHandlerProvider = Provider<MusicAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden at main');
});

// PlaybackState Notifier that synchronizes with MusicAudioHandler and persists to PlaybackRepository
class PlaybackNotifier extends Notifier<domain.PlaybackState> {
  StreamSubscription<domain.PlaybackState>? _stateSub;
  Timer? _persistenceTimer;

  /// A run of Next presses shows every target at once: the save waits for
  /// the run to settle instead of writing a row per press.
  Timer? _trackSaveTimer;
  DateTime _lastSavedAt = DateTime.now();
  bool _isDisposed = false;

  MusicAudioHandler get _handler => ref.read(audioHandlerProvider);
  PlaybackRepository get _repo => ref.read(playbackRepositoryProvider);

  @override
  domain.PlaybackState build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _stateSub?.cancel();
      _persistenceTimer?.cancel();
      _trackSaveTimer?.cancel();
    });

    Future.microtask(() => _init());

    return domain.PlaybackState(
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _init() async {
    if (_isDisposed) return;
    // 1. Try restoring last session from DB. Online items are filtered here
    // too, for rows saved before they were excluded (the old full-JSON queue
    // format kept their expiring stream URLs). Then the index is matched back
    // to the saved current item, as the repository drops ids it cannot find.
    final loaded = await _repo.loadLastPlaybackState();
    final savedState =
        loaded == null ? null : alignIndexWithCurrentItem(withoutOnlineItems(loaded));
    if (_isDisposed) return;
    if (savedState != null && savedState.queue.isNotEmpty) {
      await _handler.restoreSession(savedState);
      if (_isDisposed) return;
      state = _handler.getCurrentDomainState();
    }

    // 2. Listen to audio handler updates
    _stateSub?.cancel();
    _stateSub = _handler.domainStateStream.listen((newState) {
      if (_isDisposed) return;
      final oldState = state;
      state = newState;

      // Persistence logic:
      // Throttle writes: on track change, pause, and every ~10s while playing
      final trackChanged = oldState.currentItemId != newState.currentItemId;
      final pauseTriggered = oldState.isPlaying && !newState.isPlaying;

      if (pauseTriggered) {
        _trackSaveTimer?.cancel();
        _persistCurrentState();
      } else if (trackChanged) {
        _trackSaveTimer?.cancel();
        _trackSaveTimer = Timer(const Duration(milliseconds: 600), () {
          if (!_isDisposed) _persistCurrentState();
        });
      }
    });

    // 3. Periodic timer every ~10s while playing
    _persistenceTimer?.cancel();
    if (_isDisposed) return;
    _persistenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isDisposed) return;
      if (state.isPlaying) {
        if (DateTime.now().difference(_lastSavedAt).inSeconds >= 9) {
          _persistCurrentState();
        }
      }
    });
  }

  Future<void> _persistCurrentState() async {
    _lastSavedAt = DateTime.now();
    final safe = withoutOnlineItems(state);
    // Only online items queued (an Explore stream, the iOS Online hand-off):
    // the last local session stays in the database. Writing the empty queue
    // would lose it for good if the app is killed meanwhile.
    if (safe.queue.isEmpty && state.queue.isNotEmpty) return;
    try {
      await _repo.savePlaybackState(safe);
    } catch (e) {
      // Persistence error shouldn't crash playback
    }
  }

  /// The part of [s] that is safe to keep across app restarts.
  ///
  /// Explore items (`source == 'online'`) play from signed YouTube stream URLs
  /// that expire within hours and embed the phone's public IP address, so they
  /// are never written to the database: a restored session must not try (or
  /// keep) such a link. The queue index is moved to match the shorter queue:
  /// - the current item is kept: the index points at it again;
  /// - the current item is online: the next kept item after it becomes current
  ///   (or the last kept one before it), starting from the beginning;
  /// - nothing is left: an empty queue, so nothing is restored next launch.
  static domain.PlaybackState withoutOnlineItems(domain.PlaybackState s) {
    bool isOnline(domain_models.MediaItem m) => m.source == 'online';
    if (!s.queue.any(isOnline) && !s.originalQueue.any(isOnline)) return s;

    final queue = s.queue.where((m) => !isOnline(m)).toList();
    final originalQueue = s.originalQueue.where((m) => !isOnline(m)).toList();
    if (queue.isEmpty) {
      return s.copyWith(
        clearCurrentItemId: true,
        queue: const [],
        originalQueue: const [],
        queueIndex: -1,
        position: Duration.zero,
        duration: Duration.zero,
      );
    }

    final current = s.currentItem;
    if (current == null) {
      // No valid current item: keep "nothing selected" or clamp into range.
      return s.copyWith(
        queue: queue,
        originalQueue: originalQueue,
        queueIndex: s.queueIndex < 0 ? s.queueIndex : queue.length - 1,
      );
    }

    // Kept items before the current one = the current item's new index (or,
    // when the current item is dropped, the index of the next kept item).
    var index = s.queue.take(s.queueIndex).where((m) => !isOnline(m)).length;
    if (!isOnline(current)) {
      return s.copyWith(queue: queue, originalQueue: originalQueue, queueIndex: index);
    }
    if (index >= queue.length) index = queue.length - 1;
    final next = queue[index];
    return s.copyWith(
      currentItemId: next.id,
      queue: queue,
      originalQueue: originalQueue,
      queueIndex: index,
      position: Duration.zero,
      duration: Duration(milliseconds: next.durationMs),
    );
  }

  /// Makes a restored [s] point at its saved current item again.
  ///
  /// The repository silently skips queue ids it cannot resolve (`yt_` ids in
  /// rows saved before online items were excluded, local files deleted since
  /// the save), while the saved index and position still refer to the longer
  /// saved queue. So:
  /// - the current item is still in the queue: the index moves to it (the
  ///   position belonged to it, so it is kept);
  /// - it is gone: start from the first item at 0:00, with no current id;
  /// - the index already matches (or nothing was current): unchanged.
  static domain.PlaybackState alignIndexWithCurrentItem(domain.PlaybackState s) {
    final id = s.currentItemId;
    if (id == null || s.currentItem?.id == id) return s;
    final index = s.queue.indexWhere((m) => m.id == id);
    if (index >= 0) return s.copyWith(queueIndex: index);
    return s.copyWith(
      clearCurrentItemId: true,
      queueIndex: s.queue.isEmpty ? -1 : 0,
      position: Duration.zero,
      duration: s.queue.isEmpty ? Duration.zero : Duration(milliseconds: s.queue.first.durationMs),
    );
  }

  // Playback actions
  Future<void> loadQueue(
    List<domain_models.MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) =>
      _handler.loadQueue(
        items,
        startIndex: startIndex,
        autoPlay: autoPlay,
        shuffle: shuffle,
      );

  /// Shuffle mode as the player shows it. It is a sticky toggle (Spotify, YT
  /// Music): a tapped song plays first and the rest of its list stays
  /// shuffled, so callers pass it on instead of switching it off.
  bool get shuffleMode => state.shuffle;

  Future<void> playTrack(domain_models.MediaItem item, List<domain_models.MediaItem> allItems) async {
    int index = allItems.indexWhere((m) => m.id == item.id);
    if (index == -1) {
      index = 0;
      allItems = [item, ...allItems];
    }
    await _handler.loadQueue(allItems, startIndex: index, autoPlay: true, shuffle: shuffleMode);
  }

  // In-app controls act on the LOCAL queue. While the Online tab's YouTube
  // page owns the media session, playing or skipping here hands the session
  // back to local music (YouTube pauses). The notification, lock screen and
  // headset go through the handler's own play()/skipToNext()..., which route
  // to whichever source is active.
  Future<void> play() => _handler.playLocal();
  Future<void> pause() => _handler.pauseLocal();
  Future<void> togglePlayPause() => state.isPlaying ? pause() : play();
  Future<void> seek(Duration pos) => _handler.seekLocal(pos);
  Future<void> skipToNext() => _handler.skipToNextLocal();
  Future<void> skipToPrevious() => _handler.skipToPreviousLocal();
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);
  Future<void> setSpeed(double speed) => _handler.setSpeed(speed);
  void toggleShuffle() => _handler.toggleShuffle();
  void cycleRepeatMode() => _handler.cycleRepeatMode();
  void playNext(domain_models.MediaItem item) => _handler.playNext(item);
  void addToQueue(domain_models.MediaItem item) => _handler.addToQueue(item);
  Future<void> removeQueueItemAt(int index) => _handler.removeQueueItemAt(index);
  void reorderQueue(int oldIndex, int newIndex) => _handler.reorderQueue(oldIndex, newIndex);

  /// [items] play right after the current song, in this order (an album's
  /// or a playlist's "Play next"). With nothing queued they start playing.
  Future<void> playNextAll(List<domain_models.MediaItem> items) => _handler.playNextAll(items);

  /// [items] go to the end of the queue. With nothing queued they start playing.
  Future<void> addAllToQueue(List<domain_models.MediaItem> items) => _handler.addAllToQueue(items);

  /// Takes every copy of [mediaId] out of the queue (a deleted song). The
  /// current song is replaced by the next one; nothing happens when absent.
  Future<void> removeFromQueueById(String mediaId) => _handler.removeFromQueueById(mediaId);

  // The queue sheet's row actions, checked against the row's song id: a row
  // drawn before an earlier edit landed still reaches its own song (or
  // nothing, when that song left the queue).
  Future<void> skipToQueueEntry(int index, String expectedId) =>
      _handler.skipToQueueItem(index, expectedId: expectedId);
  Future<void> removeQueueEntry(int index, String expectedId) =>
      _handler.removeQueueItemAt(index, expectedId: expectedId);
  void moveQueueEntry(int oldIndex, int newIndex, String expectedId) =>
      _handler.reorderQueue(oldIndex, newIndex, expectedId: expectedId);

  // Sleep timer (docs/DESIGN.md 7.8). It pauses whatever owns the media
  // session, local music or the Online tab's video.
  void setSleepTimer(Duration duration) => _handler.setSleepTimer(duration);
  void setSleepTimerAtEndOfTrack() => _handler.setSleepTimerAtEndOfTrack();
  void cancelSleepTimer() => _handler.cancelSleepTimer();
}

final playbackNotifierProvider =
    NotifierProvider<PlaybackNotifier, domain.PlaybackState>(
  PlaybackNotifier.new,
);

// Distinct sub-providers
final currentMediaItemProvider = Provider<domain_models.MediaItem?>((ref) {
  return ref.watch(playbackNotifierProvider.select((s) => s.currentItem));
});

final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playbackNotifierProvider.select((s) => s.isPlaying));
});

final queueProvider = Provider<List<domain_models.MediaItem>>((ref) {
  return ref.watch(playbackNotifierProvider.select((s) => s.queue));
});

final repeatModeProvider = Provider<domain.PlaybackRepeatMode>((ref) {
  return ref.watch(playbackNotifierProvider.select((s) => s.repeatMode));
});

final shuffleProvider = Provider<bool>((ref) {
  return ref.watch(playbackNotifierProvider.select((s) => s.shuffle));
});

final playbackSpeedProvider = Provider<double>((ref) {
  return ref.watch(playbackNotifierProvider.select((s) => s.speed));
});

/// Whether Next does anything in [s]: false on the last track with repeat
/// off, the one place the mini player, Now Playing and the notification show
/// it disabled (docs/DESIGN.md 7.17). The same rule as the audio handler's.
bool canSkipNextIn(domain.PlaybackState s) => MusicAudioHandler.canSkipNextAt(
      index: s.queueIndex,
      length: s.queue.length,
      repeatMode: s.repeatMode,
    );

final canSkipNextProvider = Provider<bool>((ref) {
  return ref.watch(playbackNotifierProvider.select(canSkipNextIn));
});

/// [positions] at most once per [window], never stale: the newest value
/// waits for the end of the window instead of being dropped, and a jump of
/// more than [jump] (a seek, a new song) or a pause goes out at once.
Stream<Duration> throttlePositions(
  Stream<Duration> positions, {
  required bool Function() isPlaying,
  Stream<bool>? playingChanges,
  Duration window = const Duration(milliseconds: 240),
  Duration jump = const Duration(seconds: 1),
}) {
  late StreamController<Duration> controller;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<bool>? playingSub;
  Duration? last;
  Duration? pending;
  // Open for [window] after each value; what arrives meanwhile waits for
  // its end (timers, so fake time works in tests).
  Timer? windowTimer;

  void emit(Duration value) {
    pending = null;
    last = value;
    windowTimer?.cancel();
    windowTimer = Timer(window, () {
      windowTimer = null;
      final waiting = pending;
      if (waiting != null) emit(waiting);
    });
    controller.add(value);
  }

  void onPosition(Duration pos) {
    final previous = last;
    if (previous == null || windowTimer == null || !isPlaying() || (pos - previous).abs() > jump) {
      emit(pos);
      return;
    }
    pending = pos;
  }

  controller = StreamController<Duration>(
    onListen: () {
      positionSub = positions.listen(onPosition, onError: controller.addError);
      playingSub = playingChanges?.listen((playing) {
        // Paused: the bar stops where the music stopped, not 240 ms back.
        final value = pending;
        if (!playing && value != null) emit(value);
      });
    },
    onCancel: () async {
      windowTimer?.cancel();
      await positionSub?.cancel();
      await playingSub?.cancel();
    },
  );
  return controller.stream;
}

// Throttled position stream provider (about 4 updates per second), never stale.
final throttledPositionStreamProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final player = handler.player;
  return throttlePositions(
    player.positionStream,
    isPlaying: () => player.playing,
    playingChanges: player.playerStateStream.map((s) => s.playing).distinct(),
  );
});

/// The sleep timer, refreshed every second while it counts down (off where
/// no handler is provided: widget tests that only override the playback state).
class SleepTimerNotifier extends Notifier<domain.SleepTimerStatus> {
  Timer? _tick;

  @override
  domain.SleepTimerStatus build() {
    final MusicAudioHandler handler;
    try {
      handler = ref.watch(audioHandlerProvider);
    } catch (_) {
      return domain.SleepTimerStatus.off;
    }
    final sub = handler.sleepTimerStream.listen((status) => _show(status, handler));
    ref.onDispose(() {
      sub.cancel();
      _tick?.cancel();
    });
    final now = handler.sleepTimer;
    _schedule(now, handler);
    return now;
  }

  void _show(domain.SleepTimerStatus status, MusicAudioHandler handler) {
    state = status;
    _schedule(status, handler);
  }

  void _schedule(domain.SleepTimerStatus status, MusicAudioHandler handler) {
    _tick?.cancel();
    _tick = null;
    if (status.endsAt == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = handler.sleepTimer;
      state = now;
      if (now.endsAt == null) {
        _tick?.cancel();
        _tick = null;
      }
    });
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, domain.SleepTimerStatus>(SleepTimerNotifier.new);

/// What the Online tab's YouTube page is playing while it owns the media
/// session (null when local music owns it). The mini player shows it.
///
/// Synchronous from the first frame (no loading state that would flash the
/// local track), and null where no handler is provided (widget tests that
/// only override the local playback providers).
class ExternalMediaNotifier extends Notifier<ExternalMediaSnapshot?> {
  @override
  ExternalMediaSnapshot? build() {
    final MusicAudioHandler handler;
    try {
      handler = ref.watch(audioHandlerProvider);
    } catch (_) {
      return null;
    }
    final sub = handler.externalMediaStream.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return handler.externalMedia;
  }
}

final externalMediaProvider =
    NotifierProvider<ExternalMediaNotifier, ExternalMediaSnapshot?>(ExternalMediaNotifier.new);

// Error notifications stream
final playbackErrorStreamProvider = StreamProvider<String>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.errorEvents;
});
