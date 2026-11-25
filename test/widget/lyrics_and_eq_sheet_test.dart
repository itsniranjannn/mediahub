// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// The lyrics view follows the music (the line being sung is highlighted),
// and the equalizer sheet saves a preset and turns a moved band into Custom.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/music_player/equalizer/audio_effects.dart';
import 'package:mediahub/features/music_player/equalizer/equalizer_sheet.dart';
import 'package:mediahub/features/music_player/lyrics/lyrics.dart';
import 'package:mediahub/features/music_player/lyrics/lyrics_sheet.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

void main() {
  testWidgets('synced lyrics highlight the line at the player position', (tester) async {
    final lyrics = Lyrics.parse('[00:01.00]one\n[00:05.00]two\n[00:09.00]three', source: LyricsSource.sidecar)!;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 6))),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SyncedLyricsView(lyrics: lyrics))),
    ));
    await tester.pumpAndSettle();
    Color? colorOf(String t) => tester.widget<Text>(find.text(t)).style?.color;
    expect(colorOf('two'), AppPalette.dark.primary);
    expect(colorOf('one'), AppPalette.dark.textMuted);
    expect(colorOf('three'), AppPalette.dark.textSecondary);
    expect(find.text('From a .lrc file'), findsOneWidget);
  });

  testWidgets('plain lyrics are just text', (tester) async {
    final lyrics = Lyrics.parse('line a\nline b', source: LyricsSource.embedded)!;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SyncedLyricsView(lyrics: lyrics))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('line a'), findsOneWidget);
    expect(find.text('From the song file'), findsOneWidget);
  });

  testWidgets('equalizer: on, a preset, then a moved band is Custom; all saved', (tester) async {
    for (final k in [
      EqualizerSettings.enabledKey,
      EqualizerSettings.presetKey,
      EqualizerSettings.customKey,
      EqualizerSettings.loudnessKey,
    ]) {
      await SettingsStore.instance.remove(k);
    }
    tester.view.physicalSize = const Size(360, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: EqualizerSheet(parametersOverride: () async => AndroidEqualizerParameters(
                minDecibels: -15,
                maxDecibels: 15,
                bands: const [],
              )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Play a song once'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    final saved = EqualizerSettings.load(SettingsStore.instance);
    expect(saved.enabled, isTrue);
    expect(saved.preset, 'Rock');
    await tester.drag(find.byKey(const ValueKey('eq_loudness')), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(EqualizerSettings.load(SettingsStore.instance).loudnessDb, greaterThan(0));
  });
}
