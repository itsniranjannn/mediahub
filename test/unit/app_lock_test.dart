// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// App lock: off by default; on at start when enabled; again after N minutes
// in the background; the phone's own prompt unlocks; turning it on or off
// asks first; the lock screen covers the whole app or only Downloads and
// Online, never the picture-in-picture window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/app_lock/app_lock.dart';

class _FakeAuth implements DeviceAuthenticator {
  bool available = true;
  bool answer = true;
  int prompts = 0;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return answer;
  }

  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  late _FakeAuth auth;
  late DateTime now;

  setUp(() async {
    auth = _FakeAuth();
    now = DateTime(2026, 11, 25, 10);
    AppLockNotifier.clock = () => now;
    for (final k in [AppLockSettings.enabledKey, AppLockSettings.scopeKey, AppLockSettings.minutesKey]) {
      await SettingsStore.instance.remove(k);
    }
  });

  tearDown(() => AppLockNotifier.clock = DateTime.now);

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [deviceAuthenticatorProvider.overrideWithValue(auth)]);
    addTearDown(c.dispose);
    return c;
  }

  test('off by default: never locked', () {
    final c = container();
    final s = c.read(appLockProvider);
    expect(s.settings.enabled, isFalse);
    expect(s.locked, isFalse);
    expect(s.settings.scope, AppLockScope.wholeApp);
    c.read(appLockProvider.notifier).onLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 1));
    c.read(appLockProvider.notifier).onLifecycle(AppLifecycleState.resumed);
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('turning it on asks first; refused or no screen lock keeps it off', () async {
    final c = container();
    final n = c.read(appLockProvider.notifier);
    auth.available = false;
    expect(await n.setEnabled(true), isFalse);
    expect(auth.prompts, 0);
    auth.available = true;
    auth.answer = false;
    expect(await n.setEnabled(true), isFalse);
    expect(c.read(appLockProvider).settings.enabled, isFalse);
    auth.answer = true;
    expect(await n.setEnabled(true), isTrue);
    expect(c.read(appLockProvider).settings.enabled, isTrue);
    expect(c.read(appLockProvider).locked, isFalse, reason: 'just proved it is them');
    expect(SettingsStore.instance.getBool(AppLockSettings.enabledKey), isTrue);
  });

  test('locked at start when on; unlock needs the prompt to say yes', () async {
    await SettingsStore.instance.setBool(AppLockSettings.enabledKey, true);
    final c = container();
    expect(c.read(appLockProvider).locked, isTrue);
    auth.answer = false;
    expect(await c.read(appLockProvider.notifier).unlock(), isFalse);
    expect(c.read(appLockProvider).locked, isTrue);
    auth.answer = true;
    expect(await c.read(appLockProvider.notifier).unlock(), isTrue);
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('locks again only after N minutes in the background', () async {
    await SettingsStore.instance.setBool(AppLockSettings.enabledKey, true);
    await SettingsStore.instance.setString(AppLockSettings.minutesKey, '5');
    final c = container();
    final n = c.read(appLockProvider.notifier);
    await n.unlock();
    n.onLifecycle(AppLifecycleState.inactive);
    n.onLifecycle(AppLifecycleState.hidden);
    n.onLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    n.onLifecycle(AppLifecycleState.resumed);
    expect(c.read(appLockProvider).locked, isFalse);
    n.onLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 5));
    n.onLifecycle(AppLifecycleState.resumed);
    expect(c.read(appLockProvider).locked, isTrue);
  });

  test('"Immediately" locks on every return; the prompt itself never re-locks', () async {
    await SettingsStore.instance.setBool(AppLockSettings.enabledKey, true);
    await SettingsStore.instance.setString(AppLockSettings.minutesKey, '0');
    final c = container();
    final n = c.read(appLockProvider.notifier);
    await n.unlock();
    n.onLifecycle(AppLifecycleState.paused);
    n.onLifecycle(AppLifecycleState.resumed);
    expect(c.read(appLockProvider).locked, isTrue);
    // The PIN screen pauses MediaHub while it is open: ignored.
    final pending = n.unlock();
    n.onLifecycle(AppLifecycleState.paused);
    n.onLifecycle(AppLifecycleState.resumed);
    await pending;
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('a bad stored minutes value falls back to 1; scopes parse safely', () {
    final store = SettingsStore.forTesting();
    store.setString(AppLockSettings.minutesKey, '7');
    store.setString(AppLockSettings.scopeKey, 'whatever');
    final s = AppLockSettings.load(store);
    expect(s.lockAfterMinutes, 1);
    expect(s.scope, AppLockScope.wholeApp);
    expect(AppLockScope.parse('downloadsAndOnline'), AppLockScope.downloadsAndOnline);
  });

  test('tab scope covers only Downloads (4) and Online (3)', () {
    const s = AppLockState(
      settings: AppLockSettings(enabled: true, scope: AppLockScope.downloadsAndOnline),
      locked: true,
    );
    expect([for (var i = 0; i < 5; i++) s.coversTab(i)], [false, false, false, true, true]);
    expect(s.coversWholeApp, isFalse);
    const whole = AppLockState(settings: AppLockSettings(enabled: true), locked: true);
    expect(whole.coversWholeApp, isTrue);
    expect(whole.coversTab(4), isFalse);
  });

  group('widgets', () {
    Widget app(ProviderContainer c, Widget child) => UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: AppTheme.darkTheme, home: AppLockGate(child: child)),
        );

    testWidgets('the whole-app lock screen covers the app and unlocks with the prompt', (tester) async {
      await SettingsStore.instance.setBool(AppLockSettings.enabledKey, true);
      auth.answer = false;
      final c = container();
      await tester.pumpWidget(app(c, const Scaffold(body: Text('Library'))));
      await tester.pump();
      expect(find.text('MediaHub is locked'), findsOneWidget);
      expect(auth.prompts, 1, reason: 'asks by itself once');
      auth.answer = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('MediaHub is locked'), findsNothing);
      expect(find.text('Library'), findsOneWidget);
    });

    testWidgets('never over the picture-in-picture window', (tester) async {
      await SettingsStore.instance.setBool(AppLockSettings.enabledKey, true);
      auth.answer = false;
      final c = container();
      DeviceControls.inPip.value = true;
      addTearDown(() => DeviceControls.inPip.value = false);
      await tester.pumpWidget(app(c, const Scaffold(body: Text('Video'))));
      await tester.pump();
      expect(find.text('MediaHub is locked'), findsNothing);
      DeviceControls.inPip.value = false;
      await tester.pump();
      expect(find.text('MediaHub is locked'), findsOneWidget);
    });

    testWidgets('tab scope: Home stays open, Downloads is covered', (tester) async {
      await SettingsStore.instance.setBool(AppLockSettings.enabledKey, true);
      await SettingsStore.instance.setString(AppLockSettings.scopeKey, AppLockScope.downloadsAndOnline.name);
      auth.answer = false;
      final c = container();
      final index = ValueNotifier<int>(0);
      await tester.pumpWidget(app(
        c,
        ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, i, _) => Scaffold(body: AppLockTabCover(branchIndex: i, child: Text('Tab $i'))),
        ),
      ));
      await tester.pump();
      expect(find.text('MediaHub is locked'), findsNothing);
      expect(auth.prompts, 0);
      index.value = 4;
      await tester.pump();
      await tester.pump();
      expect(find.text('MediaHub is locked'), findsOneWidget);
      expect(auth.prompts, 1);
    });
  });
}
