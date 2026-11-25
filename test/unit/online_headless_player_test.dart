import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/online/online_bridge_protocol.dart';
import 'package:mediahub/features/online/online_headless_player.dart';
import 'package:mediahub/features/online/online_media_session.dart';
import 'package:mediahub/features/online/online_screen.dart' show OnlineAssets;
import 'package:mediahub/features/online/online_web_view.dart';

const String _token = '0123456789abcdef0123456789abcdef';
const String _url = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ';

class _Host implements ExternalPlaybackHost {
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
    last = snapshot;
  }

  @override
  void clearExternalSource(ExternalPlaybackDelegate delegate) {
    if (!identical(active, delegate)) return;
    log.add('clear');
    active = null;
  }
}

class _Page implements OnlineHeadlessPage {
  final List<String> scripts = [];
  bool disposed = false;

  @override
  Future<Object?> evaluateJavascript(String source) async {
    scripts.add(source);
    return true;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

ExternalResumeItem _item({Duration position = const Duration(seconds: 95)}) => ExternalResumeItem(
      id: 'online:dQw4w9WgXcQ',
      pageUrl: Uri.parse(_url),
      title: 'A video',
      artist: 'A channel',
      position: position,
      duration: const Duration(minutes: 4),
    );

Map<String, Object?> _media(String status, double pos, {String e = 'timeupdate'}) =>
    {'t': _token, 'u': _url, 'k': 'media', 's': status, 'p': pos, 'd': 240, 'ti': 'A video', 'ar': 'A channel', 'e': e};

void main() {
  late _Host host;
  late OnlineMediaSession session;
  late _Page page;
  late OnlineHeadlessPlayer player;
  late void Function(Object? args) toDart;
  Uri? launchedUrl;
  String? launchedScript;
  var launches = 0;
  var failLaunch = false;

  setUp(() {
    host = _Host();
    session = OnlineMediaSession(host: host);
    page = _Page();
    launches = 0;
    failLaunch = false;
    player = OnlineHeadlessPlayer(
      session: session,
      newToken: () => _token,
      loadAssets: () async => const OnlineAssets(bridgeSource: 'bridge(__MEDIAHUB_BRIDGE_TOKEN__)'),
      launch: ({required url, required bridgeScript, fixtureHtml, required onBridgeMessage}) async {
        launches++;
        if (failLaunch) throw StateError('no WebView');
        launchedUrl = url;
        launchedScript = bridgeScript;
        toDart = onBridgeMessage;
        return page;
      },
    );
  });

  tearDown(() {
    player.dispose();
    session.dispose();
  });

  test('loads the saved video at its position, then seeks and plays it once the page is ready', () async {
    expect(await player.start(_item()), isTrue);
    expect(player.isActive, isTrue);
    expect(launchedUrl.toString(), '$_url&t=95s');
    expect(launchedScript, 'bridge($_token)');
    toDart([
      {'t': _token, 'u': _url, 'k': 'ready'}
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(page.scripts, [
      BridgeCommand.seekTo(const Duration(seconds: 95)).toJavaScript(),
      const BridgeCommand.play().toJavaScript(),
    ]);
  });

  test('its playing video takes the media session; the controls reach the page', () async {
    await player.start(_item());
    toDart([_media('playing', 95, e: 'play')]);
    expect(host.active, same(session));
    expect(host.last!.playing, isTrue);
    page.scripts.clear();
    await host.active!.externalPause();
    toDart([_media('paused', 97, e: 'pause')]);
    await host.active!.externalPlay();
    await host.active!.externalSkipToNext();
    expect(page.scripts, [
      const BridgeCommand.pause().toJavaScript(),
      const BridgeCommand.play().toJavaScript(),
      const BridgeCommand.next().toJavaScript(),
    ]);
    expect(host.log, isNot(contains('clear')));
  });

  test('messages with another token are ignored', () async {
    await player.start(_item());
    toDart([
      {..._media('playing', 1), 't': 'ffffffffffffffffffffffffffffffff'}
    ]);
    expect(host.active, isNull);
  });

  test('a second start while one runs does not open another page', () async {
    await player.start(_item());
    expect(await player.start(_item()), isTrue);
    expect(launches, 1);
  });

  test('hand-back: closes the page and gives its video and position to the Online tab', () async {
    await player.start(_item());
    toDart([_media('playing', 130, e: 'play')]);
    final back = player.handBack();
    expect(back, isNotNull);
    expect(back!.playing, isTrue);
    expect(back.url.queryParameters['v'], 'dQw4w9WgXcQ');
    expect(back.url.queryParameters['t'], '130s');
    expect(page.disposed, isTrue);
    expect(player.isActive, isFalse);
    expect(session.hasSender, isFalse);
    expect(host.active, same(session), reason: 'the notification stays on the video meanwhile');
    expect(player.handBack(), isNull);
  });

  test('a page that cannot be made: false, and nothing left attached', () async {
    failLaunch = true;
    expect(await player.start(_item()), isFalse);
    expect(player.isActive, isFalse);
    expect(session.hasSender, isFalse);
  });

  test('onlineUrlAt adds t= to a watch page only', () {
    expect(onlineUrlAt(Uri.parse(_url), const Duration(seconds: 61)).queryParameters['t'], '61s');
    expect(onlineUrlAt(Uri.parse(_url), const Duration(seconds: 1)).toString(), _url);
    expect(onlineUrlAt(Uri.parse('https://m.youtube.com/'), const Duration(minutes: 3)).toString(), 'https://m.youtube.com/');
  });
}
