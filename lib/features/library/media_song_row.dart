import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../library/media_context_menu.dart';
import '../music_player/playback_notifier.dart';

class MediaSongRow extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final bool showArtwork;
  final Widget? trailing;

  const MediaSongRow({
    super.key,
    required this.item,
    this.onTap,
    this.showArtwork = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentItem = ref.watch(currentMediaItemProvider);
    final isSelected = currentItem?.id == item.id;
    final isMissing = item.availability == MediaAvailability.missing;

    return Semantics(
      label: 'Song: ${item.title} by ${item.artist ?? "Unknown artist"}',
      button: true,
      child: InkWell(
        onTap: isMissing
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File is missing or unavailable on storage')),
                );
              }
            : (onTap ??
                () {
                  ref.read(playbackNotifierProvider.notifier).loadQueue([item]);
                }),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg16,
            vertical: AppSpacing.sm8,
          ),
          child: Row(
            children: [
              if (showArtwork) ...[
                ArtworkThumbnail(
                  uri: item.uri,
                  size: 48,
                  borderRadius: AppSpacing.buttonRadius,
                ),
                const SizedBox(width: AppSpacing.md12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: AppTypography.body.copyWith(
                        color: isMissing
                            ? AppColors.textMuted
                            : isSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.artist ?? "Unknown artist"} • ${formatDuration(Duration(milliseconds: item.durationMs))}${isMissing ? " • (Missing)" : ""}',
                      style: AppTypography.metadata.copyWith(
                        color: isMissing ? AppColors.textMuted : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: item.isFavorite ? AppColors.error : AppColors.textMuted,
                  size: 20,
                ),
                tooltip: item.isFavorite ? 'Remove Favorite' : 'Add Favorite',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () {
                  ref.read(libraryRepositoryProvider).toggleFavorite(item.id);
                },
              ),
              trailing ??
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    tooltip: 'More actions',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => MediaContextMenu.show(context, ref, item),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
