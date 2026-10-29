import 'package:flutter/widgets.dart';

abstract class VideoEngine {
  Future<void> initialize(String uri);
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> dispose();

  Duration get position;
  Duration get duration;
  bool get isPlaying;
  bool get isInitialized;
  Size get videoSize;
  double get aspectRatio;

  Stream<Duration> get positionStream;
  Stream<bool> get isPlayingStream;
  Stream<String?> get errorStream;

  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain});
}
