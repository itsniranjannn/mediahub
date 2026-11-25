import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/downloads/download_link_inbox.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/online/online_background_handoff.dart';
import 'package:mediahub/features/online/online_media_session.dart';
import 'package:mediahub/features/online/online_open_request.dart';
import 'package:mediahub/features/online/online_screen.dart';
import 'package:mediahub/features/online/online_settings.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

import 'online_fakes.dart';

import '../helpers/app_fonts.dart';

const watchUrl = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ&si=tracking&pp=x';

class _Harness {
  _Harness(this.web, this.host, this.container, this.router);
  final FakeOnlineWebView web;
  final FakeExternalHost host;
  final ProviderContainer container;
  final GoRouter router;
  final List<Uri> opened = [];
  int cleared = 0;
  final List<domain.MediaItem> saved = [];

  /// (fullscreen, landscape) for every orientation / system-bar change.
  final List<(bool, bool)> chrome = [];
}

/// The music player is never driven from these widget tests.
class _NoPlayer implements HandoffPlayer {
  @override
  domain.PlaybackState? captureLocal() => null;
  @override
  HandoffPlayerState get current => const HandoffPlayerState();
  @override
  Future<void> pause() async {}
  @override
  Future<void> playAlone(domain.MediaItem item, Duration position, {bool play = true}) async {}
  @override
  Future<void> restoreLocal(domain.PlaybackState? saved) async {}
  @override
  Future<void> restoreSettings() async {}
}

Future<_Harness> _pumpOnline(WidgetTester tester, {int? androidSdk, ThemeData? theme, Uri? openRequest}) async {
  final web = FakeOnlineWebView();
  final host = FakeExternalHost();
  late _Harness h;
  final router = GoRouter(
    initialLocation: '/online',
    routes: [
      GoRoute(path: '/online', builder: (context, state) => const Scaffold(body: OnlineScreen())),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const Scaffold(body: Center(child: Text('Downloads page'))),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      onlineWebViewBuilderProvider.overrideWithValue(web.builder),
      onlineAssetsProvider.overrideWith((ref) async => fakeOnlineAssets),
      androidSdkIntProvider.overrideWith((ref) async => androidSdk),
      onlineMediaSessionProvider.overrideWith((ref) {
        final s = OnlineMediaSession(host: host);
        ref.onDispose(s.dispose);
        return s;
      }),
      onlineExternalLauncherProvider.overrideWithValue((uri) async => h.opened.add(uri)),
      onlineDataClearerProvider.overrideWithValue(() async => h.cleared++),
      onlineSaveSheetProvider.overrideWithValue((context, ref, item) async => h.saved.add(item)),
      onlineFullscreenChromeProvider.overrideWithValue(({required fullscreen, required landscape}) async {
        h.chrome.add((fullscreen, landscape));
      }),
      onlineBackgroundHandoffProvider.overrideWith((ref) {
        final handoff = OnlineBackgroundHandoff(
          session: ref.watch(onlineMediaSessionProvider),
          player: _NoPlayer(),
          resolveStreams: (id) async => throw const OnlineException('no network in tests'),
          enabled: () => false,
        );
        ref.onDispose(handoff.dispose);
        return handoff;
      }),
    ],
  );
  h = _Harness(web, host, container, router);
  if (openRequest != null) container.read(onlineOpenRequestProvider.notifier).open(openRequest);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: theme, routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
  return h;
}

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  final clipboard = <String>[];

  setUpAll(() {
    DiagnosticsService.enableDebounce = false;
  });

  setUp(() async {
    clipboard.clear();
    DeviceControls.resetPipForTests();
    await SettingsStore.instance.setBool(OnlineBackgroundPlayNotifier.prefKey, true);
    await SettingsStore.instance.setBool(OnlineAutoPipNotifier.prefKey, true);
    await SettingsStore.instance.setBool(OnlineBlockAdsNotifier.prefKey, true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
  });

  tearDown(() {
    PlatformInfo.resetForTests();
    DeviceControls.resetPipForTests();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // Emulator QA (light theme): a 1-2 px light line between the WebView and
  // the dock. The page's bottom edge sits on the dock's ink, not the canvas.
  testWidgets('light theme: the last pixels under the page are dock ink, not the light canvas', (tester) async {
    await _pumpOnline(tester, theme: AppTheme.lightTheme);
    final seam = find.byKey(const ValueKey('online_dock_seam'));
    expect(seam, findsOneWidget);
    expect(tester.widget<ColoredBox>(seam).color, AppPalette.dark.dock.withValues(alpha: 1));
    final page = tester.getRect(key('fake_webview'));
    final under = tester.getRect(seam);
    expect(under.bottom, page.bottom, reason: 'flush with the bottom of the page, where the dock starts');
    expect(under.height, onlinePageSeamHeight);
    expect(under.width, page.width);
  });

  testWidgets('loads YouTube home with the bridge injected and a token', (tester) async {
    final h = await _pumpOnline(tester);
    expect(key('fake_webview'), findsOneWidget);
    expect(h.web.config!.initialUrl.toString(), 'https://m.youtube.com/');
    expect(h.web.config!.fixtureHtml, isNull);
    expect(h.web.token, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(h.web.config!.backgroundPlay, isTrue);
  });

  testWidgets('toolbar: back/forward disabled without history, stop while loading, reload after', (tester) async {
    final h = await _pumpOnline(tester);
    IconButton button(String k) => tester.widget<IconButton>(key(k));
    expect(button('online_back').onPressed, isNull);
    expect(button('online_forward').onPressed, isNull);
    expect(find.byTooltip('Stop loading'), findsOneWidget);
    expect(key('online_load_line'), findsOneWidget);

    h.web.controller.canBack = true;
    h.web.navigate('https://m.youtube.com/', title: 'YouTube');
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Reload'), findsOneWidget);
    expect(key('online_load_line'), findsNothing);
    expect(find.text('m.youtube.com'), findsOneWidget);
    expect(button('online_back').onPressed, isNotNull);
    await tester.tap(key('online_back'));
    expect(h.web.controller.calls, contains('back'));
    await tester.tap(key('online_reload'));
    expect(h.web.controller.calls, contains('reload'));
  });

  testWidgets('the watch strip shows on watch, Shorts and live pages only', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    expect(key('online_watch_strip'), findsNothing);

    for (final url in [
      watchUrl,
      'https://m.youtube.com/shorts/aqz-KE-bpKQ',
      'https://m.youtube.com/live/jNQXAC9IVRw',
    ]) {
      h.web.navigate(url, title: 'Some video - YouTube');
      await tester.pumpAndSettle();
      expect(key('online_watch_strip'), findsOneWidget, reason: url);
      expect(key('online_copy_link'), findsOneWidget);
      expect(key('online_pip'), findsOneWidget);
      expect(key('online_background_chip'), findsOneWidget);
      expect(key('online_autopip_chip'), findsOneWidget);
      expect(find.text('Some video'), findsOneWidget, reason: 'address pill shows the title');
    }

    h.web.navigate('https://m.youtube.com/results?search_query=x');
    await tester.pumpAndSettle();
    expect(key('online_watch_strip'), findsNothing);
  });

  testWidgets('Download sends the clean link to Downloads and switches tab', (tester) async {
    PlatformInfo.debugIsAndroid = true; // the Downloads tab exists on phones only
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl, title: 'Never Gonna Give You Up - YouTube');
    await tester.pumpAndSettle();

    await tester.tap(key('online_download'));
    await tester.pumpAndSettle();

    final link = h.container.read(downloadLinkInboxProvider);
    expect(link, isNotNull);
    expect(link!.url, 'https://youtu.be/dQw4w9WgXcQ');
    expect(link.title, 'Never Gonna Give You Up');
    expect(link.inspect, isTrue);
    expect(find.text('Downloads page'), findsOneWidget);
    expect(find.text('Sent to Downloads'), findsOneWidget);
  });

  testWidgets('Download is not offered where there is no Downloads tab', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    expect(key('online_download'), findsNothing);
  });

  testWidgets('Copy link copies the canonical link and says so', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/shorts/aqz-KE-bpKQ?feature=share&si=x');
    await tester.pumpAndSettle();
    await tester.tap(key('online_copy_link'));
    await tester.pump();
    expect(clipboard, ['https://youtube.com/shorts/aqz-KE-bpKQ']);
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('on Android 13+ the system confirms the copy, so no snackbar', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    final h = await _pumpOnline(tester, androidSdk: 34);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    await tester.tap(key('online_copy_link'));
    await tester.pump();
    expect(clipboard, ['https://youtu.be/dQw4w9WgXcQ']);
    expect(find.text('Link copied'), findsNothing);
  });

  testWidgets('bridge messages with the right token reach the media session; forged ones do not', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pump();

    h.web.postMedia(token: 'ffffffffffffffffffffffffffffffff');
    h.web.postMedia(url: 'https://evil.example/watch?v=dQw4w9WgXcQ');
    expect(h.host.log, isEmpty);

    h.web.postMedia();
    expect(h.host.log, ['set']);
    expect(h.host.last!.title, 'Never Gonna Give You Up');
    expect(h.host.last!.artist, 'Rick Astley');

    // The notification's pause reaches the page as a bridge command.
    await h.host.active!.externalPause();
    expect(h.web.controller.commands.last, 'pause');
  });

  testWidgets('page settings are re-sent on every load', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pump();
    expect(h.web.controller.commands, containsAll(['setBackgroundPlay', 'setAutoPip']));
    expect(h.web.controller.scripts.where((s) => s.contains('"setBackgroundPlay",true')), isNotEmpty);
  });

  testWidgets('Background play and Auto PiP chips toggle the settings live', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.controller.scripts.clear();

    await tester.tap(key('online_background_chip'));
    await tester.pump();
    expect(h.container.read(onlineBackgroundPlayProvider), isFalse);
    expect(SettingsStore.instance.getBool(OnlineBackgroundPlayNotifier.prefKey, defaultValue: true), isFalse);
    expect(h.web.controller.calls, contains('bgAudio false'));
    expect(h.web.controller.scripts.last, contains('"setBackgroundPlay",false'));

    // The strip scrolls sideways (Save joined it): bring the chip into view.
    await tester.ensureVisible(key('online_autopip_chip'));
    await tester.pumpAndSettle();
    await tester.tap(key('online_autopip_chip'));
    await tester.pump();
    expect(h.container.read(onlineAutoPipProvider), isFalse);
    expect(h.web.controller.scripts.last, contains('"setAutoPip",false'));
  });

  testWidgets('offline: a friendly hint with Retry', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.events!.onMainFrameError(const OnlineLoadError(offline: true, description: 'net::ERR_NAME_NOT_RESOLVED'));
    await tester.pump();
    expect(find.text("You're offline"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text("You're offline"), findsNothing);
    expect(h.web.controller.calls, contains('load https://m.youtube.com/'));
  });

  testWidgets('toolbar collapses when the page scrolls down and comes back on scroll up', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    expect(key('online_address').hitTestable(), findsOneWidget);

    h.web.events!.onScrollY(100);
    h.web.events!.onScrollY(300);
    await tester.pumpAndSettle();
    expect(key('online_address').hitTestable(), findsNothing);

    h.web.events!.onScrollY(250);
    await tester.pumpAndSettle();
    expect(key('online_address').hitTestable(), findsOneWidget);
  });

  testWidgets('picture-in-picture: chrome hides and the page layout class follows', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.controller.scripts.clear();

    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    DeviceControls.handlePipChanged(true);
    await tester.pump();
    expect(DeviceControls.pipOwner.value, DeviceControls.pipOwnerOnline);
    expect(key('online_address'), findsNothing);
    expect(key('online_watch_strip'), findsNothing);
    expect(h.web.controller.scripts.last, contains('"setPipLayout",true'));

    DeviceControls.handlePipChanged(false);
    await tester.pump();
    expect(key('online_address'), findsOneWidget);
    expect(h.web.controller.scripts.last, contains('"setPipLayout",false'));
  });

  testWidgets('PiP, a small landscape window, and rotation keep the same WebView (the page survives)',
      (tester) async {
    addTearDown(tester.view.reset);
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_FakeWebSurface');
    final state = tester.state(surface);
    expect(h.web.mounts, 1);

    Future<void> check(String step) async {
      await tester.pump();
      expect(tester.state(surface), same(state), reason: step);
      expect(h.web.mounts, 1, reason: step);
    }

    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    // The PiP window: landscape and far shorter than 500 dp.
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(480, 270);
    DeviceControls.handlePipChanged(true);
    await check('enter PiP');
    expect(key('online_dock_seam'), findsNothing);
    DeviceControls.handlePipChanged(false);
    tester.view.physicalSize = const Size(720, 1480);
    await check('leave PiP');
    expect(key('online_dock_seam'), findsOneWidget);
    // Rotation into compact landscape and back.
    tester.view.physicalSize = const Size(1480, 720);
    await check('landscape');
    tester.view.physicalSize = const Size(720, 1480);
    await check('portrait');
    // PiP started from landscape, and back.
    tester.view.physicalSize = const Size(480, 270);
    DeviceControls.handlePipChanged(true);
    await check('PiP from landscape');
    DeviceControls.handlePipChanged(false);
    tester.view.physicalSize = const Size(1480, 720);
    await check('back');
    expect(h.web.controller.calls.where((c) => c.startsWith('load ')), isEmpty);
  });

  testWidgets('back on screen after a PiP whose "left" call never came: toolbar and page layout return',
      (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    DeviceControls.handlePipChanged(true);
    await tester.pump();
    expect(key('online_address'), findsNothing);
    h.web.controller.scripts.clear();

    // The floating window was closed in the background and the Activity
    // came back without onPictureInPictureModeChanged(false) reaching Dart.
    DeviceControls.handleAppResumed();
    await tester.pump();
    expect(DeviceControls.inPip.value, isFalse);
    expect(key('online_address'), findsOneWidget);
    expect(key('online_dock_seam'), findsOneWidget);
    expect(h.web.controller.scripts.last, contains('"setPipLayout",false'));
  });

  testWidgets('PiP owned by the video player leaves the page layout alone', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.controller.scripts.clear();
    await DeviceControls.setPipEligible(true); // the video player's claim
    DeviceControls.handlePipChanged(true);
    await tester.pump();
    expect(h.web.controller.scripts.where((s) => s.contains('setPipLayout')), isEmpty);
    DeviceControls.handlePipChanged(false);
    await tester.pump();
  });

  testWidgets('address pill: our search sheet, submitted inside the page (the mini player survives)', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    h.web.controller.calls.clear();

    await tester.tap(key('online_address'));
    await tester.pumpAndSettle();
    expect(key('online_search_field'), findsOneWidget, reason: 'always our own sheet');
    // What is typed is what is searched: no autocorrect, curly quotes or long dashes.
    final field = tester.widget<TextField>(key('online_search_field'));
    expect(field.autocorrect, isFalse);
    expect(field.smartQuotesType, SmartQuotesType.disabled);
    expect(field.smartDashesType, SmartDashesType.disabled);
    await tester.enterText(key('online_search_field'), 'lofi beats');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.web.controller.commands.last, 'search');
    expect(h.web.controller.scripts.last, contains('b.command("search","lofi beats")'));
    expect(h.web.controller.calls.where((c) => c.startsWith('load')), isEmpty, reason: 'no page load');
  });

  testWidgets('address pill: a page without a search field loads the results page instead', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    h.web.controller.scriptResult = false;
    await tester.tap(key('online_address'));
    await tester.pumpAndSettle();
    await tester.enterText(key('online_search_field'), 'lofi beats');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.web.controller.calls.last, 'load https://m.youtube.com/results?search_query=lofi+beats');
  });

  testWidgets('address pill: a typed YouTube link opens it; another site is searched as words', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    h.web.controller.scripts.clear();
    await tester.tap(key('online_address'));
    await tester.pumpAndSettle();
    await tester.enterText(key('online_search_field'), 'youtu.be/dQw4w9WgXcQ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.web.controller.calls.last, 'load https://youtu.be/dQw4w9WgXcQ');
    expect(h.web.controller.scripts.where((s) => s.contains('"search"')), isEmpty);

    h.web.controller.scriptResult = false;
    await tester.tap(key('online_address'));
    await tester.pumpAndSettle();
    await tester.enterText(key('online_search_field'), 'https://example.com/x');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.web.controller.calls.last, startsWith('load https://m.youtube.com/results?search_query=https'));
  });

  testWidgets('menu: switches and Clear site data with a confirm', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();

    await tester.tap(key('online_menu'));
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);
    expect(find.text('Auto picture-in-picture'), findsOneWidget);
    await tester.tap(key('online_menu_background'));
    await tester.pump();
    expect(h.container.read(onlineBackgroundPlayProvider), isFalse);

    await tester.tap(find.text('Clear site data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear YouTube data?'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(h.cleared, 1);
    expect(find.text('YouTube data cleared'), findsOneWidget);
  });

  testWidgets('system back walks back through the page history first', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.controller.canBack = true;
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    expect(h.web.controller.calls, contains('back'));
  });

  testWidgets('a renderer crash builds a fresh WebView on the same page', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    expect(h.host.log, ['set']);
    final before = h.web.mounts;

    h.web.events!.onRendererGone();
    await tester.pump();
    expect(h.web.mounts, before + 1);
    expect(h.web.config!.initialUrl.toString(), watchUrl);
    expect(h.host.log.last, 'clear', reason: 'the dead page lets go of the notification');
  });

  testWidgets('Block ads: on by default, in the script and the WebView from the start', (tester) async {
    // Nothing stored, as on a new install (setUp stores "on" for the other tests).
    await SettingsStore.instance.remove(OnlineBlockAdsNotifier.prefKey);
    final h = await _pumpOnline(tester);
    expect(h.container.read(onlineBlockAdsProvider), isTrue);
    expect(h.web.config!.blockAds, isTrue);
    expect(h.web.config!.bridgeScript, contains("var BLOCK_ADS = 'on' !== 'off';"));
    expect(h.web.config!.bridgeScript, isNot(contains('__MEDIAHUB_')));
  });

  testWidgets('a network that breaks the secure connection: says so, with Retry', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.events!.onMainFrameError(onlineSecureConnectionBlockedError);
    await tester.pump();
    expect(key('online_error'), findsOneWidget);
    expect(find.text("Can't connect securely"), findsOneWidget);
    expect(
      find.text('This network is blocking a secure connection to YouTube. Try another Wi-Fi or mobile data.'),
      findsOneWidget,
    );
    expect(find.text("You're offline"), findsNothing);
    expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);
    expect(key('online_load_line'), findsNothing, reason: 'no longer loading');
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(key('online_error'), findsNothing);
    expect(h.web.controller.calls, contains('load https://m.youtube.com/'));
  });

  testWidgets('Block ads from the menu: the same page opens again in a fresh WebView with the new choice',
      (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    expect(h.host.log, ['set']);
    final before = h.web.mounts;

    await tester.tap(key('online_menu'));
    await tester.pumpAndSettle();
    expect(find.text('Block ads'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(key('online_menu_block_ads')).value, isTrue);
    await tester.tap(key('online_menu_block_ads'));
    await tester.pump();
    expect(h.container.read(onlineBlockAdsProvider), isFalse);
    expect(h.web.mounts, before + 1, reason: 'a fresh WebView: the page script is fixed at its start');
    expect(h.web.config!.blockAds, isFalse);
    expect(h.web.config!.bridgeScript, contains("var BLOCK_ADS = 'off' !== 'off';"));
    expect(h.web.config!.initialUrl.toString(), watchUrl, reason: 'the same page');
    expect(h.host.log.last, 'clear', reason: 'the old page lets go of the notification');
    expect(tester.widget<SwitchListTile>(key('online_menu_block_ads')).value, isFalse);

    // And back on.
    await tester.tap(key('online_menu_block_ads'));
    await tester.pump();
    expect(h.web.mounts, before + 2);
    expect(h.web.config!.blockAds, isTrue);
    expect(h.web.config!.bridgeScript, contains("var BLOCK_ADS = 'on' !== 'off';"));
  });

  testWidgets('Block ads changed in Settings while the tab is open: the page opens again', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/results?search_query=lofi');
    await tester.pumpAndSettle();
    final before = h.web.mounts;
    h.container.read(onlineBlockAdsProvider.notifier).set(false);
    await tester.pump();
    expect(h.web.mounts, before + 1);
    expect(h.web.config!.initialUrl.toString(), 'https://m.youtube.com/results?search_query=lofi');
    expect(SettingsStore.instance.getBool(OnlineBlockAdsNotifier.prefKey, defaultValue: true), isFalse);
    // The same value again changes nothing.
    h.container.read(onlineBlockAdsProvider.notifier).set(false);
    await tester.pump();
    expect(h.web.mounts, before + 1);
  });

  testWidgets('a new document ends the old video: the notification lets go', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pump();
    h.web.postMedia();
    expect(h.host.active, isNotNull);
    expect(h.host.last!.playing, isTrue);

    // A full document load (our search sheet, Clear site data, a reload or
    // YouTube's own). The new bridge says "ready"; a results page has only
    // muted previews, so no media message follows.
    h.web.controller.scripts.clear();
    const results = 'https://m.youtube.com/results?search_query=x';
    h.web.events!.onLoadStart(Uri.parse(results));
    h.web.events!.onUrlChanged(Uri.parse(results));
    h.web.events!.onBridgeMessage([
      {'t': h.web.token, 'k': 'ready', 'u': results},
    ]);
    h.web.events!.onLoadStop(Uri.parse(results));
    await tester.pump();

    expect(h.web.controller.commands, contains('requestState'), reason: 'the new page is asked what plays');
    expect(h.host.last!.playing, isFalse, reason: 'the notification stops saying "playing"');
    await tester.pump(const Duration(seconds: 16));
    expect(h.host.active, isNull, reason: 'handed back to local music');
  });

  testWidgets('Download takes the media title only from the video on screen', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl, title: 'Never Gonna Give You Up - YouTube');
    await tester.pump();
    h.web.postMedia(title: 'Video A');

    // An in-page move to video B that has not reported yet.
    h.web.events!.onUrlChanged(Uri.parse('https://m.youtube.com/shorts/aqz-KE-bpKQ'));
    h.web.events!.onTitleChanged('Video B - YouTube');
    await tester.pumpAndSettle();
    await tester.tap(key('online_download'));
    await tester.pumpAndSettle();

    final link = h.container.read(downloadLinkInboxProvider)!;
    expect(link.url, 'https://youtube.com/shorts/aqz-KE-bpKQ');
    expect(link.title, 'Video B', reason: 'not the title of the previous video');
  });

  testWidgets('bridge messages are dropped while the main frame is another web site', (tester) async {
    final h = await _pumpOnline(tester);
    // A page that slipped past the navigation policy (a POST, say) claims a
    // YouTube address in its message: the WebView knows better.
    h.web.navigate('https://evil.example/landing');
    await tester.pump();
    h.web.postMedia();
    expect(h.host.log, isEmpty);

    h.web.navigate(watchUrl);
    await tester.pump();
    h.web.postMedia();
    expect(h.host.log, ['set']);
  });

  group('toolbar colours follow the theme (DESIGN.md 7.13)', () {
    for (final palette in [AppPalette.dark, AppPalette.light]) {
      final name = palette.isDark ? 'dark' : 'light';
      testWidgets('$name: canvas, bars, address pill and icons', (tester) async {
        final h = await _pumpOnline(tester, theme: AppTheme.build(palette));
        h.web.navigate(watchUrl, title: 'Never Gonna Give You Up - YouTube');
        await tester.pumpAndSettle();

        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .descendant(of: find.byType(OnlineScreen), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
              .first,
        );
        expect(region.value, AppTheme.barsFor(palette));

        final Color toolbarFill;
        if (palette.isDark) {
          final box = tester.widget<DecoratedBox>(key('online_toolbar'));
          toolbarFill = (box.decoration as BoxDecoration).color!;
          expect(toolbarFill, palette.background);
        } else {
          expect(tester.widget(key('online_toolbar')), isA<GlassContainer>());
          toolbarFill = Color.alphaBlend(palette.glass, palette.background);
        }

        // Back, forward, reload and the menu stand out from the toolbar.
        final menuIcon = tester.widget<RichText>(
          find.descendant(of: key('online_menu'), matching: find.byType(RichText)),
        );
        expect(_contrast(menuIcon.text.style!.color!, toolbarFill), greaterThanOrEqualTo(3.0));

        final pill = tester.widget<Material>(key('online_address'));
        expect(pill.color, palette.isDark ? palette.surfaceElevated : Colors.white);
        final side = (pill.shape! as StadiumBorder).side;
        expect(side, palette.isDark ? BorderSide.none : BorderSide(color: palette.outline));
      });

      testWidgets('$name: Clear site data is in the theme error colour', (tester) async {
        final h = await _pumpOnline(tester, theme: AppTheme.build(palette));
        h.web.navigate('https://m.youtube.com/');
        await tester.pumpAndSettle();
        await tester.tap(key('online_menu'));
        await tester.pumpAndSettle();
        final label = tester.widget<Text>(find.text('Clear site data'));
        expect(label.style!.color, palette.error);
        expect(_contrast(palette.error, palette.surface), greaterThanOrEqualTo(4.5));
        await tester.tap(key('online_menu_clear'));
        await tester.pumpAndSettle();
        final clear = tester.widget<TextButton>(key('online_clear_confirm'));
        expect(clear.style!.foregroundColor!.resolve({}), palette.error);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.cleared, 0);
      });
    }
  });

  testWidgets('watch strip: Volt Download and full 48 dp tap targets', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    expect(tester.widget(key('online_download')), isA<VoltButton>());
    expect(tester.getSize(key('online_watch_strip')).height, 52);
    final download = find.descendant(of: key('online_download'), matching: find.byType(FilledButton));
    expect(tester.getSize(download).height, greaterThanOrEqualTo(48));
    final strip = find.descendant(of: key('online_watch_strip'), matching: find.byType(Scrollable));
    for (final k in ['online_save', 'online_copy_link', 'online_pip', 'online_background_chip', 'online_autopip_chip']) {
      await tester.scrollUntilVisible(key(k), 80, scrollable: strip);
      expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48), reason: k);
    }
  });

  // --- fullscreen (ONL-3, ONL-4) ----------------------------------------------

  testWidgets('a fullscreen video turns the phone sideways; leaving frees it again', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia(); // 1280 x 720
    h.web.events!.onFullscreenChanged(true);
    await tester.pump();
    expect(h.chrome, [(true, true)]);
    expect(key('online_address'), findsNothing, reason: 'no chrome over a fullscreen video');
    h.web.events!.onFullscreenChanged(false);
    await tester.pump();
    expect(h.chrome, [(true, true), (false, false)]);
    expect(key('online_address'), findsOneWidget);
  });

  testWidgets('system Back in fullscreen leaves fullscreen and stops there', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.controller.canBack = true;
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.events!.onFullscreenChanged(true);
    await tester.pump();
    h.web.controller.calls.clear();

    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(handled, isTrue);
    expect(h.web.controller.commands.last, 'exitFullscreen');
    expect(h.web.controller.calls, isNot(contains('back')), reason: 'the page history stays where it is');
    expect(find.byType(OnlineScreen), findsOneWidget);
  });

  testWidgets('Back is never stuck when the page cannot leave fullscreen', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.events!.onFullscreenChanged(true);
    await tester.pump();
    h.web.controller.scriptResult = false;
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(key('online_address'), findsOneWidget);
    expect(h.chrome.last, (false, false));
  });

  testWidgets('a portrait video stays upright in fullscreen', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/shorts/aqz-KE-bpKQ');
    await tester.pumpAndSettle();
    h.web.events!.onBridgeMessage([
      {
        't': h.web.token, 'k': 'media', 'e': 'play', 'u': 'https://m.youtube.com/shorts/aqz-KE-bpKQ',
        's': 'playing', 'p': 1, 'd': 30, 'r': 1, 'ti': 'Short', 'ar': 'C', 'aw': '', 'n': false,
        'vw': 720, 'vh': 1280,
      }
    ]);
    h.web.events!.onFullscreenChanged(true);
    await tester.pump();
    expect(h.chrome, [(true, false)]);
  });

  // --- iOS parity: fullscreen only on the page's word ---------------------------

  void pageFullscreen(_Harness h, bool on) => h.web.events!.onBridgeMessage([
        {'t': h.web.token, 'k': 'fs', 'on': on, 'u': 'https://m.youtube.com/watch?v=dQw4w9WgXcQ'}
      ]);

  testWidgets("iOS: the plugin's fullscreen event alone never hides the toolbar or turns the app", (tester) async {
    PlatformInfo.debugIsIOS = true;
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    // Any app window appearing reads as "fullscreen" to the iOS plugin.
    h.web.events!.onFullscreenChanged(true);
    await tester.pump();
    expect(h.chrome, isEmpty, reason: 'no landscape lock, no hidden status bar');
    expect(key('online_address'), findsOneWidget, reason: 'the toolbar stays');

    // The page itself says a video went fullscreen: now it is real.
    pageFullscreen(h, true);
    await tester.pump();
    expect(h.chrome, [(true, true)]);
    expect(key('online_address'), findsNothing);

    // The plugin's exit (another window going away) does not end it either.
    h.web.events!.onFullscreenChanged(false);
    await tester.pump();
    expect(h.chrome, [(true, true)]);
    pageFullscreen(h, false);
    await tester.pump();
    expect(h.chrome, [(true, true), (false, false)]);
    expect(key('online_address'), findsOneWidget);
  });

  testWidgets('iOS: a new document ends a fullscreen the page had reported', (tester) async {
    PlatformInfo.debugIsIOS = true;
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    pageFullscreen(h, true);
    await tester.pump();
    expect(key('online_address'), findsNothing);
    h.web.events!.onBridgeMessage([
      {'t': h.web.token, 'k': 'ready', 'u': 'https://m.youtube.com/'}
    ]);
    await tester.pump();
    expect(h.chrome.last, (false, false));
    expect(key('online_address'), findsOneWidget);
  });

  testWidgets("Android: fullscreen follows the WebView's own events; the page's report changes nothing", (tester) async {
    PlatformInfo.debugIsAndroid = true;
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    pageFullscreen(h, true);
    await tester.pump();
    expect(h.chrome, isEmpty);
    expect(key('online_address'), findsOneWidget);
    h.web.events!.onFullscreenChanged(true);
    await tester.pump();
    expect(h.chrome, [(true, true)]);
  });

  testWidgets('iOS: mobile data off for MediaHub says so, with Retry', (tester) async {
    PlatformInfo.debugIsIOS = true;
    final h = await _pumpOnline(tester);
    h.web.events!.onMainFrameError(const OnlineLoadError(offline: true, description: 'x', mobileDataOff: true));
    await tester.pump();
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Mobile data is off for MediaHub. Turn it on in Settings, or use Wi-Fi.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  for (final ios in [true, false]) {
    testWidgets('Clear YouTube data: the dialog says what goes on ${ios ? 'an iPhone' : 'Android'}', (tester) async {
      if (ios) {
        PlatformInfo.debugIsIOS = true;
      } else {
        PlatformInfo.debugIsAndroid = true;
      }
      final h = await _pumpOnline(tester);
      h.web.navigate('https://m.youtube.com/');
      await tester.pumpAndSettle();
      await tester.tap(key('online_menu'));
      await tester.pumpAndSettle();
      // The phone's menu has more rows (downloads), so Clear may be below the fold.
      await tester.ensureVisible(key('online_menu_clear'));
      await tester.pumpAndSettle();
      await tester.tap(key('online_menu_clear'));
      await tester.pumpAndSettle();
      expect(
        find.text(ios
            ? "Signs you out and forgets YouTube's cookies, cache and saved site data on this iPhone. "
                'Your downloads and library stay.'
            : "Signs you out and forgets YouTube's cookies, cache and site settings on this phone. "
                'Your downloads and library stay.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.cleared, 0);
    });
  }

  // --- signing in to YouTube --------------------------------------------------

  testWidgets('menu: Sign in to YouTube opens Google sign-in in the tab, back to this page after', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    await tester.tap(key('online_menu'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to YouTube'), findsOneWidget);
    await tester.tap(key('online_menu_sign_in'));
    await tester.pumpAndSettle();

    final load = h.web.controller.calls.last;
    expect(load, startsWith('load https://accounts.google.com/ServiceLogin?'));
    final signIn = Uri.parse(load.substring('load '.length));
    expect(signIn.queryParameters['service'], 'youtube');
    final back = Uri.parse(signIn.queryParameters['continue']!);
    expect(back.host, 'www.youtube.com');
    expect(back.queryParameters['next'], watchUrl);
    expect(h.opened, isEmpty, reason: 'not the browser');
    expect(find.text('Sign in to YouTube'), findsNothing, reason: 'the menu closed');
  });

  testWidgets("on Google's sign-in pages the bridge is off: no commands go in, no messages count", (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    expect(h.host.log, ['set']);

    for (final page in [
      'https://accounts.google.com/v3/signin/identifier?flowName=GlifWebSignIn',
      'https://accounts.youtube.com/accounts/SetSID?ssdc=1',
    ]) {
      h.web.controller.scripts.clear();
      h.web.navigate(page, title: 'Sign in - Google Accounts');
      await tester.pumpAndSettle();
      expect(h.web.controller.scripts, isEmpty, reason: 'nothing is run in $page');
      // Even with the right token and a YouTube address in it.
      final before = List.of(h.host.log);
      h.web.postMedia();
      expect(h.host.log, before, reason: page);
      // Our own search falls back to YouTube's results page.
      await tester.tap(key('online_address'));
      await tester.pumpAndSettle();
      await tester.enterText(key('online_search_field'), 'lofi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(h.web.controller.scripts, isEmpty);
      expect(h.web.controller.calls.last, 'load https://m.youtube.com/results?search_query=lofi');
      expect(find.byKey(const ValueKey('online_watch_strip')), findsNothing);
    }

    // Back on YouTube, all is as before.
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    expect(h.web.controller.commands, containsAll(['setBackgroundPlay', 'requestState']));
  });

  testWidgets('the menu with Sign in still shows every row, Clear site data included, on a 360x740 phone',
      (tester) async {
    PlatformInfo.debugIsAndroid = true; // Open Downloads too
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    await tester.tap(key('online_menu'));
    await tester.pumpAndSettle();
    for (final row in ['Reload', 'YouTube Music', 'Sign in to YouTube', 'Open Downloads', 'Clear site data']) {
      expect(find.text(row).hitTestable(), findsOneWidget, reason: row);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sign-in page shows its own title in the address pill', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://accounts.google.com/v3/signin/identifier', title: 'Sign in - Google Accounts');
    await tester.pumpAndSettle();
    expect(find.text('Sign in - Google Accounts'), findsOneWidget);
    expect(find.byType(EmptyHint), findsNothing);
  });

  // --- YouTube Music, Save, open requests (ONL-12) ------------------------------

  testWidgets('menu: YouTube Music opens its web player in the tab', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    await tester.tap(key('online_menu'));
    await tester.pumpAndSettle();
    await tester.tap(key('online_menu_music'));
    await tester.pumpAndSettle();
    expect(h.web.controller.calls.last, 'load https://music.youtube.com/');
  });

  testWidgets('Save opens the media sheet for the video as an online item', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl, title: 'Never Gonna Give You Up - YouTube');
    await tester.pumpAndSettle();
    h.web.postMedia(title: 'Never Gonna Give You Up', artist: 'Rick Astley');
    await tester.tap(key('online_save'));
    await tester.pump();
    expect(h.saved, hasLength(1));
    final item = h.saved.single;
    expect(item.id, 'yt_dQw4w9WgXcQ');
    expect(item.source, 'online');
    expect(item.uri, 'https://youtu.be/dQw4w9WgXcQ', reason: 'the clean link, never a stream URL');
    expect(item.title, 'Never Gonna Give You Up');
    expect(item.artist, 'Rick Astley');
    expect(item.artworkPath, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(item.durationMs, 213000);
  });

  testWidgets('another screen can open a page in the tab; only YouTube pages', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();
    final notifier = h.container.read(onlineOpenRequestProvider.notifier);
    expect(notifier.open(Uri.parse('https://evil.example/watch?v=dQw4w9WgXcQ')), isFalse);
    expect(notifier.open(Uri.parse('http://m.youtube.com/watch?v=aqz-KE-bpKQ')), isTrue);
    await tester.pump();
    await tester.pump();
    expect(h.web.controller.calls.last, 'load https://m.youtube.com/watch?v=aqz-KE-bpKQ');
    expect(h.container.read(onlineOpenRequestProvider), isNull, reason: 'taken');
  });

  testWidgets('a page asked for before the tab was built is where it starts', (tester) async {
    final h = await _pumpOnline(tester, openRequest: Uri.parse('https://music.youtube.com/watch?v=jNQXAC9IVRw'));
    expect(h.web.config!.initialUrl.toString(), 'https://music.youtube.com/watch?v=jNQXAC9IVRw');
    await tester.pump();
    expect(h.container.read(onlineOpenRequestProvider), isNull);
  });

  // --- background play and iOS picture-in-picture (ONL-2, ONL-7) ---------------

  testWidgets('the session follows the Background play setting', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    final session = h.container.read(onlineMediaSessionProvider);
    expect(session.backgroundPlay, isTrue);
    await tester.tap(key('online_background_chip'));
    await tester.pump();
    expect(session.backgroundPlay, isFalse);
  });

  testWidgets('iOS: Control Center started PiP but the app never left: it closes on the way back', (tester) async {
    PlatformInfo.debugIsIOS = true;
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(h.web.controller.commands.last, 'enterPip');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.web.controller.commands, contains('exitPip'));
  });

  testWidgets('iOS: a PiP that carried the video out of the app stays open on return', (tester) async {
    PlatformInfo.debugIsIOS = true;
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    expect(h.web.controller.commands.where((c) => c == 'enterPip'), hasLength(1), reason: 'not again on the way back');
    expect(h.web.controller.commands, isNot(contains('exitPip')));
  });

  testWidgets('picture-in-picture button: icon only, no "Entering" message', (tester) async {
    PlatformInfo.debugIsIOS = true;
    final h = await _pumpOnline(tester);
    h.web.navigate(watchUrl);
    await tester.pumpAndSettle();
    h.web.postMedia();
    await tester.pump();
    expect(find.descendant(of: key('online_pip'), matching: find.byType(Text)), findsNothing);
    expect(find.byTooltip('Picture-in-picture'), findsOneWidget);
    await tester.tap(key('online_pip'));
    await tester.pump();
    expect(h.web.controller.commands.last, 'enterPip');
    expect(find.textContaining('Entering picture-in-picture'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the load-error panel fits the picture-in-picture window', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(() => DeviceControls.handlePipChanged(false));
    final h = await _pumpOnline(tester);
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    DeviceControls.handlePipChanged(true);
    // The window shrinks to the picture-in-picture size (240 x 135 dp).
    tester.view.physicalSize = const Size(240, 135);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
    expect(tester.takeException(), isNull);
    h.web.events!.onMainFrameError(onlineSecureConnectionBlockedError);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(key('online_error_compact'), findsOneWidget);
    expect(key('online_error'), findsNothing);
    expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);
    // Back to the full window: the full panel, Retry included.
    tester.view.reset();
    DeviceControls.handlePipChanged(false);
    await tester.pump();
    expect(key('online_error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // Real fonts (the test font draws every glyph as a 1 em square, far wider
  // than the app's): last in the file, so the tests above keep the test font.
  group('watch strip with the app fonts', () {
    setUpAll(loadAppFonts);

    for (final light in [false, true]) {
      testWidgets('watch strip at 360 dp: Picture-in-picture and Background play are in full view '
          '(${light ? 'paper' : 'ink'})', (tester) async {
        PlatformInfo.debugIsAndroid = true;
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final h = await _pumpOnline(tester, theme: light ? AppTheme.lightTheme : AppTheme.darkTheme);
        h.web.navigate(watchUrl);
        await tester.pumpAndSettle();
        final strip = tester.getRect(key('online_watch_strip'));
        // The last 24 dp of the strip fade out (the scroll hint).
        final clear = strip.right - 24;
        for (final k in ['online_download', 'online_pip', 'online_background_chip']) {
          final r = tester.getRect(key(k));
          expect(r.left, greaterThanOrEqualTo(strip.left), reason: k);
          expect(r.right, lessThanOrEqualTo(clear), reason: '$k ends at ${r.right}, the fade starts at $clear');
        }
        // Save and Copy link are named for screen readers and in a tooltip.
        expect(find.bySemanticsLabel('Save to Favourites or a playlist'), findsOneWidget);
        expect(find.byTooltip('Copy link', skipOffstage: false), findsOneWidget);
        expect(find.byTooltip('Picture-in-picture'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);

}
