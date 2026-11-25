// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../personal/format_options.dart';
import '../music_player/playback_notifier.dart';

/// The sound quality a download record knows, for a song's Details
/// ("MP3 · 320 kbps") and its row ("320 kbps").
class DownloadAudioQuality {
  const DownloadAudioQuality({required this.codec, this.kbps});

  /// "MP3", "M4A", "Opus" ...; null when only the bitrate is known.
  final String? codec;
  final int? kbps;

  /// "MP3 · 320 kbps", "MP3", "128 kbps".
  String get label => [
        ?codec,
        if (kbps != null) "$kbps kbps",
      ].join(' · ');

  /// The row's short form: the bitrate, else the codec.
  String get short => kbps != null ? '$kbps kbps' : codec!;

  static final RegExp _labelPattern = RegExp(r'^\s*([A-Za-z0-9]+)\s+(\d+)\s*kbps', caseSensitive: false);

  static String _codecName(String raw) {
    final c = raw.toLowerCase();
    return switch (c) {
      'opus' => 'Opus',
      'audio' => '',
      _ => c.toUpperCase(),
    };
  }

  /// What [row] says about the sound: the conversion it asked for
  /// ("mp3-320") first, then its quality label ("MP3 320 kbps",
  /// "Audio 128 kbps"). Null for a video or a row that says nothing.
  static DownloadAudioQuality? of(DownloadEntry row) {
    final conversion = AudioConversion.parse(row.audioFormat);
    if (conversion != null) {
      final q = conversion.quality;
      final kbps = q == '0' ? null : int.tryParse(q.replaceAll(RegExp('[^0-9]'), ''));
      return DownloadAudioQuality(codec: _codecName(conversion.codec), kbps: kbps);
    }
    if (row.kind == 'video') return null;
    final m = _labelPattern.firstMatch(row.qualityLabel ?? '');
    if (m == null) return null;
    final codec = _codecName(m.group(1)!);
    return DownloadAudioQuality(codec: codec.isEmpty ? null : codec, kbps: int.tryParse(m.group(2)!));
  }

  @override
  bool operator ==(Object other) => other is DownloadAudioQuality && other.codec == codec && other.kbps == kbps;

  @override
  int get hashCode => Object.hash(codec, kbps);
}

/// The sound quality of library item [mediaId]'s download, for its song
/// row. Read once per row (a saved download's quality never changes).
final downloadQualityProvider = FutureProvider.autoDispose.family<DownloadAudioQuality?, String>((ref, mediaId) {
  return downloadQualityFor(ref.watch(appDatabaseProvider), mediaId);
});

/// The quality of library item [mediaId]'s download, read once (Details).
Future<DownloadAudioQuality?> downloadQualityFor(AppDatabase db, String mediaId) async {
  try {
    final rows = await (db.select(db.downloadsTable)..where((t) => t.mediaId.equals(mediaId))).get();
    for (final r in rows) {
      final q = DownloadAudioQuality.of(r);
      if (q != null) return q;
    }
  } catch (_) {}
  return null;
}
