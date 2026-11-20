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

  const InkDock({
    super.key,
    this.miniPlayer,
    required this.navigation,
    this.blur = 24,
  });

  static const double miniPlayerHeight = 64;
  static const double navigationHeight = 64;
  static const double topRadius = 24;

  /// Bottom padding for scrolling content behind the dock: dock height plus
  /// the system inset plus 16 dp, so the last row clears the controls.
  static double contentBottomPadding(BuildContext context, {bool hasMiniPlayer = true}) =>
      (hasMiniPlayer ? miniPlayerHeight : 0) + navigationHeight + MediaQuery.paddingOf(context).bottom + 16;

  @override
  Widget build(BuildContext context) {
    final miniPlayer = this.miniPlayer;
    return Theme(
      data: InkTheme.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.barsOnInk,
        child: Builder(
          builder: (context) {
            final palette = context.palette;
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(topRadius)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: CustomPaint(
                  foregroundPainter: _DockEdgePainter(color: palette.dockLine, radius: topRadius),
                  child: ColoredBox(
                    color: palette.dock,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [?miniPlayer, navigation],
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

  const _DockEdgePainter({required this.color, required this.radius});

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
  }

  @override
  bool shouldRepaint(_DockEdgePainter oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
