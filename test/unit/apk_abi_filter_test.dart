// The family phones are arm64 only. Release builds must ship arm64-v8a native
// libraries only (youtubedl-android's Python and ffmpeg payloads dominate the
// APK), the emulator modes x86_64, and nobody may switch to --split-per-abi
// (it changes the version codes the phones update by).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final script = File('tools/device/build_apks.sh').readAsStringSync();

  test('build.gradle filters ABIs and defaults release builds to arm64-v8a', () {
    expect(gradle, contains('findProperty("mediahub.abis")'));
    expect(gradle, contains('listOf("arm64-v8a")'));
    expect(gradle, contains('abiFilters.addAll('));
    expect(gradle, contains(r'excludes += "lib/$abi/**"'));
    expect(gradle, isNot(contains(RegExp(r'^\s*splits\s*\{', multiLine: true))));
  });

  test('build_apks.sh: phone modes arm64, emulator modes x86_64, no split-per-abi', () {
    expect(script, contains('ARM=(--target-platform android-arm64 -P mediahub.abis=arm64-v8a)'));
    expect(script, contains('X64=(--target-platform android-x64 -P mediahub.abis=x86_64)'));
    String line(String mode) =>
        const LineSplitter().convert(script).firstWhere((l) => l.trimLeft().startsWith('$mode)') && l.contains('flutter build apk'));
    for (final mode in ['test', 'family', 'testrel']) {
      expect(line(mode), contains(r'"${ARM[@]}"'), reason: '$mode builds arm64');
    }
    for (final mode in ['emulator', 'relx64']) {
      expect(line(mode), contains(r'"${X64[@]}"'), reason: '$mode builds x86_64');
    }
    expect(
      const LineSplitter().convert(script).where((l) => !l.trimLeft().startsWith('#') && l.contains('--split-per-abi')),
      isEmpty,
    );
  });
}
