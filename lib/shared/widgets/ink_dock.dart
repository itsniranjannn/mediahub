import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/ink_theme.dart';

/// The Ink Dock (docs/DESIGN.md 7.7): the container for the mini player and
/// the bottom navigation. It is ink in both themes, so the place the family
/// spends most time looks the same on every phone.
///
/// It wraps its content in `InkTheme.of(context)` (so `context.palette` inside
/// is always a dark palette: [AppPalette.dark] or [AppPalette.classic]) and in [AppTheme.barsOnInk], so the Android
/// navigation bar icons stay light over it in both themes. The fill is
/// [AppPalette.dock] over a 24 blur, with 24 dp top corners and a 1 dp
/// [AppPalette.dockLine] along the top edge.
///
/// [navigation] is expected to handle the system bottom inset itself (a
/// [NavigationBar] does); the dock fill reaches under it.
class InkDock extends StatelessWidget {
  /// The 64 dp mini-player row, or null while nothing is playing.
  final Widget? miniPlayer;

  /// The 64 dp navigation (plus the system inset).
  final Widget navigation;

  final double blur;

  /// The dock always paints an opaque fill behind its rounded top corners,
  /// so the two corner gaps never show what is under it (a WebView on
  /// Samsung One UI painted its white page there): the scaffold background,
  /// or with [squareCorners] (the shell's Online tab) the dock colour itself,
  /// so the corners read square.
  final bool squareCorners;

  /// Landscape on a phone (short screen): the mini player and a slim,
  /// icons-only navigation share one row, so the page keeps most of the
  /// height. The dock's fill reaches under the side system insets (display
  /// cutout, navigation bar) while its content stays clear of them.
  final bool inline;

  const InkDock({
    super.key,
    this.miniPlayer,
    required this.navigation,
    this.blur = 24,
    this.squareCorners = false,
    this.inline = false,
  });

  /// True on a short landscape screen (a phone turned sideways), where the
  /// dock goes [inline] and the navigation turns compact.
  static bool isCompactLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.height < compactLandscapeMaxHeight;
  }

  /// Screens shorter than this (dp) in landscape get the compact dock.
  static const double compactLandscapeMaxHeight = 500;

  /// The compact (landscape) navigation's height.
  static const double compactNavigationHeight = 48;

  /// The compact navigation's width per tab.
  static const double compactSlotWidth = 64;

  /// The system bottom inset the dock pads for: the larger of the padding
  /// and the view padding, so gesture-nav phones that report the bar in only
  /// one of them still keep the labels clear of it.
  static double systemBottomInset(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).bottom;
    final view = MediaQuery.viewPaddingOf(context).bottom;
    return padding > view ? padding : view;
  }

  static const double miniPlayerHeight = 64;
  static const double navigationHeight = 64;
  static const double topRadius = 24;

  /// Bottom padding for scrolling content behind the dock: dock height plus
  /// the system inset plus 16 dp, so the last row clears the controls.
  static double contentBottomPadding(BuildContext context, {bool hasMiniPlayer = true}) =>
      (hasMiniPlayer ? miniPlayerHeight : 0) + navigationHeight + systemBottomInset(context) + 16;

  @override
  Widget build(BuildContext context) {
    final miniPlayer = this.miniPlayer;
    final pageBackground = Theme.of(context).scaffoldBackgroundColor;
    return Theme(
      data: InkTheme.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.barsOnInk,
        child: Builder(
          builder: (context) {
            final palette = context.palette;
            final backing = squareCorners ? palette.dock : pageBackground;
            // Opaque, so nothing under the dock shows through the corners.
            return DecoratedBox(
              key: const ValueKey('dock_corner_backing'),
              decoration: BoxDecoration(color: backing.withValues(alpha: 1)),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(topRadius)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: CustomPaint(
                    // Online (square corners): no light top line between the
                    // page and the ink, which read as a gap in light mode.
                    foregroundPainter: squareCorners
                        ? null
                        : _DockEdgePainter(
                      color: palette.dockLine,
                      radius: topRadius,
                      glint: palette.voltGlow.withValues(
                        alpha: palette.voltGlow.a * 1.6 > 1 ? 1 : palette.voltGlow.a * 1.6,
                      ),
                    ),
                    child: ColoredBox(
                      color: palette.dock,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: inline
                            ? [
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: MediaQuery.viewPaddingOf(context).left,
                                    right: MediaQuery.viewPaddingOf(context).right,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(child: miniPlayer ?? const SizedBox.shrink()),
                                      navigation,
                                    ],
                                  ),
                                ),
                              ]
                            : [?miniPlayer, navigation],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The 1 dp line along the dock's rounded top edge.
class _DockEdgePainter extends CustomPainter {
  final Color color;
  final double radius;
  final Color glint;

  const _DockEdgePainter({required this.color, required this.radius, this.glint = const Color(0x00000000)});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const stroke = 1.0;
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final y = stroke / 2;
    final path = Path()
      ..moveTo(y, r)
      ..arcToPoint(Offset(r, y), radius: Radius.circular(r - y))
      ..lineTo(size.width - r, y)
      ..arcToPoint(Offset(size.width - y, r), radius: Radius.circular(r - y));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );
    // A brand glint across the middle of the top edge, fading out to the
    // corners (transparent where the palette has no glow).
    if (glint.a > 0 && size.width > r * 2) {
      final rect = Rect.fromLTWH(r, 0, size.width - r * 2, stroke);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [glint.withValues(alpha: 0), glint, glint.withValues(alpha: 0)])
              .createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_DockEdgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius || oldDelegate.glint != glint;
}
