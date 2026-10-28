import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

// Note: Fonts should be bundled as assets before release for offline use.
abstract class AppTypography {
  static TextStyle get screenTitle => GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get sectionTitle => GoogleFonts.inter(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get playerTitle => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get metadata => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get label => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      );

  /// Tabular figures style helper for time/progress text.
  static TextStyle get tabularFigures => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextTheme get textTheme => TextTheme(
        headlineLarge: screenTitle,
        headlineMedium: playerTitle,
        titleLarge: sectionTitle,
        bodyLarge: body,
        bodyMedium: metadata,
        labelMedium: label,
      );
}
