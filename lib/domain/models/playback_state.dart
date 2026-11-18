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
  final List<MediaItem> originalQueue;
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
    this.originalQueue = const [],
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
    List<MediaItem>? originalQueue,
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
      originalQueue: originalQueue ?? this.originalQueue,
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
          listEquals(originalQueue, other.originalQueue) &&
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
        Object.hashAll(originalQueue),
        queueIndex,
        position,
        duration,
        isPlaying,
        repeatMode,
        shuffle,
        speed,
      );
}

/// The sleep timer (docs/DESIGN.md 7.8): off, a countdown to [endsAt], or
/// "end of song". [remaining] is the time left when this status was taken;
/// [fading] while the volume goes down before the pause.
@immutable
class SleepTimerStatus {
  final DateTime? endsAt;
  final Duration? remaining;
  final bool endOfTrack;
  final bool fading;

  const SleepTimerStatus({this.endsAt, this.remaining, this.endOfTrack = false, this.fading = false});

  /// No timer.
  static const SleepTimerStatus off = SleepTimerStatus();

  /// The presets the sleep timer sheet offers, besides "end of song".
  static const List<Duration> presets = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  bool get isActive => endsAt != null || endOfTrack || fading;

  @override
  bool operator ==(Object other) =>
      other is SleepTimerStatus &&
      other.endsAt == endsAt &&
      other.remaining == remaining &&
      other.endOfTrack == endOfTrack &&
      other.fading == fading;

  @override
  int get hashCode => Object.hash(endsAt, remaining, endOfTrack, fading);

  @override
  String toString() => 'SleepTimerStatus(endsAt: $endsAt, remaining: $remaining, endOfTrack: $endOfTrack, fading: $fading)';
}
