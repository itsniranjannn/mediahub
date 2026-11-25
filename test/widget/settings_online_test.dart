import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/online/online_settings.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';

import '../unit/fake_extractor_backend.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

MusicAudioHandler _handler() {
  final p = MockAudioPlayer();
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
    await SettingsStore.instance.setBool(OnlineBackgroundPlayNotifier.prefKey, true);
    await SettingsStore.instance.setBool(OnlineAutoPipNotifier.prefKey, true);
    await SettingsStore.instance.setBool(OnlineBlockAdsNotifier.prefKey, true);
  });

  tearDown(PlatformInfo.resetForTests);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required void Function() onClear,
    ExtractorBackend? backend,
  }) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      onlineDataClearerProvider.overrideWithValue(() async => onClear()),
      if (backend != null) extractorBackendProvider.overrideWithValue(backend),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 11000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsSectionPage.combined([SettingsSection.online, SettingsSection.downloads])),
    ));
    await tester.pump();
    return container;
  }

  testWidgets('Settings → Online: both toggles default on, switch off and persist', (tester) async {
    final c = await pump(tester, onClear: () {});
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Background play'), findsOneWidget);
    expect(find.text('Auto picture-in-picture'), findsOneWidget);
    expect(c.read(onlineBackgroundPlayProvider), isTrue);
    expect(c.read(onlineAutoPipProvider), isTrue);

    await tester.tap(find.text('Background play'));
    await tester.pump();
    expect(c.read(onlineBackgroundPlayProvider), isFalse);
    expect(SettingsStore.instance.getBool(OnlineBackgroundPlayNotifier.prefKey, defaultValue: true), isFalse);

    await tester.tap(find.text('Auto picture-in-picture'));
    await tester.pump();
    expect(c.read(onlineAutoPipProvider), isFalse);
    expect(SettingsStore.instance.getBool(OnlineAutoPipNotifier.prefKey, defaultValue: true), isFalse);
  });

  testWidgets('Settings → Online → Block ads: on by default, plain words, switches off and persists', (tester) async {
    final c = await pump(tester, onClear: () {});
    expect(find.text('Block ads'), findsOneWidget);
    expect(find.text(onlineBlockAdsSubtitle), findsOneWidget);
    expect(c.read(onlineBlockAdsProvider), isTrue);
    SwitchListTile row() => tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .firstWhere((s) => (s.title as Text).data == 'Block ads');
    expect(row().value, isTrue);

    await tester.tap(find.text('Block ads'));
    await tester.pump();
    expect(c.read(onlineBlockAdsProvider), isFalse);
    expect(row().value, isFalse);
    expect(SettingsStore.instance.getBool(OnlineBlockAdsNotifier.prefKey, defaultValue: true), isFalse);

    await tester.tap(find.text('Block ads'));
    await tester.pump();
    expect(c.read(onlineBlockAdsProvider), isTrue);
    expect(SettingsStore.instance.getBool(OnlineBlockAdsNotifier.prefKey, defaultValue: false), isTrue);
  });

  testWidgets('Block ads: on with nothing stored (a new install)', (tester) async {
    await SettingsStore.instance.remove(OnlineBlockAdsNotifier.prefKey);
    expect(OnlineBlockAdsNotifier.prefKey, 'online_block_ads', reason: 'a renamed key would lose the saved choice');
    final c = await pump(tester, onClear: () {});
    expect(c.read(onlineBlockAdsProvider), isTrue);
    final row = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .firstWhere((s) => (s.title as Text).data == 'Block ads');
    expect(row.value, isTrue);
    expect(SettingsStore.instance.getBool(OnlineBlockAdsNotifier.prefKey, defaultValue: false), isFalse,
        reason: 'still nothing stored: the default, not a saved value, said on');
  });

  testWidgets('Block ads: a saved "off" is read back', (tester) async {
    await SettingsStore.instance.setBool(OnlineBlockAdsNotifier.prefKey, false);
    final c = await pump(tester, onClear: () {});
    expect(c.read(onlineBlockAdsProvider), isFalse);
  });

  test('the Block ads words: short, plain, and say what to do when a video will not play', () {
    expect(onlineBlockAdsTitle, 'Block ads');
    expect(onlineBlockAdsSubtitle, contains('video ads'));
    expect(onlineBlockAdsSubtitle, contains("If a video won't play, turn this off."));
    expect(onlineBlockAdsSubtitle.length, lessThan(120));
  });

  testWidgets('a saved choice is read back', (tester) async {
    await SettingsStore.instance.setBool(OnlineBackgroundPlayNotifier.prefKey, false);
    final c = await pump(tester, onClear: () {});
    expect(c.read(onlineBackgroundPlayProvider), isFalse);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    final bg = switches.firstWhere((s) => (s.title as Text).data == 'Background play');
    expect(bg.value, isFalse);
  });

  /// The Clear row sits below the Online switches: scrolled into view first.
  Future<void> tapClear(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Clear YouTube data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear YouTube data'));
  }

  testWidgets('Clear YouTube data asks first; Cancel keeps everything', (tester) async {
    var cleared = 0;
    await pump(tester, onClear: () => cleared++);
    await tapClear(tester);
    await tester.pumpAndSettle();
    expect(find.text('Clear YouTube data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cleared, 0);

    await tapClear(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
    expect(find.text('YouTube data cleared'), findsOneWidget);
  });

  // Sign-in now works in the Online tab (as far as Google allows it there).
  testWidgets('Settings → Online says where to sign in, that Google may refuse, and that Clear signs out',
      (tester) async {
    await pump(tester, onClear: () {});
    expect(find.text('YouTube sign-in'), findsOneWidget);
    expect(find.text(youTubeSignInSettingsBody), findsOneWidget);
    expect(find.textContaining('Not supported'), findsNothing);
    expect(find.text("Signs you out and forgets YouTube's cookies, cache and site settings on this phone."),
        findsOneWidget);
  });

  test('the sign-in and Clear texts: short, plain and honest on both phones', () {
    expect(youTubeSignInSettingsTitle, 'YouTube sign-in');
    expect(youTubeSignInSettingsBody, contains('Sign in to YouTube'), reason: 'the menu row it points to');
    expect(youTubeSignInSettingsBody, contains('Google may refuse'));
    expect(youTubeSignInSettingsBody, isNot(contains('⋮')), reason: 'words, not a glyph the font may lack');
    expect(clearYouTubeDataSettingsSubtitle(), startsWith('Signs you out'));
    PlatformInfo.debugIsIOS = true;
    expect(clearYouTubeDataSettingsSubtitle(),
        "Signs you out and forgets YouTube's cookies, cache and saved site data on this iPhone.");
  });

  testWidgets('Clear YouTube data says it signs you out', (tester) async {
    await pump(tester, onClear: () {});
    await tapClear(tester);
    await tester.pumpAndSettle();
    expect(
      find.text("Signs you out and forgets YouTube's cookies, cache and site settings on this phone. "
          'Your downloads and library stay.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  group('Personal tools: yt-dlp Update and Reset (SEC-10)', () {
    Future<ProviderContainer> pumpAndroid(WidgetTester tester, FakeExtractorBackend backend) async {
      PlatformInfo.debugIsAndroid = true;
      await SettingsStore.instance.setBool('personal_tools_enabled', true);
      final c = await pump(tester, onClear: () {}, backend: backend);
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('off while a web link download runs, with a reason; on again after', (tester) async {
      final c = await pumpAndroid(tester, FakeExtractorBackend());
      FilledButton update() => tester.widget<FilledButton>(find.byKey(const ValueKey('settings_ytdlp_update')));
      TextButton reset() => tester.widget<TextButton>(find.byKey(const ValueKey('settings_ytdlp_reset')));
      expect(update().onPressed, isNotNull);
      expect(reset().onPressed, isNotNull);

      c.read(extractorRunningDownloadsProvider.notifier).set(1);
      await tester.pumpAndSettle();
      expect(update().onPressed, isNull);
      expect(reset().onPressed, isNull);
      expect(find.byKey(const ValueKey('settings_ytdlp_busy')), findsOneWidget);
      expect(find.text('Web link downloads are running. Update when they finish.'), findsOneWidget);

      c.read(extractorRunningDownloadsProvider.notifier).set(0);
      await tester.pumpAndSettle();
      expect(update().onPressed, isNotNull);
      expect(find.byKey(const ValueKey('settings_ytdlp_busy')), findsNothing);
    });

    testWidgets('the result is one plain line: success in the success colour, failure in the error colour',
        (tester) async {
      final backend = _FailingUpdate();
      final c = await pumpAndroid(tester, backend);
      final update = find.byKey(const ValueKey('settings_ytdlp_update'));
      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      await tester.tap(update);
      await tester.pumpAndSettle();
      final failed = tester.widget<Text>(find.text('Could not update. Check your connection.'));
      final palette = tester.element(find.byType(SettingsSectionPage)).palette;
      expect(failed.style!.color, palette.error);
      expect(c.read(personalToolsProvider).updateFailed, isTrue);

      backend.fail = false;
      await tester.tap(update);
      await tester.pumpAndSettle();
      final ok = tester.widget<Text>(find.text('Updated to 2026.11.02'));
      expect(ok.style!.color, palette.success);
    });
  });
}

class _FailingUpdate extends FakeExtractorBackend {
  bool fail = true;

  @override
  Future<String> update() async {
    if (fail) throw const ExtractorException('UPDATE_ERROR', 'java.net.UnknownHostException');
    return super.update();
  }
}

