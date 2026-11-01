import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_colors.dart';
import 'package:mediahub/app/theme/app_theme.dart';

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
  group('TASK 5.3a.1: Theme and Notice Card Contrast Tests', () {
    test('1. Warning notice card: textPrimary on surfaceElevated contrast is >= 4.5:1', () {
      final text = AppColors.textPrimary; // 0xFFF4F6FB
      final bg = AppColors.surfaceElevated; // 0xFF1A2230
      final ratio = contrastRatio(text, bg);

      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'textPrimary ($text) against surfaceElevated ($bg) should satisfy WCAG AA ratio ($ratio)');
    });

    test('2. Outlined "Open link" button: primary color against surfaceElevated contrast is >= 4.5:1', () {
      final primary = AppColors.primary; // 0xFF7C5CFF
      final bg = AppColors.surfaceElevated; // 0xFF1A2230
      final ratio = contrastRatio(primary, bg);

      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'primary button text/border ($primary) against surfaceElevated ($bg) should satisfy WCAG AA ratio ($ratio)');
    });

    test('3. Real error cards: onErrorContainer (light text) on errorContainer (dark red tint) contrast is >= 4.5:1', () {
      final theme = AppTheme.darkTheme;
      final text = theme.colorScheme.onErrorContainer; // textPrimary
      final bg = theme.colorScheme.errorContainer; // 0xFF2C151B (dark red tint)
      final ratio = contrastRatio(text, bg);

      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'onErrorContainer ($text) against errorContainer ($bg) should satisfy WCAG AA ratio ($ratio)');
    });
  });
}
