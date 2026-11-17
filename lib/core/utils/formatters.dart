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

/// Like [formatDuration] but without the leading zero of the first group
/// (`4:05`, `12:30`, `1:02:03`, `10:04:05`): the one format for every
/// visible clock (song rows, player seek labels, duration badges).
String formatClock(Duration duration) {
  final text = formatDuration(duration);
  // Five characters is always mm:ss and eight always hh:mm:ss (hours under
  // 100), negative durations included, which formatDuration shows as 00:00.
  if ((text.length == 5 || text.length == 8) && text.startsWith('0')) return text.substring(1);
  return text;
}

/// Formats byte size into human-readable string (e.g., `12.5 MB`).
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor();
  final number = bytes / pow(1024, i);
  return '${number.toStringAsFixed(1)} ${suffixes[i]}';
}

/// Zero-width space: an invisible point where a line may break.
const String _kWrapPoint = '​';

/// Display-only copy of a title that may wrap after `_`, so file-style names
/// such as `Audit_Long_Tone_5min` break between words ("Audit_Long_Tone_" /
/// "5min") instead of in the middle of one ("…5m" / "in"). Use it only for the
/// visible text of titles that get more than one line; never store, search or
/// compare the result, and keep the original title for semantics labels.
String breakableTitle(String title) {
  if (!title.contains('_')) return title;
  return title.replaceAll('_', '_$_kWrapPoint');
}
