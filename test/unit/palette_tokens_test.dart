// AppPalette.dark / .light hold exactly the values of docs/DESIGN.md: every
// role of the 2.2 token table and the gradients of section 3. The test reads
// the tables from the spec itself, so the code and the spec cannot drift.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';

/// Every colour role, by its name in the spec.
final Map<String, Color Function(AppPalette)> _roles = {
  'background': (p) => p.background,
  'surface': (p) => p.surface,
  'surfaceElevated': (p) => p.surfaceElevated,
  'surfacePressed': (p) => p.surfacePressed,
  'primary': (p) => p.primary,
  'primaryBase': (p) => p.primaryBase,
  'primaryPressed': (p) => p.primaryPressed,
  'onPrimary': (p) => p.onPrimary,
  'primaryContainer': (p) => p.primaryContainer,
  'onPrimaryContainer': (p) => p.onPrimaryContainer,
  'secondary': (p) => p.secondary,
  'onSecondary': (p) => p.onSecondary,
  'secondaryContainer': (p) => p.secondaryContainer,
  'onSecondaryContainer': (p) => p.onSecondaryContainer,
  'voltFill': (p) => p.voltFill,
  'voltPressed': (p) => p.voltPressed,
  'onVoltFill': (p) => p.onVoltFill,
  'onVoltMuted': (p) => p.onVoltMuted,
  'voltEdge': (p) => p.voltEdge,
  'voltGlow': (p) => p.voltGlow,
  'accent': (p) => p.accent,
  'onAccent': (p) => p.onAccent,
  'favorite': (p) => p.favorite,
  'textPrimary': (p) => p.textPrimary,
  'textSecondary': (p) => p.textSecondary,
  'textMuted': (p) => p.textMuted,
  'divider': (p) => p.divider,
  'outlineVariant': (p) => p.outlineVariant,
  'outline': (p) => p.outline,
  'rule': (p) => p.rule,
  'focusRing': (p) => p.focusRing,
  'dragHandle': (p) => p.dragHandle,
  'success': (p) => p.success,
  'warning': (p) => p.warning,
  'error': (p) => p.error,
  'onError': (p) => p.onError,
  'errorContainer': (p) => p.errorContainer,
  'onErrorContainer': (p) => p.onErrorContainer,
  'liveFill': (p) => p.liveFill,
  'onLive': (p) => p.onLive,
  'scrim': (p) => p.scrim,
  'glass': (p) => p.glass,
  'overlay': (p) => p.overlay,
  'onOverlay': (p) => p.onOverlay,
  'dock': (p) => p.dock,
  'onDock': (p) => p.onDock,
  'onDockMuted': (p) => p.onDockMuted,
  'dockLine': (p) => p.dockLine,
  'navIndicator': (p) => p.navIndicator,
  'onNavIndicator': (p) => p.onNavIndicator,
  'sliderActive': (p) => p.sliderActive,
  'sliderInactive': (p) => p.sliderInactive,
  'sliderThumb': (p) => p.sliderThumb,
  'snackbar': (p) => p.snackbar,
  'onSnackbar': (p) => p.onSnackbar,
  'snackbarAction': (p) => p.snackbarAction,
  'shadow': (p) => p.shadow,
  'printShadow': (p) => p.printShadow,
};

final _hex = RegExp(r'`#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})`');

Color _parse(String hex) => Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));

/// One spec cell: a colour, "same" (as the dark cell) or "none" (any fully
/// transparent colour).
sealed class _Cell {}

class _Value extends _Cell {
  _Value(this.color);
  final Color color;
}

class _Same extends _Cell {}

class _None extends _Cell {}

_Cell _cell(String text) {
  final m = _hex.firstMatch(text);
  if (m != null) return _Value(_parse(m.group(1)!));
  final t = text.trim().toLowerCase();
  if (t.startsWith('same')) return _Same();
  if (t.startsWith('none')) return _None();
  throw FormatException('unreadable cell "$text"');
}

String _section(String doc, String start, String end) {
  final a = doc.indexOf(start);
  expect(a, isNot(-1), reason: 'docs/DESIGN.md has no "$start"');
  final b = doc.indexOf(end, a + start.length);
  return doc.substring(a, b == -1 ? doc.length : b);
}

List<List<String>> _rows(String section) => [
      for (final line in section.split('\n'))
        if (line.startsWith('|') && !line.startsWith('|---'))
          line.split('|').map((c) => c.trim()).toList()..removeAt(0),
    ];

void _expectCell(_Cell cell, Color actual, String what, {Color? dark}) {
  switch (cell) {
    case _Value(:final color):
      expect(actual, color, reason: what);
    case _Same():
      expect(actual, dark, reason: '$what (same as dark)');
    case _None():
      expect(actual.a, 0, reason: '$what (none)');
  }
}

void main() {
  final doc = File('docs/DESIGN.md').readAsStringSync().replaceAll('\r\n', '\n');

  test('every role of the 2.2 token table, in both palettes', () {
    final table = _section(doc, '### 2.2 Token table', '### 2.3');
    final seen = <String>{};
    for (final row in _rows(table)) {
      final role = row.first;
      if (role == 'Role' || row.length < 3) continue;
      final getter = _roles[role];
      expect(getter, isNotNull, reason: 'the spec has a role "$role" that AppPalette lacks');
      final dark = getter!(AppPalette.dark);
      _expectCell(_cell(row[1]), dark, '$role (dark)');
      _expectCell(_cell(row[2]), getter(AppPalette.light), '$role (light)', dark: dark);
      seen.add(role);
    }
    expect(seen, _roles.keys.toSet(), reason: 'every AppPalette role is in the spec');
  });

  test('section 3 gradients: hero, primary and the 8 artwork pairs', () {
    final gradients = _section(doc, '## 3. Gradients', '## 4.');
    final heroDark = gradients.split('\n').firstWhere((l) => l.startsWith('| Dark |'));
    final heroLight = gradients.split('\n').firstWhere((l) => l.startsWith('| Light |'));
    expect(AppPalette.dark.heroGradient.colors, _hexStops(heroDark));
    expect(AppPalette.light.heroGradient.colors, _hexStops(heroLight));
    for (final p in [AppPalette.dark, AppPalette.light]) {
      for (final g in [p.heroGradient, p.primaryGradient, ...p.artworkGradients]) {
        expect(g.begin, Alignment.topLeft);
        expect(g.end, Alignment.bottomRight);
      }
    }

    final primaryLine = gradients.split('\n').firstWhere((l) => l.startsWith('**primaryGradient**'));
    expect(AppPalette.dark.primaryGradient.colors, _hexStops(primaryLine));
    expect(AppPalette.light.primaryGradient.colors, _hexStops(primaryLine));

    final pairs = _rows(gradients).where((r) => int.tryParse(r.first) != null).toList();
    expect(pairs, hasLength(8));
    for (final (i, row) in pairs.indexed) {
      final top = _parse(_hex.firstMatch(row[2])!.group(1)!);
      final deepDark = _parse(_hex.firstMatch(row[3])!.group(1)!);
      final deepLight = _parse(_hex.firstMatch(row[4])!.group(1)!);
      expect(AppPalette.dark.artworkGradients[i].colors, [top, deepDark], reason: row[1]);
      expect(AppPalette.light.artworkGradients[i].colors, [top, deepLight], reason: row[1]);
    }
  });

  group('ThemeExtension', () {
    test('copyWith replaces only what it is given', () {
      final p = AppPalette.dark.copyWith(primary: const Color(0xFF123456));
      expect(p.primary, const Color(0xFF123456));
      expect(p.background, AppPalette.dark.background);
      expect(p.brightness, Brightness.dark);
      expect(p.artworkGradients, same(AppPalette.dark.artworkGradients));
    });

    test('lerp runs every colour and gradient from dark to light', () {
      const a = AppPalette.dark;
      const b = AppPalette.light;
      expect(a.lerp(b, 0).background, a.background);
      expect(a.lerp(b, 1).background, b.background);
      final mid = a.lerp(b, 0.5);
      for (final MapEntry(key: role, value: get) in _roles.entries) {
        expect(get(mid), Color.lerp(get(a), get(b), 0.5), reason: role);
      }
      expect(mid.heroGradient, LinearGradient.lerp(a.heroGradient, b.heroGradient, 0.5));
      expect(mid.artworkGradients, hasLength(8));
      expect(mid.artworkGradients[3], LinearGradient.lerp(a.artworkGradients[3], b.artworkGradients[3], 0.5));
      expect(a.lerp(b, 0.4).brightness, Brightness.dark);
      expect(a.lerp(b, 0.6).brightness, Brightness.light);
      expect(a.lerp(null, 0.5), same(a));
    });

    test('AppPalette.of picks by brightness', () {
      expect(AppPalette.of(Brightness.dark), same(AppPalette.dark));
      expect(AppPalette.of(Brightness.light), same(AppPalette.light));
      expect(AppPalette.dark.isDark, isTrue);
      expect(AppPalette.light.isDark, isFalse);
    });
  });
}

/// Every `#RRGGBB` in a line such as "`#421E78 → #25133F → #180A2E`".
List<Color> _hexStops(String line) =>
    RegExp(r'#([0-9A-Fa-f]{6})\b').allMatches(line).map((m) => _parse(m.group(1)!)).toList();
