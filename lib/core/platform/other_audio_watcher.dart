import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the phone says about other apps' sound while the music waits to
/// resume (Android: "Resume after other apps").
@immutable
class OtherAudioState {
  const OtherAudioState({required this.otherPlaying, this.inCall = false});

  /// Another app plays music, a video or a game right now. A "not playing"
  /// report only comes once that has been quiet for about 10 seconds (a
  /// buffering pause or YouTube's "Up next" countdown is not a stop).
  final bool otherPlaying;

  /// The phone is ringing or in a call (also a voice or video chat).
  final bool inCall;

  @override
  bool operator ==(Object other) =>
      other is OtherAudioState && other.otherPlaying == otherPlaying && other.inCall == inCall;

  @override
  int get hashCode => Object.hash(otherPlaying, inCall);

  @override
  String toString() => 'OtherAudioState(otherPlaying: $otherPlaying, inCall: $inCall)';
}

/// Watches other apps' playback while the music waits for them to stop.
/// Watching only runs between [start] and [stop], so nothing is listened to
/// while nothing waits.
abstract class OtherAudioWatcher {
  /// Reports, from [start] until [stop]. The first one says how things are
  /// right then.
  Stream<OtherAudioState> get events;

  Future<void> start();

  Future<void> stop();
}

/// Android: AudioManager's playback callback in the app ("mediahub/other_audio",
/// OtherAudioChannel.kt). Other apps' players are anonymous there, but still
/// say whether they play and what for (music, a game, a call).
class MethodChannelOtherAudioWatcher implements OtherAudioWatcher {
  MethodChannelOtherAudioWatcher({MethodChannel? channel}) : _channel = channel ?? defaultChannel;

  static const MethodChannel defaultChannel = MethodChannel('mediahub/other_audio');

  final MethodChannel _channel;
  final _events = StreamController<OtherAudioState>.broadcast();
  bool _handlerSet = false;

  @override
  Stream<OtherAudioState> get events => _events.stream;

  @override
  Future<void> start() async {
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler(handlePlatformCall);
    }
    await _channel.invokeMethod<void>('start');
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Nothing to stop (no native side): nothing is watched either.
    }
  }

  /// A report from the native side.
  @visibleForTesting
  Future<void> handlePlatformCall(MethodCall call) async {
    if (call.method != 'otherAudio') return;
    final state = parse(call.arguments);
    if (state != null && !_events.isClosed) _events.add(state);
  }

  /// `{playing: bool, inCall: bool}`; null for anything else.
  @visibleForTesting
  static OtherAudioState? parse(Object? raw) {
    if (raw is! Map) return null;
    final playing = raw['playing'];
    if (playing is! bool) return null;
    final inCall = raw['inCall'];
    return OtherAudioState(otherPlaying: playing, inCall: inCall is bool && inCall);
  }
}
