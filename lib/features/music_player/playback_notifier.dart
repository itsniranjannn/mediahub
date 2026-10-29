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
  DateTime _lastSavedAt = DateTime.now();

  MusicAudioHandler get _handler => ref.read(audioHandlerProvider);
  PlaybackRepository get _repo => ref.read(playbackRepositoryProvider);

  @override
  domain.PlaybackState build() {
    ref.onDispose(() {
      _stateSub?.cancel();
      _persistenceTimer?.cancel();
    });

    Future.microtask(() => _init());

    return domain.PlaybackState(
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _init() async {
    // 1. Try restoring last session from DB
    final savedState = await _repo.loadLastPlaybackState();
    if (savedState != null && savedState.queue.isNotEmpty) {
      await _handler.restoreSession(savedState);
      state = _handler.getCurrentDomainState();
    }

    // 2. Listen to audio handler updates
    _stateSub?.cancel();
    _stateSub = _handler.domainStateStream.listen((newState) {
      final oldState = state;
      state = newState;

      // Persistence logic:
      // Throttle writes: on track change, pause, and every ~10s while playing
      final trackChanged = oldState.currentItemId != newState.currentItemId;
      final pauseTriggered = oldState.isPlaying && !newState.isPlaying;

      if (trackChanged || pauseTriggered) {
        _persistCurrentState();
      }
    });

    // 3. Periodic timer every ~10s while playing
    _persistenceTimer?.cancel();
    _persistenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (state.isPlaying) {
        if (DateTime.now().difference(_lastSavedAt).inSeconds >= 9) {
          _persistCurrentState();
        }
      }
    });
  }

  Future<void> _persistCurrentState() async {
    _lastSavedAt = DateTime.now();
    try {
      await _repo.savePlaybackState(state);
    } catch (e) {
      // Persistence error shouldn't crash playback
    }
  }

  // Playback actions
  Future<void> playTrack(domain_models.MediaItem item, List<domain_models.MediaItem> allItems) async {
    int index = allItems.indexWhere((m) => m.id == item.id);
    if (index == -1) {
      index = 0;
      allItems = [item, ...allItems];
    }
    await _handler.loadQueue(allItems, startIndex: index, autoPlay: true);
  }

  Future<void> play() => _handler.play();
  Future<void> pause() => _handler.pause();
  Future<void> seek(Duration pos) => _handler.seek(pos);
  Future<void> skipToNext() => _handler.skipToNext();
  Future<void> skipToPrevious() => _handler.skipToPrevious();
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);
  Future<void> setSpeed(double speed) => _handler.setSpeed(speed);
  void toggleShuffle() => _handler.toggleShuffle();
  void cycleRepeatMode() => _handler.cycleRepeatMode();
  void playNext(domain_models.MediaItem item) => _handler.playNext(item);
  void addToQueue(domain_models.MediaItem item) => _handler.addToQueue(item);
  Future<void> removeQueueItemAt(int index) => _handler.removeQueueItemAt(index);
  void reorderQueue(int oldIndex, int newIndex) => _handler.reorderQueue(oldIndex, newIndex);
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

// Throttled position stream provider (~4 updates per second = 250ms interval)
final throttledPositionStreamProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  DateTime lastEmission = DateTime.fromMillisecondsSinceEpoch(0);
  final controller = StreamController<Duration>();

  final sub = handler.player.positionStream.listen((pos) {
    final now = DateTime.now();
    if (now.difference(lastEmission).inMilliseconds >= 240) {
      lastEmission = now;
      controller.add(pos);
    }
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

// Error notifications stream
final playbackErrorStreamProvider = StreamProvider<String>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.errorEvents;
});
