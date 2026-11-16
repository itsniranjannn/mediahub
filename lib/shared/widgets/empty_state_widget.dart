import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Friendly full-area "nothing here" state: an icon in a soft radial circle,
/// a section-title heading, a short metadata line and an optional action.
///
/// Matches `EmptyHint` from the UI kit, and stays scrollable so long messages
/// never overflow on short screens or at large text sizes.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// Optional call to action shown under the message (e.g. a filled button).
  final Widget? action;

  /// Tint of the icon and its glow. Defaults to the brand violet.
  final Color iconColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
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
                      iconColor.withValues(alpha: 0.28),
                      iconColor.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Icon(icon, size: 38, color: iconColor),
              ),
            ),
            const SizedBox(height: AppSpacing.xl20),
            Semantics(
              header: true,
              child: Text(
                title,
                style: AppTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.sm8),
            ConstrainedBox(
              // Keeps the message to a comfortable line length on tablets.
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message,
                style: AppTypography.metadata,
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
