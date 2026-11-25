// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
// The Settings planet: one look per theme, and its slow turn stops with
// reduced motion, a paused app, a covering route and picture-in-picture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/shared/widgets/planet_backdrop.dart';

void main() {
  setUp(() => PlanetBackdrop.debugAnimate = true);
  tearDown(() => PlanetBackdrop.debugAnimate = false);

  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    bool reduceMotion = false,
    Size size = const Size(360, 780),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.classicTheme,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: const PlanetBackdrop(
              child: Scaffold(backgroundColor: Colors.transparent, body: Text('card')),
            ),
          ),
        ),
      ),
    );
  }

  PlanetBackdropState state(WidgetTester tester) => tester.state<PlanetBackdropState>(find.byType(PlanetBackdrop));

  test('each theme has its own planet', () {
    expect(PlanetLook.of(AppPalette.dark), PlanetLook.mars);
    expect(PlanetLook.of(AppPalette.light), PlanetLook.dune);
    expect(PlanetLook.of(AppPalette.classic), PlanetLook.gasGiant);
  });

  for (final (name, theme) in [
    ('Sindur dark', AppTheme.darkTheme),
    ('Sindur light', AppTheme.lightTheme),
    ('Bijuli Classic', AppTheme.classicTheme),
  ]) {
    testWidgets('renders in $name, portrait and landscape', (tester) async {
      await pump(tester, theme: theme);
      expect(find.byKey(const ValueKey('planet_backdrop')), findsOneWidget);
      expect(find.text('card'), findsOneWidget);
      await pump(tester, theme: theme, size: const Size(780, 360));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('turns slowly while visible', (tester) async {
    await pump(tester);
    expect(state(tester).isAnimating, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no motion with reduced motion', (tester) async {
    await pump(tester, reduceMotion: true);
    expect(state(tester).isAnimating, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('stops when the app is paused and resumes after', (tester) async {
    await pump(tester);
    expect(state(tester).isAnimating, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(state(tester).isAnimating, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(state(tester).isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stops in picture-in-picture', (tester) async {
    await pump(tester);
    DeviceControls.inPip.value = true;
    addTearDown(() => DeviceControls.inPip.value = false);
    expect(state(tester).isAnimating, isFalse);
    DeviceControls.inPip.value = false;
    expect(state(tester).isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stops while a route covers it', (tester) async {
    await pump(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('above'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.state<PlanetBackdropState>(find.byType(PlanetBackdrop, skipOffstage: false)).isAnimating, isFalse);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(state(tester).isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
