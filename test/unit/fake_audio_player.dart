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
/// - index, state and event changes arrive on the streams asynchronously;
/// - a song in [brokenIds] fails the way just_audio 0.10.6 reports it: the
///   error goes to [errorStream] only (never as an error on
///   playbackEventStream), the player turns idle and inactive, and a load
///   of it also throws a [PlayerException] after that report. A seek while
///   inactive only moves the index (and starts loading again when playing);
///   play while inactive loads the current song again.
class FakeAudioPlayer extends Fake implements AudioPlayer {
  FakeAudioPlayer({this.loadDelay = Duration.zero, this.seekDelay = Duration.zero});

  Duration loadDelay;
  Duration seekDelay;

  /// Song ids (the sources' tags) that cannot play.
  final Set<String> brokenIds = {};

  /// Song ids whose load never finishes (a stream that does not answer)
  /// until [stop] interrupts it, as just_audio's stop does.
  final Set<String> hangingIds = {};
  Completer<void>? _hangingLoad;

  /// Every error sent on [errorStream].
  final List<PlayerException> errorsSent = [];

  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final _indexes = StreamController<int?>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _errors = StreamController<PlayerException>.broadcast();

  /// just_audio drops the native player after an error: the next seek
  /// (while playing) or play loads the song again.
  bool _inactive = false;

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
  Stream<PlayerException> get errorStream => _errors.stream;

  /// The id of the song the player is on.
  String? get currentId {
    final i = currentIndex;
    return i == null ? null : (_children[i] as UriAudioSource).tag as String;
  }

  bool get _currentBroken => brokenIds.contains(currentId);

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
    _inactive = false;
    _state = ProcessingState.loading;
    _position = initialPosition ?? Duration.zero;
    _moveTo(initialIndex ?? 0);
    _emitState();
    await Future<void>.delayed(loadDelay);
    if (hangingIds.contains(currentId)) {
      final hang = _hangingLoad = Completer<void>();
      await hang.future;
      throw PlayerInterruptedException('Loading interrupted');
    }
    if (_currentBroken) {
      // just_audio: the platform's error event first, then the load fails.
      final error = _fail();
      throw error;
    }
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
    if (_inactive) {
      _emitEvent();
      // just_audio: "if (playing && !_active) _setPlatformActive(true)".
      if (_playing) _reactivate();
      return;
    }
    if (_state == ProcessingState.completed) _state = ProcessingState.ready;
    _emitEvent();
  }

  @override
  Future<void> play() async {
    playCalls++;
    if (_playing) return; // just_audio: "if (playing) return;"
    _playing = true;
    _emitState();
    if (_inactive) _reactivate();
  }

  /// The current song fails: error report, then idle and inactive.
  PlayerException _fail({int code = 1, String message = 'Source error'}) {
    final error = PlayerException(code, message, currentIndex);
    errorsSent.add(error);
    if (!_errors.isClosed) _errors.add(error);
    _inactive = true;
    _state = ProcessingState.idle;
    _emitState();
    return error;
  }

  /// just_audio loads the playlist again at the current index.
  void _reactivate() {
    _inactive = false;
    loads++;
    _state = ProcessingState.loading;
    _emitState();
    Timer(loadDelay, () {
      if (_states.isClosed) return;
      if (_currentBroken) {
        _fail();
        return;
      }
      _state = ProcessingState.ready;
      _emitState();
    });
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
    final hang = _hangingLoad;
    _hangingLoad = null;
    if (hang != null && !hang.isCompleted) hang.complete();
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
    final hang = _hangingLoad;
    _hangingLoad = null;
    if (hang != null && !hang.isCompleted) hang.complete();
    await _events.close();
    await _states.close();
    await _indexes.close();
    await _positions.close();
    await _durations.close();
    await _errors.close();
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

  /// The song that plays now fails (a decode error, a refused stream).
  /// [code] 10000000 is just_audio's "Connection aborted" (a newer load
  /// stopped an older one), which is not a failure of the song.
  void failCurrent({int code = 1, String message = 'Source error'}) => _fail(code: code, message: message);

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
      if (_currentBroken) _fail();
    } else if (loopMode == LoopMode.all) {
      _position = Duration.zero;
      _moveTo(0);
      _emitEvent();
      if (_currentBroken) _fail();
    } else {
      _state = ProcessingState.completed;
      _emitState();
    }
  }
}
