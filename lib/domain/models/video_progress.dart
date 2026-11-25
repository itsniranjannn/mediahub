// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';

@immutable
class VideoProgress {
  final String mediaId;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const VideoProgress({
    required this.mediaId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  /// Calculates resume position:
  /// Resume from saved position, but restart from 0 if within the last 5 seconds (5000 ms).
  static int calculateResumePosition({
    required int savedPositionMs,
    required int totalDurationMs,
  }) {
    if (savedPositionMs <= 0 || totalDurationMs <= 0) return 0;
    if ((totalDurationMs - savedPositionMs) <= 5000) {
      return 0;
    }
    return savedPositionMs;
  }

  VideoProgress copyWith({
    String? mediaId,
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
  }) {
    return VideoProgress(
      mediaId: mediaId ?? this.mediaId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoProgress &&
          runtimeType == other.runtimeType &&
          mediaId == other.mediaId &&
          positionMs == other.positionMs &&
          durationMs == other.durationMs;

  @override
  int get hashCode => Object.hash(mediaId, positionMs, durationMs);
}
