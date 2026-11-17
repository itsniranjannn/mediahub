import 'dart:math' as math;

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

/// One song in a list: rounded artwork, title, then the artist and the
/// length on one line, a heart and a "more" button. The row that is playing
/// right now sits on an inset violet pill, like the current track in the
/// queue.
class MediaSongRow extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final bool showArtwork;
  final Widget? trailing;

  static const double artworkSize = 52;
  static const double _artworkRadius = AppSpacing.sm8;

  /// Space around the row's pill: 8 dp from the screen edges, 1 dp between
  /// stacked rows.
  static const EdgeInsets _pillInset = EdgeInsets.symmetric(horizontal: AppSpacing.sm8, vertical: 1);

  /// 52 dp artwork + 2 x (1 dp inset + 5 dp) keeps every row at 64 dp.
  static const double _verticalPadding = 5;

  /// Fill of the now-playing pill (the queue uses the same).
  static const double _selectedAlpha = 0.12;

  /// Below this text scale, on screens at least [_roomyMinWidth] wide, the
  /// title keeps to one line.
  static const double _roomyMaxTextScale = 1.15;
  static const double _roomyMinWidth = 360;

  static const String _unknownArtist = 'Unknown artist';

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
    final artist = item.artist ?? _unknownArtist;

    final titleColor = isMissing
        ? AppColors.textMuted
        : isSelected
            ? AppColors.primary
            : AppColors.textPrimary;
    final radius = BorderRadius.circular(AppSpacing.buttonRadius);
    // A 360 dp phone at default text size keeps every row at 64 dp. Smaller
    // phones and larger text give the title a second line instead of cutting
    // it after a dozen characters; those rows grow with their content.
    final roomy = MediaQuery.textScalerOf(context).scale(1) < _roomyMaxTextScale &&
        MediaQuery.sizeOf(context).width >= _roomyMinWidth;
    // A two-line title may break after "_" ("Audit_Long_" / "Tone_5min");
    // one line gains nothing from the extra wrap points.
    final shownTitle = roomy ? item.title : breakableTitle(item.title);

    final VoidCallback handleTap = isMissing
        ? () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File is missing or unavailable on storage')),
            );
          }
        : (onTap ??
            () {
              ref.read(playbackNotifierProvider.notifier).loadQueue([item]);
            });

    // One screen-reader node per row, read once: this label and tap stand in
    // for the ink well and the texts under it, which are left out below.
    // "Now playing" is the selected state. The heart and "more" stay buttons
    // of their own. Not a container, so a list's own row actions (reorder,
    // swipe to remove) join this node instead of sitting on an unlabelled one.
    return Semantics(
      label: semanticsLabelFor(item, isMissing: isMissing),
      button: true,
      selected: isSelected,
      onTap: handleTap,
      child: Padding(
        padding: _pillInset,
        child: Material(
          color: isSelected ? AppColors.primary.withValues(alpha: _selectedAlpha) : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            // Keeps the ripple inside the pill.
            borderRadius: radius,
            excludeFromSemantics: true,
            onTap: handleTap,
            child: Padding(
              // 8 dp pill inset + 8 dp here: the art (or the title) starts on
              // the 16 dp gutter.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm8,
                _verticalPadding,
                0,
                _verticalPadding,
              ),
              child: Row(
                children: [
                  if (showArtwork) ...[
                    ExcludeSemantics(
                      child: _RowArtwork(item: item, isSelected: isSelected, isMissing: isMissing),
                    ),
                    const SizedBox(width: AppSpacing.md12),
                  ],
                  Expanded(
                    // The row's label already says all of this.
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            shownTitle,
                            semanticsLabel: shownTitle == item.title ? null : item.title,
                            style: AppTypography.bodyStrong.copyWith(color: titleColor),
                            maxLines: roomy ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          _MetaLine(item: item, artist: artist, isMissing: isMissing),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs4),
                  _SingleNodeHeart(
                    child: FavoriteFeedbackButton(
                      itemId: item.id,
                      isFavorite: item.isFavorite,
                      size: 20,
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
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
      ),
    );
  }

  /// `3:05` rather than `03:05`, `1:02:03` rather than `01:02:03`. Null when
  /// the length is unknown, so the row shows none instead of `--:--`.
  static String? _trackDuration(int durationMs) {
    if (durationMs <= 0) return null;
    return formatClock(Duration(milliseconds: durationMs));
  }

  /// What a screen reader says for the row, once:
  /// `Song: <title> by <artist>`, then "Downloaded" and the length when the
  /// row shows them, led by "Missing file." when the file is gone. The length
  /// is in the label rather than the value because Android reads a value
  /// before the label.
  @visibleForTesting
  static String semanticsLabelFor(MediaItem item, {required bool isMissing}) {
    final parts = ['Song: ${item.title} by ${item.artist ?? _unknownArtist}'];
    if (item.source == 'download') parts.add('Downloaded');
    final duration = _trackDuration(item.durationMs);
    if (duration != null) parts.add(duration);
    final label = parts.join(', ');
    return isMissing ? 'Missing file. $label' : label;
  }
}

/// [FavoriteFeedbackButton] names itself twice: a Semantics label around an
/// IconButton whose tooltip says the same thing. That label is not a node of
/// its own, so it merged into whatever held the button (a song row read "...
/// 5:00 / Add to favorites"). Merged into the button's node here, with the
/// tooltip kept out of semantics (it still shows on long-press), the heart is
/// one button that is read once.
class _SingleNodeHeart extends StatelessWidget {
  final Widget child;

  const _SingleNodeHeart({required this.child});

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: TooltipTheme(
        data: TooltipTheme.of(context).copyWith(excludeFromSemantics: true),
        child: child,
      ),
    );
  }
}

/// 52 dp rounded cover. Dimmed when the file is missing; an equaliser glyph
/// sits on top while the song is playing, on the full [AppColors.overlay]
/// veil so the violet glyph keeps >= 3:1 even over a white cover.
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
              color: AppColors.overlay,
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
/// "Missing" marker when the file is gone, and ended by the song's length.
///
/// The length is never cut: the artist gives way first and ellipsizes.
class _MetaLine extends StatelessWidget {
  final MediaItem item;
  final String artist;
  final bool isMissing;

  const _MetaLine({required this.item, required this.artist, required this.isMissing});

  /// Room the artist keeps (at 1.0x text, scaled with the user's text size;
  /// about ten characters) before the word "Downloaded" gives way to its
  /// icon. The word, its icon and the separator are measured in the row's
  /// own font, so a change of type scale cannot make them overflow. Narrower
  /// lines (a small phone, or large text) keep only the icon.
  static const double _minArtistWidth = 72;

  static const double _markerIconSize = 14;

  static const String _separator = ' · ';

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.metadata.copyWith(
      color: isMissing ? AppColors.textMuted : AppColors.textSecondary,
    );

    // longestLine: an ellipsized artist is as wide as what it shows, so the
    // length sits right after the "…" instead of after a gap.
    final Widget artistText = isMissing
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Missing',
                  style: style.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: '$_separator$artist'),
              ],
            ),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.longestLine,
          )
        : Text(
            artist,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.longestLine,
          );

    final isDownload = item.source == 'download';
    final lead = isDownload ? _downloadedLead(context, style, artistText) : artistText;

    final duration = MediaSongRow._trackDuration(item.durationMs);
    if (duration == null) return lead;

    // What the lead needs even when the artist is squeezed to nothing: the
    // download icon and its gap.
    final leadMinWidth = isDownload
        ? MediaQuery.textScalerOf(context).scale(_markerIconSize) + AppSpacing.xs4
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            // Loose, so the length follows the artist ("Artist · 4:05")
            // instead of floating at the far end of the line.
            Flexible(child: lead),
            // The length takes what it needs first; only a line too narrow
            // for it at all (an hour-long track at huge text) ellipsizes it
            // instead of overflowing.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, constraints.maxWidth - leadMinWidth),
              ),
              child: Text(
                '$_separator$duration',
                semanticsLabel: duration,
                style: style.copyWith(
                  color: AppColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Download marker (icon, and the word when there is room) before the
  /// artist.
  Widget _downloadedLead(BuildContext context, TextStyle style, Widget artistText) {
    // Text is never scaled down: the marker either fits at the user's text
    // size or falls back to its icon, and the artist always keeps the rest.
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final markerWidth = scaler.scale(_markerIconSize) +
        AppSpacing.xs4 +
        _textWidth('Downloaded', style, scaler, direction) +
        _textWidth(_separator, style, scaler, direction);
    final labelMinWidth = markerWidth + scaler.scale(_minArtistWidth);
    // Teal, like the "Downloaded" badge on video covers: violet means "now
    // playing" in every list.
    final markerColor = isMissing ? AppColors.textMuted : AppColors.accent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabel = constraints.maxWidth >= labelMinWidth;
        // As wide as its content, so the length can follow the artist.
        return Row(
          mainAxisSize: MainAxisSize.min,
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
                style: style.copyWith(color: markerColor),
                maxLines: 1,
              ),
              ExcludeSemantics(child: Text(_separator, style: style, maxLines: 1)),
            ],
            Flexible(child: artistText),
          ],
        );
      },
    );
  }

  /// Laid-out width of one line of [text] (plus a pixel for rounding).
  static double _textWidth(String text, TextStyle style, TextScaler scaler, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: scaler,
      textDirection: direction,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 1;
  }
}
