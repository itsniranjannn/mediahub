import 'package:flutter/material.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Friendly full-area "nothing here" state (docs/DESIGN.md 7.15): an 84 dp
/// halo holding a 38 dp icon, an optional [kicker], a `sectionTitle`
/// headline, a `body` message in textSecondary and an optional action (a
/// VoltButton if it plays or gets media, else a FilledButton).
///
/// Matches `EmptyHint` from the UI kit, and stays scrollable so long messages
/// never overflow on short screens or at large text sizes.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// Optional call to action shown under the message (e.g. a filled button).
  final Widget? action;

  /// Tint of the icon and its halo. Defaults to the palette's primary (with
  /// the halo in primaryBase); pass a palette colour such as `warning`.
  final Color? iconColor;

  /// Short app-written line above the headline, shown in capitals.
  final String? kicker;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.iconColor,
    this.kicker,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final glyph = iconColor ?? palette.primary;
    final halo = iconColor ?? palette.primaryBase;
    final kicker = this.kicker;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxxl32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      halo.withValues(alpha: 0.28),
                      halo.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Icon(icon, size: 38, color: glyph),
              ),
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
            Semantics(
              header: true,
              child: Text(
                title,
                style: type.sectionTitle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.sm8),
            ConstrainedBox(
              // Keeps the message to a comfortable line length on tablets.
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message,
                style: type.body.copyWith(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
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
