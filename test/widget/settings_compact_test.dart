// Settings is compact: 32 dp row icons, rows still 48 dp touch targets, no
// overflow at 360 dp with 1.3x text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../unit/fake_extractor_backend.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

MusicAudioHandler _handler() {
  final p = _MockAudioPlayer();
  when(() => p.playbackEventStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playerStateStream).thenAnswer((_) => const Stream.empty());
  when(() => p.currentIndexStream).thenAnswer((_) => const Stream.empty());
  when(() => p.positionStream).thenAnswer((_) => const Stream.empty());
  when(() => p.durationStream).thenAnswer((_) => const Stream.empty());
  when(() => p.dispose()).thenAnswer((_) async {});
  return MusicAudioHandler(player: p);
}

void main() {
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      extractorBackendProvider.overrideWithValue(FakeExtractorBackend()),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(360 * 3, 8000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
  }

  testWidgets('rows keep 48 dp touch targets and use 32 dp leading slots', (tester) async {
    await pump(tester);
    final tiles = find.byWidgetPredicate((w) => w is ListTile || w is SwitchListTile);
    expect(tiles, findsWidgets);
    for (final e in tiles.evaluate()) {
      expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(48));
    }
    final icons = find.descendant(of: find.byType(ListTile), matching: find.byType(Icon));
    expect(tester.getSize(icons.first).width, lessThanOrEqualTo(32));
  });

  testWidgets('no overflow at 360 dp and 1.3x text', (tester) async {
    await pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
