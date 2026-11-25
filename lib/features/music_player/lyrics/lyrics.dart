// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';

/// Where a song's lyrics came from.
enum LyricsSource { sidecar, embedded, online }

/// One line of lyrics; [time] is null for plain (unsynced) lyrics.
@immutable
class LyricsLine {
  const LyricsLine(this.time, this.text);

  final Duration? time;
  final String text;

  @override
  bool operator ==(Object other) => other is LyricsLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LyricsLine($time, $text)';
}

/// A song's lyrics, synced (every line has a time) or plain.
@immutable
class Lyrics {
  const Lyrics(this.lines, {required this.source});

  final List<LyricsLine> lines;
  final LyricsSource source;

  bool get isSynced => lines.isNotEmpty && lines.every((l) => l.time != null);

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);

  /// The line sung at [position] (the last one that started), or -1 before
  /// the first. Plain lyrics: always -1.
  int lineAt(Duration position) {
    if (!isSynced) return -1;
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time! <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// Parses [text]: LRC (`[mm:ss.xx]` stamps, several per line allowed,
  /// `[offset:+/-ms]`, metadata tags such as `[ar:]` ignored) when it has
  /// stamps, otherwise plain lines. Null when there is nothing to show.
  static Lyrics? parse(String text, {required LyricsSource source}) {
    if (text.length > maxChars) text = text.substring(0, maxChars);
    final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final timed = <LyricsLine>[];
    final plain = <LyricsLine>[];
    var offsetMs = 0;
    var sawStamp = false;
    for (final line in raw) {
      var rest = line;
      final stamps = <Duration>[];
      while (true) {
        final m = _tag.matchAsPrefix(rest);
        if (m == null) break;
        final inner = m.group(1)!;
        final stamp = _stamp.firstMatch(inner);
        if (stamp != null) {
          stamps.add(_toDuration(stamp));
        } else {
          final off = _offset.firstMatch(inner);
          if (off != null) offsetMs = int.tryParse(off.group(1)!) ?? 0;
        }
        rest = rest.substring(m.end);
      }
      final words = rest.trim();
      if (stamps.isNotEmpty) {
        sawStamp = true;
        for (final t in stamps) {
          timed.add(LyricsLine(t, words));
        }
      } else if (line.trim().isNotEmpty && !_tag.hasMatch(line.trim())) {
        plain.add(LyricsLine(null, line.trim()));
      }
    }
    Lyrics? result;
    if (sawStamp) {
      // A positive offset makes the lines come earlier (LRC convention).
      final shifted = timed.map((l) {
        final ms = l.time!.inMilliseconds - offsetMs;
        return LyricsLine(Duration(milliseconds: ms < 0 ? 0 : ms), l.text);
      }).toList()
        ..sort((a, b) => a.time!.compareTo(b.time!));
      result = Lyrics(List.unmodifiable(shifted), source: source);
    } else if (plain.isNotEmpty) {
      result = Lyrics(List.unmodifiable(plain), source: source);
    }
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// Lyrics longer than this are cut (a damaged tag cannot make a huge list).
  static const int maxChars = 200000;

  static final RegExp _tag = RegExp(r'\[([^\]\[]*)\]');
  static final RegExp _stamp = RegExp(r'^\s*(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\s*$');
  static final RegExp _offset = RegExp(r'^\s*offset\s*:\s*([+-]?\d+)\s*$', caseSensitive: false);

  static Duration _toDuration(RegExpMatch m) {
    final min = int.parse(m.group(1)!);
    final sec = int.parse(m.group(2)!);
    final frac = m.group(3);
    var ms = 0;
    if (frac != null) {
      // ".5" = 500 ms, ".05" = 50 ms, ".005" = 5 ms.
      ms = int.parse(frac.padRight(3, '0'));
    }
    return Duration(minutes: min, seconds: sec, milliseconds: ms);
  }
}
