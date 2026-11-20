import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../data/downloads/download_engine.dart';
import '../../data/downloads/youtube_link.dart';
import '../../data/downloads/youtube_stream_source.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/format_options.dart';
import '../../personal/format_selection_sheet.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';
import 'web_link_download_flow.dart';
import 'youtube_direct_resolver.dart';

/// "Choose a quality, then download" for a YouTube link without yt-dlp: on
/// iOS, and on Android when the web link downloader is off or cannot run.
///
/// Same steps as [WebLinkDownloadFlow]: a "Finding available qualities"
/// dialog with Cancel, the quality sheet, the first-use notice, then the
/// download is queued in the direct-link engine with the video's title,
/// channel and cover, so it lands in the library like any other download.
class YoutubeDirectDownloadFlow {
  YoutubeDirectDownloadFlow._();

  /// Longest the lookup may take before the dialog gives up.
  static const Duration lookupTimeout = Duration(seconds: 60);

  /// Shown under the qualities: why the list is short.
  static String get sheetNote => PlatformInfo.isAndroid
      ? 'YouTube serves these files ready to save. Turn on "Enable web link downloader" in Settings for every quality up to 4K.'
      : 'YouTube serves these files ready to save: video with sound in the qualities it offers, and audio only.';

  /// Shown instead on Android when the web link downloader is on: this sheet
  /// then only appears after yt-dlp could not read the video.
  static const String fallbackSheetNote = "MediaHub couldn't read every quality of this video, so only the files "
      'YouTube serves directly are offered. They are lower quality.';

  /// Plain words for anything the lookup can throw.
  static String friendlyError(Object? error) {
    if (error == null) return YoutubeDirectException.failed.message;
    return YoutubeDirectResolver.friendlyError(error).message;
  }

  /// Looks up [link], lets the user pick a file and queues it.
  ///
  /// [titleHint] (the title the Online tab saw) names the download when the
  /// details lookup fails. [onQueued] runs after the download was added.
  static Future<void> start(
    BuildContext context,
    WidgetRef ref,
    YoutubeLink link, {
    String? titleHint,
    VoidCallback? onQueued,
    VoidCallback? onNotificationDenied,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final resolver = ref.read(youtubeDirectResolverProvider);
    // Read before the first wait (the screen may be gone afterwards).
    final footnote = PlatformInfo.isAndroid && WebLinkDownloadFlow.isAvailable(ref) ? fallbackSheetNote : sheetNote;

    final outcome = await WebLinkDownloadFlow.lookupWithDialog<YoutubeDirectResult>(
      context,
      uri: Uri.parse(link.canonicalUrl),
      timeout: lookupTimeout,
      lookup: () => resolver.resolve(link, titleHint: titleHint),
    );
    if (outcome == null || !context.mounted) return;

    final result = outcome.value;
    if (result == null) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(outcome.error))));
      return;
    }

    final byId = {for (final c in result.choices) c.id: c};
    YoutubeDirectChoice? picked;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FormatSelectionSheet(
        metadata: sheetMetadata(result),
        choices: [for (final c in result.choices) formatChoiceFor(c)],
        footnote: footnote,
        onSelect: (choice) => picked = byId[choice.id],
      ),
    );
    final choice = picked;
    if (choice == null || !context.mounted) return;
    await _queue(context, ref, result, choice, onQueued, onNotificationDenied);
  }

  /// The sheet's header: title, channel, duration and cover.
  static ExtractorMetadata sheetMetadata(YoutubeDirectResult result) {
    final d = result.details;
    return ExtractorMetadata(
      id: result.link.videoId,
      title: d.title,
      uploader: d.author,
      durationSec: d.duration?.inSeconds ?? 0,
      thumbnailUrl: d.thumbnailUrl.isNotEmpty ? d.thumbnailUrl : result.link.thumbnailUrl,
      formats: const [],
    );
  }

  /// One row of the quality sheet for [c].
  static FormatChoice formatChoiceFor(YoutubeDirectChoice c) => FormatChoice(
        id: c.id,
        label: c.label,
        subtitle: c.subtitle,
        isAudio: c.isAudio,
        // Not a yt-dlp download: no format selector.
        selector: '',
        qualityLabel: c.qualityLabel,
        estimatedBytes: c.sizeBytes,
        streamSizes: [if (c.sizeBytes != null) c.sizeBytes!],
      );

  static Future<void> _queue(
    BuildContext context,
    WidgetRef ref,
    YoutubeDirectResult result,
    YoutubeDirectChoice choice,
    VoidCallback? onQueued,
    VoidCallback? onNotificationDenied,
  ) async {
    final granted = await WebLinkDownloadFlow.ensureNotificationPermission();
    if (!context.mounted) return;
    if (!granted) onNotificationDenied?.call();
    if (!await WebLinkDownloadFlow.confirmNotice(context, ref)) return;
    if (!context.mounted) return;

    // Read before the next await: `ref` must not be used once the calling
    // screen is gone, but the queue itself is app-wide and should still start.
    final engine = ref.read(downloadEngineProvider);
    final coordinator = ref.read(downloadQueueCoordinatorProvider.notifier);
    final freeSpace = ref.read(downloadFreeSpaceProvider);
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    // Same rule the engine applies when the download starts, told up front.
    final size = choice.sizeBytes;
    if (size != null) {
      int free;
      try {
        // Null where the phone cannot tell (iOS): no check up front.
        free = await freeSpace() ?? -1;
      } catch (_) {
        free = -1; // unknown: the engine checks again before writing
      }
      if (free >= 0 && free < size + DownloadEngine.freeSpaceMarginBytes) {
        say('Not enough free space: this download needs about ${formatFileSize(size)} '
            'and ${formatFileSize(free)} is free.');
        return;
      }
    }

    final d = result.details;
    final title = d.title.trim().isNotEmpty ? d.title.trim() : 'YouTube video';
    // iPhone: YouTube's link to the file expires after some hours, and a
    // download there often waits (it pauses whenever MediaHub is left). The
    // row keeps the video and the choice, so a resume or retry later finds
    // the file again. Android keeps its rows as they were.
    final linkSource = PlatformInfo.isIOS
        ? YoutubeStreamSource(
            videoId: result.link.videoId,
            choiceId: choice.id,
            itag: YoutubeStreamSource.itagOf(choice.uri),
            resolvedAt: DateTime.now(),
          ).encode()
        : null;
    try {
      await engine.enqueueDownload(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        // Checked again here: only YouTube's media servers, over https.
        url: YoutubeLink.trustedStreamUri(choice.uri.toString()) ??
            (throw const YoutubeDirectException('Unexpected download address.')),
        displayName: title,
        suggestedFileName: '$title.${choice.fileExtension}',
        kind: choice.isAudio ? 'audio' : 'video',
        thumbnailUrl: d.thumbnailUrl.isNotEmpty ? d.thumbnailUrl : result.link.thumbnailUrl,
        qualityLabel: choice.qualityLabel,
        uploader: d.author.isNotEmpty ? d.author : null,
        durationSec: d.duration?.inSeconds,
        totalBytes: size,
        linkSource: linkSource,
      );
    } catch (_) {
      say('Could not add this download. Please try again.');
      return;
    }
    coordinator.trigger();
    onQueued?.call();
    say('Added to Downloads: $title (${choice.qualityLabel})');
  }
}
