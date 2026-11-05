import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/utils/play_count_tracker.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../domain/models/playback_state.dart' as domain;

class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;
  final Future<void> Function(String mediaId)? onRecordPlay;
  late final PlayCountTracker _playCountTracker;
  // ignore: deprecated_member_use
  ConcatenatingAudioSource? _playlistSource;
  List<domain.MediaItem> _domainQueue = [];
  domain.PlaybackRepeatMode _repeatMode = domain.PlaybackRepeatMode.off;

  // Custom notification actions
  static const String actionToggleShuffle = 'action_toggle_shuffle';
  static const String actionCycleRepeat = 'action_cycle_repeat';

  // Headset auto-resume state
  bool _resumeOnHeadphonesReconnect = false;
  bool get resumeOnHeadphonesReconnect => _resumeOnHeadphonesReconnect;
  void setResumeOnHeadphonesReconnect(bool value) {
    _resumeOnHeadphonesReconnect = value;
  }

  DateTime? _lastNoisyPauseTimestamp;
  bool _userInteractedSinceNoisy = false;
  bool _resumeOnFocusGain = false;
  double _volumeBeforeDuck = 1.0;

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

  // Serialized queue for actions (skipToNext, skipToPrevious, queue mutations)
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
        DiagnosticsService.instance.logEvent('lock_held', {
          'action': actionName,
          'durationMs': sw.elapsedMilliseconds,
        });
      }
    });
    return completer.future;
  }

  int _consecutiveErrorSkips = 0;

  // Stream controller to broadcast error messages (e.g. unplayable or missing files)
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorEvents => _errorController.stream;

  final _domainStateController = StreamController<domain.PlaybackState>.broadcast();
  Stream<domain.PlaybackState> get domainStateStream => _domainStateController.stream;

  MusicAudioHandler({
    AudioPlayer? player,
    this.onRecordPlay,
  })  : _player = player ?? AudioPlayer(handleInterruptions: false) {
    _playCountTracker = PlayCountTracker(onCountPlay: (id) async {
      DiagnosticsService.instance.logEvent('track_play_counted', {'id': id});
      if (onRecordPlay != null) {
        await onRecordPlay!(id);
      }
    });
    DiagnosticsService.instance.logEvent('service_start');
    _init();
  }

  AudioPlayer get player => _player;
  List<domain.MediaItem> get domainQueue => List.unmodifiable(_domainQueue);
  int get currentIndex => _player.currentIndex ?? -1;
  domain.PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get shuffleEnabled => _player.shuffleModeEnabled;

  Future<void> _init() async {
    // 1. Configure audio_session
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        DiagnosticsService.instance.logEvent('audio_focus_change', {
          'begin': event.begin,
          'type': event.type.toString(),
        });

        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _volumeBeforeDuck = _player.volume;
              _player.setVolume((_volumeBeforeDuck * 0.5).clamp(0.0, 1.0));
              break;
            case AudioInterruptionType.pause:
              _resumeOnFocusGain = _resumeOnFocusGain || _player.playing;
              pause(reason: 'focus_loss_transient');
              break;
            case AudioInterruptionType.unknown:
              _resumeOnFocusGain = false;
              pause(reason: 'focus_loss_permanent');
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
      });

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

        if (_resumeOnHeadphonesReconnect && event.devicesAdded.isNotEmpty) {
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

    // 2. Listen to player events and broadcast AudioService PlaybackState on EVERY change
    _player.playbackEventStream.listen(
      (_) {
        _broadcastAudioServiceState();
      },
      onError: (Object e, StackTrace st) {
        handlePlaybackError(e);
      },
    );

    _player.playerStateStream.listen((state) {
      DiagnosticsService.instance.logEvent('processing_state_change', {
        'state': state.processingState.toString(),
        'playing': state.playing,
      });

      if (state.processingState == ProcessingState.ready && state.playing) {
        _consecutiveErrorSkips = 0;
      }
      _broadcastAudioServiceState();
      if (state.processingState == ProcessingState.completed) {
        _handlePlaybackCompleted();
      }
      _notifyDomainState();
    });

    _player.currentIndexStream.listen((idx) {
      if (idx != null && idx >= 0 && idx < _domainQueue.length) {
        final track = _domainQueue[idx];
        _playCountTracker.onTrackChanged(
          track.id,
          Duration(milliseconds: track.durationMs),
        );
      } else {
        _playCountTracker.onTrackChanged(null, Duration.zero);
      }
      _syncCurrentAudioServiceMediaItem();
      _broadcastAudioServiceState();
      _notifyDomainState();
    });

    _player.positionStream.listen((pos) {
      _playCountTracker.onPositionUpdated(pos, isPlaying: _player.playing);
      // Position stream updates are consumed by throttledPositionStreamProvider;
      // Do not broadcast domain state at 5 Hz to save CPU/battery.
    });

    _player.durationStream.listen((dur) {
      if (dur != null && _playCountTracker.currentTrackId != null) {
        _playCountTracker.onTrackChanged(_playCountTracker.currentTrackId, dur);
      }
      _broadcastAudioServiceState();
      _notifyDomainState();
    });
  }

  void handlePlaybackError(Object error) {
    DiagnosticsService.instance.logEvent('player_error', {'source': 'playbackEventStream'});
    final currIdx = _player.currentIndex ?? -1;
    String trackName = 'Unknown';
    if (currIdx >= 0 && currIdx < _domainQueue.length) {
      trackName = _domainQueue[currIdx].title;
    }
    _errorController.add('Playback error on "$trackName"');
    _consecutiveErrorSkips++;
    if (_consecutiveErrorSkips < _domainQueue.length && _domainQueue.length > 1) {
      skipToNext();
    } else {
      _consecutiveErrorSkips = 0;
      pause(reason: 'error_loop_guard');
      _errorController.add('Playback stopped: consecutive playback errors reached queue limit');
    }
  }

  void _broadcastAudioServiceState() {
    final playing = _player.playing;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState] ?? AudioProcessingState.idle;

    // Custom shuffle action icon / label
    final isShuffled = _player.shuffleModeEnabled;
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

    final currIdx = _player.currentIndex ?? -1;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          shuffleAction,
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          repeatAction,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
          MediaAction.setSpeed,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        // Compact action view indices: skipToPrevious (index 1), play/pause (index 2), skipToNext (index 3)
        androidCompactActionIndices: const [1, 2, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: currIdx >= 0 ? currIdx : null,
      ),
    );
  }

  void _notifyDomainState() {
    final currIdx = _player.currentIndex ?? -1;
    domain.MediaItem? currentItem;
    if (currIdx >= 0 && currIdx < _domainQueue.length) {
      currentItem = _domainQueue[currIdx];
    }

    _domainStateController.add(
      domain.PlaybackState(
        currentItemId: currentItem?.id,
        queue: _domainQueue,
        queueIndex: currIdx,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        isPlaying: _player.playing,
        repeatMode: _repeatMode,
        shuffle: _player.shuffleModeEnabled,
        speed: _player.speed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  domain.PlaybackState getCurrentDomainState() {
    final currIdx = _player.currentIndex ?? -1;
    domain.MediaItem? currentItem;
    if (currIdx >= 0 && currIdx < _domainQueue.length) {
      currentItem = _domainQueue[currIdx];
    }
    return domain.PlaybackState(
      currentItemId: currentItem?.id,
      queue: _domainQueue,
      queueIndex: currIdx,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      isPlaying: _player.playing,
      repeatMode: _repeatMode,
      shuffle: _player.shuffleModeEnabled,
      speed: _player.speed,
      updatedAt: DateTime.now(),
    );
  }

  // Restore session
  Future<void> restoreSession(domain.PlaybackState restored) async {
    _domainQueue = List.from(restored.queue);
    _repeatMode = restored.repeatMode;
    await _player.setSpeed(restored.speed);

    _syncAudioServiceQueue();
    if (_domainQueue.isNotEmpty) {
      final audioSources = _domainQueue.map((item) {
        return AudioSource.uri(Uri.parse(item.uri), tag: item.id);
      }).toList();

      final initialIdx = (restored.queueIndex >= 0 && restored.queueIndex < _domainQueue.length)
          ? restored.queueIndex
          : 0;

      try {
        // TODO: Replace ConcatenatingAudioSource with direct AudioPlayer methods when available in just_audio
        // ignore: deprecated_member_use
        _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(
          _playlistSource!,
          initialIndex: initialIdx,
          initialPosition: restored.position,
        );
        await _player.setShuffleModeEnabled(restored.shuffle);
        _applyLoopMode();
      } catch (e) {
        DiagnosticsService.instance.logEvent('player_error', {'source': 'restore_session'});
        debugPrint('Failed to set source on restore: $e');
      }
    }
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
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
        artUri: null, // notification artUri must not be the audio file URI
      );
    }).toList();
    queue.add(asQueue);
  }

  void _syncCurrentAudioServiceMediaItem() {
    final currIdx = _player.currentIndex ?? -1;
    if (currIdx >= 0 && currIdx < _domainQueue.length) {
      final item = _domainQueue[currIdx];
      mediaItem.add(
        MediaItem(
          id: item.id,
          album: item.album ?? '',
          title: item.title,
          artist: item.artist,
          duration: Duration(milliseconds: item.durationMs),
          artUri: null, // notification artUri must not be the audio file URI
        ),
      );
    } else {
      mediaItem.add(null);
    }
  }

  Future<void> loadQueue(List<domain.MediaItem> items, {int startIndex = 0, bool autoPlay = true}) async {
    _userInteractedSinceNoisy = true;
    if (items.isEmpty) {
      await stop(reason: 'empty_queue_load');
      _domainQueue = [];
      _syncAudioServiceQueue();
      mediaItem.add(null);
      _broadcastAudioServiceState();
      _notifyDomainState();
      return;
    }

    _domainQueue = List.from(items);
    _syncAudioServiceQueue();

    final audioSources = _domainQueue.map((item) {
      return AudioSource.uri(Uri.parse(item.uri), tag: item.id);
    }).toList();

    try {
      // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
      await _player.setAudioSource(
        _playlistSource!,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
      );
      _applyLoopMode();
    } catch (e) {
      DiagnosticsService.instance.logEvent('player_error', {'source': 'load_queue'});
      debugPrint('Error setting queue source: $e');
    }

    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();

    if (autoPlay) {
      _wantPlaying = true;
      _safeStartPlayerPlay('load_queue');
      _broadcastAudioServiceState();
    }
  }

  String _formatCaller() {
    return 'in_app';
  }

  @override
  Future<void> play({String? caller}) async {
    _userInteractedSinceNoisy = true;
    _wantPlaying = true;
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
  Future<void> pause({String? reason}) async {
    _wantPlaying = false;
    final stopReason = reason ?? 'user';
    DiagnosticsService.instance.logEvent('pause', {'reason': stopReason});
    debugPrint('[MusicAudioHandler] pause(reason: $stopReason)');
    await _player.pause();
    _broadcastAudioServiceState();
  }

  @override
  Future<void> stop({String? reason}) async {
    _wantPlaying = false;
    final stopReason = reason ?? 'user';
    DiagnosticsService.instance.logEvent('stop', {'reason': stopReason});
    debugPrint('[MusicAudioHandler] stop(reason: $stopReason)');
    await _player.stop();
    await super.stop();
    _broadcastAudioServiceState();
  }

  @override
  Future<void> seek(Duration position) async {
    _userInteractedSinceNoisy = true;
    DiagnosticsService.instance.logEvent('seek');
    debugPrint('[MusicAudioHandler] seek($position) called by: ${_formatCaller()}');
    await _player.seek(position);
    _broadcastAudioServiceState();
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
    final enabled = shuffleMode == AudioServiceShuffleMode.all || shuffleMode == AudioServiceShuffleMode.group;
    final currentPos = _player.position;
    final currIdx = _player.currentIndex;
    await _player.setShuffleModeEnabled(enabled);
    if (currIdx != null && _player.currentIndex != currIdx) {
      await _player.seek(currentPos, index: currIdx);
    }
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  void toggleShuffle() async {
    _userInteractedSinceNoisy = true;
    final nextVal = !_player.shuffleModeEnabled;
    final currentPos = _player.position;
    final currIdx = _player.currentIndex;
    await _player.setShuffleModeEnabled(nextVal);
    // Ensure position and current track are kept
    if (currIdx != null && _player.currentIndex != currIdx) {
      await _player.seek(currentPos, index: currIdx);
    }
    DiagnosticsService.instance.logEvent('shuffle_mode_changed', {'enabled': nextVal});
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == actionToggleShuffle) {
      toggleShuffle();
    } else if (name == actionCycleRepeat) {
      cycleRepeatMode();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _userInteractedSinceNoisy = true;
    if (index < 0 || index >= _domainQueue.length) return;
    try {
      await _player.seek(Duration.zero, index: index);
    } catch (e) {
      DiagnosticsService.instance.logEvent('player_error', {'source': 'skip_to_queue_item'});
      final item = _domainQueue[index];
      _errorController.add('Unable to play "${item.title}": file missing or unsupported');
      await skipToNext();
      return;
    }
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  @override
  Future<void> skipToNext() {
    _userInteractedSinceNoisy = true;
    _wantPlaying = true; // Match Spotify: skipping starts playing
    final caller = _formatCaller();
    DiagnosticsService.instance.logEvent('skipToNext', {'caller': caller});

    return _synchronized(() async {
      try {
        if (_domainQueue.isEmpty) return;

        if (_player.hasNext) {
          await _player.seekToNext();
          _syncCurrentAudioServiceMediaItem();
          _broadcastAudioServiceState();
          _notifyDomainState();
          if (_wantPlaying) {
            _safeStartPlayerPlay('skip_to_next');
          }
        } else {
          // At the end of queue
          if (_repeatMode == domain.PlaybackRepeatMode.all) {
            // Wrap around to start of queue
            await _player.seek(Duration.zero, index: 0);
            _syncCurrentAudioServiceMediaItem();
            _broadcastAudioServiceState();
            _notifyDomainState();
            if (_wantPlaying) {
              _safeStartPlayerPlay('skip_to_next_wrap_all');
            }
          } else {
            // Repeat off -> stop at last track and show paused state at start of queue
            _wantPlaying = false;
            DiagnosticsService.instance.logEvent('queue_ended', {'action': 'paused_at_start'});
            await _player.pause();
            await _player.seek(Duration.zero, index: 0);
            _syncCurrentAudioServiceMediaItem();
            _broadcastAudioServiceState();
            _notifyDomainState();
          }
        }
      } catch (e) {
        DiagnosticsService.instance.logEvent('player_error', {'source': 'skipToNext'});
        debugPrint('Error in skipToNext: $e');
      }
    }, 'skipToNext');
  }

  @override
  Future<void> skipToPrevious() {
    _userInteractedSinceNoisy = true;
    _wantPlaying = true; // Match Spotify: skipping starts playing
    final caller = _formatCaller();
    DiagnosticsService.instance.logEvent('skipToPrevious', {'caller': caller});

    return _synchronized(() async {
      try {
        if (_domainQueue.isEmpty) return;

        if (_player.position > const Duration(seconds: 3)) {
          await seek(Duration.zero);
          if (_wantPlaying) {
            _safeStartPlayerPlay('skip_to_previous_restart');
          }
          return;
        }

        if (_player.hasPrevious) {
          await _player.seekToPrevious();
          _syncCurrentAudioServiceMediaItem();
          _broadcastAudioServiceState();
          _notifyDomainState();
          if (_wantPlaying) {
            _safeStartPlayerPlay('skip_to_previous');
          }
        } else {
          // At start of queue
          if (_repeatMode == domain.PlaybackRepeatMode.all) {
            final lastIdx = _domainQueue.length - 1;
            await _player.seek(Duration.zero, index: lastIdx);
            _syncCurrentAudioServiceMediaItem();
            _broadcastAudioServiceState();
            _notifyDomainState();
            if (_wantPlaying) {
              _safeStartPlayerPlay('skip_to_previous_wrap_all');
            }
          } else {
            await seek(Duration.zero);
            if (_wantPlaying) {
              _safeStartPlayerPlay('skip_to_previous_start');
            }
          }
        }
      } catch (e) {
        DiagnosticsService.instance.logEvent('player_error', {'source': 'skipToPrevious'});
        debugPrint('Error in skipToPrevious: $e');
      }
    }, 'skipToPrevious');
  }

  void _handlePlaybackCompleted() async {
    if (_repeatMode == domain.PlaybackRepeatMode.one) {
      await seek(Duration.zero);
      _wantPlaying = true;
      _safeStartPlayerPlay('repeat_one_completed');
    } else if (_player.hasNext) {
      await skipToNext();
    } else if (_repeatMode == domain.PlaybackRepeatMode.all) {
      await _player.seek(Duration.zero, index: 0);
      _wantPlaying = true;
      _safeStartPlayerPlay('repeat_all_restart');
    } else {
      // Repeat off -> show paused state at start of queue, not silent stop
      _wantPlaying = false;
      DiagnosticsService.instance.logEvent('queue_ended', {'action': 'completed_paused_at_start'});
      await _player.pause();
      await _player.seek(Duration.zero, index: 0);
      _broadcastAudioServiceState();
      _notifyDomainState();
    }
  }

  // Queue mutations
  void playNext(domain.MediaItem item) {
    _userInteractedSinceNoisy = true;
    if (_domainQueue.isEmpty) {
      loadQueue([item]);
      return;
    }
    _synchronized(() async {
      final currIdx = _player.currentIndex ?? 0;
      int insertIndex = currIdx + 1;
      _domainQueue.insert(insertIndex, item);
      final source = AudioSource.uri(Uri.parse(item.uri), tag: item.id);
      if (_playlistSource != null) {
        await _playlistSource!.insert(insertIndex, source);
      } else {
        final audioSources = _domainQueue.map((m) => AudioSource.uri(Uri.parse(m.uri), tag: m.id)).toList();
        // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(_playlistSource!, initialIndex: currIdx, initialPosition: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    });
  }

  void addToQueue(domain.MediaItem item) {
    _userInteractedSinceNoisy = true;
    if (_domainQueue.isEmpty) {
      loadQueue([item]);
      return;
    }
    _synchronized(() async {
      final currIdx = _player.currentIndex ?? 0;
      _domainQueue.add(item);
      final source = AudioSource.uri(Uri.parse(item.uri), tag: item.id);
      if (_playlistSource != null) {
        await _playlistSource!.add(source);
      } else {
        final audioSources = _domainQueue.map((m) => AudioSource.uri(Uri.parse(m.uri), tag: m.id)).toList();
        // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(_playlistSource!, initialIndex: currIdx, initialPosition: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    });
  }

  @override
  Future<void> removeQueueItemAt(int index) {
    _userInteractedSinceNoisy = true;
    if (index < 0 || index >= _domainQueue.length) return Future.value();

    return _synchronized(() async {
      final currIdx = _player.currentIndex ?? 0;
      final isRemovingCurrent = (index == currIdx);
      _domainQueue.removeAt(index);

      if (_domainQueue.isEmpty) {
        await _player.stop();
        _playlistSource = null;
        mediaItem.add(null);
      } else {
        if (_playlistSource != null && _playlistSource!.length > index) {
          await _playlistSource!.removeAt(index);
          if (isRemovingCurrent) {
            // When removing current item, reload next track from Duration.zero
            await _player.seek(Duration.zero);
          }
        } else {
          int newIdx = currIdx;
          if (index < currIdx) {
            newIdx = currIdx - 1;
          } else if (index == currIdx && newIdx >= _domainQueue.length) {
            newIdx = _domainQueue.length - 1;
          }
          final audioSources = _domainQueue.map((m) => AudioSource.uri(Uri.parse(m.uri), tag: m.id)).toList();
          // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
          await _player.setAudioSource(
            _playlistSource!,
            initialIndex: newIdx,
            initialPosition: isRemovingCurrent ? Duration.zero : _player.position,
          );
        }
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    });
  }

  void reorderQueue(int oldIndex, int newIndex) {
    _userInteractedSinceNoisy = true;
    if (oldIndex < 0 || oldIndex >= _domainQueue.length || newIndex < 0 || newIndex >= _domainQueue.length) {
      return;
    }

    _synchronized(() async {
      final item = _domainQueue.removeAt(oldIndex);
      _domainQueue.insert(newIndex, item);

      if (_playlistSource != null && _playlistSource!.length > oldIndex) {
        await _playlistSource!.move(oldIndex, newIndex);
      } else {
        final currIdx = _player.currentIndex ?? 0;
        int updatedIdx = currIdx;
        if (currIdx == oldIndex) {
          updatedIdx = newIndex;
        } else if (currIdx > oldIndex && currIdx <= newIndex) {
          updatedIdx = currIdx - 1;
        } else if (currIdx < oldIndex && currIdx >= newIndex) {
          updatedIdx = currIdx + 1;
        }

        final audioSources = _domainQueue.map((m) => AudioSource.uri(Uri.parse(m.uri), tag: m.id)).toList();
        // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(_playlistSource!, initialIndex: updatedIdx, initialPosition: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    });
  }

  Future<void> dispose() async {
    DiagnosticsService.instance.logEvent('service_stop');
    await _player.dispose();
    await _errorController.close();
    await _domainStateController.close();
  }
}
