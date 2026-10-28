import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';

class MediaItemTile extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;

  const MediaItemTile({
    super.key,
    required this.item,
    this.onTap,
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
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          child: Icon(
            isVideo ? Icons.movie_outlined : Icons.music_note_rounded,
            color: isVideo ? AppColors.accent : AppColors.primary,
            size: 22,
          ),
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
        trailing: Text(
          item.durationMs > 0
              ? formatDuration(Duration(milliseconds: item.durationMs))
              : (isVideo ? formatFileSize(item.sizeBytes) : '--:--'),
          style: AppTypography.tabularFigures,
        ),
      ),
    );
  }
}
