import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/online/online_settings.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:mediahub/features/settings/settings_screen.dart';

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
  });

  Future<ProviderContainer> pump(WidgetTester tester, {required void Function() onClear}) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      onlineDataClearerProvider.overrideWithValue(() async => onClear()),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
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

  testWidgets('a saved choice is read back', (tester) async {
    await SettingsStore.instance.setBool(OnlineBackgroundPlayNotifier.prefKey, false);
    final c = await pump(tester, onClear: () {});
    expect(c.read(onlineBackgroundPlayProvider), isFalse);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    final bg = switches.firstWhere((s) => (s.title as Text).data == 'Background play');
    expect(bg.value, isFalse);
  });

  testWidgets('Clear YouTube data asks first; Cancel keeps everything', (tester) async {
    var cleared = 0;
    await pump(tester, onClear: () => cleared++);
    await tester.tap(find.text('Clear YouTube data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear YouTube data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cleared, 0);

    await tester.tap(find.text('Clear YouTube data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
    expect(find.text('YouTube data cleared'), findsOneWidget);
  });
}
