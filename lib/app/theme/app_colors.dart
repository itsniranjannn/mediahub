import 'package:flutter/material.dart';

/// "Midnight Violet" palette: a near-black blue canvas, soft elevated surfaces,
/// one confident violet accent, a teal secondary for video / success moments
/// and a rose reserved for favourites. Contrast of text on every surface is
/// >= 4.5:1 (checked in test/unit/card_contrast_test.dart).
abstract class AppColors {
  // Canvas & surfaces (each step is a little lighter and slightly bluer)
  static const Color background = Color(0xFF07090F);
  static const Color surface = Color(0xFF0F131C);
  static const Color surfaceElevated = Color(0xFF171C29);
  static const Color surfacePressed = Color(0xFF222A3C);

  // Brand
  static const Color primary = Color(0xFF9784FF); // 6.4:1 on background, 5.4:1 on surfaceElevated
  static const Color primaryBase = Color(0xFF7C5CFF);
  static const Color primaryPressed = Color(0xFF6846EB);
  static const Color onPrimary = Color(0xFF0C0A1C); // dark ink on the bright violet (9:1)
  static const Color accent = Color(0xFF3DE0CB); // teal: video, "live", success moments
  static const Color favorite = Color(0xFFFF5C8A); // rose: hearts only

  // Text
  static const Color textPrimary = Color(0xFFF5F7FC);
  static const Color textSecondary = Color(0xFFAAB3C5);
  static const Color textMuted = Color(0xFF7D889C);

  // Lines & states
  static const Color divider = Color(0xFF222A3A);
  static const Color success = Color(0xFF36C98F);
  static const Color warning = Color(0xFFF4B860);
  static const Color error = Color(0xFFFF647C);
  static const Color scrim = Color(0xCC05070B);

  // Gradients
  /// Soft violet glow used behind hero areas.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B2268), Color(0xFF151B3D), Color(0xFF0C101C)],
  );

  /// Primary call-to-action fill.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9F8CFF), Color(0xFF6C8BFF)],
  );

  /// Translucent fill for "glass" bars (mini player, bottom navigation).
  static const Color glass = Color(0xD90F131C);

  // Media overlays
  /// Fill behind text and badges drawn over images or video frames
  /// (duration badges, "now playing" veils). Black at ~72 %.
  static const Color overlay = Color(0xB8000000);

  /// Text and glyphs drawn on [overlay].
  static const Color onOverlay = Color(0xFFFFFFFF);

  // Artwork identity
  /// Cover gradients for songs and videos without embedded art. One is
  /// picked per item from a stable hash of its uri (see ArtworkPlaceholder),
  /// so an item keeps its colours everywhere it appears. Eight hues: violet,
  /// teal, rose, indigo, amber, cyan, magenta and dusk. Each runs from a
  /// light-ish top-left stop to a deep bottom-right stop that melts into the
  /// canvas; white glyphs at 85 % reach >= 3:1 on the top stop and >= 4.5:1
  /// in the middle (checked in test/unit/artwork_placeholder_test.dart).
  static const List<LinearGradient> artworkGradients = [
    // violet
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8270FF), Color(0xFF2A1B7A)],
    ),
    // teal
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1D968C), Color(0xFF083640)],
    ),
    // rose
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE0557F), Color(0xFF561535)],
    ),
    // indigo blue
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF5C7DF7), Color(0xFF162563)],
    ),
    // amber to wine
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC9683A), Color(0xFF661C3C)],
    ),
    // cyan
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF268EC4), Color(0xFF0C2A59)],
    ),
    // magenta
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC25BE0), Color(0xFF461663)],
    ),
    // dusk: a calm, greyed violet. It sits apart from the violet above by
    // lightness and chroma, and keeps green out of the palette (green is
    // the success colour; teal is the only cool green-blue).
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7A6CC0), Color(0xFF221B4A)],
    ),
  ];
}
