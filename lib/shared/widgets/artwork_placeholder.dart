import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Cover art for a song or video that has none of its own.
///
/// Fills its constraints with one of [AppColors.artworkGradients], picked
/// from [seed] (use the item's uri) with a stable hash, so an item wears the
/// same colours in every list, card and player. A soft highlight lifts the
/// top-left corner, faint rings echo the bottom-right on covers of
/// [ringMinSide] and up, and [icon] sits in the centre at about 40 % of the
/// shortest side (a little less on wide stills).
class ArtworkPlaceholder extends StatelessWidget {
  /// Picks the gradient. The same seed always gets the same colours.
  final String seed;

  /// Centred glyph (a note for songs, a film strip for videos ...).
  final IconData icon;

  /// Rounds the painted corners. Leave null when a parent already clips.
  final BorderRadius? borderRadius;

  const ArtworkPlaceholder({
    super.key,
    required this.seed,
    this.icon = Icons.music_note_rounded,
    this.borderRadius,
  });

  /// Glyph size as a share of the shortest side, and its bounds.
  static const double glyphFraction = 0.4;
  static const double minGlyphSize = 14;
  static const double maxGlyphSize = 96;

  /// White glyphs at this opacity stay readable on both gradient stops.
  static const double glyphOpacity = 0.85;

  /// Shortest side from which the rings are drawn. On list-sized covers
  /// they would only be hairline arcs, so small covers stay plain.
  static const double ringMinSide = 96;

  /// Size used when the parent gives no bounds at all.
  static const double _fallbackSize = 48;

  /// 32-bit FNV-1a over the UTF-8 bytes of [seed]. Unlike [String.hashCode]
  /// it is the same on every run, isolate and device.
  static int hashOf(String seed) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(seed)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Seeds for album and artist covers, kept apart from song uris so an
  /// album, its artist and its first song each get their own colours.
  static String albumSeed(String album) => 'album:$album';
  static String artistSeed(String artist) => 'artist:$artist';

  /// Index into [AppColors.artworkGradients] for [seed]. The high half of
  /// the hash is folded in first: FNV-1a's low bits only see the low bits of
  /// each byte, so uris that differ in their last digits would cluster.
  static int paletteIndexFor(String seed) {
    final hash = hashOf(seed);
    return (hash ^ (hash >> 16)) % AppColors.artworkGradients.length;
  }

  /// The cover gradient for [seed]: the same one its placeholder paints.
  static LinearGradient gradientFor(String seed) => AppColors.artworkGradients[paletteIndexFor(seed)];

  /// Glyph edge for a placeholder of [size]: [glyphFraction] of the shortest
  /// side on a square cover, a little less on wide stills (about 30 % on
  /// 16:9) so the glyph does not dominate a video frame.
  static double glyphSizeFor(Size size) {
    final shortest = size.shortestSide;
    if (shortest <= 0) return 0;
    final aspect = size.longestSide / shortest;
    final fraction = glyphFraction / math.sqrt(aspect).clamp(1.0, 1.4);
    final glyph = (shortest * fraction).clamp(minGlyphSize, maxGlyphSize);
    return math.min(glyph, shortest);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CoverPainter(gradient: gradientFor(seed), borderRadius: borderRadius),
      child: CustomSingleChildLayout(
        delegate: const _CentredGlyphLayout(),
        // Drawn at a fixed size and scaled into the slot the delegate gives
        // it, so the glyph follows the box without a LayoutBuilder (which
        // would break intrinsic and dry layout in the rows that host it).
        child: FittedBox(
          child: Icon(
            icon,
            size: _fallbackSize,
            color: Colors.white.withValues(alpha: glyphOpacity),
            shadows: const [
              Shadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fills the incoming constraints and centres a square glyph slot sized by
/// [ArtworkPlaceholder.glyphSizeFor].
class _CentredGlyphLayout extends SingleChildLayoutDelegate {
  const _CentredGlyphLayout();

  @override
  Size getSize(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : ArtworkPlaceholder._fallbackSize;
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : ArtworkPlaceholder._fallbackSize;
    return constraints.constrain(Size(width, height));
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final side = ArtworkPlaceholder.glyphSizeFor(getSize(constraints));
    return BoxConstraints.tight(Size.square(side));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset((size.width - childSize.width) / 2, (size.height - childSize.height) / 2);
  }

  @override
  bool shouldRelayout(_CentredGlyphLayout oldDelegate) => false;
}

/// Diagonal gradient, a radial highlight from the top-left corner and, on
/// covers of at least [ArtworkPlaceholder.ringMinSide], two faint rings
/// around the bottom-right corner.
class _CoverPainter extends CustomPainter {
  final LinearGradient gradient;
  final BorderRadius? borderRadius;

  const _CoverPainter({required this.gradient, required this.borderRadius});

  static const RadialGradient _highlight = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
  );

  static const List<double> _ringRadii = [0.42, 0.74];
  static const Color _ringColor = Color(0x14FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final radius = borderRadius;
    canvas.save();
    if (radius != null) canvas.clipRRect(radius.toRRect(rect));

    canvas
      ..drawRect(rect, Paint()..shader = gradient.createShader(rect))
      ..drawRect(rect, Paint()..shader = _highlight.createShader(rect));

    final shortest = size.shortestSide;
    if (shortest >= ArtworkPlaceholder.ringMinSide) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (shortest * 0.025).clamp(1.0, 3.0)
        ..color = _ringColor;
      for (final r in _ringRadii) {
        canvas.drawCircle(rect.bottomRight, shortest * r, ring);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) =>
      oldDelegate.gradient != gradient || oldDelegate.borderRadius != borderRadius;
}

/// Ambient colours taken from an item's cover palette, for the surfaces
/// around its artwork (Now Playing backdrop, the "Continue listening" card,
/// album and artist headers). Same seed, same colours as its placeholder.
/// Every surface stays dark enough for the text tokens on it (checked in
/// test/unit/artwork_placeholder_test.dart).
abstract class ArtworkTint {
  /// Light (top-left) stop of [seed]'s cover gradient.
  static Color light(String seed) => ArtworkPlaceholder.gradientFor(seed).colors.first;

  /// Deep (bottom-right) stop of [seed]'s cover gradient.
  static Color deep(String seed) => ArtworkPlaceholder.gradientFor(seed).colors.last;

  /// Opacity of the light glow around the Now Playing cover. Strong, because
  /// the scrim over it lets only the band around the cover show colour; text
  /// never sits over its peak.
  static const double backdropLightAlpha = 0.9;

  /// Opacity of the deep glow on the right of the Now Playing cover.
  static const double backdropDeepAlpha = 0.6;

  /// [AppColors.heroGradient] re-coloured with [seed]'s deep stop, for cards
  /// and headers that carry text.
  static LinearGradient surfaceGradient(String seed) {
    final deep = ArtworkTint.deep(seed);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(deep, AppColors.background, 0.3)!,
        Color.lerp(deep, AppColors.background, 0.68)!,
        AppColors.heroGradient.colors.last,
      ],
    );
  }

  /// Soft coloured shadow under a cover.
  static Color glow(String seed) => light(seed).withValues(alpha: 0.3);
}
