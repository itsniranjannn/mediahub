// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
/// The 4 dp grid, radii and touch targets (docs/DESIGN.md 7.1).
abstract class AppSpacing {
  static const double xs4 = 4.0;
  static const double sm8 = 8.0;
  static const double md12 = 12.0;
  static const double lg16 = 16.0;
  static const double xl20 = 20.0;
  static const double xxl24 = 24.0;
  static const double xxxl32 = 32.0;
  static const double giant40 = 40.0;
  static const double huge48 = 48.0;

  /// Phone gutter; tablets (600 dp and wider) use [tabletGutter].
  static const double gutter = lg16;
  static const double tabletGutter = xxl24;

  // Radii. Buttons, chips, the search field, the nav indicator and play
  // discs are stadiums (StadiumBorder), not a radius.

  /// Overlay chips (duration, "Downloaded", LIVE) and PillTag.
  static const double radiusBadge = 6.0;

  /// Artwork 56 dp and smaller.
  static const double radiusArtSmall = 10.0;

  /// Thumbnails, tiles, grid covers.
  static const double radiusThumb = 14.0;

  /// Cards and the Continue slab.
  static const double cardRadius = 20.0;

  /// Popup menus, form fields, snackbars.
  static const double radiusMenu = 16.0;

  /// Sheets (top corners) and dialogs.
  static const double radiusSheet = 28.0;

  /// The Now Playing cover.
  static const double radiusCover = 24.0;

  /// Retired: buttons are stadiums now (the button themes already draw
  /// them). Kept for the call sites that still round their own boxes with
  /// it until the screens are restyled; do not use in new code.
  static const double buttonRadius = 14.0;

  static const double minTouchTarget = 48.0;
}
