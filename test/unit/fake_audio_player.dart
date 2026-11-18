import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A just_audio player double that behaves like the real one where the
/// playback engine depends on it:
///
/// - `seek` is DROPPED while the player is loading (just_audio returns
///   without seeking in that state);
/// - `setAudioSource` goes through `loading` for [loadDelay];
/// - the current item is tracked by its source object, so an insert or a
///   removal before it in the playlist source shifts the index,
///   and removing it moves on to the item that takes its place;
/// - index, state and event changes arrive on the streams asynchronously.
class FakeAudioPlayer extends Fake implements AudioPlayer {
  FakeAudioPlayer({this.loadDelay = Duration.zero, this.seekDelay = Duration.zero});

  Duration loadDelay;
  Duration seekDelay;

  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final _indexes = StreamController<int?>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();

  AudioSource? source;
  IndexedAudioSource? _current;
  int _lastIndex = 0;
  ProcessingState _state = ProcessingState.idle;
  bool _playing = false;
  Duration _position = Duration.zero;
  double _volume = 1;
  double _speed = 1;
  @override
  LoopMode loopMode = LoopMode.off;

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int seekCalls = 0;
  int droppedSeeks = 0;
  int loads = 0;
  final List<double> volumes = [];

  // ignore: deprecated_member_use
  List<IndexedAudioSource> get _children => (source as ConcatenatingAudioSource?)?.children.cast<IndexedAudioSource>() ?? const [];

  /// The song ids the player has loaded, in its order.
  List<String> get loadedIds => [for (final c in _children) (c as UriAudioSource).tag as String];

  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;
  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<int?> get currentIndexStream => _indexes.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  int? get currentIndex {
    final children = _children;
    if (children.isEmpty) return null;
    final at = _current == null ? -1 : children.indexOf(_current!);
    if (at >= 0) {
      _lastIndex = at;
      return at;
    }
    // The current item was removed: the one now in its place plays.
    final next = _lastIndex.clamp(0, children.length - 1);
    _current = children[next];
    _lastIndex = next;
    return next;
  }

  @override
  ProcessingState get processingState => _state;
  @override
  bool get playing => _playing;
  @override
  Duration get position => _position;
  @override
  Duration get bufferedPosition => _position;
  @override
  Duration? get duration => _children.isEmpty ? null : const Duration(minutes: 3);
  @override
  double get speed => _speed;
  @override
  double get volume => _volume;

  void _emitState() {
    if (!_states.isClosed) _states.add(PlayerState(_playing, _state));
    _emitEvent();
  }

  void _emitEvent() {
    if (!_events.isClosed) {
      _events.add(PlaybackEvent(processingState: _state, updatePosition: _position, currentIndex: currentIndex));
    }
  }

  void _moveTo(int index) {
    final before = currentIndex;
    _current = _children[index];
    _lastIndex = index;
    if (before != index && !_indexes.isClosed) _indexes.add(index);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    this.source = source;
    _state = ProcessingState.loading;
    _position = initialPosition ?? Duration.zero;
    _moveTo(initialIndex ?? 0);
    _emitState();
    await Future<void>.delayed(loadDelay);
    _state = ProcessingState.ready;
    _emitState();
    return const Duration(minutes: 3);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCalls++;
    if (_state == ProcessingState.loading) {
      droppedSeeks++; // just_audio: "case ProcessingState.loading: return;"
      return;
    }
    await Future<void>.delayed(seekDelay);
    if (index != null) _moveTo(index);
    _position = position ?? Duration.zero;
    if (_state == ProcessingState.completed) _state = ProcessingState.ready;
    _emitEvent();
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
    _emitState();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
    _emitState();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _playing = false;
    _state = ProcessingState.idle;
    _emitState();
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async => loopMode = mode;

  @override
  Future<void> setSpeed(double speed) async => _speed = speed;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    await _states.close();
    await _indexes.close();
    await _positions.close();
    await _durations.close();
  }

  // --- test controls ----------------------------------------------------------

  /// The player goes into `loading` for [d] (a source reload, a slow file).
  void simulateLoading(Duration d) {
    _state = ProcessingState.loading;
    _emitState();
    Timer(d, () {
      _state = ProcessingState.ready;
      _emitState();
    });
  }

  /// The same player state once more (just_audio repeats states).
  void repeatState() => _emitState();

  set fakePosition(Duration p) {
    _position = p;
    if (!_positions.isClosed) _positions.add(p);
  }

  /// The song ends by itself: the player moves on, or completes after the
  /// last item (repeat off).
  void finishTrack() {
    final index = currentIndex ?? 0;
    if (loopMode == LoopMode.one) {
      fakePosition = const Duration(minutes: 3) - const Duration(milliseconds: 200);
      fakePosition = const Duration(milliseconds: 100);
      return;
    }
    if (index < _children.length - 1) {
      _position = Duration.zero;
      _moveTo(index + 1);
      _emitEvent();
    } else if (loopMode == LoopMode.all) {
      _position = Duration.zero;
      _moveTo(0);
      _emitEvent();
    } else {
      _state = ProcessingState.completed;
      _emitState();
    }
  }
}
