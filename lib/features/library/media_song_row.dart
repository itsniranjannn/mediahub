import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/favorite_feedback_button.dart';
import '../library/media_context_menu.dart';
import '../music_player/playback_notifier.dart';

/// One song in a list: rounded artwork, title, artist, duration, a heart and
/// a "more" button. The row that is playing right now is tinted violet.
class MediaSongRow extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final bool showArtwork;
  final Widget? trailing;

  static const double artworkSize = 52;
  static const double _artworkRadius = AppSpacing.md12;

  /// 52 dp artwork + 2 x 6 dp keeps every row at 64 dp.
  static const double _verticalPadding = 6;

  const MediaSongRow({
    super.key,
    required this.item,
    this.onTap,
    this.showArtwork = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only rebuild this row when *its* "now playing" state flips.
    final isSelected = ref.watch(currentMediaItemProvider.select((current) => current?.id == item.id));
    final isMissing = item.availability == MediaAvailability.missing;
    final artist = item.artist ?? 'Unknown artist';

    final titleColor = isMissing
        ? AppColors.textMuted
        : isSelected
            ? AppColors.primary
            : AppColors.textPrimary;

    return Semantics(
      label: 'Song: ${item.title} by $artist',
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.07) : Colors.transparent,
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg16,
              _verticalPadding,
              AppSpacing.xs4,
              _verticalPadding,
            ),
            child: Row(
              children: [
                if (showArtwork) ...[
                  _RowArtwork(item: item, isSelected: isSelected, isMissing: isMissing),
                  const SizedBox(width: AppSpacing.md12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: AppTypography.bodyStrong.copyWith(color: titleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      _MetaLine(item: item, artist: artist, isMissing: isMissing),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm8),
                Text(
                  _trackDuration(item.durationMs),
                  style: AppTypography.tabularFigures.copyWith(color: AppColors.textMuted),
                ),
                FavoriteFeedbackButton(
                  itemId: item.id,
                  isFavorite: item.isFavorite,
                  size: 20,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                ),
                trailing ??
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      color: AppColors.textSecondary,
                      tooltip: 'More actions',
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      onPressed: () => MediaContextMenu.show(context, ref, item),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `3:05` rather than `03:05`; hours stay padded (`01:02:03`).
  static String _trackDuration(int durationMs) {
    if (durationMs <= 0) return '--:--';
    final duration = Duration(milliseconds: durationMs);
    final text = formatDuration(duration);
    return duration.inHours == 0 && text.startsWith('0') ? text.substring(1) : text;
  }
}

/// 52 dp rounded cover. Dimmed when the file is missing; an equaliser glyph
/// sits on top while the song is playing.
class _RowArtwork extends StatelessWidget {
  final MediaItem item;
  final bool isSelected;
  final bool isMissing;

  const _RowArtwork({required this.item, required this.isSelected, required this.isMissing});

  @override
  Widget build(BuildContext context) {
    Widget art = ArtworkThumbnail(
      uri: item.uri,
      artworkPath: item.artworkPath,
      size: MediaSongRow.artworkSize,
      borderRadius: MediaSongRow._artworkRadius,
    );
    if (isMissing) art = Opacity(opacity: 0.45, child: art);
    if (!isSelected) return art;

    return SizedBox.square(
      dimension: MediaSongRow.artworkSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          art,
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.overlay.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(MediaSongRow._artworkRadius),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: AppColors.primary,
              size: 24,
              semanticLabel: 'Now playing',
            ),
          ),
        ],
      ),
    );
  }
}

/// Artist line, led by a "Downloaded" marker for downloaded songs and a
/// "Missing" marker when the file is gone.
class _MetaLine extends StatelessWidget {
  final MediaItem item;
  final String artist;
  final bool isMissing;

  const _MetaLine({required this.item, required this.artist, required this.isMissing});

  /// Narrowest line (at 1.0x text, scaled with the user's text size) that
  /// still shows the word "Downloaded": the word and its icon take about
  /// 100 dp, which leaves the artist at least ~11 characters. Narrower lines
  /// (a small phone, or large text) keep only the icon.
  static const double _labelMinLineWidth = 180;

  static const double _markerIconSize = 14;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.metadata.copyWith(
      color: isMissing ? AppColors.textMuted : AppColors.textSecondary,
    );

    final Widget text = isMissing
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Missing',
                  style: style.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' • $artist'),
              ],
            ),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Text(artist, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);

    if (item.source != 'download') return text;

    // Text is never scaled down: the marker either fits at the user's text
    // size or falls back to its icon, and the artist always keeps the rest.
    final labelMinWidth = MediaQuery.textScalerOf(context).scale(_labelMinLineWidth);
    final markerColor = isMissing ? AppColors.textMuted : AppColors.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabel = constraints.maxWidth >= labelMinWidth;
        return Row(
          children: [
            Icon(
              Icons.download_done_rounded,
              size: _markerIconSize,
              applyTextScaling: true,
              color: markerColor,
              semanticLabel: showLabel ? null : 'Downloaded',
            ),
            const SizedBox(width: AppSpacing.xs4),
            if (showLabel) ...[
              Text(
                'Downloaded',
                style: style.copyWith(color: markerColor, fontWeight: FontWeight.w600),
                maxLines: 1,
              ),
              Text(' • ', style: style, maxLines: 1),
            ],
            Expanded(child: text),
          ],
        );
      },
    );
  }
}
