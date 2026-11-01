import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';

class MediaItemTile extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final double? progress; // 0.0 to 1.0 for videos

  const MediaItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.onPlayNext,
    this.onAddToQueue,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = item.mediaType == MediaType.video;

    final displayTitle = isVideo
        ? item.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '')
        : item.title;

    final videoInfo = item.width != null && item.height != null && item.width! > 0 && item.height! > 0
        ? '${item.width}x${item.height}'
        : (item.durationMs > 0
            ? formatDuration(Duration(milliseconds: item.durationMs))
            : 'Video');

    return Semantics(
      label: '$displayTitle, ${item.artist ?? 'Unknown artist'}',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg16,
          vertical: AppSpacing.xs4,
        ),
        onTap: onTap,
        leading: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ArtworkThumbnail(
              uri: item.uri,
              size: 48,
              borderRadius: AppSpacing.buttonRadius,
              placeholderIcon: isVideo ? Icons.movie_outlined : Icons.music_note_rounded,
            ),
            if (isVideo && progress != null && progress! > 0)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppSpacing.buttonRadius)),
                child: SizedBox(
                  width: 48,
                  height: 3,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            if (item.source == 'download') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withAlpha(100), width: 0.8),
                ),
                child: const Text(
                  'Downloaded',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            Expanded(
              child: Text(
                displayTitle,
                style: AppTypography.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          isVideo
              ? '$videoInfo • ${formatFileSize(item.sizeBytes)}'
              : (item.artist ?? 'Unknown Artist'),
          style: AppTypography.metadata,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.durationMs > 0
                  ? formatDuration(Duration(milliseconds: item.durationMs))
                  : (isVideo ? formatFileSize(item.sizeBytes) : '--:--'),
              style: AppTypography.tabularFigures,
            ),
            if (!isVideo && (onPlayNext != null || onAddToQueue != null)) ...[
              const SizedBox(width: AppSpacing.xs4),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textMuted,
                ),
                tooltip: 'Track actions',
                onSelected: (val) {
                  if (val == 'play_next') {
                    onPlayNext?.call();
                  } else if (val == 'add_to_queue') {
                    onAddToQueue?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onPlayNext != null)
                    const PopupMenuItem(
                      value: 'play_next',
                      child: Text('Play next'),
                    ),
                  if (onAddToQueue != null)
                    const PopupMenuItem(
                      value: 'add_to_queue',
                      child: Text('Add to queue'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
