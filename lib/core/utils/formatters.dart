import 'dart:math';

/// Formats a Duration into `mm:ss` or `hh:mm:ss` string format.
String formatDuration(Duration duration) {
  if (duration.isNegative) return '00:00';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  final minutesStr = minutes.toString().padLeft(2, '0');
  final secondsStr = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    final hoursStr = hours.toString().padLeft(2, '0');
    return '$hoursStr:$minutesStr:$secondsStr';
  }
  return '$minutesStr:$secondsStr';
}

/// Formats byte size into human-readable string (e.g., `12.5 MB`).
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor();
  final number = bytes / pow(1024, i);
  return '${number.toStringAsFixed(1)} ${suffixes[i]}';
}
