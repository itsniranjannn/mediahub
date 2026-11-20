// The Online WebView: what lets a YouTube sign-in work (the user agent and
// settings), and its iOS behaviour (the iPhone app has never been built):
// new-window requests, the error screen's codes, the settings and Clear
// YouTube data. A fake WebView platform stands in for the plugin, so the real
// widget's callbacks and settings can be checked on Windows.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/features/online/online_ad_block.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:mediahub/features/online/youtube_urls.dart';

/// Every plugin call the code under test made, in order.
final List<String> _log = [];

class _FakeWebPlatform extends InAppWebViewPlatform {
  PlatformInAppWebViewWidgetCreationParams? params;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(PlatformInAppWebViewWidgetCreationParams params) {
    this.params = params;
    return _FakeWidget(params);
  }

  @override
  PlatformCookieManager createPlatformCookieManager(PlatformCookieManagerCreationParams params) =>
      _FakeCookies(params);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(PlatformWebStorageManagerCreationParams params) =>
      _FakeStorage(params);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() => _FakeController();
}

class _FakeWidget extends PlatformInAppWebViewWidget {
  _FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: ValueKey('fake_platform_webview'));

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) => throw UnimplementedError();

  @override
  void dispose() {}
}

class _FakeCookies extends PlatformCookieManager {
  _FakeCookies(super.params) : super.implementation();

  @override
  Future<bool> deleteAllCookies() async {
    _log.add('deleteAllCookies');
    return true;
  }
}

class _FakeStorage extends PlatformWebStorageManager {
  _FakeStorage(super.params) : super.implementation();

  Set<WebsiteDataType>? removedTypes;
  DateTime? removedSince;

  @override
  Future<void> deleteAllData() async {
    // Like the iOS plugin, which has no deleteAllData.
    if (PlatformInfo.isIOS) throw UnimplementedError('deleteAllData is not implemented on the current platform');
    _log.add('deleteAllData');
  }

  @override
  Future<void> removeDataModifiedSince({required Set<WebsiteDataType> dataTypes, required DateTime date}) async {
    _log.add('removeDataModifiedSince');
    removedTypes = dataTypes;
    removedSince = date;
  }
}

/// What the WebView says its own user agent is (real ones, from a Samsung
/// Galaxy S23 on Android 13 and an iPhone on iOS 17.4.1).
const _androidWebViewUa = 'Mozilla/5.0 (Linux; Android 13; SM-S911B Build/TP1A.220624.014; wv) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36';
const _androidChromeUa = 'Mozilla/5.0 (Linux; Android 13; SM-S911B) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.135 Mobile Safari/537.36';
const _iosWebViewUa = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const _iosSafariUa = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

/// The next answer of the plugin's getDefaultUserAgent.
Future<String> Function() _defaultUserAgent = () async => _androidWebViewUa;

class _FakeController extends PlatformInAppWebViewController {
  _FakeController() : super.implementation(const PlatformInAppWebViewControllerCreationParams(id: 0));

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async => _log.add('clearAllCache');

  @override
  Future<String> getDefaultUserAgent() {
    _log.add('getDefaultUserAgent');
    return _defaultUserAgent();
  }
}

/// What the real web view told the screen.
class _Events {
  final List<Uri> opened = [];
  final List<OnlineLoadError> errors = [];
  final List<bool> fullscreen = [];

  OnlineWebEvents get events => OnlineWebEvents(
        onCreated: (_) {},
        onUrlChanged: (_) {},
        onTitleChanged: (_) {},
        onProgress: (_) {},
        onLoadStart: (_) {},
        onLoadStop: (_) {},
        onMainFrameError: errors.add,
        onScrollY: (_) {},
        onBridgeMessage: (_) {},
        openExternally: (uri) async => opened.add(uri),
        onFullscreenChanged: fullscreen.add,
        onRendererGone: () {},
      );
}

final _platform = _FakeWebPlatform();

CreateWindowAction _window(String url, NavigationType? type) => CreateWindowAction(
      windowId: 1,
      request: URLRequest(url: WebUri(url)),
      // A target="_blank" link has no target frame yet: the plugin says false.
      isForMainFrame: false,
      navigationType: type,
    );

/// Pumps the real web view widget; it waits for the user agent before the
/// platform view is made, so a frame or two pass before [_platform] has it.
Future<_Events> _pumpWebView(WidgetTester tester, {bool blockAds = true}) async {
  final events = _Events();
  _platform.params = null;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => buildInAppOnlineWebView(
        context,
        OnlineWebViewConfig(
          bridgeScript: '/* bridge */',
          backgroundPlay: true,
          initialUrl: Uri.parse(youTubeHomeUrl),
          blockAds: blockAds,
        ),
        events.events,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return events;
}

/// A controller to hand the plugin's callbacks (they never use it).
InAppWebViewController _controller() => InAppWebViewController.fromPlatform(platform: _FakeController());

void main() {
  setUpAll(() {
    DiagnosticsService.enableDebounce = false;
    InAppWebViewPlatform.instance = _platform;
  });

  setUp(() {
    _log.clear();
    _defaultUserAgent = () async => _androidWebViewUa;
    resetOnlineUserAgentForTests();
  });

  tearDown(() {
    PlatformInfo.resetForTests();
    resetOnlineUserAgentForTests();
  });

  group('a page asks for a new window (iOS: target="_blank" links)', () {
    test('an outside link the user tapped opens in the browser; the answer lets the plugin drop its window', () async {
      final opened = <Uri>[];
      final handled = await handleOnlineNewWindow(
        _window('https://example.com/shop', NavigationType.LINK_ACTIVATED),
        openExternally: (uri) async => opened.add(uri),
      );
      expect(opened, [Uri.parse('https://example.com/shop')]);
      expect(handled, isFalse, reason: 'the in-place copy is then cancelled: not a tap, so never opened twice');
    });

    test('an outside link no one tapped (a script, a redirect) opens nothing', () async {
      final opened = <Uri>[];
      for (final type in [NavigationType.OTHER, null]) {
        await handleOnlineNewWindow(_window('https://ads.example/landing', type), openExternally: (u) async => opened.add(u));
      }
      expect(opened, isEmpty);
    });

    test('a YouTube link loads in place; app schemes go nowhere', () async {
      final opened = <Uri>[];
      for (final url in [
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'http://youtube.com/channel/UC1',
        'vnd.youtube://dQw4w9WgXcQ',
        'intent://x#Intent;end',
      ]) {
        final handled = await handleOnlineNewWindow(
          _window(url, NavigationType.LINK_ACTIVATED),
          openExternally: (u) async => opened.add(u),
        );
        expect(handled, isFalse, reason: url);
      }
      expect(opened, isEmpty);
    });

    test('the decision: main-frame rules, and outside links only for a tap', () {
      expect(decideOnlineNewWindow(Uri.parse('https://m.youtube.com/'), userTapped: false).kind,
          OnlineNavigationKind.allow);
      expect(decideOnlineNewWindow(Uri.parse('https://example.com/'), userTapped: true).kind,
          OnlineNavigationKind.openExternally);
      expect(decideOnlineNewWindow(Uri.parse('https://example.com/'), userTapped: false).kind,
          OnlineNavigationKind.cancel);
      expect(decideOnlineNewWindow(Uri.parse('market://details?id=x'), userTapped: true).kind,
          OnlineNavigationKind.cancel);
      expect(decideOnlineNewWindow(null, userTapped: true).kind, OnlineNavigationKind.cancel);
    });

    testWidgets('iOS: the real web view handles new windows and opens a tapped outside link', (tester) async {
      PlatformInfo.debugIsIOS = true;
      final events = await _pumpWebView(tester);
      final onCreateWindow = _platform.params!.onCreateWindow;
      expect(onCreateWindow, isNotNull);
      final handled = await onCreateWindow!(
        _controller(),
        _window('https://example.com/a', NavigationType.LINK_ACTIVATED),
      );
      expect(handled, isFalse);
      expect(events.opened, [Uri.parse('https://example.com/a')]);
    });

    testWidgets('Android: no new-window handler (its WebView loads those links in place)', (tester) async {
      PlatformInfo.debugIsAndroid = true;
      await _pumpWebView(tester);
      expect(_platform.params!.onCreateWindow, isNull);
    });
  });

  group('the error screen', () {
    const interrupted = 'domain=WebKitErrorDomain, code=102, Frame load interrupted';

    test("iOS: WebKit's 'Frame load interrupted' (102) is a normal cancel, never an error", () {
      expect(onlineLoadErrorFor(WebResourceErrorType.UNKNOWN, interrupted, isIOS: true), isNull);
      // Other WebKit codes still show.
      final other = onlineLoadErrorFor(
        WebResourceErrorType.UNKNOWN,
        'domain=WebKitErrorDomain, code=101, The URL can’t be shown',
        isIOS: true,
      );
      expect(other, isNotNull);
      expect(other!.offline, isFalse);
      expect(
        onlineLoadErrorFor(WebResourceErrorType.UNKNOWN, 'domain=WebKitErrorDomain, code=1020, x', isIOS: true),
        isNotNull,
      );
    });

    test("iOS: no data roaming, a call on the line and mobile data off for the app are 'offline'", () {
      for (final type in [
        WebResourceErrorType.INTERNATIONAL_ROAMING_OFF,
        WebResourceErrorType.CALL_IS_ACTIVE,
        WebResourceErrorType.DATA_NOT_ALLOWED,
      ]) {
        final e = onlineLoadErrorFor(type, 'x', isIOS: true);
        expect(e!.offline, isTrue, reason: '$type');
        expect(e.mobileDataOff, type == WebResourceErrorType.DATA_NOT_ALLOWED, reason: '$type');
      }
      expect(onlineLoadErrorFor(WebResourceErrorType.NOT_CONNECTED_TO_INTERNET, 'x', isIOS: true)!.offline, isTrue);
      expect(onlineLoadErrorFor(WebResourceErrorType.CANCELLED, 'x', isIOS: true), isNull);
    });

    test('Android is unchanged: cancelled loads hide, the old offline list, nothing iOS-only', () {
      expect(onlineLoadErrorFor(WebResourceErrorType.CANCELLED, 'net::ERR_ABORTED', isIOS: false), isNull);
      for (final type in [
        WebResourceErrorType.HOST_LOOKUP,
        WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
        WebResourceErrorType.NOT_CONNECTED_TO_INTERNET,
        WebResourceErrorType.NETWORK_CONNECTION_LOST,
        WebResourceErrorType.TIMEOUT,
        WebResourceErrorType.SERVER_UNREACHABLE,
        WebResourceErrorType.FAILED_SSL_HANDSHAKE,
        WebResourceErrorType.SECURE_CONNECTION_FAILED,
        WebResourceErrorType.CONNECTION_ABORTED,
        WebResourceErrorType.RESET,
        WebResourceErrorType.IO,
      ]) {
        final e = onlineLoadErrorFor(type, 'x', isIOS: false)!;
        expect(e.offline, isTrue, reason: '$type');
        expect(e.mobileDataOff, isFalse);
      }
      final unknown = onlineLoadErrorFor(WebResourceErrorType.UNKNOWN, interrupted, isIOS: false)!;
      expect(unknown.offline, isFalse);
      expect(onlineLoadErrorFor(WebResourceErrorType.DATA_NOT_ALLOWED, 'x', isIOS: false)!.offline, isFalse);
    });

    testWidgets("iOS: the real web view drops error 102 and names 'mobile data off'", (tester) async {
      PlatformInfo.debugIsIOS = true;
      final events = await _pumpWebView(tester);
      final onReceivedError = _platform.params!.onReceivedError!;
      final request = WebResourceRequest(url: WebUri('https://m.youtube.com/'), isForMainFrame: true);
      onReceivedError(
        _controller(),
        request,
        WebResourceError(type: WebResourceErrorType.UNKNOWN, description: interrupted),
      );
      expect(events.errors, isEmpty);
      onReceivedError(
        _controller(),
        request,
        WebResourceError(type: WebResourceErrorType.DATA_NOT_ALLOWED, description: 'Mobile data off'),
      );
      expect(events.errors.single.offline, isTrue);
      expect(events.errors.single.mobileDataOff, isTrue);
    });

    group('a network that breaks the secure connection (a certificate the phone does not trust)', () {
      ServerTrustChallenge challenge(String host) =>
          ServerTrustChallenge(protectionSpace: URLProtectionSpace(host: host, protocol: 'https', port: 443));

      Future<ServerTrustAuthResponseAction?> refused(String host) async =>
          (await _platform.params!.onReceivedServerTrustAuthRequest!(_controller(), challenge(host)))?.action;

      NavigationAction mainFrameLink(String url) => NavigationAction(
            request: URLRequest(url: WebUri(url)),
            isForMainFrame: true,
            hasGesture: true,
            navigationType: NavigationType.LINK_ACTIVATED,
          );

      testWidgets('Android: before any page loads, the page itself was refused: the error screen says so',
          (tester) async {
        PlatformInfo.debugIsAndroid = true;
        final events = await _pumpWebView(tester);
        expect(await refused('m.youtube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors, hasLength(1));
        final e = events.errors.single;
        expect(e.secureConnectionBlocked, isTrue);
        expect(e.offline, isFalse);
        // A redirect hop to another host before the first page (consent, www): still the page's own.
        expect(await refused('consent.youtube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors, hasLength(2));
      });

      testWidgets('Android: once a page is on screen, only its own host covers it; every bad certificate is refused',
          (tester) async {
        PlatformInfo.debugIsAndroid = true;
        final events = await _pumpWebView(tester);
        _platform.params!.onLoadStart!(_controller(), WebUri('https://m.youtube.com/'));
        for (final host in ['i.ytimg.com', 'rr1---sn-ab5l6nzr.googlevideo.com', 'googleads.g.doubleclick.net']) {
          expect(await refused(host), ServerTrustAuthResponseAction.CANCEL, reason: host);
        }
        expect(events.errors, isEmpty, reason: 'a picture, a video segment or an ad never covers a working page');
        expect(await refused('M.YouTube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors.single.secureConnectionBlocked, isTrue);
      });

      testWidgets('Android: a link to another host the main frame is loading counts as the page', (tester) async {
        PlatformInfo.debugIsAndroid = true;
        final events = await _pumpWebView(tester);
        _platform.params!.onLoadStart!(_controller(), WebUri('https://m.youtube.com/watch?v=dQw4w9WgXcQ'));
        expect(await refused('music.youtube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors, isEmpty, reason: 'nothing loads from there yet');
        final policy = await _platform.params!.shouldOverrideUrlLoading!(
          _controller(),
          mainFrameLink('https://music.youtube.com/'),
        );
        expect(policy, NavigationActionPolicy.ALLOW);
        expect(await refused('music.youtube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors.single.secureConnectionBlocked, isTrue);
        // Once that page is on screen, the old host is only a resource.
        events.errors.clear();
        _platform.params!.onLoadStart!(_controller(), WebUri('https://music.youtube.com/'));
        expect(await refused('m.youtube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors, isEmpty);
        // about:blank (the plugin's stand-in for an error page) is no page: the next refusal is the page's.
        _platform.params!.onLoadStart!(_controller(), WebUri('about:blank'));
        expect(await refused('m.youtube.com'), ServerTrustAuthResponseAction.CANCEL);
        expect(events.errors.single.secureConnectionBlocked, isTrue);
      });

      test('which host is the page: the first page, links, loads from the app and the page on screen', () {
        final hosts = OnlineMainDocumentHosts(Uri.parse('https://m.youtube.com/'));
        expect(hosts.isMainDocument('i.ytimg.com'), isTrue, reason: 'no page yet');
        hosts.shown(Uri.parse('https://m.youtube.com/'));
        expect(hosts.isMainDocument('m.youtube.com'), isTrue);
        expect(hosts.isMainDocument('i.ytimg.com'), isFalse);
        hosts.loading(Uri.parse('https://accounts.google.com/v3/signin/identifier'));
        expect(hosts.isMainDocument('accounts.google.com'), isTrue);
        expect(hosts.isMainDocument('m.youtube.com'), isTrue);
        hosts.shown(Uri.parse('https://accounts.google.com/v3/signin/identifier'));
        expect(hosts.isMainDocument('m.youtube.com'), isFalse);
        hosts.loading(null);
        hosts.loading(Uri.parse('about:blank'));
        expect(hosts.isMainDocument('m.youtube.com'), isFalse, reason: 'no web page to load: nothing changes');
      });

      testWidgets('iOS: no answer from the app (WebKit refuses a bad certificate itself), and its errors say the same',
          (tester) async {
        PlatformInfo.debugIsIOS = true;
        final events = await _pumpWebView(tester);
        expect(_platform.params!.onReceivedServerTrustAuthRequest, isNull,
            reason: 'iOS asks about trusted certificates too: answering would cost a round trip or break pages');
        final onReceivedError = _platform.params!.onReceivedError!;
        final request = WebResourceRequest(url: WebUri('https://m.youtube.com/'), isForMainFrame: true);
        for (final type in [
          WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED,
          WebResourceErrorType.SERVER_CERTIFICATE_HAS_UNKNOWN_ROOT,
          WebResourceErrorType.SERVER_CERTIFICATE_HAS_BAD_DATE,
          WebResourceErrorType.SERVER_CERTIFICATE_NOT_YET_VALID,
        ]) {
          onReceivedError(_controller(), request, WebResourceError(type: type, description: 'x'));
          expect(events.errors.last.secureConnectionBlocked, isTrue, reason: '$type');
          expect(events.errors.last.offline, isFalse);
        }
        // A picture's certificate error is not the page's.
        onReceivedError(
          _controller(),
          WebResourceRequest(url: WebUri('https://i.ytimg.com/vi/x/hq.jpg'), isForMainFrame: false),
          WebResourceError(type: WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED, description: 'x'),
        );
        expect(events.errors, hasLength(4));
        // Android never gets these types: unchanged there.
        expect(
          onlineLoadErrorFor(WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED, 'x', isIOS: false)!
              .secureConnectionBlocked,
          isFalse,
        );
      });
    });

    testWidgets('the plugin fullscreen events still reach the screen (it decides per platform)', (tester) async {
      PlatformInfo.debugIsIOS = true;
      final events = await _pumpWebView(tester);
      _platform.params!.onEnterFullscreen!(_controller());
      _platform.params!.onExitFullscreen!(_controller());
      expect(events.fullscreen, [true, false]);
    });
  });

  group('settings', () {
    test('iOS: the mobile site on every device and no link preview on a long press', () {
      final ios = onlineWebViewSettings(backgroundPlay: true, isIOS: true);
      expect(ios.preferredContentMode, UserPreferredContentMode.MOBILE);
      expect(ios.allowsLinkPreview, isFalse);
    });

    test('Android keeps the plugin defaults; nothing else differs between the two', () {
      final android = onlineWebViewSettings(backgroundPlay: true, isIOS: false);
      final defaults = InAppWebViewSettings();
      expect(android.preferredContentMode, defaults.preferredContentMode);
      expect(android.allowsLinkPreview, defaults.allowsLinkPreview);
      // Block ads differs on purpose: WebKit's rule list on iOS, no native
      // rule on Android (online_ad_block.dart).
      const perPlatform = {
        'preferredContentMode',
        'allowsLinkPreview',
        'contentBlockers',
      };
      final a = android.toMap()..removeWhere((k, _) => perPlatform.contains(k));
      final i = onlineWebViewSettings(backgroundPlay: true, isIOS: true).toMap()
        ..removeWhere((k, _) => perPlatform.contains(k));
      expect(i, a);
      expect(android.supportMultipleWindows, isFalse);
    });

    testWidgets('the real web view is built with them', (tester) async {
      PlatformInfo.debugIsIOS = true;
      await _pumpWebView(tester);
      final settings = _platform.params!.initialSettings!;
      expect(settings.preferredContentMode, UserPreferredContentMode.MOBILE);
      expect(settings.allowsLinkPreview, isFalse);
    });

    testWidgets('Block ads: the real web view gets the ad rules on iOS, no native rule on Android',
        (tester) async {
      PlatformInfo.debugIsIOS = true;
      await _pumpWebView(tester);
      var settings = _platform.params!.initialSettings!;
      expect(settings.contentBlockers, hasLength(onlineAdUrlFilters().length));
      expect(settings.regexToCancelSubFramesLoading, isNull);

      // A WebView's settings are fixed when it starts: a new one for Android.
      await tester.pumpWidget(const SizedBox());
      PlatformInfo.resetForTests();
      PlatformInfo.debugIsAndroid = true;
      await _pumpWebView(tester);
      settings = _platform.params!.initialSettings!;
      expect(settings.contentBlockers, isEmpty,
          reason: "the plugin's Android content blockers send a HEAD request for every resource");
      expect(settings.regexToCancelSubFramesLoading, isNull,
          reason: 'never consulted for an http(s) frame on Android: it would only claim to block');
    });

    testWidgets('Block ads off: no ad rules on either phone', (tester) async {
      for (final ios in [true, false]) {
        await tester.pumpWidget(const SizedBox());
        PlatformInfo.resetForTests();
        if (ios) {
          PlatformInfo.debugIsIOS = true;
        } else {
          PlatformInfo.debugIsAndroid = true;
        }
        await _pumpWebView(tester, blockAds: false);
        final settings = _platform.params!.initialSettings!;
        expect(settings.contentBlockers, isEmpty, reason: 'iOS: $ios');
        expect(settings.regexToCancelSubFramesLoading, isNull, reason: 'iOS: $ios');
      }
    });
  });

  // The owner could not sign in to YouTube in the Online tab. Google refuses
  // web views it can tell apart from a browser; the user agent and Android's
  // X-Requested-With header are two of the tells.
  group('signing in: a normal browser user agent', () {
    test("Android: the WebView's own, without '; wv', 'Build/' and 'Version/4.0' (Chrome's form)", () {
      expect(browserUserAgentFrom(_androidWebViewUa, isIOS: false), _androidChromeUa);
      // Older and newer shapes of the same thing.
      expect(
        browserUserAgentFrom(
          'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
          'Chrome/120.0.0.0 Mobile Safari/537.36',
          isIOS: false,
        ),
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      final ua = browserUserAgentFrom(_androidWebViewUa, isIOS: false)!;
      expect(ua, isNot(contains('wv')));
      expect(ua, isNot(contains('Version/')));
      expect(ua, contains('Chrome/131.0.6778.135 Mobile Safari/537.36'), reason: 'the same Chrome version');
      expect(ua, contains('SM-S911B'), reason: 'the same phone');
    });

    test("iOS: WKWebView's own, with Safari's 'Version/x.y' and 'Safari/604.1' put back", () {
      expect(browserUserAgentFrom(_iosWebViewUa, isIOS: true), _iosSafariUa);
      expect(
        browserUserAgentFrom(
          'Mozilla/5.0 (iPad; CPU OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
          isIOS: true,
        ),
        'Mozilla/5.0 (iPad; CPU OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/16.7 Mobile/15E148 Safari/604.1',
      );
    });

    test('anything unexpected keeps the WebView its own user agent', () {
      for (final (raw, ios) in [
        ('', false),
        ('', true),
        ('Dart/3.13 (dart:io)', false),
        (_androidChromeUa, false), // already a browser one: nothing to change
        (_iosSafariUa, true),
        // An iPad's desktop-class default says Macintosh: not ours to rewrite.
        ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)', true),
        ('Mozilla/5.0 (Linux; Android 13; wv) AppleWebKit/537.36 (KHTML, like Gecko)', false), // no Chrome/
        ('Mozilla/5.0 (X11; Linux x86_64) ${'A' * 600}', false),
      ]) {
        expect(browserUserAgentFrom(raw, isIOS: ios), isNull, reason: raw);
      }
    });

    test('the settings carry it, send X-Requested-With nowhere and keep the sign-in on disk', () {
      for (final ios in [false, true]) {
        final s = onlineWebViewSettings(backgroundPlay: true, isIOS: ios, userAgent: _androidChromeUa);
        expect(s.userAgent, _androidChromeUa);
        expect(s.requestedWithHeaderOriginAllowList, isEmpty);
        expect(s.requestedWithHeaderOriginAllowList, isNotNull, reason: 'null would keep the WebView default');
        expect(s.incognito, isFalse, reason: 'cookies outlive the app, so the sign-in stays');
        expect(s.cacheEnabled, isTrue);
        expect(s.thirdPartyCookiesEnabled, isFalse, reason: 'the sign-in hands over through whole pages');
        expect(s.toMap()['requestedWithHeaderOriginAllowList'], isEmpty);
      }
      // No browser user agent known: the WebView's own.
      expect(onlineWebViewSettings(backgroundPlay: true, isIOS: false).userAgent, '');
    });

    testWidgets('Android: the real web view is built with the browser user agent', (tester) async {
      PlatformInfo.debugIsAndroid = true;
      await _pumpWebView(tester);
      final settings = _platform.params!.initialSettings!;
      expect(settings.userAgent, _androidChromeUa);
      expect(settings.requestedWithHeaderOriginAllowList, isEmpty);
    });

    testWidgets('iOS: the real web view is built with the Safari user agent', (tester) async {
      PlatformInfo.debugIsIOS = true;
      _defaultUserAgent = () async => _iosWebViewUa;
      await _pumpWebView(tester);
      expect(_platform.params!.initialSettings!.userAgent, _iosSafariUa);
    });

    testWidgets('the WebView asks once per app run; a new one is built straight away', (tester) async {
      PlatformInfo.debugIsAndroid = true;
      await _pumpWebView(tester);
      expect(_log.where((c) => c == 'getDefaultUserAgent'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      _platform.params = null;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => buildInAppOnlineWebView(
            context,
            OnlineWebViewConfig(bridgeScript: '', backgroundPlay: true, initialUrl: Uri.parse(youTubeHomeUrl)),
            _Events().events,
          ),
        ),
      ));
      expect(_platform.params, isNotNull, reason: 'no wait the second time');
      expect(_platform.params!.initialSettings!.userAgent, _androidChromeUa);
      expect(_log.where((c) => c == 'getDefaultUserAgent'), hasLength(1));
    });

    testWidgets('a WebView that never answers is waited for two seconds at most, then keeps its own', (tester) async {
      PlatformInfo.debugIsIOS = true;
      // iOS's probe never calls back when its page fails.
      _defaultUserAgent = () => Completer<String>().future;
      await _pumpWebView(tester);
      expect(_platform.params, isNull, reason: 'still waiting');
      expect(find.byKey(const ValueKey('fake_platform_webview')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(_platform.params, isNotNull);
      expect(_platform.params!.initialSettings!.userAgent, '');
      expect(find.byKey(const ValueKey('fake_platform_webview')), findsOneWidget);
    });

    testWidgets('a WebView that fails to answer keeps its own at once', (tester) async {
      PlatformInfo.debugIsAndroid = true;
      _defaultUserAgent = () async => throw PlatformException(code: 'x');
      await _pumpWebView(tester);
      expect(_platform.params!.initialSettings!.userAgent, '');
    });
  });

  group('Clear YouTube data', () {
    test('iOS: every kind of site data goes (WebKit has no deleteAllData)', () async {
      PlatformInfo.debugIsIOS = true;
      await clearInAppWebViewData();
      expect(_log, ['deleteAllCookies', 'removeDataModifiedSince', 'clearAllCache']);
      final storage = WebStorageManager.instance().platform as _FakeStorage;
      expect(storage.removedTypes, WebsiteDataType.ALL);
      expect(storage.removedTypes, containsAll([
        WebsiteDataType.WKWebsiteDataTypeLocalStorage,
        WebsiteDataType.WKWebsiteDataTypeIndexedDBDatabases,
        WebsiteDataType.WKWebsiteDataTypeServiceWorkerRegistrations,
      ]));
      expect(storage.removedSince, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('Android is unchanged: deleteAllData', () async {
      PlatformInfo.debugIsAndroid = true;
      PlatformInfo.debugIsIOS = false;
      await clearInAppWebViewData();
      expect(_log, ['deleteAllCookies', 'deleteAllData', 'clearAllCache']);
    });
  });
}
