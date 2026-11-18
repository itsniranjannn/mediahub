import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import 'ui_kit.dart';

/// One library entry.
///
/// Videos render as a video card (docs/DESIGN.md 7.9): a 16:9 thumbnail at
/// radius 14 with a duration badge, a "Downloaded" badge and a Volt resume
/// line, then a two-line title, the "time left" of a part-watched video, a
/// quality / size / date line and a 48 dp ⋮ ([onMore]) for the media sheet.
/// Audio keeps a compact row with the optional "Play next" / "Add to queue"
/// menu.
class MediaItemTile extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final double? progress; // 0.0 to 1.0 for videos

  /// Opens the media sheet from the video card's ⋮; [anchor] is the button,
  /// for the popup menu on wide screens. No ⋮ when null.
  final void Function(BuildContext anchor)? onMore;

  /// A long press on the video card (the media sheet).
  final VoidCallback? onLongPress;

  const MediaItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.onPlayNext,
    this.onAddToQueue,
    this.progress,
    this.onMore,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (item.mediaType == MediaType.video) {
      return _VideoCard(item: item, progress: progress, onTap: onTap, onMore: onMore, onLongPress: onLongPress);
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
  final void Function(BuildContext anchor)? onMore;
  final VoidCallback? onLongPress;

  const _VideoCard({
    required this.item,
    required this.progress,
    required this.onTap,
    required this.onMore,
    required this.onLongPress,
  });

  /// Cards stop growing past this width so tablets and landscape stay tidy.
  static const double _maxCardWidth = 640;

  /// Thickness of the resume line along the thumbnail's bottom edge.
  static const double resumeHeight = 3;

  /// Separator between the quality, size and date parts.
  static const String _separator = ' · ';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final title = videoDisplayTitle(item.title);
    final duration = Duration(milliseconds: item.durationMs);
    final hasDuration = item.durationMs > 0;
    final isDownloaded = item.source == 'download';
    final ratio = progress;
    final isResuming = ratio != null && ratio > 0;
    final remaining = isResuming && hasDuration ? _remainingLabel(item.durationMs, ratio) : null;
    final details = _detailParts(item);
    final more = onMore;

    final semanticsLabel = [
      title,
      'Video',
      if (hasDuration) formatDuration(duration),
      if (isDownloaded) 'Downloaded',
      ...details,
      if (isResuming) '${(ratio * 100).round()} percent watched',
    ].join(', ');

    final radius = BorderRadius.circular(AppSpacing.radiusThumb);
    // Only picks the thumbnail's decode resolution; the card itself is laid
    // out by its constraints.
    final cardWidth = math.min(
      MediaQuery.sizeOf(context).width - AppSpacing.lg16 * 2,
      _maxCardWidth,
    );

    final thumbnail = DecoratedBox(
      // A hairline over the frame, so a white frame still has an edge on paper.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: palette.divider)),
      child: ClipRRect(
        borderRadius: radius,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cropped once, straight into the 16:9 box.
              ArtworkThumbnail(
                uri: item.uri,
                artworkPath: item.artworkPath,
                width: cardWidth,
                height: cardWidth * 9 / 16,
                borderRadius: 0,
                placeholderIcon: Icons.movie_outlined,
              ),
              // No scrim over the frame: every badge has its own dark chip and
              // the resume line its own dark track, so bright family videos
              // keep their colours.
              if (isDownloaded)
                const PositionedDirectional(
                  start: AppSpacing.sm8,
                  top: AppSpacing.sm8,
                  child: MediaBadge(icon: Icons.download_done_rounded, text: 'Downloaded'),
                ),
              if (hasDuration)
                PositionedDirectional(
                  end: AppSpacing.sm8,
                  bottom: isResuming ? AppSpacing.sm8 + resumeHeight : AppSpacing.sm8,
                  child: DurationBadge(duration: duration),
                ),
              if (isResuming)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: resumeHeight,
                    borderRadius: BorderRadius.zero,
                    // The overlay is ink in both themes, so the line is the
                    // ink theme's Volt on it.
                    backgroundColor: palette.overlay,
                    valueColor: AlwaysStoppedAnimation<Color>(AppPalette.dark.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          breakableTitle(title),
          semanticsLabel: title,
          style: type.bodyStrong,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Time left gets its own line, so the quality / size / date line
        // keeps the full width.
        if (remaining != null) ...[
          const SizedBox(height: 2),
          Text(
            remaining,
            style: type.metadata.copyWith(color: palette.accent, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (details.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            details.join(_separator),
            style: type.metadata,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxCardWidth),
          // One node for the card (its label and tap); the ⋮ stays a button
          // of its own.
          child: Semantics(
            button: true,
            label: semanticsLabel,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                excludeFromSemantics: true,
                borderRadius: radius,
                highlightColor: palette.surfacePressed,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(child: thumbnail),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: AppSpacing.md12, bottom: AppSpacing.xs4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: ExcludeSemantics(child: texts)),
                          if (more != null)
                            Builder(
                              builder: (buttonContext) => IconButton(
                                icon: const Icon(Icons.more_vert_rounded),
                                color: palette.textSecondary,
                                tooltip: 'More actions',
                                constraints: const BoxConstraints(
                                  minWidth: AppSpacing.minTouchTarget,
                                  minHeight: AppSpacing.minTouchTarget,
                                ),
                                // Its glyph lines up with the title's first line.
                                visualDensity: VisualDensity.compact,
                                onPressed: () => more(buttonContext),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
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
    final palette = context.palette;
    final type = context.typography;
    final artist = item.artist ?? 'Unknown Artist';
    final hasMenu = onPlayNext != null || onAddToQueue != null;

    return Semantics(
      label: '${item.title}, ${item.artist ?? 'Unknown artist'}',
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          highlightColor: palette.surfacePressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
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
                    size: 48,
                    // same corners as MediaSongRow's cover
                    borderRadius: AppSpacing.radiusArtSmall,
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
                          style: type.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        _AudioMetaLine(artist: artist, isDownloaded: item.source == 'download'),
                      ],
                    ),
                  ),
                  // An unknown length shows no clock, as in MediaSongRow.
                  if (item.durationMs > 0) ...[
                    const SizedBox(width: AppSpacing.sm8),
                    Text(
                      formatClock(Duration(milliseconds: item.durationMs)),
                      style: type.tabularFigures.copyWith(color: palette.textMuted),
                    ),
                  ],
                  if (hasMenu)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
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
    final palette = context.palette;
    final text = Text(
      artist,
      style: context.typography.metadata,
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
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: PillTag(text: 'Downloaded', icon: Icons.download_done_rounded, color: palette.accent),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: text),
      ],
    );
  }
}
