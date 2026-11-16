import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import 'ui_kit.dart';

/// One library entry.
///
/// Videos render as a cinematic card: a 16:9 thumbnail with a duration badge,
/// a thin teal resume bar, a two-line title, the teal "time left" for a
/// part-watched video and a quality / size / date line.
/// Audio keeps a compact row with the optional "Play next" / "Add to queue" menu.
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
    if (item.mediaType == MediaType.video) {
      return _VideoCard(item: item, progress: progress, onTap: onTap);
    }
    return _AudioRow(
      item: item,
      onTap: onTap,
      onPlayNext: onPlayNext,
      onAddToQueue: onAddToQueue,
    );
  }
}

// ---------------------------------------------------------------------------
// Video card
// ---------------------------------------------------------------------------

class _VideoCard extends StatelessWidget {
  final MediaItem item;
  final double? progress;
  final VoidCallback? onTap;

  const _VideoCard({required this.item, required this.progress, required this.onTap});

  /// Cards stop growing past this width so tablets and landscape stay tidy.
  static const double _maxCardWidth = 640;

  /// Separator between the quality, size and date parts.
  static const String _separator = ' · ';

  static final RegExp _extension = RegExp(r'\.[a-zA-Z0-9]{2,4}$');

  @override
  Widget build(BuildContext context) {
    final title = item.title.replaceAll(_extension, '');
    final duration = Duration(milliseconds: item.durationMs);
    final hasDuration = item.durationMs > 0;
    final isDownloaded = item.source == 'download';
    final ratio = progress;
    final isResuming = ratio != null && ratio > 0;
    final remaining = isResuming && hasDuration ? _remainingLabel(item.durationMs, ratio) : null;
    final details = _detailParts(item);

    final semanticsLabel = [
      title,
      'Video',
      if (hasDuration) formatDuration(duration),
      if (isDownloaded) 'Downloaded',
      ...details,
      if (isResuming) '${(ratio * 100).round()} percent watched',
    ].join(', ');

    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    // Only picks the thumbnail's decode resolution; the card itself is laid
    // out by its constraints.
    final cardWidth = math.min(
      MediaQuery.sizeOf(context).width - AppSpacing.lg16 * 2,
      _maxCardWidth,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxCardWidth),
          child: Semantics(
            button: true,
            label: semanticsLabel,
            onTap: onTap,
            excludeSemantics: true,
            child: Material(
              color: AppColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: const BorderSide(color: AppColors.divider),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Cropped once, straight into the 16:9 box; the card
                            // clips the corners.
                            ArtworkThumbnail(
                              uri: item.uri,
                              artworkPath: item.artworkPath,
                              width: cardWidth,
                              height: cardWidth * 9 / 16,
                              borderRadius: 0,
                              placeholderIcon: Icons.movie_outlined,
                            ),
                            // Soft scrim so the badges stay readable on bright frames.
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  // Eased (three stops) so no band shows where
                                  // it starts on smooth placeholder gradients.
                                  stops: const [0.45, 0.75, 1.0],
                                  colors: [
                                    AppColors.overlay.withValues(alpha: 0),
                                    AppColors.overlay.withValues(alpha: 0.16),
                                    AppColors.overlay.withValues(alpha: 0.54),
                                  ],
                                ),
                              ),
                            ),
                            if (isDownloaded)
                              const Positioned(
                                left: AppSpacing.md12,
                                top: AppSpacing.md12,
                                child: PillTag(
                                  text: 'Downloaded',
                                  icon: Icons.download_done_rounded,
                                  filled: true,
                                ),
                              ),
                            if (hasDuration)
                              Positioned(
                                right: AppSpacing.md12,
                                bottom: isResuming ? AppSpacing.md12 + 3 : AppSpacing.md12,
                                child: DurationBadge(duration: duration),
                              ),
                            if (isResuming)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: LinearProgressIndicator(
                                  value: ratio.clamp(0.0, 1.0),
                                  minHeight: 3,
                                  backgroundColor: AppColors.onOverlay.withValues(alpha: 0.22),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg16,
                          AppSpacing.md12,
                          AppSpacing.lg16,
                          AppSpacing.lg16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.bodyStrong,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Time left gets its own line, so the quality / size /
                            // date line keeps the full width of the card.
                            if (remaining != null) ...[
                              const SizedBox(height: AppSpacing.xs4),
                              Text(
                                remaining,
                                style: AppTypography.metadata.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (details.isNotEmpty) ...[
                              SizedBox(height: remaining != null ? 2 : AppSpacing.xs4),
                              Text(
                                details.join(_separator),
                                style: AppTypography.metadata,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Ink on top so the ripple also shows over the thumbnail.
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: onTap),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Quality, size and date, e.g. ["1080p", "12.0 MB", "Added 3 Mar"].
  static List<String> _detailParts(MediaItem item) {
    final width = item.width;
    final height = item.height;
    return [
      if (width != null && height != null && width > 0 && height > 0) _qualityLabel(width, height),
      if (item.sizeBytes > 0) formatFileSize(item.sizeBytes),
      _addedLabel(item.dateAdded),
    ];
  }

  /// Friendly resolution name based on the short side, so portrait clips read right.
  static String _qualityLabel(int width, int height) {
    final shortSide = width < height ? width : height;
    if (shortSide >= 2160) return '4K';
    if (shortSide >= 1440) return '1440p';
    if (shortSide >= 1080) return '1080p';
    if (shortSide >= 720) return '720p';
    if (shortSide >= 480) return '480p';
    return '${shortSide}p';
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _addedLabel(DateTime added) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(added.year, added.month, added.day);
    // Rounded so a daylight-saving 23 h day still counts as one day.
    final days = (today.difference(day).inHours / 24).round();
    if (days <= 0) return 'Added today';
    if (days == 1) return 'Added yesterday';
    if (days < 7) return 'Added $days days ago';
    final month = _months[added.month - 1];
    return added.year == now.year
        ? 'Added ${added.day} $month'
        : 'Added ${added.day} $month ${added.year}';
  }

  static String _remainingLabel(int durationMs, double ratio) {
    final left = Duration(milliseconds: (durationMs * (1 - ratio.clamp(0.0, 1.0))).round());
    if (left.inMinutes < 1) return 'Almost done';
    if (left.inHours < 1) return '${left.inMinutes} min left';
    final minutes = left.inMinutes.remainder(60);
    return minutes == 0 ? '${left.inHours} h left' : '${left.inHours} h $minutes min left';
  }
}

// ---------------------------------------------------------------------------
// Audio row
// ---------------------------------------------------------------------------

class _AudioRow extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;

  const _AudioRow({
    required this.item,
    required this.onTap,
    required this.onPlayNext,
    required this.onAddToQueue,
  });

  @override
  Widget build(BuildContext context) {
    final artist = item.artist ?? 'Unknown Artist';
    final hasMenu = onPlayNext != null || onAddToQueue != null;

    return Semantics(
      label: '${item.title}, ${item.artist ?? 'Unknown artist'}',
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg16,
                AppSpacing.sm8,
                hasMenu ? AppSpacing.xs4 : AppSpacing.lg16,
                AppSpacing.sm8,
              ),
              child: Row(
                children: [
                  ArtworkThumbnail(
                    uri: item.uri,
                    artworkPath: item.artworkPath,
                    size: 52,
                    borderRadius: AppSpacing.md12,
                    placeholderIcon: Icons.music_note_rounded,
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: AppTypography.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _AudioMetaLine(artist: artist, isDownloaded: item.source == 'download'),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm8),
                  Text(
                    item.durationMs > 0 ? formatDuration(Duration(milliseconds: item.durationMs)) : '--:--',
                    style: AppTypography.tabularFigures,
                  ),
                  if (hasMenu)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Artist line, led by a "Downloaded" pill for downloaded tracks.
class _AudioMetaLine extends StatelessWidget {
  final String artist;
  final bool isDownloaded;

  const _AudioMetaLine({required this.artist, required this.isDownloaded});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      artist,
      style: AppTypography.metadata,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!isDownloaded) return text;

    // The pill gets at most half the line and scales down past that (large text
    // on a small phone), so the artist always keeps the other half and nothing
    // overflows. Plain flex instead of a LayoutBuilder, so the row still reports
    // intrinsic sizes (IntrinsicHeight, dialogs, SliverFillRemaining).
    return Row(
      children: [
        const Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: PillTag(text: 'Downloaded', icon: Icons.download_done_rounded),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: text),
      ],
    );
  }
}
