// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import '../../data/database/app_database.dart';
import '../../data/downloads/download_engine.dart';
import '../../data/downloads/youtube_link.dart';
import '../../personal/format_options.dart';
import 'youtube_direct_resolver.dart';

/// The last resort for a YouTube web-link download on Android: yt-dlp could
/// not save it (even after updating itself), so the file YouTube serves
/// directly is queued instead, the same way the YouTube path without yt-dlp
/// does ([YoutubeDirectResolver]). That is a video with sound, often only
/// 360p, or M4A audio. The new download's quality chip says it was saved at
/// a lower quality ("360p · lower quality").
///
/// Used as the runner's `ExtractorFallback` (see `ExtractorDownloadRunner`).
class ExtractorYoutubeFallback {
  ExtractorYoutubeFallback({
    required this.engine,
    required this.resolver,
    this.timeout = const Duration(seconds: 60),
    String Function()? newId,
  }) : _newId = newId ?? (() => DateTime.now().microsecondsSinceEpoch.toString());

  /// The direct-link engine that downloads the replacement.
  final DownloadEngine engine;

  /// Read only when needed (never at app start).
  final YoutubeDirectResolver Function() resolver;

  /// Longest the lookup may take.
  final Duration timeout;

  /// Id of the new download (digits only, like the engine's other downloads).
  final String Function() _newId;

  /// Added to the quality chip of a replacement download.
  static const String lowerQualityNote = 'lower quality';

  /// "360p · lower quality", "Audio 128 kbps · lower quality".
  static String qualityLabelFor(YoutubeDirectChoice choice) => '${choice.qualityLabel} · $lowerQualityNote';

  /// The file closest to what was asked for: the audio file for an audio
  /// download; otherwise the highest video with sound that is not above
  /// [maxHeight] (or the lowest one above it when none fits). Null when
  /// YouTube offers no file of that kind.
  static YoutubeDirectChoice? pick(List<YoutubeDirectChoice> choices, {required bool audio, int? maxHeight}) {
    if (audio) {
      for (final c in choices) {
        if (c.isAudio) return c;
      }
      return null;
    }
    final videos = choices.where((c) => !c.isAudio).toList()
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    if (videos.isEmpty) return null;
    if (maxHeight == null) return videos.first;
    for (final v in videos) {
      if ((v.height ?? 0) <= maxHeight) return v;
    }
    return videos.last;
  }

  /// Queues the replacement for [row]. True when it was queued; false when
  /// [row] is not a YouTube video, YouTube offers nothing suitable, the lookup
  /// failed, or [stillWanted] turned false (the user paused or cancelled).
  Future<bool> call(DownloadEntry row, {required bool Function() stillWanted}) async {
    final link = YoutubeLink.tryParse(row.url);
    if (link == null) return false;
    final title = row.displayName.trim().isNotEmpty ? row.displayName.trim() : 'YouTube video';

    final YoutubeDirectResult result;
    try {
      result = await resolver().resolve(link, titleHint: title).timeout(timeout);
    } catch (_) {
      return false;
    }

    final audio = row.kind == 'audio' || (row.audioFormat ?? '').isNotEmpty;
    final choice = pick(result.choices, audio: audio, maxHeight: FormatOptions.maxHeightOf(row.formatSelector));
    if (choice == null) return false;
    // Checked again here: only YouTube's media servers, over https.
    final uri = YoutubeLink.trustedStreamUri(choice.uri.toString());
    if (uri == null) return false;
    if (!stillWanted()) return false;

    final thumb = row.thumbnailUrl;
    await engine.enqueueDownload(
      id: _newId(),
      url: uri,
      displayName: title,
      suggestedFileName: '$title.${choice.fileExtension}',
      kind: choice.isAudio ? 'audio' : 'video',
      thumbnailUrl: thumb != null && thumb.isNotEmpty ? thumb : link.thumbnailUrl,
      qualityLabel: qualityLabelFor(choice),
      uploader: row.uploader ?? (result.details.author.isNotEmpty ? result.details.author : null),
      durationSec: row.durationSec ?? result.details.duration?.inSeconds,
      totalBytes: choice.sizeBytes,
    );
    return true;
  }
}
