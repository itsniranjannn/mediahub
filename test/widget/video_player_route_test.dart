// iOS parity: the '/video_player' page and the iOS back-swipe.
//
// On iOS the Cupertino page transition lays a back-swipe strip along the
// left edge of a normal page, and its drag wins over the player's own
// horizontal seek swipe: a seek that started there would close the video.
// lib/app/router.dart pins the player on iOS to a page with no transition,
// which has no back-swipe. Android keeps the page go_router builds for every
// other screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/router.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/domain/repositories/video_engine.dart';
import 'package:mediahub/domain/repositories/video_progress_repository.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/video_player_screen.dart';

/// A five-minute video that is playing, and records the seeks it is asked for.
class _Engine implements VideoEngine {
  final List<Duration> seeks = [];
  bool _init = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  final _pos = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _err = StreamController<String?>.broadcast();

  @override
  Future<void> initialize(String uri) async => _init = true;
  @override
  Future<void> play() async {
    _playing = true;
    _playingCtl.add(true);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playingCtl.add(false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    _position = position;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {}
  @override
  Future<void> dispose() async {
    await _pos.close();
    await _playingCtl.close();
    await _err.close();
  }

  @override
  Duration get position => _position;
  @override
  Duration get duration => const Duration(minutes: 5);
  @override
  bool get isPlaying => _playing;
  @override
  bool get isInitialized => _init;
  @override
  Size get videoSize => const Size(1920, 1080);
  @override
  double get aspectRatio => 16 / 9;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<bool> get isPlayingStream => _playingCtl.stream;
  @override
  Stream<String?> get errorStream => _err.stream;
  @override
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain}) => const SizedBox.expand(key: ValueKey('video-surface'));
}

class _Progress implements VideoProgressRepository {
  @override
  Future<VideoProgress?> getProgress(String mediaId) async => null;
  @override
  Future<void> saveProgress(VideoProgress progress) async {}
  @override
  Future<void> deleteProgress(String mediaId) async {}
  @override
  Future<List<VideoProgress>> getAllProgress() async => [];
  @override
  Stream<List<VideoProgress>> watchAllProgress() => Stream.value([]);
}

class _Library implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> updateAvailability(String id, MediaAvailability availability) async {}
}

class _Host implements ExternalPlaybackHost {
  @override
  void setExternalSource(ExternalPlaybackDelegate d, ExternalMediaSnapshot s) {}
  @override
  void updateExternalMedia(ExternalPlaybackDelegate d, ExternalMediaSnapshot s) {}
  @override
  void clearExternalSource(ExternalPlaybackDelegate d) {}
}

final _item = MediaItem(
  id: 'vid-1',
  title: 'Clip',
  artist: 'Unknown',
  durationMs: 300000,
  uri: 'file:///var/mobile/Containers/Data/Application/x/Documents/Clip.mp4',
  mediaType: MediaType.video,
  sizeBytes: 1024,
  dateAdded: DateTime(2026, 1, 1),
);

void _installPlatform() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('mediahub/device_controls'), (call) async => true);
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
  );
}

void _uninstallPlatform() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('mediahub/device_controls'), null);
  messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  messenger.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle', null);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Home, then the player opened the way the app does: push('/video_player').
Future<_Engine> _openPlayer(WidgetTester tester) async {
  final engine = _Engine();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Center(child: Text('HOME')))),
      videoPlayerRoute(),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      videoEngineProvider.overrideWith((ref) {
        ref.onDispose(engine.dispose);
        return engine;
      }),
      videoProgressRepositoryProvider.overrideWithValue(_Progress()),
      libraryRepositoryProvider.overrideWithValue(_Library()),
      videoMediaHostProvider.overrideWithValue(_Host()),
    ],
    child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  unawaited(router.push('/video_player', extra: _item));
  await _settle(tester);
  await tester.pump(const Duration(seconds: 1)); // the page transition
  await _settle(tester);
  return engine;
}

PageRoute<dynamic> _playerRoute(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(VideoPlayerScreen)))! as PageRoute<dynamic>;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// The iOS back-swipe strip (Flutter's private _CupertinoBackGestureDetector).
final Finder _backSwipe = find.byWidgetPredicate(
  (w) => w.runtimeType.toString().startsWith('_CupertinoBackGestureDetector'),
  description: 'the iOS back-swipe strip',
);

void main() {
  setUp(() {
    DiagnosticsService.enableDebounce = false;
    DeviceControls.resetPipForTests();
    _installPlatform();
  });

  tearDown(() {
    _uninstallPlatform();
    PlatformInfo.resetForTests();
    DeviceControls.resetPipForTests();
  });

  testWidgets('iOS: a seek swipe that starts at the left edge seeks; there is no back-swipe to take it', (tester) async {
    PlatformInfo.debugIsIOS = true;
    final engine = await _openPlayer(tester);
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(_playerRoute(tester).settings, isA<NoTransitionPage<void>>());
    expect(_backSwipe, findsNothing);

    // 6 pt from the edge: inside the 20 pt strip a back-swipe would own.
    await tester.dragFrom(const Offset(6, 300), const Offset(500, 0));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    expect(find.byType(VideoPlayerScreen), findsOneWidget, reason: 'the video is still open');
    expect(find.text('HOME'), findsNothing);
    expect(engine.seeks, isNotEmpty, reason: 'the swipe seeked');
    expect(engine.seeks.last, greaterThan(Duration.zero));

    await _close(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets("iOS: a normal page under the app's theme has the strip (what the player must not get)", (tester) async {
    // The theme's iOS transition is Cupertino's: any MaterialPage gets the
    // back-swipe. This is what a go_router update that finds the app's
    // MaterialApp would give every `builder` route.
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: const Text('HOME')));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('PAGE')))));
    await tester.pumpAndSettle();
    expect(_backSwipe, findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('the iOS page builder: no transition, the player inside, the route state passed on', (tester) async {
    PlatformInfo.debugIsIOS = true;
    final page = videoPlayerRoute().pageBuilder!;
    late Page<void> built;
    final router = GoRouter(
      initialLocation: '/video_player',
      routes: [
        GoRoute(
          path: '/video_player',
          pageBuilder: (context, state) => built = page(context, state) as Page<void>,
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(built, isA<NoTransitionPage<void>>());
    expect(built.name, '/video_player');
    final noTransition = built as NoTransitionPage<void>;
    expect(noTransition.transitionDuration, Duration.zero);
    expect(noTransition.reverseTransitionDuration, Duration.zero);
    expect(noTransition.fullscreenDialog, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android keeps its page: the one go_router builds for every other screen', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    await _openPlayer(tester);
    final route = _playerRoute(tester);
    expect(route.fullscreenDialog, isFalse);
    // Home is a plain `builder` route too: both pages are of one kind.
    final home = ModalRoute.of(tester.element(find.text('HOME', skipOffstage: false)))!;
    expect(route.settings.runtimeType, home.settings.runtimeType);
    await _close(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('the route is built per platform: a page builder on iOS only', () {
    PlatformInfo.debugIsIOS = true;
    final ios = videoPlayerRoute();
    expect(ios.pageBuilder, isNotNull);
    expect(ios.builder, isNull);
    expect(ios.path, '/video_player');
    PlatformInfo.resetForTests();
    PlatformInfo.debugIsAndroid = true;
    final android = videoPlayerRoute();
    expect(android.pageBuilder, isNull);
    expect(android.builder, videoPlayerRouteBuilder);
    expect(android.path, '/video_player');
  });
}
