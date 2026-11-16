import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography: Inter, bundled for offline use. Weights 400/500/600 ship as
/// files; w700 is mapped to the SemiBold file in pubspec.yaml so headings never
/// get a blurry synthetic bold.
///
/// Scale (size / line height): display 32/38, screenTitle 26/32, playerTitle
/// 22/28, sectionTitle 18/24, body 15/22, metadata 13/18, label 12/16, caption 11/14.
abstract class AppTypography {
  static const String _family = 'Inter';

  static TextStyle get display => const TextStyle(
        fontFamily: _family,
        fontSize: 32,
        height: 38 / 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: AppColors.textPrimary,
      );

  static TextStyle get screenTitle => const TextStyle(
        fontFamily: _family,
        fontSize: 26,
        height: 32 / 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      );

  static TextStyle get playerTitle => const TextStyle(
        fontFamily: _family,
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      );

  static TextStyle get sectionTitle => const TextStyle(
        fontFamily: _family,
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => const TextStyle(
        fontFamily: _family,
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyStrong => const TextStyle(
        fontFamily: _family,
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get metadata => const TextStyle(
        fontFamily: _family,
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get label => const TextStyle(
        fontFamily: _family,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: AppColors.textMuted,
      );

  static TextStyle get button => const TextStyle(
        fontFamily: _family,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  /// Tabular figures style helper for time/progress text.
  static TextStyle get tabularFigures => const TextStyle(
        fontFamily: _family,
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        fontFeatures: [FontFeature.tabularFigures()],
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: _family,
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      );

  static TextTheme get textTheme => TextTheme(
        displaySmall: display,
        headlineMedium: screenTitle,
        titleLarge: sectionTitle,
        titleMedium: playerTitle,
        titleSmall: bodyStrong,
        bodyLarge: body,
        bodyMedium: metadata,
        bodySmall: caption,
        labelLarge: button,
        labelMedium: label,
      );
}
