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
import 'package:mediahub/features/downloads/download_link_inbox.dart';
import 'package:mediahub/features/online/online_media_session.dart';
import 'package:mediahub/features/online/online_screen.dart';
import 'package:mediahub/features/online/online_settings.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

import 'online_fakes.dart';

const watchUrl = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ&si=tracking&pp=x';

class _Harness {
  _Harness(this.web, this.host, this.container, this.router);
  final FakeOnlineWebView web;
  final FakeExternalHost host;
  final ProviderContainer container;
  final GoRouter router;
  final List<Uri> opened = [];
  int cleared = 0;
}

Future<_Harness> _pumpOnline(WidgetTester tester, {int? androidSdk, ThemeData? theme}) async {
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
    ],
  );
  h = _Harness(web, host, container, router);
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

  testWidgets('address pill: the page search box first, else our own search', (tester) async {
    final h = await _pumpOnline(tester);
    h.web.navigate('https://m.youtube.com/');
    await tester.pumpAndSettle();

    await tester.tap(key('online_address'));
    await tester.pumpAndSettle();
    expect(h.web.controller.commands.last, 'focusSearch');
    expect(key('online_search_field'), findsNothing, reason: 'the page focused its own box');

    h.web.controller.scriptResult = false;
    await tester.tap(key('online_address'));
    await tester.pumpAndSettle();
    await tester.enterText(key('online_search_field'), 'lofi beats');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(h.web.controller.calls.last, 'load https://m.youtube.com/results?search_query=lofi+beats');
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
    for (final k in ['online_copy_link', 'online_pip', 'online_background_chip', 'online_autopip_chip']) {
      expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48), reason: k);
    }
    final download = find.descendant(of: key('online_download'), matching: find.byType(FilledButton));
    expect(tester.getSize(download).height, greaterThanOrEqualTo(48));
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
