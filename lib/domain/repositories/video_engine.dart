// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
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

  /// [fit]: [BoxFit.contain] fits the picture, [BoxFit.cover] fills the
  /// screen (cropping), [BoxFit.fill] stretches it and [BoxFit.none] shows
  /// it at its original pixel size.
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain});
}

/// One audio track of the current video (a language or commentary track).
@immutable
class VideoAudioTrackInfo {
  const VideoAudioTrackInfo({required this.id, required this.label, required this.isSelected});

  final String id;

  /// What the menu shows ("English", "Track 2").
  final String label;
  final bool isSelected;
}

/// Abilities beyond [VideoEngine] that the real engine has and stand-ins
/// (tests, design previews) may leave out. Check with
/// `engine is VideoEngineExtras`; without them the player simply hides the
/// matching controls.
abstract interface class VideoEngineExtras {
  /// The platform player's id (Android uses it to find the video's audio
  /// session for the volume boost); null before [VideoEngine.initialize].
  int? get platformPlayerId;

  /// Fires each time playback reaches the end of the video.
  Stream<void> get completedStream;

  /// Loads sidecar subtitles (a .srt or .vtt file); null removes them.
  /// Returns false when the file cannot be read or parsed.
  Future<bool> setSubtitleFile(String? path);

  /// The subtitle line for the current position ('' when none).
  Stream<String> get captionStream;

  /// The video's audio tracks (empty when there is only the default one or
  /// the platform cannot tell).
  Future<List<VideoAudioTrackInfo>> getAudioTracks();

  Future<void> selectAudioTrack(String id);
}
