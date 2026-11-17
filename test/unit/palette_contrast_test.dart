// The contrast checks of docs/DESIGN.md section 4, ported from the
// designer's contrast_final.py, for BOTH palettes. WCAG 2.x relative
// luminance; alpha colours are composited over the named backdrop first, and
// the tints are the ones the app really paints (Color.lerp,
// ArtworkTint.surfaceGradient, PillTag.tintAlpha).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);
const _yellow = Color(0xFFFFFF00);
const _ink = Color(0xFF180A2E);
const _volt = Color(0xFFCCFF3A);

double _channel(double v) {
  final c = (v * 255.0).round().clamp(0, 255) / 255.0;
  return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// [fg] composited over [bg] (opaque result).
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg.withValues(alpha: 1));

/// WCAG ratio of [fg] on [bg]. A translucent [bg] sits on [under] (white by
/// default); a translucent [fg] sits on the result.
double ratio(Color fg, Color bg, {Color? under}) {
  var back = bg;
  if (back.a < 1) back = over(back, under ?? _white);
  var front = fg;
  if (front.a < 1) front = over(front, back);
  final a = luminance(front);
  final b = luminance(back);
  return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}

/// Collects every pair below its floor, so one run reports them all.
class _Checker {
  final List<String> failures = [];
  int checked = 0;

  void check(String label, Color fg, Color bg, double need, {Color? under}) {
    checked++;
    final r = ratio(fg, bg, under: under);
    if (r < need) {
      failures.add('$label: ${r.toStringAsFixed(2)} < $need ($fg on $bg${under == null ? '' : ' over $under'})');
    }
  }

  void expectNone() => expect(failures, isEmpty, reason: failures.join('\n'));
}

const _palettes = {'dark': AppPalette.dark, 'light': AppPalette.light};

List<Color> _surfaces(AppPalette p) => [p.background, p.surface, p.surfaceElevated, p.surfacePressed];

/// A seed for every artwork palette index.
List<String> _seedPerHue() {
  final seeds = <String>[];
  for (var i = 0; i < ArtworkPlaceholder.paletteCount; i++) {
    var n = 0;
    while (ArtworkPlaceholder.paletteIndexFor('seed$n') != i) {
      n++;
    }
    seeds.add('seed$n');
  }
  return seeds;
}

void main() {
  for (final MapEntry(key: theme, value: p) in _palettes.entries) {
    group('$theme palette', () {
      test('text roles and primary on the four surfaces and on glass over a white / black page', () {
        final c = _Checker();
        final roles = {
          'textPrimary': p.textPrimary,
          'textSecondary': p.textSecondary,
          'textMuted': p.textMuted,
          'primary': p.primary,
        };
        for (final MapEntry(key: name, value: fg) in roles.entries) {
          for (final s in _surfaces(p)) {
            c.check('$name on $s', fg, s, 4.5);
          }
          for (final page in [_white, _black]) {
            c.check('$name on glass', fg, p.glass, 4.5, under: page);
          }
        }
        expect(c.checked, 4 * 6);
        c.expectNone();
      });

      test('state colours as text on the four surfaces (surfacePressed included)', () {
        final c = _Checker();
        final roles = {
          'accent': p.accent,
          'favorite': p.favorite,
          'success': p.success,
          'warning': p.warning,
          'error': p.error,
        };
        for (final MapEntry(key: name, value: fg) in roles.entries) {
          for (final s in _surfaces(p)) {
            c.check('$name on $s', fg, s, 4.5);
          }
        }
        c.expectNone();
      });

      test('labels on fills', () {
        final c = _Checker()
          ..check('onPrimary on primary', p.onPrimary, p.primary, 4.5)
          ..check('onPrimary on primaryPressed', p.onPrimary, p.primaryPressed, 4.5)
          ..check('onVoltFill on voltFill', p.onVoltFill, p.voltFill, 4.5)
          ..check('onVoltFill on voltPressed', p.onVoltFill, p.voltPressed, 4.5)
          ..check('onVoltMuted on voltFill', p.onVoltMuted, p.voltFill, 4.5)
          ..check('onVoltMuted on voltPressed', p.onVoltMuted, p.voltPressed, 4.5)
          ..check('onVoltMuted on primaryGradient[1]', p.onVoltMuted, p.primaryGradient.colors[1], 4.5)
          ..check('Volt glyph on the ink disc (Continue card)', p.voltFill, p.onVoltFill, 4.5)
          ..check('tonal: onSecondaryContainer on secondaryContainer', p.onSecondaryContainer, p.secondaryContainer, 4.5)
          ..check('onPrimaryContainer on primaryContainer', p.onPrimaryContainer, p.primaryContainer, 4.5)
          ..check('primary on primaryContainer', p.primary, p.primaryContainer, 4.5)
          ..check('onAccent on accent', p.onAccent, p.accent, 4.5)
          ..check('onError on error', p.onError, p.error, 4.5)
          ..check('onErrorContainer on errorContainer', p.onErrorContainer, p.errorContainer, 4.5)
          ..check('error on errorContainer', p.error, p.errorContainer, 4.5)
          ..check('onLive on liveFill', p.onLive, p.liveFill, 4.5)
          ..check('onSnackbar on snackbar', p.onSnackbar, p.snackbar, 4.5)
          ..check('snackbarAction on snackbar', p.snackbarAction, p.snackbar, 4.5);
        for (final stop in p.primaryGradient.colors) {
          c.check('onVoltFill on primaryGradient $stop', p.onVoltFill, stop, 4.5);
        }
        c.expectNone();
      });

      test('outlines, focus ring, sliders and Volt shapes reach 3:1', () {
        final c = _Checker();
        for (final s in _surfaces(p)) {
          c
            ..check('outline on $s', p.outline, s, 3)
            ..check('rule on $s', p.rule, s, 3)
            ..check('dragHandle on $s', p.dragHandle, s, 3)
            ..check('focusRing on $s', p.focusRing, s, 3);
        }
        c
          ..check('sliderActive vs sliderInactive', p.sliderActive, p.sliderInactive, 3)
          ..check('sliderThumb vs surface', p.sliderThumb, p.surface, 3)
          ..check('primary glyph on the tonal tile', p.primary, p.secondaryContainer, 3)
          ..check('accent glyph on the tonal tile', p.accent, p.secondaryContainer, 3);
        if (p.isDark) {
          for (final s in _surfaces(p).take(3)) {
            c.check('Volt fill as a shape on $s', p.voltFill, s, 3);
          }
          expect(p.voltEdge.a, 0, reason: 'no ink edge on ink');
        } else {
          for (final s in [..._surfaces(p).take(3), p.voltFill]) {
            c.check('voltEdge on $s', p.voltEdge, s, 3);
          }
        }
        c.expectNone();
      });

      test('text on the hero gradient stops', () {
        final c = _Checker();
        for (final stop in p.heroGradient.colors) {
          for (final fg in [p.textPrimary, p.textSecondary, p.textMuted, p.primary]) {
            c.check('$fg on hero $stop', fg, stop, 4.5);
          }
        }
        c.expectNone();
      });

      test('Ink Dock over a white page, a black page and the canvas', () {
        final c = _Checker();
        for (final page in [_white, _black, p.background]) {
          c
            ..check('onDock on dock', p.onDock, p.dock, 4.5, under: page)
            ..check('onDockMuted on dock', p.onDockMuted, p.dock, 4.5, under: page)
            ..check('Volt indicator / play disc vs dock', p.navIndicator, p.dock, 3, under: page)
            ..check('Ice count dot vs dock', AppPalette.dark.accent, p.dock, 3, under: page);
        }
        c
          ..check('ink count on the Ice dot', p.onNavIndicator, AppPalette.dark.accent, 4.5)
          ..check('Volt progress vs dockLine', p.navIndicator, p.dockLine, 3);
        c.expectNone();
      });

      test('the stage (always dark) on its veil over a white glow', () {
        const stage = AppPalette.dark;
        final veil = over(stage.scrim, _white);
        final c = _Checker()
          ..check('stage textPrimary', stage.textPrimary, veil, 4.5)
          ..check('stage textSecondary', stage.textSecondary, veil, 4.5)
          ..check('stage Volt', stage.primary, veil, 3);
        c.expectNone();
      });

      test('overlay chips over a white, Volt, yellow and black frame', () {
        final c = _Checker();
        for (final frame in [_white, _volt, _yellow, _black]) {
          c
            ..check('onOverlay on overlay', p.onOverlay, p.overlay, 4.5, under: frame)
            ..check('MediaBadge glyph on overlay', MediaBadge.glyphColor, p.overlay, 3, under: frame)
            ..check('onLive on the LIVE chip', p.onLive, p.liveFill, 4.5, under: frame);
        }
        for (final frame in [_white, _black]) {
          c.check('Volt resume line on its overlay track', _volt, p.overlay, 3, under: frame);
        }
        c.expectNone();
      });

      test('PillTag text on its own colour at 14 % over surface / surfaceElevated', () {
        final c = _Checker();
        final roles = {
          'primary': p.primary,
          'accent': p.accent,
          'favorite': p.favorite,
          'success': p.success,
          'warning': p.warning,
          'error': p.error,
        };
        for (final MapEntry(key: name, value: color) in roles.entries) {
          for (final s in [p.surface, p.surfaceElevated]) {
            final tint = over(color.withValues(alpha: PillTag.tintAlpha), s);
            c.check('$name PillTag on $s', color, tint, 4.5);
          }
        }
        c.expectNone();
      });

      test('the empty-state icon on its 28 % halo', () {
        final halo = over(p.primaryBase.withValues(alpha: 0.28), p.background);
        final c = _Checker()..check('primary icon on the halo', p.primary, halo, 3);
        c.expectNone();
      });

      test('artwork: glyphs on the cover stops, text on the tinted surfaces (8 hues)', () {
        final c = _Checker();
        final glyph = _white.withValues(alpha: ArtworkPlaceholder.glyphOpacity);
        expect(p.artworkGradients, hasLength(8));
        for (final g in p.artworkGradients) {
          final top = g.colors.first;
          final deep = g.colors.last;
          final mid = Color.lerp(top, deep, 0.5)!;
          c
            ..check('85 % glyph on top stop $top', glyph, top, 3)
            ..check('85 % glyph on midpoint $mid', glyph, mid, 4.5)
            ..check('white on deep stop $deep', _white, deep, 4.5);
        }
        for (final seed in _seedPerHue()) {
          final stops = ArtworkTint.surfaceGradient(seed, p).colors;
          expect(stops.last, p.background);
          for (final s in stops.take(2)) {
            for (final fg in [p.textPrimary, p.textSecondary, p.textMuted, p.primary]) {
              c.check('$fg on surfaceGradient($seed) $s', fg, s, 4.5);
            }
          }
        }
        c.expectNone();
      });
    });
  }

  test('figures quoted in docs/DESIGN.md section 4 (spot checks)', () {
    const d = AppPalette.dark;
    const l = AppPalette.light;
    expect(ratio(d.textPrimary, d.background), closeTo(17.00, 0.02));
    expect(ratio(l.textPrimary, l.background), closeTo(16.78, 0.02));
    expect(ratio(l.primary, l.surfaceElevated), closeTo(7.34, 0.02));
    expect(ratio(d.onVoltFill, d.voltFill), closeTo(15.99, 0.02));
    expect(ratio(l.outline, l.surfacePressed), closeTo(3.12, 0.02));
    expect(ratio(MediaBadge.glyphColor, d.overlay, under: _white), closeTo(4.12, 0.03));
    // Not pass/fail: the reason every Volt fill on paper carries the ink edge.
    expect(ratio(_volt, l.background), lessThan(1.1));
    expect(_ink, d.background);
  });
}
