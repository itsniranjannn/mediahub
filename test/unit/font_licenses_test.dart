// The bundled fonts: every family in pubspec.yaml has its file and its SIL
// OFL licence, the licences page lists them, and Inter is gone.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/app.dart';
import 'package:mediahub/app/theme/font_licenses.dart';

import '../helpers/app_fonts.dart';

String _normalised(String text) => text.replaceAll('\r\n', '\n').replaceFirst('﻿', '');

void main() {
  test('pubspec registers the three Sindur families, every file exists, Inter is gone', () {
    final families = bundledFontFamilies();
    expect(families.map((f) => f.family), ['Fraunces', 'Poppins', 'DMMono']);
    for (final family in families) {
      expect(family.assets, isNotEmpty, reason: family.family);
      for (final asset in family.assets) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
    expect(RegExp(r'\bInter\b').hasMatch(File('pubspec.yaml').readAsStringSync()), isFalse);
    final leftovers = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.startsWith('Inter') || name == 'OFL.txt');
    expect(leftovers, isEmpty);
  });

  test('the embedded licence texts are the files in assets/fonts/licenses/', () {
    expect(fontLicenses, hasLength(3));
    for (final license in fontLicenses) {
      final file = File('assets/fonts/licenses/${license.file}');
      expect(file.existsSync(), isTrue, reason: license.file);
      expect(license.text, _normalised(file.readAsStringSync()), reason: license.file);
      expect(license.text, contains('SIL Open Font License, Version 1.1'));
    }
  });

  test('the licences page lists every bundled family once', () async {
    MediaHubApp.ensureStartup();
    MediaHubApp.ensureStartup();
    final entries = await LicenseRegistry.licenses.toList();
    for (final license in fontLicenses) {
      final matches = entries.where((e) => e.packages.contains(license.family)).toList();
      expect(matches, hasLength(1), reason: license.family);
      final paragraphs = matches.single.paragraphs.map((p) => p.text).join('\n');
      expect(paragraphs, contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
  });
}
