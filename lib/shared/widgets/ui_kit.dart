import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/services/artwork_presence.dart';
import '../../core/services/artwork_service.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';

export 'ink_dock.dart';

// Every widget here reads `context.palette`, so it is right in both the ink
// and the paper theme. The three Volt widgets (VoltButton, VoltDisc,
// VoltSlab) are the only places outside the theme that paint Volt fills
// (test/unit/volt_usage_test.dart); on paper they always carry the 1.5 dp
// ink edge.

/// A blurred, translucent surface: [AppPalette.glass] (paper glass in the
/// light theme), or [color] when given.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;
  final double blur;

  /// Overrides the palette's glass fill.
  final Color? color;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.border,
    this.blur = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? context.palette.glass,
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Screen section heading with an optional trailing action.
///
/// The action's label ends on the same edge as the title's gutter: the
/// button's own [actionButtonPadding] makes up the part of the end padding
/// it takes away, so "See all" lines up with the cards below it while its
/// touch target stays at least 48 dp tall and 64 dp wide.
///
/// With a [kicker] (docs/DESIGN.md 7.5) the header stacks, top to bottom: a
/// 2 dp [AppPalette.rule] across the gutter ([showRule]), 12 dp, the kicker
/// in `overline` / primary, 4 dp, then the title row. Use the rule only on
/// screen-level sections, never inside sheets or cards.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  /// Short app-written line above the title ("FROM YOUR LIBRARY"). Shown in
  /// capitals; never user content.
  final String? kicker;

  /// Draws the 2 dp rule above the kicker. Defaults to whether there is a
  /// [kicker].
  final bool? showRule;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.kicker,
    this.showRule,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg16,
      AppSpacing.xxl24,
      AppSpacing.lg16,
      AppSpacing.sm8,
    ),
  });

  /// Horizontal padding inside the action button, fixed at every text size
  /// so the label's end edge never moves.
  static const double actionButtonPadding = AppSpacing.md12;

  /// Thickness of the rule above a kicker.
  static const double ruleThickness = 2;

  /// Length of the brand segment that leads the rule.
  static const double ruleAccentWidth = 28;

  /// The action button's narrowest width (Material's TextButton minimum).
  static const double _actionMinWidth = 64;

  /// Style for a section's trailing [TextButton].
  static final ButtonStyle actionStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: actionButtonPadding),
  );

  /// [padding] with its end side shortened by the action button's own
  /// padding, so the label (not the button's box) sits on the gutter.
  static EdgeInsets paddingWithAction(EdgeInsetsGeometry padding, TextDirection direction) {
    final resolved = padding.resolve(direction);
    double shorten(double side) => math.max(0, side - actionButtonPadding);
    return direction == TextDirection.ltr
        ? resolved.copyWith(right: shorten(resolved.right))
        : resolved.copyWith(left: shorten(resolved.left));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final label = actionLabel;
    final direction = Directionality.of(context);
    final resolved = padding.resolve(direction);
    final outer = label == null ? resolved : paddingWithAction(padding, direction);

    final titleText = Semantics(
      header: true,
      child: Text(title, style: type.sectionTitle),
    );

    // The action keeps its 48 dp target but takes no height of its own: it
    // is laid over the header, centred on the title's last line, and the
    // title row only reserves its width. A header with "See all" is then as
    // tall as one without, and its kicker sits as close to the title.
    final scaler = MediaQuery.textScalerOf(context);
    double reserve = 0;
    if (label != null) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: type.button),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      reserve = math.max(_actionMinWidth, painter.width + actionButtonPadding * 2) + 1;
      painter.dispose();
    }
    final row = Row(
      children: [
        Expanded(child: titleText),
        if (label != null) SizedBox(width: reserve),
      ],
    );

    final kicker = this.kicker;
    final rule = showRule ?? kicker != null;
    // The rule and kicker keep the full gutter even where the action button
    // borrows part of the end padding.
    final borrowed = (resolved.horizontal - outer.horizontal).clamp(0.0, double.infinity);
    final Widget header = kicker == null && !rule
        ? Padding(padding: outer, child: row)
        : Padding(
            padding: outer,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(end: borrowed),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rule) ...[
                        // The rule, led by a short brand segment.
                        Container(
                          height: ruleThickness,
                          color: palette.rule,
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(width: ruleAccentWidth, color: palette.primaryBase),
                        ),
                        const SizedBox(height: AppSpacing.md12),
                      ],
                      if (kicker != null) ...[
                        Text(
                          kicker.toUpperCase(),
                          semanticsLabel: kicker,
                          style: type.overline.copyWith(color: palette.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs4),
                      ],
                    ],
                  ),
                ),
                row,
              ],
            ),
          );
    if (label == null) return header;

    final titleLine = scaler.scale(type.sectionTitle.fontSize!) * type.sectionTitle.height!;
    final end = direction == TextDirection.ltr ? outer.right : outer.left;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        header,
        PositionedDirectional(
          end: end,
          bottom: outer.bottom + titleLine / 2 - kMinInteractiveDimension / 2,
          height: kMinInteractiveDimension,
          child: Center(
            child: TextButton(style: actionStyle, onPressed: onAction, child: Text(label)),
          ),
        ),
      ],
    );
  }
}

/// Small rounded label ("Video", "1080p", "Family use" ...) in the `badge`
/// type, radius 6.
///
/// Tinted (default): [color] text on [color] at 14 %. Filled: [color] fill
/// with [onColor] text; use the on-colour pairs only (primary / onPrimary,
/// accent / onAccent, liveFill / onLive). [color] defaults to the palette's
/// primary and [onColor] to its onPrimary.
class PillTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  final Color? onColor;
  final bool filled;

  const PillTag({
    super.key,
    required this.text,
    this.icon,
    this.color,
    this.onColor,
    this.filled = false,
  });

  /// Opacity of the tinted fill.
  static const double tintAlpha = 0.14;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = this.color ?? palette.primary;
    final ink = filled ? (onColor ?? palette.onPrimary) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: tintAlpha),
        borderRadius: BorderRadius.circular(AppSpacing.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.of(palette).badge.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark chip every badge over a cover or video frame sits on, so it
/// reads on any picture, bright or dark. Overlay chips look the same in both
/// themes.
class _OverlayChip extends StatelessWidget {
  final Widget child;
  final Color? color;

  const _OverlayChip({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? context.palette.overlay,
        borderRadius: BorderRadius.circular(AppSpacing.radiusBadge),
      ),
      child: child,
    );
  }
}

/// Running time over a thumbnail ("3:05", "1:02:03"), or a LIVE marker.
///
/// The time is tabular `badge` figures on the dark [AppPalette.overlay]
/// chip, so it reads on any frame, bright or dark. LIVE is a solid
/// [AppPalette.liveFill] chip with a white label (no dot).
class DurationBadge extends StatelessWidget {
  final Duration? duration;
  final bool isLive;

  const DurationBadge({super.key, required Duration this.duration}) : isLive = false;

  /// A solid "LIVE" chip, for live streams (which have no length).
  const DurationBadge.live({super.key})
      : duration = null,
        isLive = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final badge = AppTypography.of(palette).badge;
    if (isLive) {
      return _OverlayChip(
        color: palette.liveFill,
        child: Text('LIVE', style: badge.copyWith(color: palette.onLive), maxLines: 1),
      );
    }
    return _OverlayChip(
      child: Text(
        formatClock(duration ?? Duration.zero),
        style: badge.copyWith(
          color: palette.onOverlay,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        maxLines: 1,
      ),
    );
  }
}

/// A status over a cover or video frame ("Downloaded"): a 16 dp Ice glyph
/// and white text on the same dark chip as [DurationBadge], so every badge
/// over media looks alike and reads on any picture.
class MediaBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const MediaBadge({super.key, required this.icon, required this.text});

  static const double _iconSize = 16;

  /// Ice in both themes: the chip is ink in both, and the paper theme's deep
  /// ice would not read on it (docs/DESIGN.md 4: 4.12:1 or more over a white
  /// frame).
  static Color get glyphColor => AppPalette.dark.accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _OverlayChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _iconSize, color: glyphColor),
          const SizedBox(width: AppSpacing.xs4),
          Text(
            text,
            style: AppTypography.of(palette).badge.copyWith(color: palette.onOverlay),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Rounded surface used for grouped content (settings groups, empty states
/// ...): [AppPalette.surface], radius 20, a 1 dp [AppPalette.divider] edge;
/// [AppPalette.surfacePressed] while pressed.
///
/// A [gradient] that changes (a card switching to the neutral violet once a
/// cover finishes loading) cross-fades instead of snapping; instantly with
/// reduced motion.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg16),
    this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gradient = this.gradient;
    if (gradient == null) return _card(palette, null);
    return TweenAnimationBuilder<Gradient?>(
      tween: _GradientTween(end: gradient),
      duration: MotionTokens.duration(context, MotionTokens.page),
      curve: MotionTokens.easeOut,
      builder: (context, value, _) => _card(palette, value ?? gradient),
    );
  }

  /// The soft ink shadow under a card on paper (none on ink, where the
  /// hairline edge separates it).
  static List<BoxShadow> shadowsFor(AppPalette palette) => palette.isDark
      ? const []
      : [
          BoxShadow(color: palette.schemeShadow.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: palette.schemeShadow.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 6)),
        ];

  Widget _card(AppPalette palette, Gradient? gradient) {
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    final card = Material(
      color: gradient == null ? palette.surface : Colors.transparent,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: radius,
          border: Border.all(color: palette.divider),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          highlightColor: palette.surfacePressed,
          splashColor: palette.primaryBase.withValues(alpha: 0.10),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    final shadows = shadowsFor(palette);
    if (shadows.isEmpty) return card;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child: card,
    );
  }
}

class _GradientTween extends Tween<Gradient?> {
  _GradientTween({super.end});

  @override
  Gradient? lerp(double t) => Gradient.lerp(begin, end, t);
}

/// Friendly "nothing here" block (docs/DESIGN.md 7.15): an 84 dp halo
/// ([AppPalette.primaryBase] at 28 % to 4 %) holding a 38 dp primary icon,
/// an optional [kicker], a `sectionTitle` headline and a `body` message in
/// textSecondary. One [action] at most: a [VoltButton] if it plays or gets
/// media, else a FilledButton.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Short app-written line above the headline, shown in capitals.
  final String? kicker;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.kicker,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final kicker = this.kicker;
    return Center(
      child: EntranceFade(
        child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.primaryBase.withValues(alpha: 0.22)),
                gradient: RadialGradient(
                  colors: [
                    palette.primaryBase.withValues(alpha: 0.28),
                    palette.primaryBase.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Icon(icon, size: 38, color: palette.primary),
            ),
            const SizedBox(height: AppSpacing.xl20),
            if (kicker != null) ...[
              Text(
                kicker.toUpperCase(),
                semanticsLabel: kicker,
                style: type.overline.copyWith(color: palette.primary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs4),
            ],
            Text(title, style: type.sectionTitle, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm8),
            Text(
              message,
              style: type.body.copyWith(color: palette.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl20),
              action!,
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// A round tonal icon button (docs/DESIGN.md 7.3): the icon on a
/// [AppPalette.secondaryContainer] disc, 48 dp, with the crimson press wash
/// and a 0.97 press scale (instant with reduced motion). For secondary
/// actions next to a [VoltButton] (shuffle, add to playlist ...).
class TonalIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  const TonalIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
  });

  @override
  State<TonalIconButton> createState() => _TonalIconButtonState();
}

class _TonalIconButtonState extends State<TonalIconButton> with _PressedState<TonalIconButton> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = IconButton.filledTonal(
      statesController: states,
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      style: IconButton.styleFrom(
        backgroundColor: palette.secondaryContainer,
        foregroundColor: palette.onSecondaryContainer,
        disabledBackgroundColor: palette.textPrimary.withValues(alpha: 0.12),
        disabledForegroundColor: palette.textPrimary.withValues(alpha: 0.38),
        fixedSize: Size.square(widget.size),
        shape: const CircleBorder(),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return palette.primaryBase.withValues(alpha: 0.18);
          if (s.contains(WidgetState.focused)) return palette.primaryBase.withValues(alpha: 0.14);
          if (s.contains(WidgetState.hovered)) return palette.primaryBase.withValues(alpha: 0.08);
          return null;
        }),
      ),
      icon: Icon(widget.icon),
    );
    return _PressScale(pressed: pressed, child: button);
  }
}

// ---------------------------------------------------------------------------
// Volt: the loud brand fill (docs/DESIGN.md 7.2 and 7.4). Only for "play" and
// "get" actions (Play, Play all, Download, Save offline, Continue).

/// Thickness of the ink edge every Volt fill carries on paper.
const double voltEdgeWidth = 1.5;

/// The ink edge of a Volt fill: [AppPalette.voltEdge] on paper, nothing on
/// ink (where the edge colour is transparent).
BorderSide _voltEdge(AppPalette palette) =>
    palette.voltEdge.a > 0 ? BorderSide(color: palette.voltEdge, width: voltEdgeWidth) : BorderSide.none;

/// Scales a Volt widget to [MotionTokens.pressedScale] while it is pressed
/// (120 ms ease-out; instant with reduced motion).
class _PressScale extends StatelessWidget {
  final bool pressed;
  final Widget child;

  const _PressScale({required this.pressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: pressed ? MotionTokens.pressedScale : 1,
      duration: MotionTokens.duration(context, MotionTokens.micro),
      curve: MotionTokens.easeOut,
      child: child,
    );
  }
}

/// Tracks whether a button's [WidgetStatesController] reports pressed.
mixin _PressedState<T extends StatefulWidget> on State<T> {
  final WidgetStatesController states = WidgetStatesController();
  bool pressed = false;

  @override
  void initState() {
    super.initState();
    states.addListener(_onStates);
  }

  void _onStates() {
    final now = states.value.contains(WidgetState.pressed);
    if (now != pressed && mounted) setState(() => pressed = now);
  }

  @override
  void dispose() {
    states
      ..removeListener(_onStates)
      ..dispose();
    super.dispose();
  }
}

/// The "play" and "get" button: Play all, Download, Save offline, Fetch link.
///
/// A stadium in the Volt sheen ([AppPalette.primaryGradient]) with an ink
/// label and a 20 dp leading [icon]; on paper it carries the 1.5 dp ink
/// edge. 52 dp tall, or 40 dp ([VoltButton.compact]) in toolbars, always
/// inside a 48 dp touch target. Pressed: [AppPalette.voltPressed] and a
/// 0.97 scale. Disabled: [AppPalette.surfacePressed] with a textMuted label
/// (paper keeps an outline edge).
class VoltButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// 40 dp tall with 12 dp side padding, for toolbars and the watch strip.
  final bool compact;

  /// Fills the available width (the Downloads link field's button).
  final bool expand;

  final FocusNode? focusNode;
  final bool autofocus;

  const VoltButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.onLongPress,
    this.expand = false,
    this.focusNode,
    this.autofocus = false,
  }) : compact = false;

  const VoltButton.compact({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
  })  : compact = true,
        expand = false;

  static const double height = 52;
  static const double compactHeight = 40;
  static const double iconSize = 20;

  @override
  State<VoltButton> createState() => _VoltButtonState();
}

class _VoltButtonState extends State<VoltButton> with _PressedState<VoltButton> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final height = widget.compact ? VoltButton.compactHeight : VoltButton.height;

    Color foreground(Set<WidgetState> s) => s.contains(WidgetState.disabled) ? palette.textMuted : palette.onVoltFill;

    final style = ButtonStyle(
      textStyle: WidgetStatePropertyAll(type.button),
      foregroundColor: WidgetStateProperty.resolveWith(foreground),
      iconColor: WidgetStateProperty.resolveWith(foreground),
      iconSize: const WidgetStatePropertyAll(VoltButton.iconSize),
      // The fill is drawn by the background builder below.
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return Colors.transparent;
        if (s.contains(WidgetState.focused)) return palette.onVoltFill.withValues(alpha: 0.10);
        if (s.contains(WidgetState.hovered)) return palette.onVoltFill.withValues(alpha: 0.08);
        return null;
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: widget.compact ? AppSpacing.md12 : AppSpacing.xxl24),
      ),
      minimumSize: WidgetStatePropertyAll(widget.expand ? Size.fromHeight(height) : Size(height, height)),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      // The button's own Material paints its border under the background,
      // so the edge is part of the background decoration instead.
      side: const WidgetStatePropertyAll(BorderSide.none),
      backgroundBuilder: (context, states, child) => DecoratedBox(
        decoration: _voltButtonDecoration(palette, states),
        child: child,
      ),
    );

    final icon = widget.icon;
    final label = Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final button = icon == null
        ? FilledButton(
            style: style,
            statesController: states,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onPressed: widget.onPressed,
            onLongPress: widget.onLongPress,
            child: label,
          )
        : FilledButton.icon(
            style: style,
            statesController: states,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onPressed: widget.onPressed,
            onLongPress: widget.onLongPress,
            icon: Icon(icon),
            label: label,
          );
    return _PressScale(pressed: pressed, child: button);
  }
}

/// [VoltButton]'s fill and edge for [states]: the sheen, the pressed Volt, or
/// the disabled surface; the ink edge on paper (an outline when disabled),
/// and a 2 dp ink ring while focused by keyboard or D-pad.
ShapeDecoration _voltButtonDecoration(AppPalette palette, Set<WidgetState> states) {
  final disabled = states.contains(WidgetState.disabled);
  final pressed = states.contains(WidgetState.pressed);
  BorderSide side;
  if (disabled) {
    side = palette.isDark ? BorderSide.none : BorderSide(color: palette.outline, width: voltEdgeWidth);
  } else if (states.contains(WidgetState.focused)) {
    side = BorderSide(color: palette.onVoltFill, width: 2);
  } else {
    side = _voltEdge(palette);
  }
  return ShapeDecoration(
    shape: StadiumBorder(side: side),
    color: disabled ? palette.surfacePressed : (pressed ? palette.voltPressed : null),
    gradient: disabled || pressed ? null : palette.primaryGradient,
    shadows: voltGlowShadows(palette, disabled: disabled, pressed: pressed),
  );
}

/// The soft crimson glow under an enabled Volt button or disc: only where the
/// palette has a glow (ink; transparent on paper, where the ink edge does the
/// job), tighter while pressed, none when disabled.
List<BoxShadow> voltGlowShadows(AppPalette palette, {bool disabled = false, bool pressed = false}) {
  if (disabled || palette.voltGlow.a == 0) return const [];
  return [
    BoxShadow(
      color: palette.voltGlow,
      blurRadius: pressed ? 8 : 18,
      offset: Offset(0, pressed ? 2 : 6),
      spreadRadius: -2,
    ),
  ];
}

/// Round Volt play button with an ink glyph: [small] 44 dp (mini player, 24
/// glyph), [medium] 56 dp (detail hero, 28), [large] 72 dp (the stage, 36,
/// with [AppPalette.voltGlow] under it on ink). On paper it carries the ink
/// edge. Always inside a 48 dp touch target.
class VoltDisc extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  /// Read by screen readers ("Play", "Pause").
  final String? semanticLabel;

  /// Shown on long press / hover. Leave null where the label is obvious.
  final String? tooltip;

  const VoltDisc({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = medium,
    this.semanticLabel,
    this.tooltip,
  });

  static const double small = 44;
  static const double medium = 56;
  static const double large = 72;

  /// Glyph edge for a disc of [size]: 24 / 28 / 36 for the three sizes.
  static double glyphSizeFor(double size) {
    if (size <= small) return 24;
    if (size <= medium) return 28;
    if (size <= large) return 36;
    return size / 2;
  }

  @override
  State<VoltDisc> createState() => _VoltDiscState();
}

class _VoltDiscState extends State<VoltDisc> with _PressedState<VoltDisc> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.size;
    final edge = _voltEdge(palette);
    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return palette.surfacePressed;
        if (s.contains(WidgetState.pressed)) return palette.voltPressed;
        return palette.voltFill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? palette.textMuted : palette.onVoltFill,
      ),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return Colors.transparent;
        if (s.contains(WidgetState.focused)) return palette.onVoltFill.withValues(alpha: 0.10);
        if (s.contains(WidgetState.hovered)) return palette.onVoltFill.withValues(alpha: 0.08);
        return null;
      }),
      side: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.focused)) return BorderSide(color: palette.onVoltFill, width: 2);
        if (s.contains(WidgetState.disabled) && !palette.isDark) {
          return BorderSide(color: palette.outline, width: voltEdgeWidth);
        }
        return edge;
      }),
      shape: const WidgetStatePropertyAll(CircleBorder()),
      fixedSize: WidgetStatePropertyAll(Size.square(size)),
      minimumSize: WidgetStatePropertyAll(Size.square(size)),
      maximumSize: WidgetStatePropertyAll(Size.square(size)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      iconSize: WidgetStatePropertyAll(VoltDisc.glyphSizeFor(size)),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      elevation: const WidgetStatePropertyAll(0),
    );

    Widget disc = IconButton(
      style: style,
      statesController: states,
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      icon: Icon(widget.icon, semanticLabel: widget.semanticLabel),
    );

    // The glow under the stage disc only, and only where the palette has one
    // (none on paper).
    if (size >= VoltDisc.large && palette.voltGlow.a > 0 && widget.onPressed != null) {
      disc = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: palette.voltGlow, blurRadius: pressed ? 12 : 24)],
        ),
        child: disc,
      );
    }
    return _PressScale(pressed: pressed, child: disc);
  }
}

/// The "Continue listening" card at the top of Home (docs/DESIGN.md 7.4): the
/// one loud brand block on the screen.
///
/// The Volt sheen with radius 20 and 16 dp padding (plus the ink edge on
/// paper); a [kicker] in `overline` / onVoltMuted; the [title] in `cardTitle`
/// ink (one line, two at large text sizes; file-style names wrap at
/// underscores); a [subtitle] (the artist) in `metadata` / onVoltMuted,
/// followed by a [meta] figure ("2:19 left") that is never cut; a trailing
/// 48 dp ink disc with a Volt play glyph ([onPlay]);
/// and, with a [progress], a 3 dp ink line on an ink-20 % track 8 dp above
/// the bottom edge. Tap = [onTap] (resume), long press = [onLongPress]
/// (media sheet).
class VoltSlab extends StatefulWidget {
  final String title;
  final String kicker;
  final String? subtitle;

  /// A figure after the [subtitle], such as "2:19 left": the leading number
  /// (a clock or count) in DM Mono, after a " · ". The subtitle gives way
  /// first, so the figure is never ellipsized.
  final String? meta;

  /// 0..1, or null for no progress line.
  final double? progress;

  /// Optional art before the text (a 56 dp cover at radius 10).
  final Widget? leading;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlay;
  final IconData playIcon;
  final String playSemanticLabel;

  const VoltSlab({
    super.key,
    required this.title,
    this.kicker = 'Continue listening',
    this.subtitle,
    this.meta,
    this.progress,
    this.leading,
    this.onTap,
    this.onLongPress,
    this.onPlay,
    this.playIcon = Icons.play_arrow_rounded,
    this.playSemanticLabel = 'Play',
  });

  static const double playDiscSize = 48;
  static const double progressHeight = 3;
  static const double progressInset = 8;

  @override
  State<VoltSlab> createState() => _VoltSlabState();
}

class _VoltSlabState extends State<VoltSlab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    final shape = RoundedRectangleBorder(borderRadius: radius, side: _voltEdge(palette));
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    final subtitle = widget.subtitle;
    final meta = widget.meta;
    final progress = widget.progress?.clamp(0.0, 1.0);
    final leading = widget.leading;
    final metaStyle = type.metadata.copyWith(color: palette.onVoltMuted);

    Widget? metaLine;
    if (meta != null) {
      // "2:19 left": the figure in DM Mono at the meta line's size.
      final figure = RegExp(r'^[0-9:.,]+').stringMatch(meta) ?? '';
      metaLine = Text.rich(
        TextSpan(
          children: [
            if (subtitle != null) const TextSpan(text: ' · '),
            if (figure.isNotEmpty)
              TextSpan(
                text: figure,
                style: type.tabularFigures.copyWith(
                  fontSize: metaStyle.fontSize,
                  height: metaStyle.height,
                  color: palette.onVoltMuted,
                ),
              ),
            TextSpan(text: meta.substring(figure.length)),
          ],
        ),
        semanticsLabel: meta,
        style: metaStyle,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
    }

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.kicker.toUpperCase(),
          semanticsLabel: widget.kicker,
          style: type.overline.copyWith(color: palette.onVoltMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs4),
        Text(
          breakableTitle(widget.title),
          semanticsLabel: widget.title,
          style: type.cardTitle.copyWith(color: palette.onVoltFill),
          maxLines: largeText ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null && metaLine == null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: metaStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (metaLine != null) ...[
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                if (subtitle != null)
                  Flexible(
                    child: Text(
                      subtitle,
                      style: metaStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // An ellipsized artist is as wide as what it shows, so
                      // the figure follows the "…" without a gap.
                      textWidthBasis: TextWidthBasis.longestLine,
                    ),
                  ),
                // Only a line too narrow for the figure itself cuts it.
                ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth), child: metaLine),
              ],
            ),
          ),
        ],
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg16),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: AppSpacing.md12)],
          Expanded(child: text),
          const SizedBox(width: AppSpacing.md12),
          IconButton(
            onPressed: widget.onPlay,
            tooltip: widget.playSemanticLabel,
            style: IconButton.styleFrom(
              backgroundColor: palette.onVoltFill,
              foregroundColor: palette.voltFill,
              fixedSize: const Size.square(VoltSlab.playDiscSize),
              iconSize: 28,
              shape: const CircleBorder(),
            ),
            icon: Icon(widget.playIcon),
          ),
        ],
      ),
    );

    return _PressScale(
      pressed: _pressed,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: ShapeDecoration(shape: shape, gradient: palette.primaryGradient),
          child: InkWell(
            customBorder: shape,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            overlayColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.pressed)) return palette.onVoltFill.withValues(alpha: 0.10);
              if (s.contains(WidgetState.focused)) return palette.onVoltFill.withValues(alpha: 0.10);
              if (s.contains(WidgetState.hovered)) return palette.onVoltFill.withValues(alpha: 0.08);
              return null;
            }),
            child: progress == null
                ? content
                : Stack(
                    children: [
                      content,
                      PositionedDirectional(
                        start: AppSpacing.lg16,
                        end: AppSpacing.lg16,
                        bottom: VoltSlab.progressInset,
                        height: VoltSlab.progressHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(VoltSlab.progressHeight / 2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: VoltSlab.progressHeight,
                            color: palette.onVoltFill,
                            backgroundColor: palette.onVoltFill.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Builds [builder] with whether [item] has a real cover ([hasRealArtwork]),
/// and builds it again once the device's art for [item] finishes loading.
///
/// Surfaces tinted with an item's palette use this to switch to the neutral
/// brand colours when the item shows its own cover, including the first
/// time the cover loads (a plain [hasRealArtwork] check at build time would
/// miss it). Pass the lookup size of the `ArtworkThumbnail` that shows the
/// cover (256 up to 150 dp, 512 up to 300 dp), so both share one platform
/// lookup. [child], when given, is passed through to [builder] unchanged
/// (as in [ValueListenableBuilder]), so a large subtree is not rebuilt.
class ArtworkPresenceBuilder extends StatefulWidget {
  final MediaItem? item;
  final int lookupSize;
  final Widget Function(BuildContext context, bool hasArtwork, Widget? child) builder;
  final Widget? child;

  /// What [builder] gets while the device lookup has not answered yet (an
  /// empty art cache right after launch). True, the default, starts on the
  /// neutral colours, so a song that has a cover (most do) never flashes
  /// its placeholder palette first; one without a cover then fades to its
  /// palette. A lookup that already found nothing answers false at once.
  final bool assumeArtworkWhileLoading;

  const ArtworkPresenceBuilder({
    super.key,
    required this.item,
    required this.lookupSize,
    required this.builder,
    this.child,
    this.assumeArtworkWhileLoading = true,
  });

  @override
  State<ArtworkPresenceBuilder> createState() => _ArtworkPresenceBuilderState();
}

class _ArtworkPresenceBuilderState extends State<ArtworkPresenceBuilder> {
  bool _hasArtwork = false;
  String? _uri;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ArtworkPresenceBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item?.uri != widget.item?.uri ||
        oldWidget.item?.artworkPath != widget.item?.artworkPath ||
        oldWidget.lookupSize != widget.lookupSize) {
      _resolve();
    }
  }

  void _resolve() {
    final item = widget.item;
    _uri = item?.uri;
    if (item == null) {
      _hasArtwork = false;
      return;
    }
    if (hasRealArtwork(item)) {
      _hasArtwork = true;
      return;
    }
    final service = ArtworkService.instance;
    final uri = item.uri;
    if (service.isKnownMissing(uri, size: widget.lookupSize)) {
      _hasArtwork = false;
      return;
    }

    _hasArtwork = widget.assumeArtworkWhileLoading;
    final lookupSize = widget.lookupSize;
    service.getArtwork(uri, size: lookupSize).catchError((Object _) => null).then((bytes) {
      // A newer item or lookup size started its own lookup.
      if (!mounted || _uri != uri || widget.lookupSize != lookupSize) return;
      final hasArtwork = bytes != null;
      if (hasArtwork == _hasArtwork) return;
      setState(() => _hasArtwork = hasArtwork);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _hasArtwork, widget.child);
}

/// The masthead band at the top of a screen (docs/DESIGN.md 7.5): a rounded
/// [AppPalette.heroGradient] card holding the page title and its summary.
/// Text on it uses the ordinary text colours, which the contrast tests check
/// against every gradient stop.
class HeroBand extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  /// Adds the Sindur v2 glow: a soft wine orb in the top end corner and a
  /// plum / indigo one at the bottom start, painted under the child. Purely
  /// decorative; the text still sits on the verified hero gradient stops.
  final bool glow;

  static const EdgeInsetsGeometry defaultPadding = EdgeInsets.fromLTRB(
    AppSpacing.xl20,
    AppSpacing.xl20,
    AppSpacing.xl20,
    AppSpacing.lg16,
  );

  const HeroBand({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = defaultPadding,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    Widget content = Padding(padding: padding, child: child);
    if (glow) {
      content = Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.95, -1.1),
                    radius: 1.1,
                    colors: [palette.primaryBase.withValues(alpha: palette.isDark ? 0.30 : 0.10), palette.primaryBase.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.1, 1.2),
                    radius: 1.0,
                    colors: [palette.secondaryContainer.withValues(alpha: palette.isDark ? 0.55 : 0.35), palette.secondaryContainer.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          content,
        ],
      );
    }
    return Container(
      margin: margin,
      width: double.infinity,
      clipBehavior: glow ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        gradient: palette.heroGradient,
        borderRadius: radius,
        border: Border.all(color: palette.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: content,
    );
  }
}

/// A large Volt block (Sindur v2 Home bento): a big glyph over a Fraunces
/// label on the loud brand fill, the primary gradient sheen included.
///
/// Effects: a slow diagonal shine sweeps across it every [shineEvery] (none
/// with reduced motion), the Volt glow sits under it on ink, and a press
/// scales it to 0.97 with a ripple while the glyph gives a small turn.
class VoltTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String semanticLabel;
  final double height;
  final VoidCallback onTap;

  const VoltTile({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.height,
    required this.onTap,
  });

  /// Time between two shine sweeps.
  static const Duration shineEvery = Duration(seconds: 6);

  /// Length of one sweep.
  static const Duration shineSweep = Duration(milliseconds: 1400);

  @override
  State<VoltTile> createState() => _VoltTileState();
}

class _VoltTileState extends State<VoltTile> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(vsync: this, duration: VoltTile.shineSweep);
  Timer? _timer;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MotionTokens.duration(context, MotionTokens.page) == Duration.zero;
    if (reduced) {
      _timer?.cancel();
      _timer = null;
      _shine.value = 0;
    } else {
      _timer ??= Timer.periodic(VoltTile.shineEvery, (_) {
        if (mounted && TickerMode.valuesOf(context).enabled) _shine.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shine.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (value != _pressed) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    final press = MotionTokens.duration(context, MotionTokens.micro);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed ? MotionTokens.pressedScale : 1,
        duration: press,
        curve: MotionTokens.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: voltGlowShadows(palette, pressed: _pressed),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: ShapeDecoration(
                gradient: palette.primaryGradient,
                shape: RoundedRectangleBorder(borderRadius: radius, side: _voltEdge(palette)),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: radius),
                onTap: widget.onTap,
                onHighlightChanged: _setPressed,
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ClipRRect(
                            borderRadius: radius,
                            child: AnimatedBuilder(
                              animation: _shine,
                              builder: (context, _) => _shine.value == 0 || _shine.value == 1
                                  ? const SizedBox.shrink()
                                  : CustomPaint(
                                      key: const ValueKey('volt_tile_shine'),
                                      painter: _ShinePainter(_shine.value, palette.onVoltFill),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PressGlyph(
                              pressed: _pressed,
                              child: Icon(widget.icon, size: 32, color: palette.onVoltFill),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                widget.label,
                                style: type.cardTitle.copyWith(color: palette.onVoltFill),
                                maxLines: 1,
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
      ),
    );
  }
}

/// The shine band: a soft diagonal streak at [t] (0..1) of its way across.
class _ShinePainter extends CustomPainter {
  final double t;
  final Color tint;

  const _ShinePainter(this.t, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final band = size.shortestSide * 0.9;
    final travel = size.width + size.height + band * 2;
    final x = -band - size.height + travel * Curves.easeInOut.transform(t);
    final rect = Rect.fromLTWH(x, 0, band, size.height);
    canvas
      ..save()
      ..translate(rect.center.dx, size.height / 2)
      ..skew(-0.5, 0)
      ..translate(-rect.center.dx, -size.height / 2)
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [tint.withValues(alpha: 0), tint.withValues(alpha: 0.14), tint.withValues(alpha: 0)],
          ).createShader(rect),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_ShinePainter oldDelegate) => oldDelegate.t != t || oldDelegate.tint != tint;
}

/// A glyph that gives a small turn and grows a touch while [pressed]
/// (instant with reduced motion). Used by the Home bento tiles.
class PressGlyph extends StatelessWidget {
  final bool pressed;
  final Widget child;

  const PressGlyph({super.key, required this.pressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.duration(context, MotionTokens.feedback);
    return AnimatedRotation(
      turns: pressed ? -0.03 : 0,
      duration: duration,
      curve: MotionTokens.easeOut,
      child: AnimatedScale(
        scale: pressed ? 1.12 : 1,
        duration: duration,
        curve: MotionTokens.easeOut,
        child: child,
      ),
    );
  }
}

/// The Sindur v2 spark: a short rounded amber bar that marks a section title.
/// Decorative (never the only cue), so it skips the text contrast floors.
class SparkMark extends StatelessWidget {
  final double height;
  const SparkMark({super.key, this.height = 18});

  static const double width = 4;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.palette.navIndicator,
          borderRadius: BorderRadius.circular(width),
        ),
      ),
    );
  }
}

/// Fades [child] in and lifts it 8 dp on first build ([MotionTokens.page],
/// emphasised curve), [index] x 40 ms after the first item so a list
/// staggers. Shown at once with reduced motion. Purely visual: the child is
/// built, laid out and in the semantics tree from the first frame.
class EntranceFade extends StatefulWidget {
  final Widget child;
  final int index;

  const EntranceFade({super.key, required this.child, this.index = 0});

  static const Duration stagger = Duration(milliseconds: 40);

  /// Items after this many share its delay, so a long list never waits.
  static const int maxStagger = 6;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _curve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final base = MotionTokens.duration(context, MotionTokens.page);
    if (base == Duration.zero) return;
    final delay = EntranceFade.stagger * math.min(widget.index, EntranceFade.maxStagger);
    final total = base + delay;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _curve = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: MotionTokens.emphasized),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null) return widget.child;
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        alwaysIncludeSemantics: true,
        child: Transform.translate(offset: Offset(0, 8 * (1 - curve.value)), child: child),
      ),
      child: widget.child,
    );
  }
}
