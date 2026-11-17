// Volt is contained (docs/DESIGN.md 0.6, 9 and 10): the brand fill reaches
// the screen only through VoltButton, VoltDisc, VoltSlab (ui_kit.dart) and
// the chip theme (app_theme.dart), which draw the ink edge on paper. Any
// other file that paints voltFill / primaryGradient / onVoltFill could put a
// lime fill on paper without its edge (1.05:1), so this test fails on it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to name the Volt fill tokens.
const _allowed = {
  'lib/shared/widgets/ui_kit.dart',
  'lib/app/theme/app_theme.dart',
  'lib/app/theme/app_palette.dart',
};

/// Screens that still paint the legacy `AppColors.primaryGradient` from
/// before the redesign, with how many reads each may keep. They move to
/// VoltButton / VoltSlab when the screens are restyled; the count may only
/// go down. Do not add entries.
const _legacy = {
  'lib/features/library/detail_screens.dart': 1,
  'lib/features/library/media_context_menu.dart': 1,
  'lib/features/music_player/music_screen.dart': 1,
  'lib/features/settings/settings_screen.dart': 1,
};

/// Legacy `AppColors.primary` / `AppColors.primaryPressed` reads per file.
/// Those are Volt in both themes, so a fill through them has no ink edge on
/// paper (1.05:1) and the token test above cannot see it. Screens move to
/// `context.palette.primary` (text and icons) or the Volt widgets (fills)
/// when they are restyled. A count may only go down (lower it here when it
/// does), and no other file may start reading them.
const _legacyPrimary = {
  'lib/app/app_shell.dart': 2,
  'lib/features/downloads/downloads_screen.dart': 10,
  'lib/features/downloads/web_link_download_flow.dart': 2,
  'lib/features/home/home_screen.dart': 6,
  'lib/features/library/detail_screens.dart': 1,
  'lib/features/library/media_context_menu.dart': 2,
  'lib/features/library/media_song_row.dart': 3,
  'lib/features/music_player/mini_player.dart': 3,
  'lib/features/music_player/music_screen.dart': 9,
  'lib/features/music_player/now_playing_sheet.dart': 11,
  'lib/features/music_player/queue_sheet.dart': 3,
  'lib/features/settings/settings_screen.dart': 1,
  'lib/features/video_player/video_player_screen.dart': 6,
  'lib/features/video_player/videos_screen.dart': 2,
  'lib/personal/format_selection_sheet.dart': 2,
  'lib/shared/widgets/empty_state_widget.dart': 1,
};

final _token = RegExp(r'\b(voltFill|voltPressed|primaryGradient|onVoltFill)\b');
final _legacyPrimaryRead = RegExp(r'\bAppColors\.primary(Pressed)?\b');

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

Iterable<(String, File)> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => (f.path.replaceAll(r'\', '/'), f));

void main() {
  test('Volt fill tokens appear only in ui_kit, app_theme and app_palette', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    var scanned = 0;
    for (final file in files) {
      scanned++;
      final path = file.path.replaceAll(r'\', '/');
      if (_allowed.contains(path)) continue;
      final hits = _uses(file);
      if (hits.isEmpty) continue;
      final legacyReads = hits.where((h) => h.contains('AppColors.primaryGradient')).length;
      final allowance = _legacy[path] ?? 0;
      final others = hits.where((h) => !h.contains('AppColors.primaryGradient')).toList();
      if (others.isNotEmpty || legacyReads > allowance) {
        offenders.add('$path\n  ${hits.join('\n  ')}');
      }
    }
    expect(scanned, greaterThan(20), reason: 'run from the package root');
    expect(
      offenders,
      isEmpty,
      reason: 'Paint Volt through VoltButton, VoltDisc or VoltSlab (lib/shared/widgets/ui_kit.dart); '
          'use context.palette.primary for brand-coloured text and icons.\n${offenders.join('\n')}',
    );
  });

  test('legacy AppColors.primary reads only go down (a Volt fill without its ink edge)', () {
    final over = <String>[];
    final tighter = <String>[];
    for (final (path, file) in _libFiles()) {
      if (_allowed.contains(path)) continue;
      final hits = _matches(file, _legacyPrimaryRead);
      final allowance = _legacyPrimary[path] ?? 0;
      if (hits.length > allowance) over.add('$path: ${hits.length} > $allowance\n  ${hits.join('\n  ')}');
      if (hits.length < allowance) tighter.add('$path: $allowance -> ${hits.length}');
    }
    for (final path in _legacyPrimary.keys) {
      if (!File(path).existsSync()) tighter.add('$path: gone, drop its entry');
    }
    expect(
      over,
      isEmpty,
      reason: 'New code reads context.palette.primary for text and icons and paints Volt fills with '
          'VoltButton, VoltDisc or VoltSlab.\n${over.join('\n')}',
    );
    expect(tighter, isEmpty, reason: 'Fewer reads now: lower _legacyPrimary to match.\n${tighter.join('\n')}');
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

  test('the ratchet patterns see what they are meant to', () {
    final probe = File('${Directory.systemTemp.createTempSync('volt_usage').path}/probe.dart')
      ..writeAsStringSync('''
final a = AppColors.primary;
final b = AppColors.primaryPressed; final c = AppColors.primary;
final d = AppColors.primaryBase; // AppColors.primary in a trailing comment
// AppColors.primary in a comment line
final e = FilledButton.styleFrom(backgroundColor: context.palette.primary);
final f = BoxDecoration(color: p.primary);
''');
    addTearDown(() => probe.parent.deleteSync(recursive: true));
    expect(_matches(probe, _legacyPrimaryRead), hasLength(3));
    expect(_matches(probe, _primaryFill), hasLength(1));
  });

  test('the allowed files really are where the Volt widgets and the chip sticker live', () {
    expect(_uses(File('lib/shared/widgets/ui_kit.dart')), isNotEmpty);
    expect(_uses(File('lib/app/theme/app_theme.dart')).join('\n'), contains('voltFill'));
  });
}
