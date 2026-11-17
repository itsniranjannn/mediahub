// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/utils/play_count_tracker.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../domain/models/playback_state.dart' as domain;

/// What an external player (the Online tab's YouTube page) shows in the media
/// notification, on the lock screen and on Bluetooth displays.
@immutable
class ExternalMediaSnapshot {
  const ExternalMediaSnapshot({
    required this.id,
    required this.title,
    this.artist,
    this.artUri,
    required this.playing,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration,
    this.speed = 1.0,
    this.canSkipNext = false,
  });

  /// Stable id of what is playing (e.g. `online:<videoId>`).
  final String id;
  final String title;

  /// Channel name.
  final String? artist;

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

  @override
  bool operator ==(Object other) =>
      other is ExternalMediaSnapshot &&
      other.id == id &&
      other.title == title &&
      other.artist == artist &&
      other.artUri == artUri &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.position == position &&
      other.duration == duration &&
      other.speed == speed &&
      other.canSkipNext == canSkipNext;

  @override
  int get hashCode =>
      Object.hash(id, title, artist, artUri, playing, buffering, position, duration, speed, canSkipNext);
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

class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler implements ExternalPlaybackHost {
  final AudioPlayer _player;
  final Future<void> Function(String mediaId)? onRecordPlay;

  /// Called once per track when the player learns a duration that the library
  /// did not know yet (downloaded files are stored with duration 0).
  final Future<void> Function(String mediaId, int durationMs)? onDurationKnown;
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

  UriAudioSource _sourceFor(domain.MediaItem item) =>
      AudioSource.uri(_audioUri(item.uri), tag: item.id);

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

  static Uri? _artUri(domain.MediaItem item) {
    final path = item.artworkPath;
    if (path == null) return null;
    // Online items carry the https thumbnail, downloads a local image file.
    return path.startsWith('http://') || path.startsWith('https://') ? Uri.parse(path) : Uri.file(path);
  }

  /// Removes the first element with [id]; keeps duplicates that follow.
  static void _removeFirstById(List<domain.MediaItem> list, String id) {
    final i = list.indexWhere((m) => m.id == id);
    if (i >= 0) list.removeAt(i);
  }

  // Custom notification actions
  static const String actionToggleShuffle = 'action_toggle_shuffle';
  static const String actionCycleRepeat = 'action_cycle_repeat';

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

  // Serialized queue for actions with pending skip counter debouncing
  Future<void> _actionChain = Future.value();
  int _pendingSkips = 0;
  Timer? _debounceSkipPlayTimer;

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

  int _consecutiveErrorSkips = 0;
  String _lastLoggedPlayerState = '';

  // Stream controller to broadcast error messages (e.g. unplayable or missing files)
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorEvents => _errorController.stream;

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

  MusicAudioHandler({
    AudioPlayer? player,
    this.onRecordPlay,
    this.onDurationKnown,
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

  Future<void> _init() async {
    // 1. Configure audio_session
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
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
      if (_suppressIndexEvents) return;
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
      _reportLearnedDuration(dur);
      _broadcastAudioServiceState();
      _notifyDomainState();
    });
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
      _skipToNextLocalImpl();
    } else {
      _consecutiveErrorSkips = 0;
      _pauseLocalImpl(reason: 'error_loop_guard');
      _errorController.add('Playback stopped: consecutive playback errors reached queue limit');
    }
  }

  void _broadcastAudioServiceState() {
    // While an external source owns the session, local player events (the
    // pause that handed over, buffering, ...) must not overwrite its state.
    if (_external != null) return;
    final playing = _player.playing;
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
        originalQueue: _originalQueue,
        queueIndex: currIdx,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        isPlaying: _player.playing,
        repeatMode: _repeatMode,
        shuffle: _shuffleEnabled,
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
      originalQueue: _originalQueue,
      queueIndex: currIdx,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      isPlaying: _player.playing,
      repeatMode: _repeatMode,
      shuffle: _shuffleEnabled,
      speed: _player.speed,
      updatedAt: DateTime.now(),
    );
  }

  // Restore session
  Future<void> restoreSession(domain.PlaybackState restored) async {
    _originalQueue = List.from(restored.originalQueue.isNotEmpty ? restored.originalQueue : restored.queue);
    _playOrderQueue = List.from(restored.queue);
    _shuffleEnabled = restored.shuffle;
    _repeatMode = restored.repeatMode;
    await _player.setSpeed(restored.speed);

    _syncAudioServiceQueue();
    if (_domainQueue.isNotEmpty) {
      final audioSources = _domainQueue.map((item) {
        return AudioSource.uri(_audioUri(item.uri), tag: item.id);
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
        // Never the audio file URI itself; only a real image file (downloads).
        artUri: _artUri(item),
      );
    }).toList();
    queue.add(asQueue);
  }

  void _syncCurrentAudioServiceMediaItem() {
    if (_external != null) return; // the external source's item stays on show
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
          artUri: _artUri(item),
        ),
      );
    } else {
      mediaItem.add(null);
    }
  }

  Future<void> loadQueue(
    List<domain.MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) async {
    _userInteractedSinceNoisy = true;
    if (items.isEmpty) {
      await _stopLocalImpl(reason: 'empty_queue_load');
      _originalQueue = [];
      _playOrderQueue = [];
      _shuffleEnabled = false;
      _syncAudioServiceQueue();
      if (_external == null) mediaItem.add(null);
      _broadcastAudioServiceState();
      _notifyDomainState();
      return;
    }
    // Starting local music hands the session back from YouTube (which pauses).
    if (autoPlay) _releaseExternal(reason: 'local_queue');

    _originalQueue = List.from(items);
    _shuffleEnabled = shuffle;

    if (shuffle) {
      // Start at startIndex as first item, shuffle the rest
      final safeStart = (startIndex >= 0 && startIndex < items.length) ? startIndex : 0;
      final startItem = items[safeStart];
      final remaining = List<domain.MediaItem>.from(items)..removeAt(safeStart);
      _fisherYatesShuffle(remaining);
      _playOrderQueue = [startItem, ...remaining];
    } else {
      _playOrderQueue = List.from(items);
    }

    _syncAudioServiceQueue();

    final audioSources = _domainQueue.map((item) {
      return AudioSource.uri(_audioUri(item.uri), tag: item.id);
    }).toList();

    try {
      // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
      await _player.setAudioSource(
        _playlistSource!,
        initialIndex: shuffle ? 0 : startIndex,
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

  // --- external source -----------------------------------------------------

  @override
  void setExternalSource(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    final previous = _external;
    if (previous != null && !identical(previous, delegate)) {
      _safeDelegateCall(previous.onExternalSourceReleased);
    }
    _external = delegate;
    if (previous == null) {
      DiagnosticsService.instance.logEvent('external_source_start');
      // Local music pauses (it stays queued and resumes from its own controls).
      _wantPlaying = false;
      _resumeOnFocusGain = false;
      _debounceSkipPlayTimer?.cancel();
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
    final previous = _externalMedia;
    _externalMedia = s;

    final item = MediaItem(
      id: s.id,
      title: s.title.isEmpty ? 'YouTube' : s.title,
      artist: (s.artist == null || s.artist!.isEmpty) ? null : s.artist,
      album: 'YouTube',
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

  // --- transport: system entry points route to the external source -------

  /// In-app "play" for the local queue (Music, Now Playing, local mini player).
  Future<void> playLocal() {
    _releaseExternal(reason: 'local_play');
    return _playLocalImpl(caller: 'in_app');
  }

  /// In-app "pause" for the local queue.
  Future<void> pauseLocal() => _pauseLocalImpl();

  /// In-app seek in the local track.
  Future<void> seekLocal(Duration position) => _seekLocalImpl(position);

  /// In-app "next" for the local queue (starts local playback).
  Future<void> skipToNextLocal() {
    _releaseExternal(reason: 'local_next');
    return _skipToNextLocalImpl();
  }

  /// In-app "previous" for the local queue (starts local playback).
  Future<void> skipToPreviousLocal() {
    _releaseExternal(reason: 'local_previous');
    return _skipToPreviousLocalImpl();
  }

  @override
  Future<void> play({String? caller}) {
    final ext = _external;
    if (ext != null) {
      DiagnosticsService.instance.logEvent('play', {'caller': caller ?? 'system', 'target': 'external'});
      return ext.externalPlay();
    }
    return _playLocalImpl(caller: caller);
  }

  Future<void> _playLocalImpl({String? caller}) async {
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
  Future<void> pause({String? reason}) {
    final ext = _external;
    if (ext != null) {
      DiagnosticsService.instance.logEvent('pause', {'reason': reason ?? 'user', 'target': 'external'});
      return ext.externalPause();
    }
    return _pauseLocalImpl(reason: reason);
  }

  Future<void> _pauseLocalImpl({String? reason}) async {
    _wantPlaying = false;
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

  Future<void> _seekLocalImpl(Duration position) async {
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

      final src = _playlistSource;
      if (src != null && currentItem != null && src.length == _playOrderQueue.length) {
        // Seamless: the playing track keeps playing, only its neighbours change.
        await _reorderAroundCurrent(src, currIdx, newIndex);
        // The player moves its own index along; this only fires if it did not.
        if ((_player.currentIndex ?? -1) != newIndex) {
          await _player.seek(currentPos, index: newIndex);
        }
      } else {
        final audioSources = _playOrderQueue.map(_sourceFor).toList();
        // ignore: deprecated_member_use
        _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(
          _playlistSource!,
          initialIndex: newIndex,
          initialPosition: currentPos,
        );
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
    if (_external != null) return; // shuffle / repeat are not shown for YouTube
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
      await _skipToNextLocalImpl();
      return;
    }
    _syncCurrentAudioServiceMediaItem();
    _broadcastAudioServiceState();
    _notifyDomainState();
  }

  void _schedulePlayAfterSkips(String caller) {
    _debounceSkipPlayTimer?.cancel();
    if (_pendingSkips <= 0) {
      if (_wantPlaying) {
        _safeStartPlayerPlay(caller);
      }
    } else {
      _debounceSkipPlayTimer = Timer(const Duration(milliseconds: 150), () {
        if (_pendingSkips <= 0 && _wantPlaying) {
          _safeStartPlayerPlay(caller);
        }
      });
    }
  }

  @override
  Future<void> skipToNext() {
    final ext = _external;
    if (ext != null) return ext.externalSkipToNext();
    return _skipToNextLocalImpl();
  }

  Future<void> _skipToNextLocalImpl() {
    _userInteractedSinceNoisy = true;
    _wantPlaying = true; // Match Spotify: skipping starts playing
    _pendingSkips++;
    final caller = _formatCaller();

    return _synchronized(() async {
      try {
        if (_domainQueue.isEmpty) return;

        final beforeIdx = _player.currentIndex ?? -1;
        final beforeId = (beforeIdx >= 0 && beforeIdx < _domainQueue.length) ? _domainQueue[beforeIdx].id : null;
        DiagnosticsService.instance.logEvent('skip_start', {
          'action': 'skipToNext',
          'caller': caller,
          'beforeTrackId': beforeId,
          'beforeQueuePosition': beforeIdx,
        });

        if (_player.hasNext) {
          await _player.seekToNext();
        } else {
          // At the end of queue
          if (_repeatMode == domain.PlaybackRepeatMode.all) {
            if (_shuffleEnabled && _domainQueue.length > 1) {
              // Reshuffle at wrap: ensure the new cycle does not start with the track that just played
              final lastPlayedItem = (beforeIdx >= 0 && beforeIdx < _domainQueue.length)
                  ? _domainQueue[beforeIdx]
                  : null;
              final reshuffled = List<domain.MediaItem>.from(_originalQueue);
              _fisherYatesShuffle(reshuffled);

              // If the first item matches the last played item, swap with another item
              if (lastPlayedItem != null && reshuffled.first.id == lastPlayedItem.id && reshuffled.length > 1) {
                final temp = reshuffled[0];
                reshuffled[0] = reshuffled[1];
                reshuffled[1] = temp;
              }

              _playOrderQueue = reshuffled;
              final audioSources = _playOrderQueue.map((item) {
                return AudioSource.uri(_audioUri(item.uri), tag: item.id);
              }).toList();
              // ignore: deprecated_member_use
              _playlistSource = ConcatenatingAudioSource(children: audioSources);
              await _player.setAudioSource(
                _playlistSource!,
                initialIndex: 0,
                initialPosition: Duration.zero,
              );
            } else {
              // Wrap around to start of queue
              await _player.seek(Duration.zero, index: 0);
            }
          } else {
            // Repeat off -> stop at last track and show paused state at start of queue
            _wantPlaying = false;
            DiagnosticsService.instance.logEvent('queue_ended', {'action': 'paused_at_start'});
            await _player.pause();
            await _player.seek(Duration.zero, index: 0);
          }
        }

        final afterIdx = _player.currentIndex ?? -1;
        final afterId = (afterIdx >= 0 && afterIdx < _domainQueue.length) ? _domainQueue[afterIdx].id : null;
        DiagnosticsService.instance.logEvent('skip_complete', {
          'action': 'skipToNext',
          'afterTrackId': afterId,
          'afterQueuePosition': afterIdx,
        });

        _syncCurrentAudioServiceMediaItem();
        _broadcastAudioServiceState();
        _notifyDomainState();
      } catch (e) {
        DiagnosticsService.instance.logEvent('player_error', {'source': 'skipToNext'});
        debugPrint('Error in skipToNext: $e');
      } finally {
        _pendingSkips = (_pendingSkips - 1).clamp(0, 9999);
        _schedulePlayAfterSkips('skip_to_next');
      }
    }, 'skipToNext');
  }

  @override
  Future<void> skipToPrevious() {
    final ext = _external;
    if (ext != null) return ext.externalSkipToPrevious();
    return _skipToPreviousLocalImpl();
  }

  Future<void> _skipToPreviousLocalImpl() {
    _userInteractedSinceNoisy = true;
    _wantPlaying = true; // Match Spotify: skipping starts playing
    _pendingSkips++;
    final caller = _formatCaller();

    return _synchronized(() async {
      try {
        if (_domainQueue.isEmpty) return;

        final beforeIdx = _player.currentIndex ?? -1;
        final beforeId = (beforeIdx >= 0 && beforeIdx < _domainQueue.length) ? _domainQueue[beforeIdx].id : null;
        DiagnosticsService.instance.logEvent('skip_start', {
          'action': 'skipToPrevious',
          'caller': caller,
          'beforeTrackId': beforeId,
          'beforeQueuePosition': beforeIdx,
        });

        if (_player.position > const Duration(seconds: 3)) {
          await _seekLocalImpl(Duration.zero);
          return;
        }

        if (_player.hasPrevious) {
          await _player.seekToPrevious();
        } else {
          // At start of queue
          if (_repeatMode == domain.PlaybackRepeatMode.all) {
            final lastIdx = _domainQueue.length - 1;
            await _player.seek(Duration.zero, index: lastIdx);
          } else {
            await _seekLocalImpl(Duration.zero);
          }
        }

        final afterIdx = _player.currentIndex ?? -1;
        final afterId = (afterIdx >= 0 && afterIdx < _domainQueue.length) ? _domainQueue[afterIdx].id : null;
        DiagnosticsService.instance.logEvent('skip_complete', {
          'action': 'skipToPrevious',
          'afterTrackId': afterId,
          'afterQueuePosition': afterIdx,
        });

        _syncCurrentAudioServiceMediaItem();
        _broadcastAudioServiceState();
        _notifyDomainState();
      } catch (e) {
        DiagnosticsService.instance.logEvent('player_error', {'source': 'skipToPrevious'});
        debugPrint('Error in skipToPrevious: $e');
      } finally {
        _pendingSkips = (_pendingSkips - 1).clamp(0, 9999);
        _schedulePlayAfterSkips('skip_to_previous');
      }
    }, 'skipToPrevious');
  }

  void _handlePlaybackCompleted() async {
    if (_repeatMode == domain.PlaybackRepeatMode.one) {
      await _seekLocalImpl(Duration.zero);
      _wantPlaying = true;
      _safeStartPlayerPlay('repeat_one_completed');
    } else if (_player.hasNext) {
      await _skipToNextLocalImpl();
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
  Future<void> playNext(domain.MediaItem item) {
    _userInteractedSinceNoisy = true;
    if (_domainQueue.isEmpty) {
      return loadQueue([item]);
    }
    return _synchronized(() async {
      final currIdx = _player.currentIndex ?? 0;
      int insertIndex = currIdx + 1;
      _playOrderQueue.insert(insertIndex, item);
      // Keep the original (un-shuffled) order in step, duplicates included.
      final currentItem = currIdx < _playOrderQueue.length ? _playOrderQueue[currIdx] : null;
      final origIdx = currentItem == null ? -1 : _originalQueue.indexWhere((m) => m.id == currentItem.id);
      if (origIdx >= 0) {
        _originalQueue.insert(origIdx + 1, item);
      } else {
        _originalQueue.add(item);
      }
      final source = AudioSource.uri(_audioUri(item.uri), tag: item.id);
      if (_playlistSource != null) {
        await _playlistSource!.insert(insertIndex, source);
      } else {
        final audioSources = _domainQueue.map((m) => AudioSource.uri(_audioUri(m.uri), tag: m.id)).toList();
        // ignore: deprecated_member_use
        _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(_playlistSource!, initialIndex: currIdx, initialPosition: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'playNext');
  }

  Future<void> addToQueue(domain.MediaItem item) {
    _userInteractedSinceNoisy = true;
    if (_domainQueue.isEmpty) {
      return loadQueue([item]);
    }
    return _synchronized(() async {
      final currIdx = _player.currentIndex ?? 0;
      _playOrderQueue.add(item);
      _originalQueue.add(item);
      final source = AudioSource.uri(_audioUri(item.uri), tag: item.id);
      if (_playlistSource != null) {
        await _playlistSource!.add(source);
      } else {
        final audioSources = _domainQueue.map((m) => AudioSource.uri(_audioUri(m.uri), tag: m.id)).toList();
        // ignore: deprecated_member_use
        _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(_playlistSource!, initialIndex: currIdx, initialPosition: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'addToQueue');
  }

  @override
  Future<void> removeQueueItemAt(int index) {
    _userInteractedSinceNoisy = true;
    if (index < 0 || index >= _domainQueue.length) return Future.value();

    return _synchronized(() async {
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
        if (_external == null) mediaItem.add(null);
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
          final audioSources = _domainQueue.map((m) => AudioSource.uri(_audioUri(m.uri), tag: m.id)).toList();
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
    }, 'removeQueueItemAt');
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) {
    _userInteractedSinceNoisy = true;
    if (oldIndex < 0 || oldIndex >= _domainQueue.length || newIndex < 0 || newIndex >= _domainQueue.length) {
      return Future.value();
    }

    return _synchronized(() async {
      final item = _playOrderQueue.removeAt(oldIndex);
      _playOrderQueue.insert(newIndex, item);

      if (!_shuffleEnabled) {
        final origItem = _originalQueue.removeAt(oldIndex);
        _originalQueue.insert(newIndex, origItem);
      }

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

        final audioSources = _domainQueue.map((m) => AudioSource.uri(_audioUri(m.uri), tag: m.id)).toList();
        // ignore: deprecated_member_use
        _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await _player.setAudioSource(_playlistSource!, initialIndex: updatedIdx, initialPosition: _player.position);
      }

      _syncAudioServiceQueue();
      _broadcastAudioServiceState();
      _notifyDomainState();
    }, 'reorderQueue');
  }

  Future<void> dispose() async {
    DiagnosticsService.instance.logEvent('service_stop');
    _external = null;
    await _player.dispose();
    await _errorController.close();
    await _domainStateController.close();
    await _externalController.close();
  }
}
