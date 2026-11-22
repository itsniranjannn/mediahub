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

  static const Duration _timeout = Duration(seconds: 12);

  /// For unit/widget tests: allows mocking or replacing the resolver function.
  static Future<ExtractorMetadata?> Function(Uri uri)? overrideResolver;

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
      final videoFuture = yt.videos.get(videoId).timeout(_timeout);
      final manifestFuture = yt.videos.streamsClient.getManifest(videoId).timeout(_timeout);

      final video = await videoFuture;
      final manifest = await manifestFuture;

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
        title: video.title.trim().isNotEmpty ? video.title.trim() : 'YouTube Video',
        uploader: video.author.trim(),
        durationSec: video.duration?.inSeconds ?? 0,
        thumbnailUrl: video.thumbnails.highResUrl,
        formats: formats,
        extractorArgs: null,
      );
    } finally {
      yt.close();
    }
  }
}
