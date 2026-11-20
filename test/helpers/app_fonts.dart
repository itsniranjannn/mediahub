// Loads the app's bundled fonts into the test engine, so text is measured
// with the real families (the default test font draws every glyph as a
// 1 em square). The list comes from the `fonts:` block of pubspec.yaml, so a
// family added there is picked up here too.
import 'dart:io';

import 'package:flutter/services.dart';

/// One family from pubspec.yaml and its font files.
class BundledFontFamily {
  const BundledFontFamily(this.family, this.assets);

  final String family;
  final List<String> assets;
}

/// The `fonts:` block of [pubspecPath] (relative to the package root, where
/// `flutter test` runs).
List<BundledFontFamily> bundledFontFamilies({String pubspecPath = 'pubspec.yaml'}) {
  final families = <BundledFontFamily>[];
  String? family;
  var assets = <String>[];
  var inFonts = false;
  final familyLine = RegExp(r'^\s*-\s*family:\s*(\S+)\s*$');
  final assetLine = RegExp(r'^\s*-?\s*asset:\s*(\S+)\s*$');

  void flush() {
    if (family != null) families.add(BundledFontFamily(family!, List.unmodifiable(assets)));
    family = null;
    assets = <String>[];
  }

  for (final raw in File(pubspecPath).readAsLinesSync()) {
    final line = raw.replaceAll('\r', '');
    if (RegExp(r'^  fonts:\s*$').hasMatch(line)) {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;
    // The block ends at the next key of the `flutter:` section or the file.
    if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#') && !line.startsWith('    ')) break;
    final f = familyLine.firstMatch(line);
    if (f != null) {
      flush();
      family = f.group(1);
      continue;
    }
    final a = assetLine.firstMatch(line);
    if (a != null && family != null) assets.add(a.group(1)!);
  }
  flush();
  return families;
}

Future<void>? _loading;

/// Registers every bundled family with the test engine (once per test
/// isolate). Use as `setUpAll(loadAppFonts)`.
Future<void> loadAppFonts() => _loading ??= _load();

Future<void> _load() async {
  final families = bundledFontFamilies();
  if (families.isEmpty) throw StateError('no fonts found in pubspec.yaml');
  for (final entry in families) {
    final loader = FontLoader(entry.family);
    for (final asset in entry.assets) {
      final bytes = File(asset).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}
