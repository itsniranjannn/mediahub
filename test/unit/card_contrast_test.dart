import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

// WCAG Luminance and Contrast Ratio calculation formulas
double _luminance(Color color) {
  final r = (color.r * 255.0).round().clamp(0, 255) / 255.0;
  final g = (color.g * 255.0).round().clamp(0, 255) / 255.0;
  final b = (color.b * 255.0).round().clamp(0, 255) / 255.0;

  double getComponent(double v) {
    return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * getComponent(r) + 0.7152 * getComponent(g) + 0.0722 * getComponent(b);
}

double contrastRatio(Color color1, Color color2) {
  final lum1 = _luminance(color1);
  final lum2 = _luminance(color2);
  final brightest = max(lum1, lum2);
  final darkest = min(lum1, lum2);
  return (brightest + 0.05) / (darkest + 0.05);
}

void main() {
  // Every check runs on the ink (dark) and the paper (light) theme.
  final themes = {
    'dark': (AppPalette.dark, AppTheme.darkTheme),
    'light': (AppPalette.light, AppTheme.lightTheme),
  };

  for (final MapEntry(key: name, value: (palette, theme)) in themes.entries) {
    group('TASK 5.3a.1: Theme and Notice Card Contrast Tests ($name)', () {
      test('1. Warning notice card: textPrimary on surfaceElevated contrast is >= 4.5:1', () {
        final text = palette.textPrimary;
        final bg = palette.surfaceElevated;
        final ratio = contrastRatio(text, bg);

        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: 'textPrimary ($text) against surfaceElevated ($bg) should satisfy WCAG AA ratio ($ratio)');
      });

      test('2. Outlined "Open link" button: primary color against surfaceElevated contrast is >= 4.5:1', () {
        final primary = palette.primary;
        final bg = palette.surfaceElevated;
        final ratio = contrastRatio(primary, bg);

        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: 'primary button text/border ($primary) against surfaceElevated ($bg) should satisfy WCAG AA ratio ($ratio)');
      });

      test('3. Real error cards: onErrorContainer on errorContainer contrast is >= 4.5:1', () {
        final text = theme.colorScheme.onErrorContainer;
        final bg = theme.colorScheme.errorContainer;
        expect(text, palette.onErrorContainer);
        expect(bg, palette.errorContainer);
        final ratio = contrastRatio(text, bg);

        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: 'onErrorContainer ($text) against errorContainer ($bg) should satisfy WCAG AA ratio ($ratio)');
      });

      test('4. Tonal buttons: the tonal label on secondaryContainer is >= 4.5:1, not the accent fallback', () {
        final scheme = theme.colorScheme;
        expect(scheme.secondaryContainer, palette.secondaryContainer);
        expect(scheme.onSecondaryContainer, palette.onSecondaryContainer);
        expect(scheme.secondaryContainer, isNot(palette.accent));
        final ratio = contrastRatio(scheme.onSecondaryContainer, scheme.secondaryContainer);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: 'tonal label contrast $ratio');
      });

      test('5. The filled button theme leaves colours to the scheme, so tonal and filled differ', () {
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor, isNull);
        expect(style.foregroundColor, isNull);
        // Filled: primary / onPrimary from the scheme.
        final scheme = theme.colorScheme;
        expect(contrastRatio(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
      });

      test('6. The now-playing row pill (12% primary on the canvas) keeps every row text >= 4.5:1', () {
        final pill = Color.alphaBlend(palette.primary.withValues(alpha: 0.12), palette.background);
        for (final text in [palette.primary, palette.textPrimary, palette.textSecondary, palette.textMuted]) {
          expect(contrastRatio(text, pill), greaterThanOrEqualTo(4.5), reason: '$text on the pill');
        }
      });

      test('7. MediaBadge: Ice glyph >= 3:1 and white text >= 4.5:1 on the overlay over a white frame', () {
        final chip = Color.alphaBlend(palette.overlay, const Color(0xFFFFFFFF));
        expect(contrastRatio(MediaBadge.glyphColor, chip), greaterThanOrEqualTo(3.0));
        expect(contrastRatio(palette.onOverlay, chip), greaterThanOrEqualTo(4.5));
      });
    });
  }
}
