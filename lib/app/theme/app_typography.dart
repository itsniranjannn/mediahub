// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Every text role of the Sindur type scale (docs/DESIGN.md section 6),
/// coloured for one [AppPalette]. Get one with [AppTypography.of] or
/// `context.typography`.
///
/// Three voices with clear jobs:
/// - **Fraunces** ([display], [sectionTitle]): a warm, soft serif for the
///   headings the app itself writes. Latin only, so never below 18, never in
///   rows, never for a string that came from a file, tag, URL or person.
/// - **Poppins** ([greeting], [screenTitle], [playerTitle], [cardTitle],
///   [body], [bodyStrong], [metadata], [label], [chipLabel], [button],
///   [caption]): every name of a thing and every line people read. One design
///   for Latin and Devanagari, so a Nepali song title never switches font.
/// - **DM Mono** with Poppins for Devanagari ([tabularFigures], [index],
///   [overline], [badge], [figureLarge]): times, sizes, track numbers and
///   kickers.
///
/// Every style uses [TextLeadingDistribution.even]; styles that can carry
/// user content keep `letterSpacing: 0`, because tracking breaks the
/// Devanagari headline bar and collides conjuncts.
@immutable
class AppTextStyles {
  const AppTextStyles({
    required this.display,
    required this.greeting,
    required this.screenTitle,
    required this.playerTitle,
    required this.cardTitle,
    required this.sectionTitle,
    required this.body,
    required this.bodyStrong,
    required this.metadata,
    required this.label,
    required this.chipLabel,
    required this.button,
    required this.caption,
    required this.tabularFigures,
    required this.index,
    required this.overline,
    required this.badge,
    required this.figureLarge,
  });

  /// F 32/40 w700. Tab mastheads only ("Music", "Videos" ...). One line.
  final TextStyle display;

  /// P 30/42 w700. The Home greeting ("नमस्ते").
  final TextStyle greeting;

  /// P 24/34 w700. App bar titles, album / artist / playlist headers, the
  /// video title on the watch screen. Max 2 lines.
  final TextStyle screenTitle;

  /// P 22/30 w600. Now Playing and video player titles. Max 2 lines.
  final TextStyle playerTitle;

  /// P 20/28 w700. Continue-listening slab and hero tiles. 1-2 lines.
  final TextStyle cardTitle;

  /// F 18/26 w600. "Recently played", sheet and dialog titles (app strings).
  final TextStyle sectionTitle;

  /// P 16/24 w400. Paragraphs, sheet rows, dialog body, inputs.
  final TextStyle body;

  /// P 16/24 w600. Song and video titles in rows.
  final TextStyle bodyStrong;

  /// P 14/20 w400, textSecondary. "Artist · Album", "Channel · 1.2 GB".
  final TextStyle metadata;

  /// P 12/16 w600, +0.2, textMuted. Nav and form labels (app strings only).
  final TextStyle label;

  /// P 14/20 w600. Chips (may carry artist names).
  final TextStyle chipLabel;

  /// P 15/20 w600, no colour (the button gives it). Every button label.
  final TextStyle button;

  /// P 12/16 w400, textMuted. Helper, error and empty-state fine print.
  final TextStyle caption;

  /// M 13/18 w500 tabular, textSecondary. Seek times, durations, sizes, %.
  final TextStyle tabularFigures;

  /// M 13/18 w500 tabular, textMuted. Track numbers "01 02 03".
  final TextStyle index;

  /// M 11/16 w500, +1.1, textSecondary. UPPERCASE kickers (app strings only).
  final TextStyle overline;

  /// M 12/16 w500, +0.2, onOverlay. Duration badge, "1080P", "LIVE", PillTag.
  final TextStyle badge;

  /// M 28/32 w500 tabular, -0.5. Download %, storage totals, countdowns.
  final TextStyle figureLarge;
}

/// The Sindur type scale: three bundled families (pubspec.yaml) and the
/// roles in [AppTextStyles].
///
/// Get the roles with [of] and a palette, or `context.typography` (the
/// surrounding theme's palette).
abstract final class AppTypography {
  /// Families as registered in pubspec.yaml.
  static const String fraunces = 'Fraunces';
  static const String poppins = 'Poppins';
  static const String dmMono = 'DMMono';

  /// Fraunces is Latin only: a Nepali word in a static heading falls back to
  /// Poppins.
  static const List<String> headingFallback = [poppins];

  /// Poppins draws Latin and Devanagari itself; nothing else is bundled.
  static const List<String> titleFallback = <String>[];

  /// DM Mono (and text without a role) falls back to Poppins for Devanagari.
  static const List<String> readingFallback = [poppins];

  /// `ThemeData.fontFamily` (with [readingFallback]): text without a role
  /// reads in Poppins.
  static const String defaultFamily = poppins;

  static final AppTextStyles _dark = _build(AppPalette.dark);
  static final AppTextStyles _light = _build(AppPalette.light);
  static final AppTextStyles _classic = _build(AppPalette.classic);

  /// Every role coloured for [palette]. The three built-in palettes are cached;
  /// any other (a palette mid-way through a theme change) is built on demand.
  static AppTextStyles of(AppPalette palette) {
    if (identical(palette, AppPalette.dark)) return _dark;
    if (identical(palette, AppPalette.light)) return _light;
    if (identical(palette, AppPalette.classic)) return _classic;
    return _build(palette);
  }

  /// The roles on their Material 3 slots, for `ThemeData.textTheme`.
  static TextTheme textTheme([AppPalette palette = AppPalette.dark]) {
    final s = of(palette);
    return TextTheme(
      displaySmall: s.display,
      headlineLarge: s.greeting,
      headlineMedium: s.screenTitle,
      headlineSmall: s.cardTitle,
      titleLarge: s.sectionTitle,
      titleMedium: s.playerTitle,
      titleSmall: s.bodyStrong,
      bodyLarge: s.body,
      bodyMedium: s.metadata,
      bodySmall: s.caption,
      labelLarge: s.button,
      labelMedium: s.label,
      labelSmall: s.overline,
    );
  }

  static TextStyle _style({
    required String family,
    required List<String> fallback,
    required double size,
    required double line,
    required FontWeight weight,
    double letterSpacing = 0,
    Color? color,
    List<FontFeature>? features,
  }) {
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: line / size,
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      fontFeatures: features,
    );
  }

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static AppTextStyles _build(AppPalette p) {
    return AppTextStyles(
      display: _style(
        family: fraunces,
        fallback: headingFallback,
        size: 32,
        line: 40,
        weight: FontWeight.w700,
        letterSpacing: -0.5,
        color: p.textPrimary,
      ),
      greeting: _style(
        family: poppins,
        fallback: titleFallback,
        size: 30,
        line: 42,
        weight: FontWeight.w700,
        color: p.textPrimary,
      ),
      screenTitle: _style(
        family: poppins,
        fallback: titleFallback,
        size: 24,
        line: 34,
        weight: FontWeight.w700,
        color: p.textPrimary,
      ),
      playerTitle: _style(
        family: poppins,
        fallback: titleFallback,
        size: 22,
        line: 30,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      cardTitle: _style(
        family: poppins,
        fallback: titleFallback,
        size: 20,
        line: 28,
        weight: FontWeight.w700,
        color: p.textPrimary,
      ),
      sectionTitle: _style(
        family: fraunces,
        fallback: headingFallback,
        size: 18,
        line: 26,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      body: _style(
        family: poppins,
        fallback: titleFallback,
        size: 16,
        line: 24,
        weight: FontWeight.w400,
        color: p.textPrimary,
      ),
      bodyStrong: _style(
        family: poppins,
        fallback: titleFallback,
        size: 16,
        line: 24,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      metadata: _style(
        family: poppins,
        fallback: titleFallback,
        size: 14,
        line: 20,
        weight: FontWeight.w400,
        color: p.textSecondary,
      ),
      label: _style(
        family: poppins,
        fallback: titleFallback,
        size: 12,
        line: 16,
        weight: FontWeight.w600,
        letterSpacing: 0.2,
        color: p.textMuted,
      ),
      chipLabel: _style(
        family: poppins,
        fallback: titleFallback,
        size: 14,
        line: 20,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      button: _style(
        family: poppins,
        fallback: titleFallback,
        size: 15,
        line: 20,
        weight: FontWeight.w600,
      ),
      caption: _style(
        family: poppins,
        fallback: titleFallback,
        size: 12,
        line: 16,
        weight: FontWeight.w400,
        color: p.textMuted,
      ),
      tabularFigures: _style(
        family: dmMono,
        fallback: readingFallback,
        size: 13,
        line: 18,
        weight: FontWeight.w500,
        color: p.textSecondary,
        features: _tabular,
      ),
      index: _style(
        family: dmMono,
        fallback: readingFallback,
        size: 13,
        line: 18,
        weight: FontWeight.w500,
        color: p.textMuted,
        features: _tabular,
      ),
      overline: _style(
        family: dmMono,
        fallback: readingFallback,
        size: 11,
        line: 16,
        weight: FontWeight.w500,
        letterSpacing: 1.1,
        color: p.textSecondary,
      ),
      badge: _style(
        family: dmMono,
        fallback: readingFallback,
        size: 12,
        line: 16,
        weight: FontWeight.w500,
        letterSpacing: 0.2,
        color: p.onOverlay,
      ),
      figureLarge: _style(
        family: dmMono,
        fallback: readingFallback,
        size: 28,
        line: 32,
        weight: FontWeight.w500,
        letterSpacing: -0.5,
        color: p.textPrimary,
        features: _tabular,
      ),
    );
  }
}

/// `context.typography`: [AppTypography.of] the surrounding theme's palette.
extension TypographyX on BuildContext {
  AppTextStyles get typography => AppTypography.of(palette);
}
