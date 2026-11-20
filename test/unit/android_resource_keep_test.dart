// Release builds shrink resources (isShrinkResources = true). Drawables that
// Dart names by string (audio_service's notification buttons and the
// status-bar icon) are invisible to the shrinker, so each one must match a
// pattern in res/raw/keep.xml, or the release APK loses it: a missing small
// icon makes startForeground fail as soon as music starts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every drawable named from Dart is kept in release builds', () {
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    final attr = RegExp(r'tools:keep="([^"]*)"').firstMatch(keep);
    expect(attr, isNotNull, reason: 'keep.xml has a tools:keep list');
    final patterns = [
      for (final p in attr!.group(1)!.split(','))
        if (p.trim().startsWith('@drawable/'))
          RegExp('^${RegExp.escape(p.trim().substring('@drawable/'.length)).replaceAll(r'\*', '.*')}\$'),
    ];

    final named = <String>{};
    final ref = RegExp(r"'drawable/([a-z0-9_]+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in ref.allMatches(f.readAsStringSync())) {
        named.add(m.group(1)!);
      }
    }
    expect(named, contains('ic_stat_mediahub'), reason: 'the status-bar icon is named from main.dart');
    expect(named, contains('ic_action_favorite_on'));

    for (final name in named) {
      expect(File('android/app/src/main/res/drawable/$name.xml').existsSync() ||
              File('android/app/src/main/res/drawable/$name.png').existsSync(),
          isTrue,
          reason: 'drawable/$name exists');
      expect(patterns.any((p) => p.hasMatch(name)), isTrue, reason: 'drawable/$name is in keep.xml');
    }
  });
}
