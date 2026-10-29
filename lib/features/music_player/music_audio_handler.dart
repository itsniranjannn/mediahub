import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../domain/models/playback_state.dart' as domain;

class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;
  List<domain.MediaItem> _domainQueue = [];
  int _currentIndex = -1;
  domain.PlaybackRepeatMode _repeatMode = domain.PlaybackRepeatMode.off;
  bool _shuffle = false;
  List<int> _shuffledIndices = [];

  // Stream controller to broadcast error messages (e.g. unplayable or missing files)
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorEvents => _errorController.stream;

  final _domainStateController = StreamController<domain.PlaybackState>.broadcast();
  Stream<domain.PlaybackState> get domainStateStream => _domainStateController.stream;

  MusicAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _init();
  }

  AudioPlayer get player => _player;
  List<domain.MediaItem> get domainQueue => List.unmodifiable(_domainQueue);
  int get currentIndex => _currentIndex;
  domain.PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get shuffleEnabled => _shuffle;

  Future<void> _init() async {
    // 1. Configure audio_session
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged
        pause();
      });
    } catch (e) {
      debugPrint('Error configuring AudioSession: $e');
    }

    // 2. Listen to player state and broadcast AudioService PlaybackState
    _player.playbackEventStream.listen(_broadcastAudioServiceState);

    // Listen to completion to advance queue or repeat
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handlePlaybackCompleted();
      }
      _notifyDomainState();
    });

    _player.positionStream.listen((_) => _notifyDomainState());
    _player.durationStream.listen((_) => _notifyDomainState());
  }

  void _broadcastAudioServiceState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState] ?? AudioProcessingState.idle;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
          MediaAction.setSpeed,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
      ),
    );
  }

  void _notifyDomainState() {
    domain.MediaItem? currentItem;
    if (_currentIndex >= 0 && _currentIndex < _domainQueue.length) {
      currentItem = _domainQueue[_currentIndex];
    }

    _domainStateController.add(
      domain.PlaybackState(
        currentItemId: currentItem?.id,
        queue: _domainQueue,
        queueIndex: _currentIndex,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        isPlaying: _player.playing,
        repeatMode: _repeatMode,
        shuffle: _shuffle,
        speed: _player.speed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  domain.PlaybackState getCurrentDomainState() {
    domain.MediaItem? currentItem;
    if (_currentIndex >= 0 && _currentIndex < _domainQueue.length) {
      currentItem = _domainQueue[_currentIndex];
    }
    return domain.PlaybackState(
      currentItemId: currentItem?.id,
      queue: _domainQueue,
      queueIndex: _currentIndex,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      isPlaying: _player.playing,
      repeatMode: _repeatMode,
      shuffle: _shuffle,
      speed: _player.speed,
      updatedAt: DateTime.now(),
    );
  }

  // Restore session
  Future<void> restoreSession(domain.PlaybackState restored) async {
    _domainQueue = List.from(restored.queue);
    _currentIndex = restored.queueIndex;
    _repeatMode = restored.repeatMode;
    _shuffle = restored.shuffle;
    await _player.setSpeed(restored.speed);

    _syncAudioServiceQueue();
    if (_currentIndex >= 0 && _currentIndex < _domainQueue.length) {
      final item = _domainQueue[_currentIndex];
      _syncCurrentAudioServiceMediaItem(item);
      try {
        await _player.setAudioSource(AudioSource.uri(Uri.parse(item.uri)), initialPosition: restored.position);
      } catch (e) {
        debugPrint('Failed to set source on restore: $e');
      }
    }
    _notifyDomainState();
  }

  void _syncAudioServiceQueue() {
    final asQueue = _domainQueue.map((item) {
      return MediaItem(
        id: item.id,
        album: item.album ?? '',
        title: item.title,
        artist: item.artist,
        duration: Duration(milliseconds: item.durationMs),
        artUri: item.uri.isNotEmpty ? Uri.parse(item.uri) : null,
      );
    }).toList();
    queue.add(asQueue);
  }

  void _syncCurrentAudioServiceMediaItem(domain.MediaItem item) {
    mediaItem.add(
      MediaItem(
        id: item.id,
        album: item.album ?? '',
        title: item.title,
        artist: item.artist,
        duration: Duration(milliseconds: item.durationMs),
        artUri: item.uri.isNotEmpty ? Uri.parse(item.uri) : null,
      ),
    );
  }

  Future<void> loadQueue(List<domain.MediaItem> items, {int startIndex = 0, bool autoPlay = true}) async {
    if (items.isEmpty) {
      await stop();
      _domainQueue = [];
      _currentIndex = -1;
      _syncAudioServiceQueue();
      mediaItem.add(null);
      _notifyDomainState();
      return;
    }

    _domainQueue = List.from(items);
    _syncAudioServiceQueue();
    _generateShuffleIndices();
    await skipToQueueItem(startIndex);
    if (autoPlay) {
      await play();
    }
  }

  @override
  Future<void> play() async {
    if (_currentIndex < 0 && _domainQueue.isNotEmpty) {
      await skipToQueueItem(0);
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _notifyDomainState();
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
    _notifyDomainState();
  }

  void cycleRepeatMode() {
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
    _notifyDomainState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffle = shuffleMode == AudioServiceShuffleMode.all || shuffleMode == AudioServiceShuffleMode.group;
    if (_shuffle) {
      _generateShuffleIndices();
    }
    _notifyDomainState();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) {
      _generateShuffleIndices();
    }
    _notifyDomainState();
  }

  void _generateShuffleIndices() {
    _shuffledIndices = List.generate(_domainQueue.length, (i) => i);
    _shuffledIndices.shuffle();
    if (_currentIndex >= 0 && _shuffledIndices.contains(_currentIndex)) {
      _shuffledIndices.remove(_currentIndex);
      _shuffledIndices.insert(0, _currentIndex);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _domainQueue.length) return;
    _currentIndex = index;
    final item = _domainQueue[_currentIndex];
    _syncCurrentAudioServiceMediaItem(item);

    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(item.uri)));
    } catch (e) {
      debugPrint('Error playing ${item.title}: $e');
      _errorController.add('Unable to play "${item.title}": file missing or unsupported');
      // Auto skip to next track without crashing
      await skipToNext();
      return;
    }
    _notifyDomainState();
  }

  @override
  Future<void> skipToNext() async {
    if (_domainQueue.isEmpty) return;

    if (_shuffle && _shuffledIndices.isNotEmpty) {
      int currPos = _shuffledIndices.indexOf(_currentIndex);
      if (currPos != -1 && currPos + 1 < _shuffledIndices.length) {
        await skipToQueueItem(_shuffledIndices[currPos + 1]);
        await play();
        return;
      } else if (_repeatMode == domain.PlaybackRepeatMode.all) {
        _generateShuffleIndices();
        await skipToQueueItem(_shuffledIndices.first);
        await play();
        return;
      }
    } else {
      if (_currentIndex + 1 < _domainQueue.length) {
        await skipToQueueItem(_currentIndex + 1);
        await play();
        return;
      } else if (_repeatMode == domain.PlaybackRepeatMode.all) {
        await skipToQueueItem(0);
        await play();
        return;
      }
    }

    // End of queue reached and not repeating all
    await pause();
    await seek(Duration.zero);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_domainQueue.isEmpty) return;

    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    if (_shuffle && _shuffledIndices.isNotEmpty) {
      int currPos = _shuffledIndices.indexOf(_currentIndex);
      if (currPos > 0) {
        await skipToQueueItem(_shuffledIndices[currPos - 1]);
        await play();
        return;
      }
    } else {
      if (_currentIndex - 1 >= 0) {
        await skipToQueueItem(_currentIndex - 1);
        await play();
        return;
      }
    }
    await seek(Duration.zero);
  }

  void _handlePlaybackCompleted() async {
    if (_repeatMode == domain.PlaybackRepeatMode.one) {
      await seek(Duration.zero);
      await play();
    } else {
      await skipToNext();
    }
  }

  // Queue mutations:
  // Play next
  void playNext(domain.MediaItem item) {
    if (_domainQueue.isEmpty) {
      loadQueue([item]);
      return;
    }
    int insertIndex = _currentIndex + 1;
    _domainQueue.insert(insertIndex, item);
    _syncAudioServiceQueue();
    if (_shuffle) _generateShuffleIndices();
    _notifyDomainState();
  }

  // Add to queue
  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    // AudioService default add
  }

  void addToQueue(domain.MediaItem item) {
    _domainQueue.add(item);
    _syncAudioServiceQueue();
    if (_shuffle) _generateShuffleIndices();
    _notifyDomainState();
  }

  // Remove from queue
  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _domainQueue.length) return;
    final removingCurrent = index == _currentIndex;
    _domainQueue.removeAt(index);
    if (_shuffle) _generateShuffleIndices();

    if (removingCurrent) {
      if (_domainQueue.isEmpty) {
        _currentIndex = -1;
        await _player.stop();
        mediaItem.add(null);
      } else {
        if (_currentIndex >= _domainQueue.length) {
          _currentIndex = _domainQueue.length - 1;
        }
        await skipToQueueItem(_currentIndex);
      }
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    _syncAudioServiceQueue();
    _notifyDomainState();
  }

  // Reorder queue
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _domainQueue.length || newIndex < 0 || newIndex > _domainQueue.length) {
      return;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _domainQueue.removeAt(oldIndex);
    _domainQueue.insert(newIndex, item);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
      _currentIndex--;
    } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
      _currentIndex++;
    }

    _syncAudioServiceQueue();
    _notifyDomainState();
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _errorController.close();
    await _domainStateController.close();
  }
}
