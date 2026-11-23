// Emulator QA: with a bottom sheet open, the mini player and the Ink Dock
// stayed bright and tappable above it, because the sheet was pushed on the
// tab's own navigator (under the shell's dock). Every sheet in the app opens
// on the root navigator, so its barrier covers the dock too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every showModalBottomSheet in lib/ opens on the root navigator', () {
    final missing = <String>[];
    final call = RegExp(r'showModalBottomSheet(<[^>]*>)?\(');
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        final lineStart = source.lastIndexOf('\n', match.start) + 1;
        if (source.substring(lineStart, match.start).trimLeft().startsWith('//')) continue; // a comment
        // The call's arguments: up to the matching closing parenthesis.
        var depth = 0;
        var end = match.end - 1;
        for (var i = match.end - 1; i < source.length; i++) {
          final c = source[i];
          if (c == '(') depth++;
          if (c == ')' && --depth == 0) {
            end = i;
            break;
          }
        }
        final args = source.substring(match.end, end);
        if (!args.contains('useRootNavigator: true')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          missing.add('${file.path}:$line');
        }
      }
    }
    expect(missing, isEmpty, reason: 'these sheets would open under the Ink Dock');
  });
}
