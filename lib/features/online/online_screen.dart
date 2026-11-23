import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/ink_theme.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform_info.dart';
import '../../domain/models/media_item.dart' as domain;
import '../../shared/widgets/ui_kit.dart';
import '../downloads/download_link_inbox.dart';
import '../library/library_notifier.dart';
import '../library/media_context_menu.dart';
import 'online_background_handoff.dart';
import 'online_bridge_protocol.dart';
import 'online_media_session.dart';
import 'online_open_request.dart';
import 'online_settings.dart';
import 'online_web_view.dart';
import 'youtube_urls.dart';

/// Debug / test builds only: `--dart-define=MEDIAHUB_ONLINE_FIXTURE=true`
/// loads `assets/web/online_fixture.html` as if it were a YouTube watch page,
/// so the bridge, the notification and picture-in-picture can be tried on an
/// emulator that cannot reach YouTube. Always off in release builds.
const bool kOnlineFixture = bool.fromEnvironment('MEDIAHUB_ONLINE_FIXTURE') && !kReleaseMode;

/// The fixture's page address (a valid-looking 11-character id).
const String onlineFixtureUrl = 'https://m.youtube.com/watch?v=fixture0001';

/// The injected script and (in fixture builds) the fixture page.
class OnlineAssets {
  const OnlineAssets({required this.bridgeSource, this.fixtureHtml});
  final String bridgeSource;
  final String? fixtureHtml;
}

final onlineAssetsProvider = FutureProvider<OnlineAssets>((ref) async {
  final bridge = await rootBundle.loadString('assets/web/youtube_bridge.js');
  final fixture = kOnlineFixture ? await rootBundle.loadString('assets/web/online_fixture.html') : null;
  return OnlineAssets(bridgeSource: bridge, fixtureHtml: fixture);
});

/// Android API level (null elsewhere): Android 13+ shows its own "Copied" toast.
final androidSdkIntProvider = FutureProvider<int?>((ref) async {
  if (!PlatformInfo.isAndroid) return null;
  try {
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  } catch (_) {
    return null;
  }
});

/// YouTube Music's own web player (Online ⋮ → YouTube Music).
const String youTubeMusicHomeUrl = 'https://music.youtube.com/';

/// How far the dock's ink reaches up under the bottom of the YouTube page
/// (covers device-pixel rounding of the WebView's size).
const double onlinePageSeamHeight = 3;

/// Opens the media sheet (Like, Add to playlist ...) for an online item from
/// the watch strip's Save button. Tests override it.
final onlineSaveSheetProvider = Provider<Future<void> Function(BuildContext context, WidgetRef ref, domain.MediaItem item)>(
  (ref) => (context, ref, item) => MediaContextMenu.show(context, ref, item),
);

/// Orientation and system bars while a page video is fullscreen. Tests
/// override it (the platform channel is not there in `flutter test`).
typedef OnlineFullscreenChrome = Future<void> Function({required bool fullscreen, required bool landscape});

final onlineFullscreenChromeProvider = Provider<OnlineFullscreenChrome>((ref) => applyOnlineFullscreenChrome);

/// A wide video fills the phone sideways; leaving fullscreen frees the
/// rotation again and brings the system bars back.
Future<void> applyOnlineFullscreenChrome({required bool fullscreen, required bool landscape}) async {
  try {
    if (fullscreen) {
      if (landscape) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(const []);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  } catch (e) {
    debugPrint('[Online] fullscreen chrome failed: $e');
  }
}

/// Opens a non-YouTube link in the phone's browser (or the app that owns it).
final onlineExternalLauncherProvider = Provider<Future<void> Function(Uri uri)>((ref) {
  return (uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Online] could not open $uri: $e');
    }
  };
});

/// Real YouTube inside the app: the mobile site in a WebView, with MediaHub's
/// own toolbar around it (DESIGN.md 7.13). The tab is kept alive by the shell's
/// indexed stack, so the page (and a playing video) survives tab switches.
class OnlineScreen extends ConsumerStatefulWidget {
  const OnlineScreen({super.key});

  @override
  ConsumerState<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends ConsumerState<OnlineScreen> with WidgetsBindingObserver {
  static const double _row1Height = 56;
  static const double _stripHeight = 52;

  final String _token = newOnlineBridgeToken();
  OnlineWebController? _controller;
  late final OnlineMediaSession _session;
  late final OnlineBackgroundHandoff _handoff;
  late final OnlineFullscreenChrome _fullscreenChrome;
  StreamSubscription<void>? _pipDismissedSub;

  Uri? _url;
  String? _title;
  int _progress = 100;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  OnlineLoadError? _error;
  bool _collapsed = false;
  int _lastScrollY = 0;
  bool _fullscreen = false;
  bool _pipLayout = false;

  /// Keeps the WebView's element (and the page in it) when the layout
  /// around it changes: picture-in-picture, fullscreen, rotation.
  final GlobalKey _webSubtreeKey = GlobalKey(debugLabel: 'online_web');
  bool _lastPipWasOurs = false;
  bool _visible = true;
  bool _fullscreenChromeApplied = false;

  /// iOS: picture-in-picture started by the app going inactive (Control
  /// Center, a notification pulled down). If the app never actually left,
  /// it is closed again on the way back.
  bool _autoPipOnInactive = false;
  bool _reachedHidden = false;

  /// Bumped when the renderer dies, to build a fresh WebView.
  int _generation = 0;
  Uri _initialUrl = Uri.parse(kOnlineFixture ? onlineFixtureUrl : youTubeHomeUrl);

  @override
  void initState() {
    super.initState();
    _session = ref.read(onlineMediaSessionProvider);
    _handoff = ref.read(onlineBackgroundHandoffProvider);
    _fullscreenChrome = ref.read(onlineFullscreenChromeProvider);
    _session.backgroundPlay = ref.read(onlineBackgroundPlayProvider);
    _session.media.addListener(_onMediaChanged);
    // Another screen asked for a page before this tab was first built.
    final requested = ref.read(onlineOpenRequestProvider);
    if (requested != null) {
      _initialUrl = requested;
      Future.microtask(() {
        if (mounted) ref.read(onlineOpenRequestProvider.notifier).clear();
      });
    }
    WidgetsBinding.instance.addObserver(this);
    DeviceControls.init();
    DeviceControls.inPip.addListener(_onPipChanged);
    _pipDismissedSub = DeviceControls.pipDismissed.listen((_) {
      if (_lastPipWasOurs) _session.send(const BridgeCommand.pause());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shell turns tickers off for tabs that are not on screen, and the
    // navigator for routes covered by another page.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _visible) {
      _visible = visible;
      _updatePipEligibility();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceControls.inPip.removeListener(_onPipChanged);
    _pipDismissedSub?.cancel();
    _session.media.removeListener(_onMediaChanged);
    _session.detachPage();
    DeviceControls.setPipEligible(false, owner: DeviceControls.pipOwnerOnline);
    if (_fullscreenChromeApplied) _fullscreenChrome(fullscreen: false, landscape: false);
    super.dispose();
  }

  // --- web view events ------------------------------------------------------

  void _onCreated(OnlineWebController controller) {
    _controller = controller;
    _session.attachSender((command) async {
      final c = _controller;
      if (c == null) return false;
      // Commands go to YouTube pages only: never into Google's sign-in
      // pages (or any other site), where there is no bridge to answer.
      if (!_onYouTubeOrBlank()) return false;
      final result = await c.evaluateJavascript(command.toJavaScript());
      // Android decodes the JSON `true`; iOS may hand back 1 for a JS boolean.
      return result == true || result == 1 || result == 'true';
    });
  }

  void _onUrlChanged(Uri? url) {
    if (!mounted || url == null) return;
    if (url.toString() != _url?.toString()) {
      setState(() {
        _url = url;
        _collapsed = false;
      });
      _updatePipEligibility();
    }
    _refreshHistory();
  }

  void _onLoadStart(Uri? url) {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      if (url != null) _url = url;
    });
  }

  void _onLoadStop(Uri? url) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (url != null) _url = url;
    });
    _refreshHistory();
    _pushPageSettings();
  }

  void _onProgress(int progress) {
    if (!mounted) return;
    final loading = progress < 100;
    if (progress != _progress || loading != _loading) {
      setState(() {
        _progress = progress;
        _loading = loading;
      });
    }
  }

  void _onTitle(String? title) {
    if (!mounted || title == _title) return;
    setState(() => _title = title);
  }

  void _onError(OnlineLoadError error) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _loading = false;
    });
    _updatePipEligibility();
  }

  void _onScrollY(int y) {
    final delta = y - _lastScrollY;
    _lastScrollY = y;
    bool? collapse;
    if (y <= 8) {
      collapse = false;
    } else if (delta > 12 && y > _row1Height) {
      collapse = true;
    } else if (delta < -12) {
      collapse = false;
    }
    if (collapse != null && collapse != _collapsed && mounted) {
      setState(() => _collapsed = collapse!);
    }
  }

  /// False while the main frame is a web page other than YouTube (Google's
  /// sign-in, say). Before the first address, and on about:blank or the
  /// debug fixture's data page, it is true.
  bool _onYouTubeOrBlank() {
    final url = _url;
    final web = url != null && (url.scheme == 'https' || url.scheme == 'http');
    return !web || isYouTubePage(url);
  }

  void _onBridgeMessage(Object? args) {
    final message = parseBridgeMessage(args, token: _token);
    if (message == null) return;
    // The page names its own address in every message; the WebView's own
    // record of the main frame must not say it is some other web site
    // (Google's sign-in pages included).
    if (!_onYouTubeOrBlank()) return;
    if (message is BridgeFullscreenMessage) {
      _onPageFullscreen(message.active);
      return;
    }
    if (message is BridgeReadyMessage) {
      _pushPageSettings();
      // iOS: a new document has no fullscreen video (the old one went with it).
      if (PlatformInfo.isIOS && _fullscreen) _onFullscreen(false);
    }
    _session.handleMessage(message);
  }

  /// The WebView's own fullscreen events. Android: they are the truth. iOS:
  /// the plugin calls any app window that appears (a share sheet, a system
  /// prompt, even while this tab is not on screen) a fullscreen video, which
  /// would hide the toolbar and turn the app sideways by mistake, so there only
  /// the page's own word counts ([_onPageFullscreen]).
  void _onWebViewFullscreen(bool fullscreen) {
    if (PlatformInfo.isIOS) return;
    _onFullscreen(fullscreen);
  }

  /// iOS: the bridge saw a video enter or leave fullscreen.
  void _onPageFullscreen(bool fullscreen) {
    if (!PlatformInfo.isIOS) return; // Android follows the WebView's events
    _onFullscreen(fullscreen);
  }

  void _onFullscreen(bool fullscreen) {
    if (!mounted) return;
    if (fullscreen != _fullscreen) setState(() => _fullscreen = fullscreen);
    if (fullscreen == _fullscreenChromeApplied) return;
    _fullscreenChromeApplied = fullscreen;
    // A wide video turns the phone sideways (16:9 when its size is unknown).
    final landscape = fullscreen && (_session.media.value?.aspectRatio ?? 16 / 9) > 1;
    _fullscreenChrome(fullscreen: fullscreen, landscape: landscape);
  }

  /// System Back while a video is fullscreen leaves fullscreen and stops there.
  Future<void> _exitFullscreen() async {
    final ok = await _session.send(const BridgeCommand.exitFullscreen());
    // The page could not leave it (no bridge, or nothing it knows as
    // fullscreen): drop our fullscreen state so Back is never stuck.
    if (!ok) _onFullscreen(false);
  }

  void _onRendererGone() => _startFreshWebView();

  /// Settings → Online → Block ads changed. The page script and the
  /// WebView's request rules are fixed when a WebView starts, so a fresh one
  /// opens the same page with the new choice (like a reload).
  void _onBlockAdsChanged() {
    DiagnosticsService.instance.logEvent('online_block_ads_reload');
    _startFreshWebView();
  }

  /// A new WebView on the page on screen (or where the tab started, when
  /// that is not a YouTube page): the old one and its video go away.
  void _startFreshWebView() {
    if (!mounted) return;
    _controller = null;
    _session.detachPage();
    setState(() {
      _initialUrl = (_url != null && isYouTubePage(_url!)) ? _url! : _initialUrl;
      _generation++;
      _loading = true;
      _error = null;
    });
  }

  Future<void> _refreshHistory() async {
    final c = _controller;
    if (c == null) return;
    try {
      final back = await c.canGoBack();
      final forward = await c.canGoForward();
      if (mounted && (back != _canGoBack || forward != _canGoForward)) {
        setState(() {
          _canGoBack = back;
          _canGoForward = forward;
        });
      }
    } catch (_) {}
  }

  /// Re-sends the toggles after every new document (the script starts fresh)
  /// and asks the page what is playing now, so a video that went away with
  /// the old document does not stay "playing" in the notification.
  void _pushPageSettings() {
    final background = ref.read(onlineBackgroundPlayProvider);
    final autoPip = ref.read(onlineAutoPipProvider);
    _session.send(BridgeCommand.setBackgroundPlay(background));
    _session.send(BridgeCommand.setAutoPip(autoPip));
    if (_pipLayout) _session.send(const BridgeCommand.setPipLayout(true));
    _session.send(const BridgeCommand.requestState());
  }

  // --- media session / picture-in-picture -----------------------------------

  void _onMediaChanged() {
    _updatePipEligibility();
    final media = _session.media.value;
    // iOS: have the audio stream ready before the app leaves the screen.
    if (media != null && media.isPlaying) _handoff.prefetch(media.videoId);
  }

  /// Android: the system may enter picture-in-picture by itself when the user
  /// leaves the app, while a video plays on this (visible) tab and Auto PiP is on.
  void _updatePipEligibility() {
    if (!PlatformInfo.isAndroid) return;
    final media = _session.media.value;
    final eligible = mounted &&
        _visible &&
        ref.read(onlineAutoPipProvider) &&
        _error == null &&
        isYouTubeVideoPage(_url) &&
        (media?.isPlaying ?? false);
    DeviceControls.setPipEligible(
      eligible,
      owner: DeviceControls.pipOwnerOnline,
      aspect: media?.aspectRatio ?? 16 / 9,
    );
  }

  void _onPipChanged() {
    final inPip = DeviceControls.inPip.value;
    final ours = inPip && DeviceControls.pipOwner.value == DeviceControls.pipOwnerOnline;
    if (inPip) _lastPipWasOurs = ours;
    if (ours != _pipLayout) {
      _pipLayout = ours;
      _session.send(BridgeCommand.setPipLayout(ours));
    }
    if (!inPip) _updatePipEligibility(); // a manual PiP claim ends with the window
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && PlatformInfo.isIOS && _shouldAutoPip() && !_reachedHidden) {
      // iOS: the browser's own picture-in-picture is the way a video keeps
      // showing (and playing) once the app leaves the screen.
      _autoPipOnInactive = true;
      _handoff.pipRequested();
      _session.send(const BridgeCommand.enterPip());
    }
    // The hand-off first: it decides whether the page is paused on purpose
    // before the session considers undoing a pause.
    _handoff.lifecycleChanged(state);
    _session.appLifecycleChanged(state);
    switch (state) {
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
        _reachedHidden = true;
      case AppLifecycleState.paused:
        _reachedHidden = true;
        final inPip = DeviceControls.inPip.value || _session.browserPipActive.value;
        if (!ref.read(onlineBackgroundPlayProvider) && !inPip) {
          _session.send(const BridgeCommand.pause());
        }
      case AppLifecycleState.resumed:
        // A picture-in-picture that Control Center started, while the app
        // never left the screen, closes again.
        if (_autoPipOnInactive && !_reachedHidden && PlatformInfo.isIOS) {
          _session.send(const BridgeCommand.exitPip());
        }
        _autoPipOnInactive = false;
        _reachedHidden = false;
        _session.send(const BridgeCommand.requestState());
        _updatePipEligibility();
      case AppLifecycleState.detached:
        break;
    }
  }

  bool _shouldAutoPip() =>
      _visible &&
      ref.read(onlineAutoPipProvider) &&
      isYouTubeVideoPage(_url) &&
      (_session.media.value?.isPlaying ?? false);

  // --- actions --------------------------------------------------------------

  void _snack(String text, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _copyLink() async {
    final link = canonicalYouTubeLink(_url);
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    HapticFeedback.selectionClick();
    DiagnosticsService.instance.logEvent('online_link_copied');
    if (!mounted) return;
    // Android 13+ confirms clipboard writes itself.
    final sdk = ref.read(androidSdkIntProvider).value;
    if (PlatformInfo.isAndroid && (sdk ?? 0) >= 33) return;
    _snack('Link copied');
  }

  /// The media title only when it belongs to the video on screen: after a
  /// move from video A to B the last report may still be A's.
  String _videoTitle() {
    final media = _currentMedia();
    final title = media?.title;
    return (title != null && title.isNotEmpty) ? title : addressLabel(title: _title, url: _url);
  }

  /// The page's last report, if it is about the video on screen.
  OnlineMediaState? _currentMedia() {
    final media = _session.media.value;
    final videoId = youTubeVideoId(_url);
    return (media != null && videoId != null && media.videoId == videoId) ? media : null;
  }

  void _download() {
    final link = canonicalYouTubeLink(_url);
    if (link == null) return;
    final pageTitle = _videoTitle();
    ref.read(downloadLinkInboxProvider.notifier).send(PendingDownloadLink(link, title: pageTitle, inspect: true));
    DiagnosticsService.instance.logEvent('online_sent_to_downloads');
    _snack('Sent to Downloads');
    GoRouter.maybeOf(context)?.go('/downloads');
  }

  /// Save: Like or add the video to a playlist (the library's own media
  /// sheet, which knows online items).
  Future<void> _save() async {
    final link = canonicalYouTubeLink(_url);
    final videoId = youTubeVideoId(_url);
    if (link == null || videoId == null) return;
    final media = _currentMedia();
    final item = domain.MediaItem(
      id: 'yt_$videoId',
      uri: link,
      mediaType: domain.MediaType.audio,
      title: _videoTitle(),
      artist: (media?.artist.isNotEmpty ?? false) ? media!.artist : null,
      album: 'YouTube',
      durationMs: media?.duration?.inMilliseconds ?? 0,
      sizeBytes: 0,
      dateAdded: DateTime.now(),
      source: 'online',
      artworkPath: media?.artworkUrl ?? youTubeThumbnailFor(videoId),
    );
    DiagnosticsService.instance.logEvent('online_save_opened');
    await ref.read(onlineSaveSheetProvider)(context, ref, item);
  }

  Future<void> _enterPip() async {
    if (PlatformInfo.isAndroid) {
      final aspect = _session.media.value?.aspectRatio ?? 16 / 9;
      await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline, aspect: aspect);
      final ok = await DeviceControls.enterPip();
      if (!ok) {
        _updatePipEligibility();
        if (!mounted) return;
        _snack(
          'Picture-in-picture is off',
          action: SnackBarAction(label: 'Settings', onPressed: _openAppSettings),
        );
      }
      return;
    }
    final ok = await _session.send(const BridgeCommand.enterPip());
    if (!ok && mounted) _snack('Picture-in-picture is not available for this video');
  }

  Future<void> _openAppSettings() async {
    try {
      await ref.read(mediaPermissionServiceProvider).openSettings();
    } catch (_) {}
  }

  void _setBackgroundPlay(bool on) {
    ref.read(onlineBackgroundPlayProvider.notifier).set(on);
  }

  void _setAutoPip(bool on) {
    ref.read(onlineAutoPipProvider.notifier).set(on);
  }

  Future<void> _reloadOrStop() async {
    final c = _controller;
    if (c == null) return;
    if (_loading) {
      await c.stopLoading();
      if (mounted) setState(() => _loading = false);
    } else {
      await c.reload();
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final c = _controller;
    if (c == null) return;
    if (_url == null) {
      await c.loadUrl(_initialUrl);
    } else {
      await c.reload();
    }
  }

  /// Our own search sheet. The query is submitted inside the page (YouTube's
  /// single-page app keeps its mini player playing); only when the page has
  /// no search field to use is the results page loaded instead.
  Future<void> _openSearch() async {
    final query = await showModalBottomSheet<String>(
      // Over the Ink Dock: the sheet's barrier covers and dims it too.
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _SearchSheet(),
    );
    final q = query?.trim() ?? '';
    if (q.isEmpty || !mounted) return;
    // A YouTube link typed or pasted in opens that page; other links and
    // words are searched as before.
    final page = youTubePageFromTyped(q);
    if (page != null) {
      await _controller?.loadUrl(page);
      return;
    }
    final inPage = await _session.send(BridgeCommand.search(q));
    if (inPage || !mounted) return;
    await _controller?.loadUrl(youTubeSearchUri(q));
  }

  /// Another screen asked for [uri] (a saved online song, say).
  void _openRequested(Uri uri) {
    final c = _controller;
    if (c != null) {
      c.loadUrl(uri);
    } else {
      setState(() => _initialUrl = uri);
    }
    Future.microtask(() {
      if (mounted) ref.read(onlineOpenRequestProvider.notifier).clear();
    });
  }

  /// Google's sign-in for YouTube, in the tab; it comes back to this page
  /// (or YouTube's home) when done. Google may still refuse a sign-in inside
  /// an app: its own page then says so.
  void _openSignIn() {
    DiagnosticsService.instance.logEvent('online_sign_in_opened');
    _controller?.loadUrl(youTubeSignInUri(returnTo: _url));
  }

  Future<void> _confirmClearData() async {
    final ok = await confirmClearYouTubeData(context);
    if (!ok || !mounted) return;
    await ref.read(onlineDataClearerProvider)();
    if (!mounted) return;
    _snack('YouTube data cleared');
    await _controller?.loadUrl(_initialUrl);
  }

  Future<void> _openMenu() async {
    await showModalBottomSheet<void>(
      // Over the Ink Dock: the sheet's barrier covers and dims it too.
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      // As tall as its rows (it still scrolls on a short screen), so Clear
      // site data at the bottom is in view on a phone.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _OnlineMenuSheet(
        onReload: () {
          Navigator.of(sheetContext).pop();
          _controller?.reload();
        },
        onYouTubeMusic: () {
          Navigator.of(sheetContext).pop();
          _controller?.loadUrl(Uri.parse(youTubeMusicHomeUrl));
        },
        onSignIn: () {
          Navigator.of(sheetContext).pop();
          _openSignIn();
        },
        onOpenDownloads: PlatformInfo.supportsDownloads
            ? () {
                Navigator.of(sheetContext).pop();
                GoRouter.maybeOf(context)?.go('/downloads');
              }
            : null,
        onClearData: () {
          Navigator.of(sheetContext).pop();
          _confirmClearData();
        },
      ),
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(onlineBackgroundPlayProvider, (previous, next) {
      _session.backgroundPlay = next;
      _session.send(BridgeCommand.setBackgroundPlay(next));
      _controller?.setBackgroundAudioAllowed(next);
    });
    ref.listen<Uri?>(onlineOpenRequestProvider, (previous, next) {
      if (next != null) _openRequested(next);
    });
    ref.listen<bool>(onlineAutoPipProvider, (previous, next) {
      _session.send(BridgeCommand.setAutoPip(next));
      _updatePipEligibility();
    });
    ref.listen<bool>(onlineBlockAdsProvider, (previous, next) {
      if (previous != next) _onBlockAdsChanged();
    });

    final assets = ref.watch(onlineAssetsProvider);
    ref.watch(androidSdkIntProvider); // warm: "Copy link" reads it synchronously
    final inPip = DeviceControls.inPip.value;
    final showChrome = !inPip && !_fullscreen;
    final isVideoPage = isYouTubeVideoPage(_url);
    final p = context.palette;

    final Widget web = assets.when(
      data: (a) => _buildWebView(context, a),
      loading: () => const SizedBox.expand(),
      error: (e, _) => EmptyHint(
        icon: Icons.error_outline_rounded,
        title: 'Online is unavailable',
        message: 'MediaHub could not start the YouTube page.',
        action: FilledButton(
          onPressed: () => ref.invalidate(onlineAssetsProvider),
          child: const Text('Retry'),
        ),
      ),
    );

    return PopScope(
      // System back leaves a fullscreen video first, then walks back
      // through YouTube's own history.
      canPop: !_canGoBack && !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_fullscreen) {
          _exitFullscreen();
        } else if (_canGoBack) {
          _controller?.goBack();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // The status bar sits on the toolbar, which is the canvas colour.
        value: AppTheme.barsFor(p),
        child: Material(
          color: p.background,
          child: Column(
            children: [
              if (showChrome)
                _Toolbar(
                  collapsed: _collapsed,
                  row1: _buildRow1(context),
                  strip: isVideoPage ? _buildWatchStrip(context) : null,
                ),
              // 2 dp load line under the toolbar (no track).
              SizedBox(
                height: 2,
                child: showChrome && _loading
                    ? LinearProgressIndicator(
                        key: const ValueKey('online_load_line'),
                        minHeight: 2,
                        value: _progress > 0 && _progress < 100 ? _progress / 100 : null,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(p.primary),
                        semanticsLabel: 'Loading page',
                      )
                    : null,
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Under the page's last few pixels: the dock's ink. The
                    // WebView is sized to whole device pixels, so a sliver
                    // of the light canvas used to show above the dock.
                    //
                    // Every child here is keyed: the seam comes and goes
                    // with the chrome (picture-in-picture, fullscreen), and
                    // an unkeyed list would hand the WebView's slot to the
                    // seam and build a fresh WebView (black PiP window, the
                    // watch page lost).
                    if (showChrome)
                      Positioned(
                        key: const ValueKey('online_dock_seam_slot'),
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: onlinePageSeamHeight,
                        child: ColoredBox(
                          key: const ValueKey('online_dock_seam'),
                          color: InkTheme.paletteOf(context).dock.withValues(alpha: 1),
                        ),
                      ),
                    // Clipped to its own box: the page ends above the dock
                    // and never paints into the dock's corner area.
                    Positioned.fill(
                      key: const ValueKey('online_web_slot'),
                      child: KeyedSubtree(key: _webSubtreeKey, child: ClipRect(child: web)),
                    ),
                    if (_error != null)
                      Positioned.fill(
                        key: const ValueKey('online_error_slot'),
                        child: ColoredBox(
                          color: p.background,
                          child: EmptyHint(
                            key: const ValueKey('online_error'),
                            icon: _error!.secureConnectionBlocked
                                ? Icons.gpp_bad_rounded
                                : _error!.offline
                                    ? Icons.wifi_off_rounded
                                    : Icons.cloud_off_rounded,
                            title: _error!.secureConnectionBlocked
                                ? "Can't connect securely"
                                : _error!.offline
                                    ? "You're offline"
                                    : "Couldn't load YouTube",
                            message: _error!.secureConnectionBlocked
                                ? onlineSecureConnectionBlockedMessage
                                : _error!.mobileDataOff
                                    ? 'Mobile data is off for MediaHub. Turn it on in Settings, or use Wi-Fi.'
                                    : _error!.offline
                                        ? 'Connect to the internet to browse YouTube.'
                                        : 'Something went wrong while opening the page.',
                            action: FilledButton(onPressed: _retry, child: const Text('Retry')),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext context, OnlineAssets assets) {
    final builder = ref.read(onlineWebViewBuilderProvider);
    final blockAds = ref.read(onlineBlockAdsProvider);
    final config = OnlineWebViewConfig(
      bridgeScript: buildBridgeScript(assets.bridgeSource, _token, blockAds: blockAds),
      backgroundPlay: ref.read(onlineBackgroundPlayProvider),
      initialUrl: _initialUrl,
      blockAds: blockAds,
      fixtureHtml: assets.fixtureHtml,
    );
    final events = OnlineWebEvents(
      onCreated: _onCreated,
      onUrlChanged: _onUrlChanged,
      onTitleChanged: _onTitle,
      onProgress: _onProgress,
      onLoadStart: _onLoadStart,
      onLoadStop: _onLoadStop,
      onMainFrameError: _onError,
      onScrollY: _onScrollY,
      onBridgeMessage: _onBridgeMessage,
      openExternally: ref.read(onlineExternalLauncherProvider),
      onFullscreenChanged: _onWebViewFullscreen,
      onRendererGone: _onRendererGone,
    );
    return KeyedSubtree(
      key: ValueKey('online_webview_$_generation'),
      child: builder(context, config, events),
    );
  }

  Widget _buildRow1(BuildContext context) {
    final label = addressLabel(title: _title, url: _url);
    return SizedBox(
      height: _row1Height,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.xs4),
          IconButton(
            key: const ValueKey('online_back'),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: _canGoBack ? () => _controller?.goBack() : null,
          ),
          IconButton(
            key: const ValueKey('online_forward'),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'Forward',
            onPressed: _canGoForward ? () => _controller?.goForward() : null,
          ),
          Expanded(child: _AddressPill(label: label, onTap: _openSearch)),
          IconButton(
            key: const ValueKey('online_reload'),
            icon: Icon(_loading ? Icons.close_rounded : Icons.refresh_rounded),
            tooltip: _loading ? 'Stop loading' : 'Reload',
            onPressed: _controller == null ? null : _reloadOrStop,
          ),
          IconButton(
            key: const ValueKey('online_menu'),
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More options',
            onPressed: _openMenu,
          ),
          const SizedBox(width: AppSpacing.xs4),
        ],
      ),
    );
  }

  Widget _buildWatchStrip(BuildContext context) {
    final background = ref.watch(onlineBackgroundPlayProvider);
    final autoPip = ref.watch(onlineAutoPipProvider);
    // Picture-in-picture, Save and Copy link are round icon buttons (their
    // names in the tooltip and for screen readers), so Download, PiP and
    // Background play, what this tab is for, stay in view on a 360 dp phone.
    Widget iconAction(String key, IconData icon, String label, VoidCallback onPressed) => Semantics(
          label: label,
          button: true,
          excludeSemantics: true,
          onTap: onPressed,
          child: Tooltip(
            message: label,
            child: OutlinedButton(
              key: ValueKey(key),
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: Icon(icon, size: 20),
            ),
          ),
        );
    final items = <Widget>[
      if (PlatformInfo.supportsDownloads)
        VoltButton.compact(
          key: const ValueKey('online_download'),
          label: 'Download',
          icon: Icons.download_rounded,
          onPressed: _download,
        ),
      iconAction('online_pip', Icons.picture_in_picture_alt_rounded, 'Picture-in-picture', _enterPip),
      FilterChip(
        key: const ValueKey('online_background_chip'),
        // Short on screen; read and shown in full ("Background play").
        label: const Text('Background', semanticsLabel: 'Background play'),
        tooltip: 'Background play: keeps playing with the screen off',
        selected: background,
        onSelected: _setBackgroundPlay,
      ),
      iconAction('online_save', Icons.library_add_rounded, 'Save to Favourites or a playlist', _save),
      iconAction('online_copy_link', Icons.link_rounded, 'Copy link', _copyLink),
      FilterChip(
        key: const ValueKey('online_autopip_chip'),
        label: const Text('Auto PiP'),
        selected: autoPip,
        onSelected: _setAutoPip,
      ),
    ];
    return SizedBox(
      key: const ValueKey('online_watch_strip'),
      height: _stripHeight,
      child: ShaderMask(
        // A 24 dp fade at the end hints that the strip scrolls.
        shaderCallback: (rect) {
          final stop = rect.width <= 0 ? 1.0 : (1 - 24 / rect.width).clamp(0.0, 1.0);
          return LinearGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: [0, stop, 1],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // 52 - 2 x 2 = 48 dp across: the 40 dp buttons and chips keep their
          // full 48 dp tap targets (DESIGN.md 7.1).
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: 2),
          itemCount: items.length,
          // 4 dp between the 48 dp targets: the round buttons and chips sit
          // inside theirs, so the visible gaps stay about 8 dp.
          separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.xs4),
          itemBuilder: (context, index) => Center(child: items[index]),
        ),
      ),
    );
  }
}

/// Status-bar inset, then the two toolbar rows; both rows collapse together.
/// Solid ink in the dark theme, glass paper in the light one (DESIGN.md 7.13),
/// with a 1 dp divider along the bottom in both.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.collapsed, required this.row1, required this.strip});

  final bool collapsed;
  final Widget row1;
  final Widget? strip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final edge = Border(bottom: BorderSide(color: p.divider));
    final rows = _rows(context);
    if (!p.isDark) {
      return GlassContainer(key: const ValueKey('online_toolbar'), blur: 24, border: edge, child: rows);
    }
    return DecoratedBox(
      key: const ValueKey('online_toolbar'),
      decoration: BoxDecoration(color: p.background, border: edge),
      child: rows,
    );
  }

  Widget _rows(BuildContext context) {
    final duration = MotionTokens.duration(context, MotionTokens.page);
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: ClipRect(
        child: AnimatedAlign(
          duration: duration,
          curve: MotionTokens.easeOut,
          alignment: Alignment.bottomCenter,
          heightFactor: collapsed ? 0 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row1,
              AnimatedSize(
                duration: duration,
                curve: MotionTokens.easeOut,
                alignment: Alignment.topCenter,
                child: strip ?? const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressPill extends StatelessWidget {
  const _AddressPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Search YouTube',
      value: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const ValueKey('online_address'),
        // Dark: a raised ink pill; light: white with a 1 dp outline.
        color: p.isDark ? p.surfaceElevated : Colors.white,
        shape: StadiumBorder(side: p.isDark ? BorderSide.none : BorderSide(color: p.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: p.textSecondary),
                  const SizedBox(width: AppSpacing.sm8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.metadata.copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Our own search box, used when the page's search field cannot be focused.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet();

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        0,
        AppSpacing.lg16,
        AppSpacing.lg16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: TextField(
        key: const ValueKey('online_search_field'),
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.search,
        // What is typed is what is searched: no curly quotes or long dashes
        // from the iPhone keyboard, no romanised Nepali word 'corrected'.
        autocorrect: false,
        smartQuotesType: SmartQuotesType.disabled,
        smartDashesType: SmartDashesType.disabled,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Search YouTube',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'Search',
            onPressed: _submit,
          ),
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
        ),
      ),
    );
  }
}

/// The ⋮ sheet: Reload · YouTube Music · Sign in to YouTube · Open Downloads ·
/// Background play · Auto PiP · Block ads · Clear site data.
class _OnlineMenuSheet extends ConsumerWidget {
  const _OnlineMenuSheet({
    required this.onReload,
    required this.onYouTubeMusic,
    required this.onSignIn,
    required this.onOpenDownloads,
    required this.onClearData,
  });

  final VoidCallback onReload;
  final VoidCallback onYouTubeMusic;
  final VoidCallback onSignIn;
  final VoidCallback? onOpenDownloads;
  final VoidCallback onClearData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(onlineBackgroundPlayProvider);
    final autoPip = ref.watch(onlineAutoPipProvider);
    final blockAds = ref.watch(onlineBlockAdsProvider);
    final p = context.palette;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Reload'),
              onTap: onReload,
            ),
            ListTile(
              key: const ValueKey('online_menu_music'),
              leading: const Icon(Icons.library_music_rounded),
              title: const Text('YouTube Music'),
              onTap: onYouTubeMusic,
            ),
            ListTile(
              key: const ValueKey('online_menu_sign_in'),
              leading: const Icon(Icons.account_circle_rounded),
              title: const Text('Sign in to YouTube'),
              onTap: onSignIn,
            ),
            if (onOpenDownloads != null)
              ListTile(
                leading: const Icon(Icons.file_download_rounded),
                title: const Text('Open Downloads'),
                onTap: onOpenDownloads,
              ),
            SwitchListTile(
              key: const ValueKey('online_menu_background'),
              secondary: const Icon(Icons.headphones_rounded),
              title: const Text('Background play'),
              value: background,
              onChanged: (v) => ref.read(onlineBackgroundPlayProvider.notifier).set(v),
            ),
            SwitchListTile(
              key: const ValueKey('online_menu_autopip'),
              secondary: const Icon(Icons.picture_in_picture_alt_rounded),
              title: const Text('Auto picture-in-picture'),
              value: autoPip,
              onChanged: (v) => ref.read(onlineAutoPipProvider.notifier).set(v),
            ),
            // A change opens the page again (the tab says so by reloading).
            SwitchListTile(
              key: const ValueKey('online_menu_block_ads'),
              secondary: const Icon(Icons.block_rounded),
              title: const Text(onlineBlockAdsTitle),
              value: blockAds,
              onChanged: (v) => ref.read(onlineBlockAdsProvider.notifier).set(v),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('online_menu_clear'),
              leading: Icon(Icons.delete_sweep_rounded, color: p.error),
              title: Text('Clear site data', style: context.typography.body.copyWith(color: p.error)),
              onTap: onClearData,
            ),
          ],
        ),
      ),
    );
  }
}

/// What "Clear YouTube data" removes, in the words of the confirm dialog.
/// The cookies hold the sign-in, so it signs you out too. iOS clears
/// WebKit's whole data store for the page (see clearInAppWebViewData), which
/// includes the saved site data.
String clearYouTubeDataDetails() => PlatformInfo.isIOS
    ? "Signs you out and forgets YouTube's cookies, cache and saved site data on this iPhone. "
        'Your downloads and library stay.'
    : "Signs you out and forgets YouTube's cookies, cache and site settings on this phone. "
        'Your downloads and library stay.';

/// "Clear YouTube data?" confirm dialog (also used by Settings → Online).
Future<bool> confirmClearYouTubeData(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear YouTube data?'),
      content: Text(clearYouTubeDataDetails()),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          key: const ValueKey('online_clear_confirm'),
          style: TextButton.styleFrom(foregroundColor: context.palette.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
