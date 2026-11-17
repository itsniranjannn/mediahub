import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
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
  const OnlineLoadError({required this.offline, required this.description});

  /// No connection, DNS failure, timeout or a host that cannot be reached.
  final bool offline;
  final String description;
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
    await WebStorageManager.instance().deleteAllData();
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

class _InAppOnlineWebViewState extends State<_InAppOnlineWebView> {
  // Built once: the WebView must not be recreated by rebuilds of the screen.
  late final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    // Commands from the notification start playback without a tap in the page.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    allowsPictureInPictureMediaPlayback: true,
    allowsAirPlayForMediaPlayback: true,
    allowBackgroundAudioPlaying: widget.config.backgroundPlay,
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
    final config = widget.config;
    final events = widget.events;
    final fixture = config.fixtureHtml;
    return InAppWebView(
      initialSettings: _settings,
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
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) return;
        final t = error.type;
        if (t == WebResourceErrorType.CANCELLED) return;
        final offline = t == WebResourceErrorType.HOST_LOOKUP ||
            t == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
            t == WebResourceErrorType.NOT_CONNECTED_TO_INTERNET ||
            t == WebResourceErrorType.NETWORK_CONNECTION_LOST ||
            t == WebResourceErrorType.TIMEOUT ||
            t == WebResourceErrorType.SERVER_UNREACHABLE ||
            t == WebResourceErrorType.FAILED_SSL_HANDSHAKE ||
            t == WebResourceErrorType.SECURE_CONNECTION_FAILED ||
            t == WebResourceErrorType.CONNECTION_ABORTED ||
            t == WebResourceErrorType.RESET ||
            t == WebResourceErrorType.IO;
        DiagnosticsService.instance.logEvent('online_load_error', {'type': t.toString()});
        events.onMainFrameError(OnlineLoadError(offline: offline, description: error.description));
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
