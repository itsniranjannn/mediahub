// Settings is compact: 32 dp row icons, rows still 48 dp touch targets, no
// overflow at 360 dp with 1.3x text.
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/core/core_watermark.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';
import 'package:mediahub/shared/widgets/brand_marks.dart';
import 'package:mediahub/shared/widgets/choice_dialogs.dart';
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
    final container = ProviderContainer(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        extractorBackendProvider.overrideWithValue(FakeExtractorBackend()),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(360 * 3, 8000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
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

  testWidgets('the top level is one small row per group, and each opens its page', (tester) async {
    await pump(tester);
    final shown = SettingsSection.values.where((s) => s.isAvailable).toList();
    for (final section in shown) {
      final row = find.byKey(ValueKey('settings_section_${section.name}'));
      expect(row, findsOneWidget, reason: section.name);
      expect(tester.getSize(row).height, lessThanOrEqualTo(72), reason: '${section.name} stays a small row');
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSectionPage), findsOneWidget, reason: section.name);
      expect(find.widgetWithText(AppBar, section.title), findsOneWidget, reason: section.name);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the footer carries the logo, the wordmark and the author', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('settings_footer')), findsOneWidget);
    // Pinned: the Scaffold's bottom bar, not a row of the list.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isA<SettingsFooter>());
    // A slim strip, never a screen-filling one (the bar's height is loose).
    final footerHeight = tester.getSize(find.byKey(const ValueKey('settings_footer'))).height;
    expect(footerHeight, lessThan(110));
    // Every row stays reachable above it.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final lastRow = find.byKey(ValueKey('settings_section_${SettingsSection.values.last.name}'));
    expect(
      tester.getBottomLeft(lastRow).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('settings_footer'))).dy),
    );
    expect(find.text(CoreWatermark.fullName), findsOneWidget);
    expect(find.text('Crafted by'), findsOneWidget);
    // The signature reads as one phrase.
    expect(find.bySemanticsLabel('Crafted by ${CoreWatermark.fullName}'), findsOneWidget);
    expect(find.byType(MediaHubWordmark), findsOneWidget);
    expect(find.byType(MediaHubLogo), findsOneWidget);
    // The licences live on the About page, not at the top level.
    expect(find.byKey(const ValueKey('settings_licences')), findsNothing);
    expect(find.text('Open-source licences'), findsNothing);
  });

  testWidgets('About lists the open-source licences as a row that opens the licence page', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_section_about')));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings_licences'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Open-source licences')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.byIcon(Icons.chevron_right_rounded)), findsOneWidget);
    expect(find.descendant(of: row, matching: find.byIcon(Icons.description_rounded)), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('the footer stacks on a narrow screen with large text', (tester) async {
    await pump(tester, textScale: 2);
    tester.view.physicalSize = const Size(280 * 3, 8000 * 3);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('settings_footer'))).height, lessThan(260));
  });

  testWidgets('the settings picker marks the current choice, returns a tap and fits landscape', (tester) async {
    tester.view.physicalSize = const Size(800 * 3, 360 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showChoiceDialog<int>(
              context,
              title: 'Lock again',
              current: 1,
              options: [
                for (final m in [0, 1, 5, 15, 30]) ChoiceOption(m, '$m minutes'),
              ],
              footnote: 'A note under the choices.',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.ensureVisible(find.text('5 minutes'));
    await tester.tap(find.text('5 minutes'));
    await tester.pumpAndSettle();
    expect(picked, 5);
  });

  testWidgets('a destructive confirmation: Cancel is false, the red button is true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await confirmDestructive(context, title: 'Delete from phone?', message: 'Gone.'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_destructive')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Equalizer and "Save downloads to" are each their own tappable node', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    addTearDown(PlatformInfo.resetForTests);
    final handle = tester.ensureSemantics();
    await pump(tester);
    for (final (section, label) in [
      (SettingsSection.playback, 'Equalizer'),
      (SettingsSection.downloads, 'Save downloads to'),
    ]) {
      await tester.tap(find.byKey(ValueKey('settings_section_${section.name}')));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.text(label));
      final card = tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(ClipRRect)).first);
      expect(node.rect.height, lessThan(card.height), reason: '$label is not the whole card');
      final row = tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first);
      expect(node.rect.height, moreOrLessEquals(row.height, epsilon: 1), reason: '$label: the row, not more');
      // "Save downloads to" is disabled on this test phone (no MediaStore save).
      final tappable = tester.widget<ListTile>(find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first).onTap != null;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), tappable, reason: label);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    handle.dispose();
  });

  testWidgets('"Save downloads to" on a phone that cannot is disabled, not a dead tap', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    addTearDown(PlatformInfo.resetForTests);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('settings_section_downloads')));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.descendant(of: find.byKey(const ValueKey('save_location_row')), matching: find.byType(ListTile)),
    );
    expect(tile.onTap, isNull);
    expect(tile.enabled, isFalse);
  });
}
