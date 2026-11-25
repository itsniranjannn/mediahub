// Settings rows added when the package changes came together:
// - Audio & headset → "Resume after other apps" (Android only): music that
//   another app's sound paused plays again once that app stops.
// - Personal tools → the yt-dlp row says when MediaHub last updated it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/music_player/resume_after_other_apps.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/personal/extractor_auto_updater.dart';
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

  setUp(() async {
    await SettingsStore.instance.setBool(ResumeAfterOtherAppsNotifier.prefKey, true);
  });

  tearDown(PlatformInfo.resetForTests);

  Future<ProviderContainer> pump(WidgetTester tester, {FakeExtractorBackend? backend}) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      extractorBackendProvider.overrideWithValue(backend ?? FakeExtractorBackend()),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 11000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsSectionPage.combined([SettingsSection.playback, SettingsSection.downloads])),
    ));
    await tester.pump();
    return container;
  }

  testWidgets('Playback & audio: shows Equalizer and Find lyrics online; auto-resume toggles removed', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pump(tester);

    expect(find.text('Playback & audio'), findsWidgets);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Find lyrics online'), findsOneWidget);
    // Auto-resume switches were removed from settings and left always enabled by default
    expect(find.text('Resume after other apps'), findsNothing);
    expect(find.text('Resume when headphones reconnect'), findsNothing);
  });

  testWidgets('Personal tools: the yt-dlp row says when MediaHub last updated it', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await SettingsStore.instance.setBool('personal_tools_enabled', true);
    await SettingsStore.instance
        .setString(ExtractorAutoUpdater.lastUpdatedKey, '${DateTime.now().millisecondsSinceEpoch}');
    addTearDown(() => SettingsStore.instance.setString(ExtractorAutoUpdater.lastUpdatedKey, ''));
    final backend = FakeExtractorBackend()..currentVersion = '2026.11.10';
    await pump(tester, backend: backend);
    // The version is read in the background once the card is built.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('yt-dlp engine version'), findsOneWidget);
    expect(find.text('2026.11.10 · Updated today'), findsOneWidget);
  });
}
