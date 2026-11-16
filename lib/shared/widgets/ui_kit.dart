import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';

/// A blurred, translucent surface (bottom navigation, mini player).
class GlassContainer extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;
  final double blur;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.border,
    this.blur = 24,
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
            color: AppColors.glass,
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
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg16,
      AppSpacing.xxl24,
      AppSpacing.lg16,
      AppSpacing.sm8,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppTypography.sectionTitle),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Small rounded label ("Video", "1080p", "Downloaded" ...).
class PillTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  final bool filled;

  const PillTag({
    super.key,
    required this.text,
    this.icon,
    this.color = AppColors.primary,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? AppColors.onPrimary : color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppTypography.caption.copyWith(
              color: filled ? AppColors.onPrimary : color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Running time over a thumbnail ("03:05", "01:02:03"), or a LIVE marker.
///
/// A dark [AppColors.overlay] chip with [AppColors.onOverlay] tabular
/// figures, so it reads on any frame, bright or dark.
class DurationBadge extends StatelessWidget {
  final Duration? duration;
  final bool isLive;

  const DurationBadge({super.key, required Duration this.duration}) : isLive = false;

  /// "LIVE" with a red dot, for live streams (which have no length).
  const DurationBadge.live({super.key})
      : duration = null,
        isLive = true;

  static const double _radius = 6;
  static const double _dotSize = 6;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.tabularFigures.copyWith(
      color: AppColors.onOverlay,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: isLive ? 0.6 : 0.1,
    );
    final text = Text(
      isLive ? 'LIVE' : formatDuration(duration ?? Duration.zero),
      style: style,
      maxLines: 1,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.overlay,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: isLive
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                text,
              ],
            )
          : text,
    );
  }
}

/// Rounded surface used for grouped content (settings groups, empty states ...).
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
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    return Material(
      color: gradient == null ? AppColors.surface : Colors.transparent,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: radius,
          border: Border.all(color: AppColors.divider),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Friendly "nothing here" block with an icon in a soft circle.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
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
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.28),
                    AppColors.primary.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Icon(icon, size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.xl20),
            Text(title, style: AppTypography.sectionTitle, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm8),
            Text(message, style: AppTypography.metadata, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
