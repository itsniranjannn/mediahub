import 'package:flutter/widgets.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/online/online_bridge_protocol.dart';
import 'package:mediahub/features/online/online_screen.dart';
import 'package:mediahub/features/online/online_web_view.dart';

/// Records what the Online screen asks of its WebView.
class FakeOnlineWebController implements OnlineWebController {
  final List<String> calls = [];
  final List<String> scripts = [];
  bool canBack = false;
  bool canForward = false;

  /// What evaluateJavascript returns (the bridge answers true when it ran a command).
  Object? scriptResult = true;

  @override
  Future<void> loadUrl(Uri url) async => calls.add('load $url');

  @override
  Future<void> goBack() async => calls.add('back');

  @override
  Future<void> goForward() async => calls.add('forward');

  @override
  Future<void> reload() async => calls.add('reload');

  @override
  Future<void> stopLoading() async => calls.add('stop');

  @override
  Future<bool> canGoBack() async => canBack;

  @override
  Future<bool> canGoForward() async => canForward;

  @override
  Future<Object?> evaluateJavascript(String source) async {
    scripts.add(source);
    return scriptResult;
  }

  @override
  Future<void> setBackgroundAudioAllowed(bool allowed) async => calls.add('bgAudio $allowed');

  /// Names of the bridge commands sent so far, e.g. ['setBackgroundPlay', 'pause'].
  List<String> get commands => scripts
      .map((s) => RegExp(r'b\.command\("([A-Za-z]+)"').firstMatch(s)?.group(1))
      .whereType<String>()
      .toList();
}

/// A stand-in for the platform WebView: hands the screen [controller] and
/// keeps the [events] so a test can play the page's part.
class FakeOnlineWebView {
  FakeOnlineWebView() : controller = FakeOnlineWebController();

  final FakeOnlineWebController controller;
  OnlineWebEvents? events;
  OnlineWebViewConfig? config;
  /// WebViews created (a rebuild of the screen does not create a new one).
  int mounts = 0;

  OnlineWebViewBuilder get builder => (context, config, events) {
        this.config = config;
        this.events = events;
        return _FakeWebSurface(onMount: () {
          mounts++;
          events.onCreated(controller);
        });
      };

  /// The token the screen injected into the bridge script.
  String get token => RegExp(r"var TOKEN = '([0-9a-f]+)'").firstMatch(config!.bridgeScript)!.group(1)!;

  /// The page navigated (YouTube's own SPA navigations land here too).
  void navigate(String url, {String? title}) {
    final uri = Uri.parse(url);
    events!.onLoadStart(uri);
    events!.onUrlChanged(uri);
    if (title != null) events!.onTitleChanged(title);
    events!.onProgress(100);
    events!.onLoadStop(uri);
  }

  /// The bridge posts a media message.
  void postMedia({
    String status = 'playing',
    String url = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
    String title = 'Never Gonna Give You Up',
    String artist = 'Rick Astley',
    double position = 12,
    double duration = 213,
    bool hasNext = true,
    String event = 'play',
    String? token,
  }) {
    events!.onBridgeMessage([
      {
        't': token ?? this.token,
        'k': 'media',
        'e': event,
        'u': url,
        's': status,
        'p': position,
        'd': duration,
        'r': 1,
        'ti': title,
        'ar': artist,
        'aw': '',
        'n': hasNext,
        'vw': 1280,
        'vh': 720,
      }
    ]);
  }
}

class _FakeWebSurface extends StatefulWidget {
  const _FakeWebSurface({required this.onMount});
  final VoidCallback onMount;

  @override
  State<_FakeWebSurface> createState() => _FakeWebSurfaceState();
}

class _FakeWebSurfaceState extends State<_FakeWebSurface> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: ValueKey('fake_webview'));
}

/// The bridge source without touching the asset bundle.
const OnlineAssets fakeOnlineAssets = OnlineAssets(
  bridgeSource: "(function(){var TOKEN = '$onlineBridgeTokenPlaceholder';"
      "var BLOCK_ADS = '$onlineBridgeBlockAdsPlaceholder' !== 'off';})();",
);

/// Stands in for the audio handler's external-source side.
class FakeExternalHost implements ExternalPlaybackHost {
  final List<String> log = [];
  ExternalPlaybackDelegate? active;
  ExternalMediaSnapshot? last;

  @override
  void setExternalSource(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    log.add('set');
    active = delegate;
    last = snapshot;
  }

  @override
  void updateExternalMedia(ExternalPlaybackDelegate delegate, ExternalMediaSnapshot snapshot) {
    if (!identical(active, delegate)) return;
    log.add('update');
    last = snapshot;
  }

  @override
  void clearExternalSource(ExternalPlaybackDelegate delegate) {
    if (!identical(active, delegate)) return;
    log.add('clear');
    active = null;
  }
}
