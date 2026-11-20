import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_typography.dart';

/// The Home hero greeting with a name: "नमस्ते," and beside it (or on the
/// next line when there is no room) the name in Fraunces bold italic with a
/// gradient fill and a small waving hand. The name fades and slides in once
/// with a light sweep; with reduced motion it is drawn static.
class GreetingName extends StatefulWidget {
  final String name;

  const GreetingName({super.key, required this.name});

  static const String namaste = 'नमस्ते,';

  /// Dark: rose → amber. Light: wine → indigo. Both checked against the hero.
  static const List<Color> darkGradient = [Color(0xFFFF7A92), Color(0xFFF69E1C)];
  static const List<Color> lightGradient = [Color(0xFF81021F), Color(0xFF3F2A8C)];

  static const Duration revealDuration = Duration(milliseconds: 1100);

  @override
  State<GreetingName> createState() => _GreetingNameState();
}

class _GreetingNameState extends State<GreetingName> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: GreetingName.revealDuration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(GreetingName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name && MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final colors = palette.isDark ? GreetingName.darkGradient : GreetingName.lightGradient;
    final nameStyle = type.greeting.copyWith(
      fontFamily: AppTypography.fraunces,
      fontFamilyFallback: AppTypography.headingFallback,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.3,
      color: Colors.white, // replaced by the gradient (srcIn)
    );

    final reveal = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOutCubic));

    final name = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // A light band sweeps once across the gradient, then settles.
        final t = _controller.value;
        final sweep = Curves.easeInOut.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0));
        final shine = t >= 1 ? 0.0 : (1 - (2 * sweep - 1).abs());
        final highlight = Color.lerp(colors.first, Colors.white, (palette.isDark ? 0.55 : 0.2) * shine)!;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final mid = (-0.2 + 1.4 * sweep).clamp(0.0, 1.0);
            return LinearGradient(
              colors: [colors.first, highlight, colors.last],
              stops: [0, mid, 1],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Text(
        widget.name,
        key: const ValueKey('greeting_name'),
        style: nameStyle,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final hand = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Two small waves, then still.
        final wave = t >= 1 ? 0.0 : 0.35 * (1 - t) * _wave(t);
        return Transform.rotate(angle: wave, alignment: Alignment.bottomCenter, child: child);
      },
      child: Icon(Icons.waving_hand_rounded, size: 22, color: colors.last, key: const ValueKey('greeting_wave')),
    );

    return Semantics(
      header: true,
      label: '${GreetingName.namaste} ${widget.name}',
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          Text(GreetingName.namaste, style: type.greeting, maxLines: 1),
          FadeTransition(
            opacity: reveal,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(reveal),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Padding(padding: const EdgeInsets.only(right: 2), child: name)),
                  const SizedBox(width: 6),
                  hand,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _wave(double t) {
    const waves = 2.0;
    final x = (t * waves * 2) % 2;
    return x < 1 ? x * 2 - 1 : 3 - x * 2;
  }
}
