// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';

typedef PlayCountCallback = Future<void> Function(String mediaId);

/// Tracks actual played duration of a track to ensure play count and lastPlayed
/// are only updated after the track has played 30 seconds or 50% of its length,
/// whichever is smaller, once per play.
/// Skipping within 5 seconds does not count.
class PlayCountTracker {
  final PlayCountCallback onCountPlay;

  String? _currentTrackId;
  Duration _trackDuration = Duration.zero;
  Duration _accumulatedPlayedTime = Duration.zero;
  Duration? _lastPosition;
  bool _hasCountedCurrentPlay = false;

  PlayCountTracker({required this.onCountPlay});

  String? get currentTrackId => _currentTrackId;
  Duration get accumulatedPlayedTime => _accumulatedPlayedTime;
  bool get hasCountedCurrentPlay => _hasCountedCurrentPlay;

  /// Called when the track changes or resets.
  void onTrackChanged(String? newTrackId, Duration duration) {
    if (_currentTrackId == newTrackId && newTrackId != null) {
      if (_trackDuration == Duration.zero && duration > Duration.zero) {
        _trackDuration = duration;
      }
      return;
    }

    _currentTrackId = newTrackId;
    _trackDuration = duration;
    _accumulatedPlayedTime = Duration.zero;
    _lastPosition = null;
    _hasCountedCurrentPlay = false;
  }

  /// Directly accumulates playback duration.
  void accumulatePlayback(Duration delta) {
    if (_currentTrackId == null || _hasCountedCurrentPlay) return;
    _accumulatedPlayedTime += delta;
    _checkThreshold();
  }

  /// Updates current position from player stream.
  void onPositionUpdated(Duration currentPosition, {required bool isPlaying}) {
    if (_currentTrackId == null || _hasCountedCurrentPlay) {
      _lastPosition = currentPosition;
      return;
    }

    if (!isPlaying) {
      _lastPosition = currentPosition;
      return;
    }

    if (_lastPosition == null) {
      _lastPosition = currentPosition;
      return;
    }

    final delta = currentPosition - _lastPosition!;
    // Normal playback advancement: positive and <= 2 seconds
    if (delta > Duration.zero && delta <= const Duration(seconds: 2)) {
      _accumulatedPlayedTime += delta;
    }

    _lastPosition = currentPosition;
    _checkThreshold();
  }

  void _checkThreshold() {
    if (_hasCountedCurrentPlay || _currentTrackId == null) return;

    // Skipping within 5 seconds does not count
    if (_accumulatedPlayedTime < const Duration(seconds: 5)) {
      return;
    }

    // Threshold: 30 seconds or 50% of track length, whichever is smaller
    final halfDuration = _trackDuration > Duration.zero
        ? Duration(milliseconds: _trackDuration.inMilliseconds ~/ 2)
        : const Duration(seconds: 30);

    final effectiveThreshold = halfDuration < const Duration(seconds: 30)
        ? halfDuration
        : const Duration(seconds: 30);

    if (_accumulatedPlayedTime >= effectiveThreshold) {
      _hasCountedCurrentPlay = true;
      final id = _currentTrackId!;
      onCountPlay(id).catchError((e) {
        debugPrint('[PlayCountTracker] Failed to record play: $e');
      });
    }
  }
}
