import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
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

    return Semantics(
      label: '${item.title}, ${item.artist ?? 'Unknown artist'}',
      button: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg16,
          vertical: AppSpacing.xs4,
        ),
        onTap: onTap,
        leading: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              child: Icon(
                isVideo ? Icons.movie_outlined : Icons.music_note_rounded,
                color: isVideo ? AppColors.accent : AppColors.primary,
                size: 24,
              ),
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
        title: Text(
          item.title,
          style: AppTypography.body,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isVideo
              ? '${formatFileSize(item.sizeBytes)} • ${item.artist ?? 'Local Video'}'
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
                      child: Row(
                        children: [
                          Icon(Icons.playlist_play_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Play next'),
                        ],
                      ),
                    ),
                  if (onAddToQueue != null)
                    const PopupMenuItem(
                      value: 'add_to_queue',
                      child: Row(
                        children: [
                          Icon(Icons.queue_music_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Add to queue'),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
