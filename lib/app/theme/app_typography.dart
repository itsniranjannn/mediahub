import 'package:flutter/material.dart';
import 'app_colors.dart';

// Note: Inter font is bundled as a local asset for reliable offline use.
abstract class AppTypography {
  static TextStyle get screenTitle => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get sectionTitle => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get playerTitle => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get metadata => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get label => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      );

  /// Tabular figures style helper for time/progress text.
  static TextStyle get tabularFigures => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        fontFeatures: [FontFeature.tabularFigures()],
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      );

  static TextTheme get textTheme => TextTheme(
        headlineMedium: screenTitle,
        titleLarge: sectionTitle,
        titleMedium: playerTitle,
        bodyLarge: body,
        bodyMedium: metadata,
        labelMedium: label,
      );
}
