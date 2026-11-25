// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../core/platform/device_controls.dart';

/// Which planet a theme shows behind Settings.
enum PlanetLook {
  /// Sindur dark: a black-red, Mars-like world with a rose rim.
  mars,

  /// Sindur light: a sand and wine dune world with a lavender haze.
  dune,

  /// Bijuli Classic: a violet gas giant with a thin lime rim.
  gasGiant;

  static PlanetLook of(AppPalette palette) {
    if (palette.background == AppPalette.classic.background) return PlanetLook.gasGiant;
    return palette.isDark ? PlanetLook.mars : PlanetLook.dune;
  }
}

/// One large planet, mostly off-screen, behind Settings and its pages: its
/// centre is off-screen to the left, so its lit arc runs from the top-left,
/// out to about 70% of the width at mid-height, and back to the bottom-left.
/// The page colour is painted here, so the Scaffold on top is transparent;
/// cards and bars stay opaque over it.
///
/// Only the surface features turn (one turn per [period]). They are painted
/// once into their own layer and rotated by a Transform at about 15 fps from
/// a low-rate timer, never on every vsync. The motion stops with reduced
/// motion, when the app is not resumed, while a route covers this one
/// (TickerMode) and in picture-in-picture.
class PlanetBackdrop extends StatefulWidget {
  const PlanetBackdrop({super.key, required this.child, this.variant = 0});

  final Widget child;

  /// Small per-page shift of the crop (0 is Settings itself).
  final int variant;

  /// One full turn of the surface.
  static const Duration period = Duration(seconds: 90);

  /// Time between two rotation steps (about 15 fps: one turn takes 90 s, so
  /// the limb moves under 2 dp a step; 30 fps doubled the cost for no visible gain).
  static const Duration step = Duration(milliseconds: 66);

  /// Tests that only check layout turn the motion off globally (see
  /// test/flutter_test_config.dart) so `pumpAndSettle` can settle.
  static bool debugAnimate = true;

  @override
  State<PlanetBackdrop> createState() => PlanetBackdropState();
}

@visibleForTesting
class PlanetBackdropState extends State<PlanetBackdrop> {
  final ValueNotifier<double> _turn = ValueNotifier<double>(0);
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  AppLifecycleState? _appState = WidgetsBinding.instance.lifecycleState;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _reduceMotion = false;

  /// True while the surface is turning.
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

  bool get _shouldRun =>
      PlanetBackdrop.debugAnimate &&
      !_reduceMotion &&
      (_tickerMode?.value.enabled ?? true) &&
      !DeviceControls.inPip.value &&
      (_appState == null || _appState == AppLifecycleState.resumed);

  void _sync() {
    if (!mounted) return;
    if (_shouldRun) {
      if (_timer != null) return;
      _clock.start();
      _timer = Timer.periodic(PlanetBackdrop.step, (_) {
        final t = _clock.elapsedMicroseconds / PlanetBackdrop.period.inMicroseconds;
        _turn.value = t - t.floorToDouble();
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _clock.stop();
    }
  }

  ui.Image? _image;
  (PlanetLook, int)? _imageKey;

  /// The surface features, painted once into an image of [px] pixels; each
  /// frame only rotates it (a rotated picture would miss the raster cache and
  /// be re-rasterised every frame).
  ui.Image _surfaceImage(PlanetLook look, int px) {
    final image = _image;
    if (image != null && _imageKey == (look, px)) return image;
    final recorder = ui.PictureRecorder();
    _SurfacePainter(look).paint(Canvas(recorder), Size.square(px.toDouble()));
    final picture = recorder.endRecording();
    _image?.dispose();
    _image = picture.toImageSync(px, px);
    _imageKey = (look, px);
    picture.dispose();
    return _image!;
  }

  @override
  void dispose() {
    _image?.dispose();
    _timer?.cancel();
    _lifecycle.dispose();
    _tickerMode?.removeListener(_sync);
    DeviceControls.inPip.removeListener(_sync);
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final look = PlanetLook.of(palette);
    return ColoredBox(
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: RepaintBoundary(
              key: const ValueKey('planet_backdrop'),
              child: LayoutBuilder(
                builder: (context, box) {
                  final g = _PlanetGeometry.of(box.biggest, widget.variant);
                  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
                  final surface = RawImage(
                    image: _surfaceImage(look, (g.radius * 2 * dpr).clamp(64, 2048).round()),
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  );
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(child: CustomPaint(painter: _BodyPainter(look, g))),
                      ),
                      Positioned(
                        left: g.center.dx - g.radius,
                        top: g.center.dy - g.radius,
                        width: g.radius * 2,
                        height: g.radius * 2,
                        child: ClipOval(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _turn,
                            child: surface,
                            builder: (context, turn, child) =>
                                Transform.rotate(angle: turn * 2 * math.pi, child: child),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(child: CustomPaint(painter: _ShadePainter(look, g))),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Where the sphere sits: centre below and right of the screen, so only the
/// upper-left arc shows. Landscape moves it right.
class _PlanetGeometry {
  const _PlanetGeometry(this.center, this.radius);

  final Offset center;
  final double radius;

  static _PlanetGeometry of(Size size, int variant) {
    final w = size.width, h = size.height;
    // Per-page nudge of the centre, up or down a little.
    final cy = h * (0.5 + (variant % 3 - 1) * 0.03);
    if (w > h) {
      // Landscape: a shorter, wider screen; keep a left-side arc.
      final r = h * 0.78;
      return _PlanetGeometry(Offset(-r * 0.22, cy), r);
    }
    // The right edge crosses 70% of the width at mid-height and the arc
    // meets the left edge near the top and the bottom.
    final reach = w * 0.7, half = h * 0.42;
    final offset = math.max((half * half - reach * reach) / (2 * reach), reach * 0.25);
    return _PlanetGeometry(Offset(-offset, cy), offset + reach);
  }
}

class _Colors {
  const _Colors({
    required this.lit,
    required this.mid,
    required this.deep,
    required this.glow,
    required this.rim,
    required this.band,
    required this.bandLight,
    required this.crater,
    required this.opacity,
  });

  final Color lit, mid, deep, glow, rim, band, bandLight, crater;
  final double opacity;

  static _Colors of(PlanetLook look) => switch (look) {
    PlanetLook.mars => const _Colors(
      lit: Color(0xFF55101E),
      mid: Color(0xFF22060C),
      deep: Color(0xFF070103),
      glow: Color(0xFFCC324C),
      rim: Color(0xFFFF7A92),
      band: Color(0xFF14030A),
      bandLight: Color(0xFF8A2234),
      crater: Color(0xFF0C0205),
      opacity: 0.95,
    ),
    PlanetLook.dune => const _Colors(
      lit: Color(0xFFF1DDB4),
      mid: Color(0xFFD8B68A),
      deep: Color(0xFF7E3C4A),
      glow: Color(0xFFAAA6E3),
      rim: Color(0xFFC6CBE8),
      band: Color(0xFFB98A68),
      bandLight: Color(0xFFFFF3DC),
      crater: Color(0xFF8A4A50),
      opacity: 0.9,
    ),
    PlanetLook.gasGiant => const _Colors(
      lit: Color(0xFF4B2DA6),
      mid: Color(0xFF26144F),
      deep: Color(0xFF12072A),
      glow: Color(0xFF7B5CFF),
      rim: Color(0xFFCCFF3A),
      band: Color(0xFF0E0422),
      bandLight: Color(0xFF9B7BFF),
      crater: Color(0xFF1E0F3C),
      opacity: 0.95,
    ),
  };
}

/// Light comes from the upper right, so the lit limb faces the cards.
const Alignment _light = Alignment(0.7, -0.35);

/// Static: the halo outside the sphere and its base body gradient.
class _BodyPainter extends CustomPainter {
  _BodyPainter(this.look, this.g);

  final PlanetLook look;
  final _PlanetGeometry g;

  @override
  void paint(Canvas canvas, Size size) {
    final c = _Colors.of(look);
    final r = g.radius;
    final circle = Rect.fromCircle(center: g.center, radius: r);
    // Soft halo just outside the limb.
    final halo = Rect.fromCircle(center: g.center, radius: r * 1.18);
    canvas.drawCircle(
      g.center,
      r * 1.18,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.glow.withValues(alpha: 0.0),
            c.glow.withValues(alpha: look == PlanetLook.dune ? 0.22 : 0.22),
            c.glow.withValues(alpha: 0.0),
          ],
          stops: const [0.80, 0.855, 1.0],
        ).createShader(halo),
    );
    canvas.drawCircle(
      g.center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: _light,
          radius: 1.25,
          colors: [
            c.lit.withValues(alpha: c.opacity),
            c.mid.withValues(alpha: c.opacity),
            c.deep.withValues(alpha: c.opacity),
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(circle),
    );
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.look != look || old.g.center != g.center || old.g.radius != g.radius;
}

/// The turning layer: bands, dunes and soft craters, painted once into an
/// image (see [PlanetBackdropState._surfaceImage]).
class _SurfacePainter extends CustomPainter {
  _SurfacePainter(this.look);

  final PlanetLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final c = _Colors.of(look);
    final r = size.width / 2;
    final o = Offset(r, r);
    final rnd = math.Random(look.index * 31 + 7);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(-0.35);

    // Bands across the disc, softened by a vertical gradient each.
    final bandCount = look == PlanetLook.gasGiant ? 9 : 6;
    for (var i = 0; i < bandCount; i++) {
      final y = -r + (i + 0.5 + rnd.nextDouble() * 0.4) * (2 * r / bandCount);
      final h = r * (look == PlanetLook.gasGiant ? 0.10 : 0.07) * (0.6 + rnd.nextDouble());
      final dark = i.isEven;
      final color = dark ? c.band : c.bandLight;
      final alpha = switch (look) {
        PlanetLook.gasGiant => dark ? 0.55 : 0.16,
        PlanetLook.mars => dark ? 0.45 : 0.10,
        PlanetLook.dune => dark ? 0.5 : 0.4,
      };
      final rect = Rect.fromLTRB(-r * 1.1, y - h, r * 1.1, y + h);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect);
      if (look == PlanetLook.dune) {
        // Dunes: gentle waves rather than straight bands.
        final path = Path()..moveTo(rect.left, y);
        for (var x = rect.left; x <= rect.right; x += r * 0.08) {
          path.lineTo(x, y + math.sin(x / r * 9 + i) * h * 0.45);
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 1.2
            ..color = color.withValues(alpha: alpha * 0.8)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.5),
        );
      } else {
        canvas.drawRect(rect, paint);
      }
    }

    // Soft craters (Mars and the dunes); storms on the gas giant.
    final spots = look == PlanetLook.gasGiant ? 4 : 14;
    for (var i = 0; i < spots; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final d = math.sqrt(rnd.nextDouble()) * r * 0.95;
      final p = Offset(math.cos(a) * d, math.sin(a) * d);
      final s = r * (look == PlanetLook.gasGiant ? 0.06 : 0.025 + rnd.nextDouble() * 0.045);
      final rect = Rect.fromCenter(center: p, width: s * 2.2, height: s * 1.5);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.25, 0.3),
            colors: [
              c.crater.withValues(alpha: look == PlanetLook.dune ? 0.22 : 0.28),
              c.crater.withValues(alpha: 0.10),
              c.bandLight.withValues(alpha: look == PlanetLook.mars ? 0.10 : 0.14),
              c.bandLight.withValues(alpha: 0),
            ],
            stops: const [0, 0.55, 0.8, 1],
          ).createShader(rect.inflate(s * 0.2)),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SurfacePainter old) => old.look != look;
}

/// Static, over the turning layer: night-side shading (so the features turn
/// under fixed light) and the lit rim.
class _ShadePainter extends CustomPainter {
  _ShadePainter(this.look, this.g);

  final PlanetLook look;
  final _PlanetGeometry g;

  @override
  void paint(Canvas canvas, Size size) {
    final c = _Colors.of(look);
    final r = g.radius;
    final circle = Rect.fromCircle(center: g.center, radius: r);
    canvas.drawCircle(
      g.center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: _light,
          radius: 1.35,
          colors: [c.deep.withValues(alpha: 0), c.deep.withValues(alpha: 0.30), c.deep.withValues(alpha: 0.85)],
          stops: const [0.0, 0.35, 0.8],
        ).createShader(circle),
    );
    // Inner limb glow: the lit edge, strongest toward the light.
    canvas.drawCircle(
      g.center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.glow.withValues(alpha: 0),
            c.glow.withValues(alpha: look == PlanetLook.dune ? 0.30 : 0.35),
          ],
          stops: const [0.86, 1.0],
        ).createShader(circle),
    );
    // Thin atmospheric rim, bright toward the upper left.
    final rimRect = circle.deflate(1);
    canvas.drawCircle(
      g.center,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = look == PlanetLook.gasGiant ? 1.2 : 1.6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2)
        ..shader = SweepGradient(
          colors: [
            c.rim.withValues(alpha: 0.05),
            c.rim.withValues(alpha: look == PlanetLook.gasGiant ? 0.55 : 0.8),
            c.rim.withValues(alpha: 0.05),
          ],
          stops: const [0.25, 0.5, 0.75],
          // Brightest just above the right-hand point of the limb.
          transform: const GradientRotation(math.pi - 0.35),
        ).createShader(rimRect),
    );
    if (look == PlanetLook.gasGiant) {
      // A faint lime ring just off the limb.
      canvas.drawCircle(
        g.center,
        r * 1.06,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.rim.withValues(alpha: 0.10),
      );
    }
  }

  @override
  bool shouldRepaint(_ShadePainter old) => old.look != look || old.g.center != g.center || old.g.radius != g.radius;
}
