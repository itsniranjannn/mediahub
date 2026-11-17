import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Every text role of the Bijuli type scale (docs/DESIGN.md section 6),
/// coloured for one [AppPalette]. Get one with [AppTypography.of] or
/// `context.typography`.
///
/// Four voices with clear jobs:
/// - **Unbounded** ([display], [sectionTitle]): headings the app itself
///   writes. Never below 18, never in rows, never for a string that came
///   from a file, tag, URL or person.
/// - **Anek Devanagari Wide** ([greeting], [screenTitle], [playerTitle],
///   [cardTitle]): every name of a thing, in Latin or Devanagari. Never
///   below 20.
/// - **Atkinson Hyperlegible Next** with Mukta for Devanagari ([body],
///   [bodyStrong], [metadata], [label], [chipLabel], [button], [caption]):
///   every line people read.
/// - **DM Mono** with Mukta ([tabularFigures], [index], [overline], [badge],
///   [figureLarge]): times, sizes, track numbers and kickers.
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

  /// U 32/40 w700. Tab mastheads only ("Music", "Videos" ...). One line.
  final TextStyle display;

  /// A 30/42 w700. The Home greeting ("नमस्ते").
  final TextStyle greeting;

  /// A 24/34 w700. App bar titles, album / artist / playlist headers, the
  /// video title on the watch screen. Max 2 lines.
  final TextStyle screenTitle;

  /// A 22/30 w600. Now Playing and video player titles. Max 2 lines.
  final TextStyle playerTitle;

  /// A 20/28 w700. Continue-listening slab and hero tiles. 1-2 lines.
  final TextStyle cardTitle;

  /// U 18/26 w600. "Recently played", sheet and dialog titles (app strings).
  final TextStyle sectionTitle;

  /// T 16/24 w400. Paragraphs, sheet rows, dialog body, inputs.
  final TextStyle body;

  /// T 16/24 w600. Song and video titles in rows.
  final TextStyle bodyStrong;

  /// T 14/20 w400, textSecondary. "Artist · Album", "Channel · 1.2 GB".
  final TextStyle metadata;

  /// T 12/16 w600, +0.2, textMuted. Nav and form labels (app strings only).
  final TextStyle label;

  /// T 14/20 w600. Chips (may carry artist names).
  final TextStyle chipLabel;

  /// T 15/20 w700, +0.15, no colour (the button gives it). Every button label.
  final TextStyle button;

  /// T 12/16 w400, textMuted. Helper, error and empty-state fine print.
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

/// The Bijuli type scale: five bundled families (pubspec.yaml) and the roles
/// in [AppTextStyles].
///
/// Use [of] with a palette (or `context.typography`) in new code. The static
/// getters ([display], [body], [metadata] ...) are the same styles coloured
/// for [AppPalette.dark]; they keep the existing call sites working until the
/// screens move to the palette-aware styles.
abstract final class AppTypography {
  /// Families as registered in pubspec.yaml.
  static const String unbounded = 'Unbounded';
  static const String anekWide = 'AnekWide';
  static const String atkinson = 'AtkinsonNext';
  static const String mukta = 'Mukta';
  static const String dmMono = 'DMMono';

  /// Unbounded is Latin only: a Nepali word in a static heading falls back to
  /// Anek, which is the same width class.
  static const List<String> headingFallback = [anekWide];

  /// Anek draws Latin and Devanagari; Atkinson and Mukta cover the symbols
  /// it lacks.
  static const List<String> titleFallback = [atkinson, mukta];

  /// Atkinson (reading text) and DM Mono fall back to Mukta for Devanagari.
  static const List<String> readingFallback = [mukta];

  /// `ThemeData.fontFamily` (with [readingFallback]): text without a role
  /// reads in Atkinson.
  static const String defaultFamily = atkinson;

  static final AppTextStyles _dark = _build(AppPalette.dark);
  static final AppTextStyles _light = _build(AppPalette.light);

  /// Every role coloured for [palette]. The two built-in palettes are cached;
  /// any other (a palette mid-way through a theme change) is built on demand.
  static AppTextStyles of(AppPalette palette) {
    if (identical(palette, AppPalette.dark)) return _dark;
    if (identical(palette, AppPalette.light)) return _light;
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
        family: unbounded,
        fallback: headingFallback,
        size: 32,
        line: 40,
        weight: FontWeight.w700,
        letterSpacing: -0.5,
        color: p.textPrimary,
      ),
      greeting: _style(
        family: anekWide,
        fallback: titleFallback,
        size: 30,
        line: 42,
        weight: FontWeight.w700,
        color: p.textPrimary,
      ),
      screenTitle: _style(
        family: anekWide,
        fallback: titleFallback,
        size: 24,
        line: 34,
        weight: FontWeight.w700,
        color: p.textPrimary,
      ),
      playerTitle: _style(
        family: anekWide,
        fallback: titleFallback,
        size: 22,
        line: 30,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      cardTitle: _style(
        family: anekWide,
        fallback: titleFallback,
        size: 20,
        line: 28,
        weight: FontWeight.w700,
        color: p.textPrimary,
      ),
      sectionTitle: _style(
        family: unbounded,
        fallback: headingFallback,
        size: 18,
        line: 26,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      body: _style(
        family: atkinson,
        fallback: readingFallback,
        size: 16,
        line: 24,
        weight: FontWeight.w400,
        color: p.textPrimary,
      ),
      bodyStrong: _style(
        family: atkinson,
        fallback: readingFallback,
        size: 16,
        line: 24,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      metadata: _style(
        family: atkinson,
        fallback: readingFallback,
        size: 14,
        line: 20,
        weight: FontWeight.w400,
        color: p.textSecondary,
      ),
      label: _style(
        family: atkinson,
        fallback: readingFallback,
        size: 12,
        line: 16,
        weight: FontWeight.w600,
        letterSpacing: 0.2,
        color: p.textMuted,
      ),
      chipLabel: _style(
        family: atkinson,
        fallback: readingFallback,
        size: 14,
        line: 20,
        weight: FontWeight.w600,
        color: p.textPrimary,
      ),
      button: _style(
        family: atkinson,
        fallback: readingFallback,
        size: 15,
        line: 20,
        weight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
      caption: _style(
        family: atkinson,
        fallback: readingFallback,
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

  // Dark-palette styles under the names the screens already use.

  static TextStyle get display => _dark.display;
  static TextStyle get greeting => _dark.greeting;
  static TextStyle get screenTitle => _dark.screenTitle;
  static TextStyle get playerTitle => _dark.playerTitle;
  static TextStyle get cardTitle => _dark.cardTitle;
  static TextStyle get sectionTitle => _dark.sectionTitle;
  static TextStyle get body => _dark.body;
  static TextStyle get bodyStrong => _dark.bodyStrong;
  static TextStyle get metadata => _dark.metadata;
  static TextStyle get label => _dark.label;
  static TextStyle get chipLabel => _dark.chipLabel;
  static TextStyle get button => _dark.button;
  static TextStyle get caption => _dark.caption;

  /// Tabular figures for time and progress text.
  static TextStyle get tabularFigures => _dark.tabularFigures;
  static TextStyle get index => _dark.index;
  static TextStyle get overline => _dark.overline;
  static TextStyle get badge => _dark.badge;
  static TextStyle get figureLarge => _dark.figureLarge;
}

/// `context.typography`: [AppTypography.of] the surrounding theme's palette.
extension TypographyX on BuildContext {
  AppTextStyles get typography => AppTypography.of(palette);
}
