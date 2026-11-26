// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app/theme/app_palette.dart';
import '../../core/platform/device_controls.dart';

/// A rich cosmic universe backdrop for the Downloads screen:
/// - Deterministic twinkling starfield (layered background stars)
/// - Multi-color glowing nebulae (radial gradients using primary and accent tones)
/// - Miniature celestial orbs (distant tiny planets, moons and planetary rings)
///
/// Follows the same battery-preserving low-power periodic update pattern as [PlanetBackdrop],
/// pausing on reduced motion, PiP, inactive lifecycle, or when [debugAnimate] is false.
class CosmosBackdrop extends StatefulWidget {
  const CosmosBackdrop({super.key, required this.child});

  final Widget child;

  /// Full cycle of celestial shimmer / orbital drift.
  static const Duration period = Duration(seconds: 45);

  /// Low-rate refresh (15 fps) to eliminate GPU/battery drain.
  static const Duration step = Duration(milliseconds: 66);

  /// Tests that check layout turn this off globally so pumpAndSettle can settle.
  static bool debugAnimate = true;

  @override
  State<CosmosBackdrop> createState() => CosmosBackdropState();
}

@visibleForTesting
class CosmosBackdropState extends State<CosmosBackdrop> {
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  AppLifecycleState? _appState = WidgetsBinding.instance.lifecycleState;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _reduceMotion = false;

  bool get isAnimating => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        _appState = s;
        _sync();
      },
    );
    DeviceControls.inPip.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final mode = TickerMode.getValuesNotifier(context);
    if (!identical(mode, _tickerMode)) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = mode..addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    DeviceControls.inPip.removeListener(_sync);
    _tickerMode?.removeListener(_sync);
    _progress.dispose();
    super.dispose();
  }

  bool get _shouldRun =>
      CosmosBackdrop.debugAnimate &&
      !_reduceMotion &&
      (_tickerMode?.value.enabled ?? true) &&
      !DeviceControls.inPip.value &&
      (_appState == null || _appState == AppLifecycleState.resumed);

  void _sync() {
    if (!mounted) return;
    if (_shouldRun) {
      if (_timer != null) return;
      _clock.start();
      _timer = Timer.periodic(CosmosBackdrop.step, (_) {
        final t = _clock.elapsedMicroseconds / CosmosBackdrop.period.inMicroseconds;
        _progress.value = t - t.floorToDouble();
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _clock.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = palette.isDark;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: palette.background,
          ),
        ),
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, progress, _) {
              return CustomPaint(
                painter: _CosmosPainter(
                  progress: progress,
                  palette: palette,
                  isDark: isDark,
                ),
              );
            },
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _CosmosPainter extends CustomPainter {
  final double progress;
  final AppPalette palette;
  final bool isDark;

  _CosmosPainter({
    required this.progress,
    required this.palette,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final primary = palette.primary;
    final accent = palette.accent;

    // 1. Nebulae Gradients
    final n1Center = Offset(
      size.width * 0.78 + math.sin(progress * 2 * math.pi) * 12,
      size.height * 0.18 + math.cos(progress * 2 * math.pi) * 16,
    );
    final n1Radius = size.width * 0.65;
    canvas.drawCircle(
      n1Center,
      n1Radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.13 : 0.08),
            accent.withValues(alpha: isDark ? 0.04 : 0.02),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: n1Center, radius: n1Radius)),
    );

    final n2Center = Offset(
      size.width * 0.22 - math.cos(progress * 2 * math.pi) * 15,
      size.height * 0.72 + math.sin(progress * 2 * math.pi) * 12,
    );
    final n2Radius = size.width * 0.75;
    canvas.drawCircle(
      n2Center,
      n2Radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: isDark ? 0.11 : 0.07),
            primary.withValues(alpha: isDark ? 0.03 : 0.015),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: n2Center, radius: n2Radius)),
    );

    // 2. Twinkling Starfield (Deterministic Pseudo-Random)
    const starCount = 52;
    for (int i = 0; i < starCount; i++) {
      final seedX = ((i * 137.5) % 1000) / 1000.0;
      final seedY = ((i * 293.7 + 123) % 1000) / 1000.0;
      final starSize = (i % 5 == 0) ? 1.8 : ((i % 3 == 0) ? 1.3 : 0.9);
      final phase = (i * 0.23);
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi * 3 + phase));

      final x = seedX * size.width;
      final y = seedY * size.height;

      final starColor = (i % 4 == 0)
          ? accent.withValues(alpha: (isDark ? 0.75 : 0.45) * twinkle)
          : (i % 6 == 0
              ? primary.withValues(alpha: (isDark ? 0.70 : 0.40) * twinkle)
              : palette.textPrimary.withValues(alpha: (isDark ? 0.55 : 0.30) * twinkle));

      canvas.drawCircle(
        Offset(x, y),
        starSize,
        Paint()..color = starColor,
      );
    }

    // 3. Miniature Distant Celestial Orbs
    // Small planet 1: Top right mini orb
    final p1Center = Offset(
      size.width * 0.86,
      size.height * 0.09,
    );
    const p1Radius = 14.0;
    canvas.drawCircle(
      p1Center,
      p1Radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            accent.withValues(alpha: isDark ? 0.85 : 0.55),
            primary.withValues(alpha: isDark ? 0.5 : 0.3),
            palette.background.withValues(alpha: 0.9),
          ],
        ).createShader(Rect.fromCircle(center: p1Center, radius: p1Radius)),
    );

    // Small planet 2: Lower left tiny crescent orb with ring
    final p2Center = Offset(
      size.width * 0.12,
      size.height * 0.48,
    );
    const p2Radius = 8.0;
    canvas.drawCircle(
      p2Center,
      p2Radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            primary.withValues(alpha: isDark ? 0.9 : 0.6),
            palette.background.withValues(alpha: 0.8),
          ],
        ).createShader(Rect.fromCircle(center: p2Center, radius: p2Radius)),
    );
    // Planet 2 ring
    canvas.save();
    canvas.translate(p2Center.dx, p2Center.dy);
    canvas.rotate(-math.pi / 6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: p2Radius * 3.2, height: p2Radius * 0.9),
      Paint()
        ..color = primary.withValues(alpha: isDark ? 0.35 : 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CosmosPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark || oldDelegate.palette != palette;
}
