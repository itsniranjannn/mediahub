// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../data/downloads/youtube_link.dart';
import '../../personal/extractor_backend.dart';

/// Fast metadata and format resolver for YouTube links using [YoutubeExplode].
///
/// Fetches title, author, duration, thumbnail and the full list of video and audio
/// formats over direct HTTPS in ~1s without invoking the native Python/yt-dlp runtime.
/// The resulting [ExtractorMetadata] feeds seamlessly into [FormatSelectionSheet]
/// and [ExtractorDownloadRunner] so the background service runs the chosen quality with yt-dlp.
class FastYoutubeExtractorResolver {
  FastYoutubeExtractorResolver._();

  static const Duration _timeout = Duration(seconds: 6);

  /// For unit/widget tests: allows mocking or replacing the resolver function.
  static Future<ExtractorMetadata?> Function(Uri uri)? overrideResolver;

  /// How long the details (title, length) may lag behind a finished
  /// manifest before the qualities show without them.
  static const Duration detailsGrace = Duration(milliseconds: 800);

  /// Waits for [manifest] (its error is thrown) and then at most [grace]
  /// more for [details]; details that fail or lag come back as null. Both
  /// futures are already running, so neither waits for the other.
  static Future<(M, D?)> manifestWithDetails<M, D>(
    Future<M> manifest,
    Future<D> details, {
    Duration grace = detailsGrace,
  }) async {
    // Handled now, so a details error while the manifest is awaited is
    // never reported as unhandled.
    final safeDetails = details.then<D?>((d) => d, onError: (Object _) => null);
    final m = await manifest;
    final d = await safeDetails.timeout(grace, onTimeout: () => null);
    return (m, d);
  }

  /// Resolves an [ExtractorMetadata] for [uri] if it is a valid YouTube video link.
  /// Returns null if [uri] is not a YouTube link.
  static Future<ExtractorMetadata?> resolve(Uri uri) async {
    if (overrideResolver != null) {
      return overrideResolver!(uri);
    }

    final link = YoutubeLink.parse(uri);
    if (link == null) return null;
    final videoId = link.videoId;
    if (!YoutubeLink.isValidId(videoId)) return null;

    final yt = YoutubeExplode();
    try {
      // Both requests start at once. Only the stream manifest is required:
      // a details lookup that fails or lags no longer throws the whole fast
      // result away (which sent the lookup on to the much slower yt-dlp).
      final (manifest, video) = await manifestWithDetails(
        yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.androidVr,
            YoutubeApiClient.android,
            YoutubeApiClient.androidSdkless,
          ],
        ).timeout(_timeout),
        yt.videos.get(videoId).timeout(_timeout),
      );

      final formats = <ExtractorFormat>[];

      // Muxed streams
      for (final s in manifest.muxed) {
        formats.add(ExtractorFormat(
          formatId: s.tag.toString(),
          ext: s.container.name,
          formatNote: '${s.videoResolution.height}p',
          hasVideo: true,
          hasAudio: true,
          height: s.videoResolution.height,
          width: s.videoResolution.width,
          filesize: s.size.totalBytes,
          tbr: s.bitrate.kiloBitsPerSecond,
          vcodec: s.videoCodec,
          acodec: s.audioCodec,
        ));
      }

      // Video-only streams (e.g. 1080p, 1440p, 4K)
      for (final s in manifest.videoOnly) {
        formats.add(ExtractorFormat(
          formatId: s.tag.toString(),
          ext: s.container.name,
          formatNote: '${s.videoResolution.height}p',
          hasVideo: true,
          hasAudio: false,
          height: s.videoResolution.height,
          width: s.videoResolution.width,
          filesize: s.size.totalBytes,
          tbr: s.bitrate.kiloBitsPerSecond,
          vcodec: s.videoCodec,
          fps: s.framerate.framesPerSecond.toDouble(),
        ));
      }

      // Audio-only streams
      for (final s in manifest.audioOnly) {
        formats.add(ExtractorFormat(
          formatId: s.tag.toString(),
          ext: s.container.name,
          formatNote: '${s.bitrate.kiloBitsPerSecond.round()}k',
          hasVideo: false,
          hasAudio: true,
          height: 0,
          width: 0,
          filesize: s.size.totalBytes,
          abr: s.bitrate.kiloBitsPerSecond,
          acodec: s.audioCodec,
        ));
      }

      return ExtractorMetadata(
        id: videoId,
        title: (video?.title.trim().isNotEmpty ?? false) ? video!.title.trim() : 'YouTube Video',
        uploader: video?.author.trim() ?? '',
        durationSec: video?.duration?.inSeconds ?? 0,
        thumbnailUrl: video?.thumbnails.highResUrl ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        formats: formats,
        extractorArgs: 'youtube:player_client=android_vr',
      );
    } finally {
      yt.close();
    }
  }
}
