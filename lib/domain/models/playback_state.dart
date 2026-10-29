import 'package:flutter/foundation.dart';
import 'media_item.dart';

enum PlaybackRepeatMode {
  off,
  all,
  one,
}

@immutable
class PlaybackState {
  final String? currentItemId;
  final List<MediaItem> queue;
  final int queueIndex;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final PlaybackRepeatMode repeatMode;
  final bool shuffle;
  final double speed;
  final DateTime updatedAt;

  const PlaybackState({
    this.currentItemId,
    this.queue = const [],
    this.queueIndex = -1,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.repeatMode = PlaybackRepeatMode.off,
    this.shuffle = false,
    this.speed = 1.0,
    required this.updatedAt,
  });

  MediaItem? get currentItem {
    if (queueIndex >= 0 && queueIndex < queue.length) {
      return queue[queueIndex];
    }
    return null;
  }

  PlaybackState copyWith({
    String? currentItemId,
    bool clearCurrentItemId = false,
    List<MediaItem>? queue,
    int? queueIndex,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    PlaybackRepeatMode? repeatMode,
    bool? shuffle,
    double? speed,
    DateTime? updatedAt,
  }) {
    return PlaybackState(
      currentItemId: clearCurrentItemId ? null : (currentItemId ?? this.currentItemId),
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffle: shuffle ?? this.shuffle,
      speed: speed ?? this.speed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          runtimeType == other.runtimeType &&
          currentItemId == other.currentItemId &&
          listEquals(queue, other.queue) &&
          queueIndex == other.queueIndex &&
          position == other.position &&
          duration == other.duration &&
          isPlaying == other.isPlaying &&
          repeatMode == other.repeatMode &&
          shuffle == other.shuffle &&
          speed == other.speed;

  @override
  int get hashCode => Object.hash(
        currentItemId,
        Object.hashAll(queue),
        queueIndex,
        position,
        duration,
        isPlaying,
        repeatMode,
        shuffle,
        speed,
      );
}

