import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/services/artwork_presence.dart';
import '../../core/services/artwork_service.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';

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
///
/// The action's label ends on the same edge as the title's gutter: the
/// button's own [actionButtonPadding] makes up the part of the end padding
/// it takes away, so "See all" lines up with the cards below it while its
/// touch target stays at least 48 dp tall and 64 dp wide.
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

  /// Horizontal padding inside the action button, fixed at every text size
  /// so the label's end edge never moves.
  static const double actionButtonPadding = AppSpacing.md12;

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
    final label = actionLabel;
    return Padding(
      padding: label == null ? padding : paddingWithAction(padding, Directionality.of(context)),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppTypography.sectionTitle),
            ),
          ),
          if (label != null)
            TextButton(style: actionStyle, onPressed: onAction, child: Text(label)),
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

/// Text on an [AppColors.overlay] chip: 12/16 semibold, white.
TextStyle _overlayTextStyle({double letterSpacing = 0.1}) => AppTypography.caption.copyWith(
      color: AppColors.onOverlay,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: letterSpacing,
    );

/// The dark chip every badge over a cover or video frame sits on, so it
/// reads on any picture, bright or dark.
class _OverlayChip extends StatelessWidget {
  final Widget child;

  const _OverlayChip({required this.child});

  static const double _radius = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.overlay,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: child,
    );
  }
}

/// Running time over a thumbnail ("3:05", "1:02:03"), or a LIVE marker.
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

  static const double _dotSize = 6;

  @override
  Widget build(BuildContext context) {
    final style = _overlayTextStyle(letterSpacing: isLive ? 0.6 : 0.1).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final text = Text(
      isLive ? 'LIVE' : formatClock(duration ?? Duration.zero),
      style: style,
      maxLines: 1,
    );
    return _OverlayChip(
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

/// A status over a cover or video frame ("Downloaded"): a small teal glyph
/// and white text on the same dark chip as [DurationBadge], so every badge
/// over media looks alike and reads on any picture.
class MediaBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const MediaBadge({super.key, required this.icon, required this.text});

  static const double _iconSize = 12;

  @override
  Widget build(BuildContext context) {
    return _OverlayChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _iconSize, color: AppColors.accent),
          const SizedBox(width: AppSpacing.xs4),
          Text(text, style: _overlayTextStyle(), maxLines: 1),
        ],
      ),
    );
  }
}

/// Rounded surface used for grouped content (settings groups, empty states ...).
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
    final gradient = this.gradient;
    if (gradient == null) return _card(null);
    return TweenAnimationBuilder<Gradient?>(
      tween: _GradientTween(end: gradient),
      duration: MotionTokens.duration(context, MotionTokens.page),
      curve: MotionTokens.easeOut,
      builder: (context, value, _) => _card(value ?? gradient),
    );
  }

  Widget _card(Gradient? gradient) {
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

class _GradientTween extends Tween<Gradient?> {
  _GradientTween({super.end});

  @override
  Gradient? lerp(double t) => Gradient.lerp(begin, end, t);
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
