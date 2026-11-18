// Volt is contained (docs/DESIGN.md 0.6, 9 and 10): the brand fill reaches
// the screen only through VoltButton, VoltDisc, VoltSlab (ui_kit.dart) and
// the chip theme (app_theme.dart), which draw the ink edge on paper. Any
// other file that paints voltFill / primaryGradient / onVoltFill could put a
// lime fill on paper without its edge (1.05:1), so this test fails on it.
//
// The legacy dark-only constants (`AppColors`, and the `AppTypography.body`
// style getters) are gone now that every screen reads the theme's palette;
// this test keeps them from coming back.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to name the Volt fill tokens.
const _allowed = {
  'lib/shared/widgets/ui_kit.dart',
  'lib/app/theme/app_theme.dart',
  'lib/app/theme/app_palette.dart',
};

final _token = RegExp(r'\b(voltFill|voltPressed|primaryGradient|onVoltFill)\b');

/// The removed legacy API: the `AppColors` constants (always the dark
/// palette, so wrong on paper) and the static `AppTypography` role getters
/// (the dark palette's styles). Read `context.palette` / `context.typography`
/// (or `AppPalette.dark` / `AppTypography.of(palette)` where there is no
/// context); `AppTypography.of`, `.textTheme` and the family constants stay.
final _legacyApi = RegExp(
  r'\bAppColors\b|\bAppTypography\.(display|greeting|screenTitle|playerTitle|cardTitle|sectionTitle|body|'
  r'bodyStrong|metadata|label|chipLabel|button|caption|tabularFigures|index|overline|badge|figureLarge)\b',
);

/// A fill painted with the palette's primary: Volt in the dark theme, so it
/// belongs in a Volt widget.
final _primaryFill = RegExp(
  r'\b(backgroundColor|fillColor|selectedColor|indicatorColor)\s*:\s*(const\s+)?(context\.palette|palette|p)\.primary\b',
);

/// Code lines of [file] matching [pattern] (comment lines and trailing
/// comments skipped), as "line: code".
List<String> _matches(File file, RegExp pattern) {
  final hits = <String>[];
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) continue;
    final code = line.split(RegExp(r'\s//')).first;
    for (var n = pattern.allMatches(code).length; n > 0; n--) {
      hits.add('${i + 1}: ${trimmed.trim()}');
    }
  }
  return hits;
}

/// Code lines of [file] that name a Volt token.
List<String> _uses(File file) => _matches(file, _token).toSet().toList();

Iterable<(String, File)> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => (f.path.replaceAll(r'\', '/'), f));

Iterable<(String, File)> _libFiles() => _dartFiles('lib');

void main() {
  test('Volt fill tokens appear only in ui_kit, app_theme and app_palette', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final (path, file) in _libFiles()) {
      scanned++;
      if (_allowed.contains(path)) continue;
      final hits = _uses(file);
      if (hits.isNotEmpty) offenders.add('$path\n  ${hits.join('\n  ')}');
    }
    expect(scanned, greaterThan(20), reason: 'run from the package root');
    expect(
      offenders,
      isEmpty,
      reason: 'Paint Volt through VoltButton, VoltDisc or VoltSlab (lib/shared/widgets/ui_kit.dart); '
          'use context.palette.primary for brand-coloured text and icons.\n${offenders.join('\n')}',
    );
  });

  test('the legacy AppColors constants and AppTypography role getters stay gone', () {
    final offenders = <String>[];
    for (final root in ['lib', 'test', 'tools']) {
      for (final (path, file) in _dartFiles(root)) {
        if (path.endsWith('test/unit/volt_usage_test.dart')) continue;
        final hits = _matches(file, _legacyApi);
        if (hits.isNotEmpty) offenders.add('$path\n  ${hits.join('\n  ')}');
      }
    }
    expect(File('lib/app/theme/app_colors.dart').existsSync(), isFalse, reason: 'the legacy re-export is gone');
    expect(
      offenders,
      isEmpty,
      reason: 'They are always the dark palette, so wrong on paper. Read context.palette / context.typography '
          '(AppPalette.dark or AppTypography.of(palette) where there is no context).\n${offenders.join('\n')}',
    );
  });

  test('no fill is painted with the palette primary outside ui_kit and app_theme', () {
    final offenders = <String>[];
    for (final (path, file) in _libFiles()) {
      if (_allowed.contains(path)) continue;
      final hits = _matches(file, _primaryFill);
      if (hits.isNotEmpty) offenders.add('$path\n  ${hits.join('\n  ')}');
    }
    expect(
      offenders,
      isEmpty,
      reason: 'In the dark theme primary is Volt: paint the fill with a Volt widget.\n${offenders.join('\n')}',
    );
  });

  test('the patterns see what they are meant to', () {
    final probe = File('${Directory.systemTemp.createTempSync('volt_usage').path}/probe.dart')
      ..writeAsStringSync('''
final a = AppColors.primary;
final b = AppTypography.body; final c = AppTypography.of(p).body;
final d = AppTypography.dmMono; // AppColors.primary in a trailing comment
// AppColors.primary in a comment line
final e = FilledButton.styleFrom(backgroundColor: context.palette.primary);
final f = BoxDecoration(color: p.primary);
final g = AppTypography.textTheme(p); final h = AppTypography.metadata;
''');
    addTearDown(() => probe.parent.deleteSync(recursive: true));
    expect(_matches(probe, _legacyApi), hasLength(3));
    expect(_matches(probe, _primaryFill), hasLength(1));
  });

  test('the allowed files really are where the Volt widgets and the chip sticker live', () {
    expect(_uses(File('lib/shared/widgets/ui_kit.dart')), isNotEmpty);
    expect(_uses(File('lib/app/theme/app_theme.dart')).join('\n'), contains('voltFill'));
  });
}
