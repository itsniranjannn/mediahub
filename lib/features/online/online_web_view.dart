import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform_info.dart';
import 'online_bridge_protocol.dart';
import 'youtube_urls.dart';

/// What the Online screen needs from the WebView. Kept small so widget tests
/// can drive the screen with a fake (platform views do not run in `flutter test`).
abstract class OnlineWebController {
  Future<void> loadUrl(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stopLoading();
  Future<bool> canGoBack();
  Future<bool> canGoForward();

  /// Runs [source] in the page's main frame and returns its result.
  Future<Object?> evaluateJavascript(String source);

  /// Android: lets the page keep playing when the app's window is hidden
  /// (the WebView then never tells the page it went invisible).
  Future<void> setBackgroundAudioAllowed(bool allowed);
}

/// A main-frame load failure, reduced to what the screen shows.
class OnlineLoadError {
  const OnlineLoadError({required this.offline, required this.description, this.mobileDataOff = false});

  /// No connection, DNS failure, timeout or a host that cannot be reached.
  final bool offline;
  final String description;

  /// iOS: mobile data is switched off for MediaHub in the phone's Settings.
  final bool mobileDataOff;
}

/// Main-frame failures that mean "no usable connection".
final List<WebResourceErrorType> _offlineErrors = [
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
];

/// iOS's own "no network" reasons: data roaming off (-1018), a phone call
/// holding the line (-1019) and mobile data switched off for the app (-1020).
final List<WebResourceErrorType> _iosOfflineErrors = [
  WebResourceErrorType.INTERNATIONAL_ROAMING_OFF,
  WebResourceErrorType.CALL_IS_ACTIVE,
  WebResourceErrorType.DATA_NOT_ALLOWED,
];

/// WebKit's "Frame load interrupted" (WebKitErrorDomain 102): a load that was
/// stopped on purpose (a link MediaHub opened in the browser instead, or the
/// http to https swap). The iOS plugin reports it as type unknown (-1), with
/// the domain and code at the start of the description.
final RegExp _webKitFrameLoadInterrupted = RegExp(r'domain=WebKitErrorDomain, code=102(?!\d)');

/// What the error screen shows for a failed main-frame load, or null when the
/// failure is a normal cancel the user should never see.
OnlineLoadError? onlineLoadErrorFor(WebResourceErrorType type, String description, {required bool isIOS}) {
  if (type == WebResourceErrorType.CANCELLED) return null;
  if (isIOS && _webKitFrameLoadInterrupted.hasMatch(description)) return null;
  final offline = _offlineErrors.any((t) => t == type) || (isIOS && _iosOfflineErrors.any((t) => t == type));
  return OnlineLoadError(
    offline: offline,
    description: description,
    mobileDataOff: isIOS && type == WebResourceErrorType.DATA_NOT_ALLOWED,
  );
}

/// Callbacks from the WebView to the screen.
class OnlineWebEvents {
  const OnlineWebEvents({
    required this.onCreated,
    required this.onUrlChanged,
    required this.onTitleChanged,
    required this.onProgress,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onMainFrameError,
    required this.onScrollY,
    required this.onBridgeMessage,
    required this.openExternally,
    required this.onFullscreenChanged,
    required this.onRendererGone,
  });

  final void Function(OnlineWebController controller) onCreated;
  final void Function(Uri? url) onUrlChanged;
  final void Function(String? title) onTitleChanged;

  /// 0-100.
  final void Function(int progress) onProgress;
  final void Function(Uri? url) onLoadStart;
  final void Function(Uri? url) onLoadStop;
  final void Function(OnlineLoadError error) onMainFrameError;
  final void Function(int y) onScrollY;

  /// The raw arguments of a `mediahubBridge` handler call (validated by the screen).
  final void Function(Object? args) onBridgeMessage;
  final Future<void> Function(Uri uri) openExternally;
  final void Function(bool fullscreen) onFullscreenChanged;

  /// The page's renderer process died (Android may kill it to free memory):
  /// the screen recreates the WebView.
  final void Function() onRendererGone;
}

/// How the WebView starts.
class OnlineWebViewConfig {
  const OnlineWebViewConfig({
    required this.bridgeScript,
    required this.backgroundPlay,
    required this.initialUrl,
    this.fixtureHtml,
  });

  /// The media bridge with its token filled in.
  final String bridgeScript;
  final bool backgroundPlay;
  final Uri initialUrl;

  /// Debug fixture: this page is loaded with [initialUrl] as its base URL
  /// instead of fetching [initialUrl].
  final String? fixtureHtml;
}

typedef OnlineWebViewBuilder = Widget Function(
  BuildContext context,
  OnlineWebViewConfig config,
  OnlineWebEvents events,
);

/// Builds the real WebView. Tests override it with a fake.
final onlineWebViewBuilderProvider = Provider<OnlineWebViewBuilder>((ref) => buildInAppOnlineWebView);

/// Clears YouTube cookies, cache and site storage (Settings → Online and the ⋮ menu).
typedef OnlineDataClearer = Future<void> Function();

final onlineDataClearerProvider = Provider<OnlineDataClearer>((ref) => clearInAppWebViewData);

Future<void> clearInAppWebViewData() async {
  try {
    await CookieManager.instance().deleteAllCookies();
  } catch (e) {
    debugPrint('[Online] cookie clear failed: $e');
  }
  try {
    if (PlatformInfo.isIOS) {
      // iOS has no deleteAllData (it throws UnimplementedError): WebKit's data
      // store removes every kind of site data (local storage, IndexedDB,
      // service workers, cookies and caches) changed since 1970, which is all.
      await WebStorageManager.instance().removeDataModifiedSince(
        dataTypes: WebsiteDataType.ALL,
        date: DateTime.fromMillisecondsSinceEpoch(0),
      );
    } else {
      await WebStorageManager.instance().deleteAllData();
    }
  } catch (e) {
    debugPrint('[Online] storage clear failed: $e');
  }
  try {
    await InAppWebViewController.clearAllCache();
  } catch (e) {
    debugPrint('[Online] cache clear failed: $e');
  }
  DiagnosticsService.instance.logEvent('online_site_data_cleared');
}

Widget buildInAppOnlineWebView(BuildContext context, OnlineWebViewConfig config, OnlineWebEvents events) {
  return _InAppOnlineWebView(config: config, events: events);
}

/// Origins the bridge script may be injected into. Android document-start
/// scripts honour this list; iOS ignores it (and Android's fallback for older
/// WebViews injects everywhere), so the script itself also returns at once on
/// anything but an https YouTube page.
const Set<String> _bridgeOrigins = {'https://youtube.com', 'https://*.youtube.com'};

class _InAppOnlineWebView extends StatefulWidget {
  const _InAppOnlineWebView({required this.config, required this.events});

  final OnlineWebViewConfig config;
  final OnlineWebEvents events;

  @override
  State<_InAppOnlineWebView> createState() => _InAppOnlineWebViewState();
}

final RegExp _androidWebViewToken = RegExp(r';\s*wv(?=\s*[;)])');
final RegExp _androidBuildToken = RegExp(r'\s+Build/[^;)]*');
final RegExp _versionToken = RegExp(r'\s*\bVersion/\d+(?:\.\d+)*');
final RegExp _iosVersion = RegExp(r'\bOS (\d+)_(\d+)(?:_\d+)? like Mac OS X');

/// The phone's normal browser user agent, built from the WebView's own
/// [webViewUserAgent], or null to keep the WebView's own.
///
/// Google refuses to sign in inside web views it can tell apart from a
/// browser, and the user agent is one of the tells:
/// - Android's WebView says "; wv", "Build/..." and "Version/4.0" where
///   Chrome says none of them. Dropping the three leaves Chrome's own form
///   (the same Chrome version and phone model).
/// - iOS's WKWebView leaves out Safari's "Version/x.y" and "Safari/604.1";
///   they are put back, with the iOS version as Safari's version. A user
///   agent that is not an iPhone, iPad or iPod one (an iPad's desktop-class
///   default) is kept as it is.
String? browserUserAgentFrom(String webViewUserAgent, {required bool isIOS}) {
  final ua = webViewUserAgent.trim();
  if (ua.isEmpty || ua.length > 512 || !ua.startsWith('Mozilla/5.0 (')) return null;
  if (!isIOS) {
    if (!ua.contains('Chrome/') || !ua.contains('Android')) return null;
    final browser = ua
        .replaceAll(_androidWebViewToken, '')
        .replaceAll(_androidBuildToken, '')
        .replaceAll(_versionToken, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    return browser == ua ? null : browser;
  }
  if (!RegExp(r'\((iPhone|iPad|iPod)').hasMatch(ua)) return null;
  final os = _iosVersion.firstMatch(ua);
  if (os == null) return null;
  var browser = ua;
  if (!browser.contains('Version/')) {
    final safariVersion = 'Version/${os.group(1)}.${os.group(2)}';
    final mobile = browser.indexOf(' Mobile/');
    browser = mobile < 0 ? '$browser $safariVersion' : browser.replaceRange(mobile, mobile, ' $safariVersion');
  }
  if (!browser.contains('Safari/')) browser = '$browser Safari/604.1';
  return browser == ua ? null : browser;
}

/// The browser user agent once it is known (see [onlineBrowserUserAgent]).
String? _resolvedUserAgent;
bool _userAgentResolved = false;
Future<String?>? _pendingUserAgent;

/// Asks the WebView for its default user agent once per app run and turns
/// it into the phone's browser one ([browserUserAgentFrom]). Null when the
/// WebView does not answer within two seconds or the answer is not one we
/// know: the WebView then keeps its own.
Future<String?> onlineBrowserUserAgent({required bool isIOS}) {
  if (_userAgentResolved) return Future.value(_resolvedUserAgent);
  return _pendingUserAgent ??= () async {
    String? ua;
    try {
      // iOS never answers when its probe page fails: hence the time limit.
      final own = await InAppWebViewController.getDefaultUserAgent().timeout(const Duration(seconds: 2));
      ua = browserUserAgentFrom(own, isIOS: isIOS);
      _resolvedUserAgent = ua;
      _userAgentResolved = true;
    } catch (e) {
      debugPrint('[Online] default user agent unavailable: $e');
    } finally {
      _pendingUserAgent = null;
    }
    DiagnosticsService.instance.logEvent('online_user_agent', {'browser': ua != null});
    return ua;
  }();
}

@visibleForTesting
void resetOnlineUserAgentForTests() {
  _resolvedUserAgent = null;
  _userAgentResolved = false;
  _pendingUserAgent = null;
}

/// The Online WebView's settings.
///
/// Both platforms: [userAgent] (the phone's browser one, see
/// [browserUserAgentFrom]; empty keeps the WebView's own), and Android's
/// X-Requested-With header (the app's package name, another web-view tell)
/// goes to no site at all where the WebView lets the app choose. Cookies stay
/// on disk, so a sign-in lasts until "Clear YouTube data"; third-party
/// cookies stay off (the sign-in hands over through whole pages, which set
/// first-party cookies).
///
/// iOS only: the mobile site on every device ([UserPreferredContentMode.MOBILE];
/// the plugin's default, "recommended", gives an iPad desktop YouTube), and
/// no link preview on a long press (WebKit's preview card can load and show
/// an outside page inside the app). Android keeps the plugin defaults for both.
InAppWebViewSettings onlineWebViewSettings({
  required bool backgroundPlay,
  required bool isIOS,
  String? userAgent,
}) =>
    InAppWebViewSettings(
      userAgent: userAgent ?? '',
      requestedWithHeaderOriginAllowList: const <String>{},
      incognito: false,
      cacheEnabled: true,
      javaScriptEnabled: true,
      // Commands from the notification start playback without a tap in the page.
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      allowsAirPlayForMediaPlayback: true,
      allowBackgroundAudioPlaying: backgroundPlay,
      useShouldOverrideUrlLoading: true,
      useOnRenderProcessGone: true,
      // No file access, no mixed content, no pop-up windows, no location.
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
      geolocationEnabled: false,
      thirdPartyCookiesEnabled: false,
      saveFormData: false,
      safeBrowsingEnabled: true,
      isFraudulentWebsiteWarningEnabled: true,
      upgradeKnownHostsToHTTPS: true,
      // Our own offline hint replaces the WebView's error page.
      disableDefaultErrorPage: true,
      supportZoom: false,
      allowsBackForwardNavigationGestures: true,
      isInspectable: kDebugMode,
      useHybridComposition: true,
      preferredContentMode: isIOS ? UserPreferredContentMode.MOBILE : UserPreferredContentMode.RECOMMENDED,
      allowsLinkPreview: !isIOS,
    );

/// iOS: the page asked for a new window (a `target="_blank"` link). The
/// plugin has already made a hidden window for it; answering false lets the
/// plugin drop that window and load the request in this same view instead,
/// where shouldOverrideUrlLoading applies the usual rules: a YouTube page
/// loads in place, and anything else is cancelled there (a load the plugin
/// starts itself never counts as a tap, so an outside link never opens
/// twice). So an outside link the user tapped is opened in the browser here,
/// and the answer is always false.
Future<bool> handleOnlineNewWindow(
  CreateWindowAction action, {
  required Future<void> Function(Uri uri) openExternally,
}) async {
  final type = action.navigationType;
  final tapped = isUserNavigation(
    hasGesture: action.hasGesture,
    linkOrFormActivated: type == NavigationType.LINK_ACTIVATED || type == NavigationType.FORM_SUBMITTED,
  );
  final decision = decideOnlineNewWindow(action.request.url, userTapped: tapped);
  DiagnosticsService.instance.logEvent('online_new_window', {'kind': decision.kind.name});
  final target = decision.uri;
  if (decision.kind == OnlineNavigationKind.openExternally && target != null) {
    await openExternally(target);
  }
  return false;
}

class _InAppOnlineWebViewState extends State<_InAppOnlineWebView> {
  // Built once, when the user agent is known: the WebView must not be
  // recreated by rebuilds of the screen.
  InAppWebViewSettings? _settings;

  @override
  void initState() {
    super.initState();
    final isIOS = PlatformInfo.isIOS;
    if (_userAgentResolved) {
      _settings = _settingsWith(_resolvedUserAgent, isIOS);
      return;
    }
    // The first page load already carries the browser user agent, so the
    // WebView waits for it (a few milliseconds, two seconds at most).
    onlineBrowserUserAgent(isIOS: isIOS).then((ua) {
      if (!mounted || _settings != null) return;
      setState(() => _settings = _settingsWith(ua, isIOS));
    });
  }

  InAppWebViewSettings _settingsWith(String? userAgent, bool isIOS) => onlineWebViewSettings(
        backgroundPlay: widget.config.backgroundPlay,
        isIOS: isIOS,
        userAgent: userAgent,
      );

  late final UnmodifiableListView<UserScript> _scripts = UnmodifiableListView([
    UserScript(
      groupName: 'mediahub',
      source: widget.config.bridgeScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
      allowedOriginRules: _bridgeOrigins,
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) return const SizedBox.expand();
    final config = widget.config;
    final events = widget.events;
    final fixture = config.fixtureHtml;
    return InAppWebView(
      initialSettings: settings,
      initialUserScripts: _scripts,
      initialUrlRequest: fixture == null ? URLRequest(url: WebUri.uri(config.initialUrl)) : null,
      initialData: fixture == null
          ? null
          : InAppWebViewInitialData(
              data: fixture,
              baseUrl: WebUri.uri(config.initialUrl),
              historyUrl: WebUri.uri(config.initialUrl),
            ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: onlineBridgeHandlerName,
          callback: (args) {
            events.onBridgeMessage(args);
            return null;
          },
        );
        events.onCreated(_InAppController(controller));
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url;
        final decision = decideOnlineNavigation(url, isMainFrame: action.isForMainFrame);
        switch (decision.kind) {
          case OnlineNavigationKind.allow:
            final upgraded = decision.uri;
            if (upgraded != null && url != null && upgraded.toString() != url.toString()) {
              await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(upgraded)));
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          case OnlineNavigationKind.openExternally:
            final target = decision.uri;
            final type = action.navigationType;
            final tapped = isUserNavigation(
              hasGesture: action.hasGesture,
              linkOrFormActivated: type == NavigationType.LINK_ACTIVATED || type == NavigationType.FORM_SUBMITTED,
            );
            if (target != null && tapped) {
              // Only links the user tapped open another app; a page cannot
              // bounce the phone to the browser on its own.
              await events.openExternally(target);
            }
            return NavigationActionPolicy.CANCEL;
          case OnlineNavigationKind.cancel:
            return NavigationActionPolicy.CANCEL;
        }
      },
      onLoadStart: (controller, url) => events.onLoadStart(url),
      onLoadStop: (controller, url) => events.onLoadStop(url),
      onUpdateVisitedHistory: (controller, url, isReload) => events.onUrlChanged(url),
      onTitleChanged: (controller, title) => events.onTitleChanged(title),
      onProgressChanged: (controller, progress) => events.onProgress(progress),
      onScrollChanged: (controller, x, y) => events.onScrollY(y),
      // iOS only: Android never asks for a window (multiple windows are off).
      onCreateWindow: PlatformInfo.isIOS
          ? (controller, action) => handleOnlineNewWindow(action, openExternally: events.openExternally)
          : null,
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) return;
        final shown = onlineLoadErrorFor(error.type, error.description, isIOS: PlatformInfo.isIOS);
        if (shown == null) return;
        DiagnosticsService.instance.logEvent('online_load_error', {'type': error.type.toString()});
        events.onMainFrameError(shown);
      },
      onEnterFullscreen: (controller) => events.onFullscreenChanged(true),
      onExitFullscreen: (controller) => events.onFullscreenChanged(false),
      onPermissionRequest: (controller, request) async =>
          PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
      onGeolocationPermissionsShowPrompt: (controller, origin) async =>
          GeolocationPermissionShowPromptResponse(origin: origin, allow: false, retain: false),
      onRenderProcessGone: (controller, detail) {
        DiagnosticsService.instance.logEvent('online_renderer_gone', {'crash': detail.didCrash});
        events.onRendererGone();
      },
      onWebContentProcessDidTerminate: (controller) {
        DiagnosticsService.instance.logEvent('online_renderer_gone', {'crash': true});
        controller.reload();
      },
    );
  }
}

class _InAppController implements OnlineWebController {
  _InAppController(this._c);

  final InAppWebViewController _c;

  @override
  Future<void> loadUrl(Uri url) => _c.loadUrl(urlRequest: URLRequest(url: WebUri.uri(url)));

  @override
  Future<void> goBack() => _c.goBack();

  @override
  Future<void> goForward() => _c.goForward();

  @override
  Future<void> reload() => _c.reload();

  @override
  Future<void> stopLoading() => _c.stopLoading();

  @override
  Future<bool> canGoBack() => _c.canGoBack();

  @override
  Future<bool> canGoForward() => _c.canGoForward();

  @override
  Future<Object?> evaluateJavascript(String source) => _c.evaluateJavascript(source: source);

  @override
  Future<void> setBackgroundAudioAllowed(bool allowed) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // setSettings replaces every setting it is given, so start from the
    // current ones and change only this flag.
    final current = await _c.getSettings();
    if (current == null || current.allowBackgroundAudioPlaying == allowed) return;
    current.allowBackgroundAudioPlaying = allowed;
    await _c.setSettings(settings: current);
  }
}
