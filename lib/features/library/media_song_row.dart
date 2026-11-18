import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/favorite_feedback_button.dart';
import '../library/media_context_menu.dart';
import '../music_player/playback_notifier.dart';

/// One song in a list (docs/DESIGN.md 7.6): 48 dp art at radius 10 (or a
/// 32 dp track number in album and playlist lists, [index]), the title, then
/// "Artist · 4:05" with the length in DM Mono, a heart and a ⋮ that opens
/// the media sheet. A long press opens the sheet too.
///
/// The heart button only fits a roomy row (360 dp or wider at text below
/// 1.15x). A narrower row keeps its width for the artist: favourites show a
/// 16 dp Flare heart before the meta line instead, and the media sheet
/// toggles it.
///
/// The row that is playing right now is marked three ways, never by colour
/// alone: a 3 dp primary bar on the leading edge, an equaliser glyph (Volt on
/// the dark veil over the art, or in place of the track number) and the
/// title in primary; screen readers hear it as the row's selected state.
class MediaSongRow extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final bool showArtwork;
  final Widget? trailing;

  /// 1-based track number shown in a 32 dp column instead of the art.
  final int? index;

  /// Actions this row's media sheet leaves out ("Go to album" on the album's
  /// own page).
  final Set<MediaAction> menuWithout;

  /// A long press opens the media sheet. Off where a long press drags the
  /// row (playlists).
  final bool longPressOpensMenu;

  static const double artworkSize = 48;
  static const double artworkRadius = AppSpacing.radiusArtSmall;
  static const double minHeight = 64;
  static const double indexWidth = 32;

  /// The now-playing bar: 3 dp wide, 12 dp in from the row's top and bottom.
  static const double playingBarWidth = 3;
  static const double playingBarInset = 12;

  /// 48 dp art + 2 x 8 dp keeps a one-line row at 64 dp.
  static const double _verticalPadding = 8;

  /// Below this text scale, on screens at least [_roomyMinWidth] wide, the
  /// title keeps to one line.
  static const double _roomyMaxTextScale = 1.15;
  static const double _roomyMinWidth = 360;

  static const double _iconSize = 24;

  static const String _unknownArtist = 'Unknown artist';

  const MediaSongRow({
    super.key,
    required this.item,
    this.onTap,
    this.showArtwork = true,
    this.trailing,
    this.index,
    this.menuWithout = const {},
    this.longPressOpensMenu = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.typography;
    // Only rebuild this row when *its* "now playing" state flips.
    final isSelected = ref.watch(currentMediaItemProvider.select((current) => current?.id == item.id));
    final isMissing = item.availability == MediaAvailability.missing;
    final artist = item.artist ?? _unknownArtist;

    final titleColor = isMissing
        ? palette.textMuted
        : isSelected
            ? palette.primary
            : palette.textPrimary;
    // A 360 dp phone at default text size keeps every row at 64 dp. Smaller
    // phones and larger text give the title a second line instead of cutting
    // it after a dozen characters; those rows grow with their content.
    final roomy = MediaQuery.textScalerOf(context).scale(1) < _roomyMaxTextScale &&
        MediaQuery.sizeOf(context).width >= _roomyMinWidth;
    // A two-line title may break after "_" ("Audit_Long_" / "Tone_5min");
    // one line gains nothing from the extra wrap points.
    final shownTitle = roomy ? item.title : breakableTitle(item.title);
    // Small rows mark a favourite instead of offering the heart button.
    final markFavorite =
        !roomy && (ref.watch(isFavoriteProvider(item.id)).asData?.value ?? item.isFavorite);

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

    void openMenu(BuildContext anchor) =>
        MediaContextMenu.show(context, ref, item, anchorContext: anchor, without: menuWithout);
    final VoidCallback? handleLongPress = longPressOpensMenu ? () => openMenu(context) : null;

    final int? number = index;
    final Widget? leading = number != null
        ? _IndexCell(number: number, isSelected: isSelected, isMissing: isMissing)
        : showArtwork
            ? _RowArtwork(item: item, isSelected: isSelected, isMissing: isMissing)
            : null;

    // One screen-reader node per row, read once: this label and tap stand in
    // for the ink well and the texts under it, which are left out below.
    // "Now playing" is the selected state. The heart and "more" stay buttons
    // of their own. Not a container, so a list's own row actions (reorder,
    // swipe to remove) join this node instead of sitting on an unlabelled one.
    return Semantics(
      label: markFavorite
          ? '${semanticsLabelFor(item, isMissing: isMissing)}, Favorite'
          : semanticsLabelFor(item, isMissing: isMissing),
      button: true,
      selected: isSelected,
      onTap: handleTap,
      onLongPress: handleLongPress,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: handleTap,
          onLongPress: handleLongPress,
          highlightColor: palette.surfacePressed,
          splashColor: palette.primaryBase.withValues(alpha: 0.12),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: minHeight),
                child: Padding(
                  // The art (or the track number, or the title) starts on
                  // the 16 dp gutter.
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg16,
                    _verticalPadding,
                    AppSpacing.xs4,
                    _verticalPadding,
                  ),
                  child: Row(
                    children: [
                      if (leading != null) ...[
                        ExcludeSemantics(child: leading),
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
                                style: type.bodyStrong.copyWith(color: titleColor),
                                maxLines: roomy ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              if (markFavorite)
                                Row(
                                  children: [
                                    const _FavoriteMark(),
                                    Expanded(child: _MetaLine(item: item, artist: artist, isMissing: isMissing)),
                                  ],
                                )
                              else
                                _MetaLine(item: item, artist: artist, isMissing: isMissing),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs4),
                      if (roomy)
                        _SingleNodeHeart(
                          child: FavoriteFeedbackButton(
                            itemId: item.id,
                            isFavorite: item.isFavorite,
                            size: _iconSize,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                          ),
                        ),
                      trailing ??
                          Builder(
                            builder: (buttonContext) => IconButton(
                              icon: const Icon(Icons.more_vert_rounded, size: _iconSize),
                              color: palette.textSecondary,
                              tooltip: 'More actions',
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              onPressed: () => openMenu(buttonContext),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if (isSelected)
                PositionedDirectional(
                  start: 0,
                  top: playingBarInset,
                  bottom: playingBarInset,
                  width: playingBarWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(2)),
                    ),
                  ),
                ),
            ],
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

/// A favourite on a row too small for the heart button: a 16 dp filled
/// heart in Flare before the meta line (the row's label says "Favorite").
class _FavoriteMark extends StatelessWidget {
  const _FavoriteMark();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.textScalerOf(context).scale(16);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs4),
      child: Icon(Icons.favorite_rounded, size: size, color: context.palette.favorite),
    );
  }
}

/// The equaliser glyph that marks the playing row.
const IconData _playingGlyph = Icons.graphic_eq_rounded;

/// 48 dp cover at radius 10. Dimmed when the file is missing; while the song
/// is playing an equaliser sits on top, in Volt on the dark overlay veil (the
/// veil is ink in both themes, so the glyph keeps >= 3:1 even over a white
/// cover).
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
      borderRadius: MediaSongRow.artworkRadius,
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
              color: context.palette.overlay,
              borderRadius: BorderRadius.circular(MediaSongRow.artworkRadius),
            ),
            child: Icon(
              _playingGlyph,
              // The veil is ink in both themes: the ink theme's Volt reads on it.
              color: AppPalette.dark.primary,
              size: 24,
              semanticLabel: 'Now playing',
            ),
          ),
        ],
      ),
    );
  }
}

/// The 32 dp track number ("01") of album and playlist lists, in DM Mono;
/// the playing row shows the equaliser in primary instead.
class _IndexCell extends StatelessWidget {
  final int number;
  final bool isSelected;
  final bool isMissing;

  const _IndexCell({required this.number, required this.isSelected, required this.isMissing});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: MediaSongRow.indexWidth,
      child: Center(
        child: isSelected
            ? Icon(_playingGlyph, color: palette.primary, size: 22, semanticLabel: 'Now playing')
            : Text(
                number.toString().padLeft(2, '0'),
                style: context.typography.index.copyWith(
                  color: isMissing ? palette.textMuted.withValues(alpha: 0.6) : null,
                ),
                maxLines: 1,
                softWrap: false,
              ),
      ),
    );
  }
}

/// Artist line, led by a "Downloaded" marker for downloaded songs and a
/// "Missing" marker when the file is gone, and ended by the song's length in
/// DM Mono.
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

  static const double _markerIconSize = 16;

  static const String _separator = ' · ';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final style = type.metadata.copyWith(
      color: isMissing ? palette.textMuted : palette.textSecondary,
    );

    // longestLine: an ellipsized artist is as wide as what it shows, so the
    // length sits right after the "…" instead of after a gap.
    final Widget artistText = isMissing
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Missing',
                  style: style.copyWith(color: palette.warning, fontWeight: FontWeight.w600),
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

    // DM Mono at the meta line's size and line height, in textMuted.
    final clockStyle = type.tabularFigures.copyWith(
      fontSize: style.fontSize,
      height: style.height,
      color: palette.textMuted,
    );

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
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: _separator, style: style.copyWith(color: palette.textMuted)),
                    TextSpan(text: duration, style: clockStyle),
                  ],
                ),
                semanticsLabel: duration,
                style: style,
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
    // Ice, like the "Downloaded" badge on video covers: primary means "now
    // playing" in every list.
    final palette = context.palette;
    final markerColor = isMissing ? palette.textMuted : palette.accent;

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
