// Probe tests for the video player's controls (fix plan P3: VID-01..18).
// Each test drives the real screen and notifier with a scripted engine and
// mocked platform channels, and checks what reaches the platform.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/utils/formatters.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/domain/repositories/video_engine.dart';
import 'package:mediahub/domain/repositories/video_progress_repository.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/video_player_screen.dart';
import 'package:mediahub/features/video_player/video_queue.dart';

/// A scripted engine with every extra: records what the notifier asks.
class _Engine implements VideoEngine, VideoEngineExtras {
  _Engine({
    this.name = 'engine',
    this.size = const Size(1920, 1080),
    this.playerId = 7,
  });

  final String name;
  final Size size;
  final Duration length = const Duration(minutes: 5);
  final int playerId;
  final List<String> initializedWith = [];
  final List<Duration> seeks = [];
  final List<String?> subtitleFiles = [];
  int playCalls = 0;
  int pauseCalls = 0;
  bool disposed = false;
  BoxFit? lastFit;
  bool _playing = false;
  bool _init = false;
  Duration _position = Duration.zero;
  final _pos = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _err = StreamController<String?>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _captions = StreamController<String>.broadcast();

  void emitPosition(Duration p) {
    _position = p;
    _pos.add(p);
  }

  void complete() {
    _position = length;
    _pos.add(length);
    _playing = false;
    _playingCtl.add(false);
    _completed.add(null);
  }

  void emitCaption(String text) => _captions.add(text);

  /// The player blips "playing" and stops at the end again (and fires its
  /// end event once more), as ExoPlayer can after the end.
  void reportEndAgain() {
    _playingCtl.add(true);
    _pos.add(length);
    _playingCtl.add(false);
    _completed.add(null);
  }

  @override
  Future<void> initialize(String uri) async {
    initializedWith.add(uri);
    _init = true;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
    _playingCtl.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
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
    if (disposed) return;
    disposed = true;
    await _pos.close();
    await _playingCtl.close();
    await _err.close();
    await _completed.close();
    await _captions.close();
  }

  @override
  Duration get position => _position;
  @override
  Duration get duration => length;
  @override
  bool get isPlaying => _playing;
  @override
  bool get isInitialized => _init;
  @override
  Size get videoSize => size;
  @override
  double get aspectRatio => size.width / size.height;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<bool> get isPlayingStream => _playingCtl.stream;
  @override
  Stream<String?> get errorStream => _err.stream;

  @override
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain}) {
    lastFit = fit;
    return SizedBox.expand(key: ValueKey('surface-$name'));
  }

  // --- extras ---
  @override
  int? get platformPlayerId => _init ? playerId : null;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<String> get captionStream => _captions.stream;
  @override
  Future<bool> setSubtitleFile(String? path) async {
    subtitleFiles.add(path);
    return true;
  }

  @override
  Future<List<VideoAudioTrackInfo>> getAudioTracks() async => const [];
  @override
  Future<void> selectAudioTrack(String id) async {}
}

class _Progress implements VideoProgressRepository {
  final List<VideoProgress> saved = [];
  @override
  Future<VideoProgress?> getProgress(String mediaId) async => null;
  @override
  Future<void> saveProgress(VideoProgress progress) async => saved.add(progress);
  @override
  Future<void> deleteProgress(String mediaId) async {}
  @override
  Future<List<VideoProgress>> getAllProgress() async => saved;
  @override
  Stream<List<VideoProgress>> watchAllProgress() => Stream.value(saved);
}

class _Library implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> updateAvailability(String id, MediaAvailability availability) async {}
}

/// Records what the video tells the phone's media session.
class _Host implements ExternalPlaybackHost {
  final List<String> log = [];
  ExternalPlaybackDelegate? delegate;
  ExternalMediaSnapshot? last;

  @override
  void setExternalSource(ExternalPlaybackDelegate d, ExternalMediaSnapshot s) {
    log.add('set:${s.playing}');
    delegate = d;
    last = s;
  }

  @override
  void updateExternalMedia(ExternalPlaybackDelegate d, ExternalMediaSnapshot s) {
    log.add('update:${s.playing}');
    last = s;
  }

  @override
  void clearExternalSource(ExternalPlaybackDelegate d) {
    log.add('clear');
    delegate = null;
  }
}

MediaItem _video(String id, {String? uri}) => MediaItem(
      id: id,
      title: 'Clip_$id',
      artist: 'Unknown',
      durationMs: 300000,
      uri: uri ?? 'content://media/external/video/media/$id',
      mediaType: MediaType.video,
      sizeBytes: 1024,
      dateAdded: DateTime(2026, 1, 1),
    );

/// The platform side: device controls, orientation calls and wakelock.
class _Platform {
  double volume = 0.5;
  double brightness = 0.5;
  bool boostWorks = true;
  final List<MethodCall> device = [];
  final List<List<String>> orientations = [];

  Iterable<MethodCall> calls(String method) => device.where((c) => c.method == method);

  List<double> get volumeWrites => [for (final c in calls('setVolume')) ((c.arguments as Map)['value'] as num).toDouble()];

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('mediahub/device_controls'), (call) async {
      device.add(call);
      switch (call.method) {
        case 'getVolume':
          return volume;
        case 'getBrightness':
          return brightness;
        case 'setVolume':
          volume = ((call.arguments as Map)['value'] as num).toDouble();
          return true;
        case 'setVideoBoost':
          return boostWorks;
        case 'enterPip':
          return true;
        default:
          return true;
      }
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add([for (final o in call.arguments as List) o as String]);
      }
      return null;
    });
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  }

  void uninstall() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('mediahub/device_controls'), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      null,
    );
  }
}

class _Harness {
  _Harness(this.engines);
  final List<_Engine> engines;
  int created = 0;
  final progress = _Progress();
  final host = _Host();
  final handoffs = <(String, Duration)>[];

  VideoEngine create(Ref ref) {
    final e = engines[created++];
    ref.onDispose(() => e.dispose());
    return e;
  }
}

/// Opens the player from a plain page (so Back pops to it).
Future<void> _open(
  WidgetTester tester,
  _Harness h, {
  required MediaItem item,
  VideoQueue? queue,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoEngineProvider.overrideWith(h.create),
        videoProgressRepositoryProvider.overrideWithValue(h.progress),
        libraryRepositoryProvider.overrideWithValue(_Library()),
        videoMediaHostProvider.overrideWithValue(h.host),
        videoAudioHandoffProvider.overrideWithValue((item, position) async {
          h.handoffs.add((item.id, position));
        }),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(item: item, queue: queue)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

VideoPlayerControllerNotifier _notifierOf(WidgetTester tester, MediaItem item) {
  final container = ProviderScope.containerOf(tester.element(find.byType(VideoPlayerScreen)));
  return container.read(videoPlayerControllerProvider(item).notifier);
}

VideoPlaybackState _stateOf(WidgetTester tester, MediaItem item) {
  final container = ProviderScope.containerOf(tester.element(find.byType(VideoPlayerScreen)));
  return container.read(videoPlayerControllerProvider(item));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late _Platform platform;

  setUp(() {
    DiagnosticsService.enableDebounce = false;
    DeviceControls.resetPipForTests();
    PlatformInfo.debugIsAndroid = true;
    platform = _Platform()..install();
  });

  tearDown(() {
    platform.uninstall();
    PlatformInfo.resetForTests();
    DeviceControls.resetPipForTests();
  });

  group('VID-02 volume swipe follows the phone', () {
    testWidgets('a swipe starts from the volume the phone has now, not the one at opening', (tester) async {
      platform.volume = 0.9; // the player opens at 90 %
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);

      // The hardware keys take it to 20 % without the player hearing about it.
      platform.volume = 0.2;
      platform.device.clear();

      // Swipe up a little on the right half (volume).
      await tester.dragFrom(const Offset(700, 300), const Offset(0, -90));
      await tester.pump(const Duration(milliseconds: 200));

      expect(platform.calls('getVolume'), isNotEmpty, reason: 're-read at the swipe start');
      final writes = platform.volumeWrites;
      expect(writes, isNotEmpty);
      // From 20 % upwards; the stale 90 % would have jumped to ~100 %.
      expect(writes.every((v) => v > 0.2 && v < 0.6), isTrue, reason: '$writes');
      expect(find.textContaining('%'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('the volume keys show the same HUD, and the next swipe starts there', (tester) async {
      platform.volume = 0.5;
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);
      expect(platform.calls('watchVolume').last.arguments, {'on': true});

      await DeviceControls.handlePlatformCall(const MethodCall('volumeChanged', 0.4));
      await tester.pump();
      expect(find.text('40%'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('40%'), findsNothing);

      await _unmount(tester);
      expect(platform.calls('watchVolume').last.arguments, {'on': false}, reason: 'receiver off with the player');
    });
  });

  group('VID-01 volume raiser', () {
    testWidgets('past full volume the swipe boosts this video, shown as a warning "Boost" zone', (tester) async {
      platform.volume = 1.0;
      final item = _video('a');
      await _open(tester, _Harness([_Engine(playerId: 42)]), item: item);

      await tester.dragFrom(const Offset(700, 400), const Offset(0, -150));
      await tester.pump(const Duration(milliseconds: 200));

      final boosts = platform.calls('setVideoBoost').toList();
      expect(boosts, isNotEmpty);
      final last = boosts.last.arguments as Map;
      expect(last['playerId'], 42, reason: "the video's own player, never session 0 / the music player");
      expect(last['percent'] as int, inInclusiveRange(110, 200));
      expect(find.textContaining('Boost'), findsOneWidget);
      expect(_stateOf(tester, item).boostPercent, last['percent']);

      await _unmount(tester);
      // Back to 100 % when the player closes.
      expect(platform.calls('releaseVideoBoost'), isNotEmpty);
    });

    testWidgets("a late echo of the swipe's own volume writes does not undo the boost", (tester) async {
      platform.volume = 0.9;
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);
      await tester.dragFrom(const Offset(700, 400), const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 200));
      final boosted = _stateOf(tester, item).boostPercent;
      expect(boosted, greaterThan(100));

      // The phone reports the intermediate 93 % write after the finger is up.
      await DeviceControls.handlePlatformCall(const MethodCall('volumeChanged', 0.93));
      await tester.pump();
      expect(_stateOf(tester, item).boostPercent, boosted);

      // A real key press later (lowering the phone's volume) does end it.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      await DeviceControls.handlePlatformCall(const MethodCall('volumeChanged', 0.8));
      await tester.pump();
      expect(_stateOf(tester, item).boostPercent, 100);
      await tester.pump(const Duration(seconds: 1));
      await _unmount(tester);
    });

    testWidgets('the Volume button opens a 0-200 % slider; above 150 % a one-time hearing note', (tester) async {
      platform.volume = 1.0;
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);

      await tester.tap(find.byTooltip('Volume'));
      await tester.pump();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(2));
      final volumeSlider = sliders.firstWhere((s) => s.max == 2.0);
      expect(volumeSlider.value, 1.0);

      volumeSlider.onChangeStart!(1.0);
      volumeSlider.onChanged!(1.8);
      volumeSlider.onChangeEnd!(1.8);
      await tester.pump();
      expect((platform.calls('setVideoBoost').last.arguments as Map)['percent'], 180);
      expect(find.textContaining('Loud sound can harm your hearing'), findsWidgets);
      // Once only.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      volumeSlider.onChanged!(1.9);
      await tester.pump();
      expect(find.textContaining('Loud sound can harm your hearing'), findsNothing);

      // Back under full: the boost goes, the phone's volume follows.
      volumeSlider.onChanged!(0.5);
      await tester.pump();
      expect(_stateOf(tester, item).boostPercent, 100);
      expect(platform.volume, closeTo(0.5, 0.001));

      await _unmount(tester);
    });

    for (final (width, scale) in [(360.0, 1.0), (320.0, 1.3)]) {
      testWidgets('the open Volume panel never covers the transport ($width dp, ${scale}x text)', (tester) async {
        tester.view.physicalSize = Size(width * 3, 2100);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        platform.volume = 1.0;
        final a = _video('a');
        final b = _video('b');
        await _open(tester, _Harness([_Engine()]), item: a, queue: VideoQueue(items: [a, b], index: 0));
        await tester.tap(find.byTooltip('Volume'));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        final panel = tester.getRect(find.byKey(const ValueKey('video-volume-panel')));
        for (final tip in ['Forward 10 seconds', 'Next video', 'Pause', 'Rewind 10 seconds']) {
          final button = tester.getRect(find.byTooltip(tip));
          expect(button.overlaps(panel), isFalse, reason: '$tip at $button, panel at $panel');
          expect(button.width, greaterThanOrEqualTo(32), reason: '$tip stays tappable');
        }
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      });
    }

    testWidgets('a phone that refuses the boost caps the volume at 100 %', (tester) async {
      platform.volume = 1.0;
      platform.boostWorks = false;
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);

      await tester.dragFrom(const Offset(700, 400), const Offset(0, -150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text("Volume boost isn't available on this phone"), findsOneWidget);
      final s = _stateOf(tester, item);
      expect(s.boostSupported, isFalse);
      expect(s.boostPercent, 100);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('Volume'));
      await tester.pump();
      expect(tester.widgetList<Slider>(find.byType(Slider)).map((s) => s.max), contains(1.0));
      await _unmount(tester);
    });
  });

  group('VID-04 / VID-05 orientation', () {
    testWidgets('a wide video starts in landscape; the button cycles Portrait, Auto, Landscape', (tester) async {
      final item = _video('a');
      await _open(tester, _Harness([_Engine(size: const Size(1920, 1080))]), item: item);
      expect(platform.orientations.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);

      await tester.tap(find.byTooltip('Rotation: Landscape locked'));
      await tester.pump();
      expect(platform.orientations.last, ['DeviceOrientation.portraitUp']);
      expect(find.text('Portrait locked'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Rotation: Portrait locked'));
      await tester.pump();
      // Auto follows the phone, and so its own rotation lock.
      expect(platform.orientations.last, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(find.text('Auto-rotate'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _unmount(tester);
    });

    testWidgets('leaving the player frees the whole app (no portrait lock), already during the pop', (tester) async {
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);
      platform.orientations.clear();

      await tester.tap(find.bySemanticsLabel('Exit Video Player'));
      await tester.pump();
      // The pop itself frees it, before the list below is laid out again.
      expect(platform.orientations, isNotEmpty);
      expect(platform.orientations.first, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(platform.orientations.every((o) => o.isEmpty), isTrue, reason: '${platform.orientations}');
      await _unmount(tester);
    });
  });

  group('VID-03 Back saves the position', () {
    testWidgets('Back right after seekTo(4:00) while paused saves 240000', (tester) async {
      final item = _video('a');
      final h = _Harness([_Engine()]);
      await _open(tester, h, item: item);
      final notifier = _notifierOf(tester, item);
      await notifier.togglePlayPause(); // pause
      await tester.pump();
      h.progress.saved.clear();

      await notifier.seekTo(const Duration(minutes: 4));
      await tester.tap(find.bySemanticsLabel('Exit Video Player'));
      await tester.pumpAndSettle();

      expect(h.progress.saved.map((p) => p.positionMs), contains(240000));
      expect(h.progress.saved.last.positionMs, 240000);
      await _unmount(tester);
    });

    testWidgets('a seek while paused is saved by itself soon after', (tester) async {
      final item = _video('a');
      final h = _Harness([_Engine()]);
      await _open(tester, h, item: item);
      final notifier = _notifierOf(tester, item);
      await notifier.togglePlayPause();
      await tester.pump();
      h.progress.saved.clear();

      await notifier.seekTo(const Duration(minutes: 2));
      await notifier.seekTo(const Duration(minutes: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(h.progress.saved.map((p) => p.positionMs), [180000], reason: 'once, the last position');
      await _unmount(tester);
    });
  });

  group('VID-06 the controls stay while in use', () {
    testWidgets('dragging the scrubber holds them; letting go hides them 3 s later', (tester) async {
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);
      final slider = find.byWidgetPredicate((w) => w is Slider && w.max > 2);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(seconds: 5));
      expect(_stateOf(tester, item).showControls, isTrue);

      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(_stateOf(tester, item).showControls, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(_stateOf(tester, item).showControls, isFalse);
      await _unmount(tester);
    });
  });

  group('VID-07 / VID-12 sound never carries on by itself', () {
    testWidgets('headphones unplugged: the video pauses', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      expect(platform.calls('watchNoisy').last.arguments, {'on': true});

      await DeviceControls.handlePlatformCall(const MethodCall('becomingNoisy'));
      await tester.pump();
      expect(engine.pauseCalls, 1);
      expect(_stateOf(tester, item).isPlaying, isFalse);

      await _unmount(tester);
      expect(platform.calls('watchNoisy').last.arguments, {'on': false});
    });

    testWidgets('closing its picture-in-picture window pauses the video', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      DeviceControls.handlePipChanged(true);
      await tester.pump();
      DeviceControls.handlePipChanged(false);
      await DeviceControls.handlePlatformCall(const MethodCall('pipDismissed'));
      await tester.pump();
      expect(engine.pauseCalls, 1);
      await _unmount(tester);
    });

    testWidgets('Play as audio hands the current position to the music player and closes', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      final h = _Harness([engine]);
      await _open(tester, h, item: item);
      engine.emitPosition(const Duration(seconds: 75));
      await tester.pump();

      await tester.tap(find.byTooltip('Play as audio'));
      await tester.pumpAndSettle();
      expect(h.handoffs, [('a', const Duration(seconds: 75))]);
      expect(engine.pauseCalls, greaterThanOrEqualTo(1));
      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(h.progress.saved.last.positionMs, 75000);
      expect(h.host.log.last, 'clear', reason: 'the media session goes back before the music player claims it');
      await _unmount(tester);
    });
  });

  group('VID-08 notification, lock screen and headset', () {
    testWidgets('the playing video claims the media session, follows pause, and lets go on exit', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      final h = _Harness([engine]);
      await _open(tester, h, item: item);
      expect(h.host.log.first, 'set:true');
      expect(h.host.last!.title, 'Clip_a');
      expect(h.host.last!.id, 'video:a');
      expect(h.host.last!.album, 'Video');

      await h.host.delegate!.externalPause();
      await tester.pump();
      expect(engine.pauseCalls, 1);
      expect(h.host.log.last, 'update:false');

      // Next with no queue: 10 s on.
      engine.emitPosition(const Duration(seconds: 30));
      await tester.pump();
      await h.host.delegate!.externalSkipToNext();
      expect(engine.seeks.last, const Duration(seconds: 40));

      await _unmount(tester);
      expect(h.host.log.last, 'clear');
    });
  });

  group('VID-09 / VID-10 picture-in-picture', () {
    testWidgets('offered only while playing; its window gets rewind / play-pause / forward', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      final eligibility = platform.calls('setPipEligible').toList();
      expect((eligibility.last.arguments as Map)['eligible'], isTrue);
      expect((eligibility.last.arguments as Map)['actionsPlaying'], isTrue);

      final notifier = _notifierOf(tester, item);
      await notifier.togglePlayPause(); // paused: no auto picture-in-picture
      await tester.pump();
      expect((platform.calls('setPipEligible').last.arguments as Map)['eligible'], isFalse);

      // Its own window stays eligible (and keeps its buttons) while paused.
      await notifier.togglePlayPause();
      await tester.pump();
      DeviceControls.handlePipChanged(true);
      await tester.pump();
      await notifier.togglePlayPause();
      await tester.pump();
      final args = platform.calls('setPipEligible').last.arguments as Map;
      expect(args['eligible'], isTrue);
      expect(args['actionsPlaying'], isFalse, reason: 'the middle button now shows Play');

      engine.emitPosition(const Duration(seconds: 60));
      await tester.pump();
      await DeviceControls.handlePlatformCall(const MethodCall('pipAction', 'forward'));
      await tester.pump();
      expect(engine.seeks.last, const Duration(seconds: 70));
      final plays = engine.playCalls;
      await DeviceControls.handlePlatformCall(const MethodCall('pipAction', 'playPause'));
      await tester.pump();
      expect(engine.playCalls, plays + 1);
      DeviceControls.handlePipChanged(false);
      await _unmount(tester);
    });

    testWidgets("another screen's window ignores the video's buttons", (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      DeviceControls.pipOwner.value = DeviceControls.pipOwnerOnline;
      await DeviceControls.handlePlatformCall(const MethodCall('pipAction', 'forward'));
      await tester.pump();
      expect(engine.seeks, isEmpty);
      await _unmount(tester);
    });
  });

  group('VID-11 / VID-16 next video, Up next and Replay', () {
    testWidgets('Next saves this video, frees its player and plays the next one', (tester) async {
      final a = _video('a');
      final b = _video('b');
      final first = _Engine(name: 'a');
      final second = _Engine(name: 'b');
      final h = _Harness([first, second]);
      await _open(tester, h, item: a, queue: VideoQueue(items: [a, b], index: 0));
      first.emitPosition(const Duration(seconds: 50));
      await tester.pump();
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_previous_rounded)).onPressed, isNull);

      await tester.tap(find.byTooltip('Next video'));
      await _settle(tester);

      expect(h.progress.saved.any((p) => p.mediaId == 'a' && p.positionMs == 50000), isTrue);
      expect(first.disposed, isTrue);
      expect(second.initializedWith, [b.uri]);
      expect(find.text(breakableTitle('Clip_b')), findsOneWidget);
      expect(find.byKey(const ValueKey('surface-b')), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_next_rounded)).onPressed, isNull);
      await _unmount(tester);
    });

    testWidgets('at the end: Replay, and Up next starts the next video after 5 s', (tester) async {
      final a = _video('a');
      final b = _video('b');
      final first = _Engine(name: 'a');
      final second = _Engine(name: 'b');
      await _open(tester, _Harness([first, second]), item: a, queue: VideoQueue(items: [a, b], index: 0));

      first.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Replay'), findsOneWidget);
      expect(find.text('UP NEXT IN 5 S'), findsOneWidget);
      expect(find.text(breakableTitle('Clip_b')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('UP NEXT IN 2 S'), findsOneWidget);
      expect(second.initializedWith, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(second.initializedWith, [b.uri]);
      await _unmount(tester);
    });

    testWidgets('Cancel keeps the finished video; Replay starts it again', (tester) async {
      final a = _video('a');
      final b = _video('b');
      final first = _Engine(name: 'a');
      final second = _Engine(name: 'b');
      await _open(tester, _Harness([first, second]), item: a, queue: VideoQueue(items: [a, b], index: 0));

      first.complete();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(seconds: 6));
      expect(second.initializedWith, isEmpty);
      expect(find.textContaining('UP NEXT'), findsNothing);

      final plays = first.playCalls;
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      expect(first.seeks.last, Duration.zero);
      expect(first.playCalls, plays + 1);
      await _unmount(tester);
    });
  });

  // Emulator QA: Cancel on the Up next card must stop the next video for
  // good, even when the player reports the end once more afterwards.
  group('Up next Cancel', () {
    testWidgets('Cancel stops autoplay, also after a second end signal; Play now still works', (tester) async {
      final a = _video('a');
      final b = _video('b');
      final first = _Engine(name: 'a');
      final second = _Engine(name: 'b');
      await _open(tester, _Harness([first, second]), item: a, queue: VideoQueue(items: [a, b], index: 0));

      first.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('UP NEXT IN 5 S'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.textContaining('UP NEXT'), findsNothing);

      first.reportEndAgain();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('UP NEXT'), findsNothing, reason: 'the countdown does not come back');
      await tester.pump(const Duration(seconds: 10));
      expect(second.initializedWith, isEmpty, reason: 'the next video never starts by itself');
      expect(find.text(breakableTitle('Clip_a')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('after Cancel, Replay to the end offers Up next again', (tester) async {
      final a = _video('a');
      final b = _video('b');
      final first = _Engine(name: 'a');
      final second = _Engine(name: 'b');
      await _open(tester, _Harness([first, second]), item: a, queue: VideoQueue(items: [a, b], index: 0));

      first.complete();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      first.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('UP NEXT IN 5 S'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('VID-14 picture size', () {
    testWidgets('the button cycles Fill, Stretch, Original, Fit', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      expect(engine.lastFit, BoxFit.contain);

      await tester.tap(find.byTooltip('Picture size: Fit to screen'));
      await tester.pump();
      expect(engine.lastFit, BoxFit.cover);
      expect(find.text('Fill screen'), findsOneWidget);
      await tester.tap(find.byTooltip('Picture size: Fill screen'));
      await tester.pump();
      expect(engine.lastFit, BoxFit.fill);
      await tester.tap(find.byTooltip('Picture size: Stretch'));
      await tester.pump();
      expect(engine.lastFit, BoxFit.none);
      await tester.tap(find.byTooltip('Picture size: Original size'));
      await tester.pump();
      expect(engine.lastFit, BoxFit.contain);
      await tester.pump(const Duration(seconds: 2));
      await _unmount(tester);
    });

    testWidgets('pinching out fills the screen, pinching in fits it, without seeking', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      _notifierOf(tester, item).toggleControls(); // hide the controls
      await tester.pump(const Duration(milliseconds: 300));

      Future<void> pinch(double from, double to) async {
        final g1 = await tester.startGesture(Offset(400 - from, 300), pointer: 1);
        final g2 = await tester.startGesture(Offset(400 + from, 300), pointer: 2);
        for (var i = 1; i <= 5; i++) {
          final d = from + (to - from) * i / 5;
          await g1.moveTo(Offset(400 - d, 300));
          await g2.moveTo(Offset(400 + d, 300));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await pinch(60, 200);
      expect(engine.lastFit, BoxFit.cover);
      await pinch(200, 60);
      expect(engine.lastFit, BoxFit.contain);
      expect(engine.seeks, isEmpty, reason: 'a pinch is not a seek swipe');
      await tester.pump(const Duration(seconds: 2));
      await _unmount(tester);
    });
  });

  group('VID-13 sidecar subtitles', () {
    testWidgets('a .srt next to a download loads; CC turns it off and on', (tester) async {
      final dir = Directory.systemTemp.createTempSync('mediahub_srt_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final srt = File('${dir.path}${Platform.pathSeparator}movie.srt')
        ..writeAsStringSync('1\n00:00:01,000 --> 00:00:04,000\nHello\n');
      final video = '${dir.path}${Platform.pathSeparator}movie.mp4';
      final item = _video('a', uri: video);
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);

      expect(engine.subtitleFiles, [srt.path]);
      engine.emitCaption('Hello there');
      await tester.pump();
      expect(find.text('Hello there'), findsOneWidget);

      await tester.tap(find.byTooltip('Turn subtitles off'));
      await tester.pump();
      expect(engine.subtitleFiles.last, isNull);
      expect(find.text('Hello there'), findsNothing);
      await tester.tap(find.byTooltip('Turn subtitles on'));
      await tester.pump();
      expect(engine.subtitleFiles.last, srt.path);
      await _unmount(tester);
    });

    test('sidecarSubtitlePath: only local files, .srt before .vtt', () {
      final existing = {'/v/movie.vtt', '/v/clip.srt', '/v/clip.vtt'};
      bool exists(String p) => existing.contains(p);
      expect(sidecarSubtitlePath('/v/clip.mp4', exists: exists), '/v/clip.srt');
      expect(sidecarSubtitlePath('/v/movie.mkv', exists: exists), '/v/movie.vtt');
      expect(sidecarSubtitlePath('/v/none.mp4', exists: exists), isNull);
      expect(sidecarSubtitlePath('content://media/external/video/media/3', exists: (_) => true), isNull);
      expect(sidecarSubtitlePath('https://x/clip.mp4', exists: (_) => true), isNull);
    });
  });

  group('VID-15 iOS: no brightness or volume HUD', () {
    testWidgets('a vertical swipe off Android shows nothing and calls nothing', (tester) async {
      PlatformInfo.debugIsAndroid = false;
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);
      await tester.dragFrom(const Offset(100, 300), const Offset(0, -120));
      await tester.pump();
      expect(find.byIcon(Icons.brightness_6_rounded), findsNothing);
      expect(find.byTooltip('Volume'), findsNothing);
      expect(platform.calls('setBrightness'), isEmpty);
      await _unmount(tester);
    });
  });

  group('VID-17 double tap', () {
    testWidgets('shows a side bubble; more taps on that side add 10 s each from the last request', (tester) async {
      final item = _video('a');
      final engine = _Engine();
      await _open(tester, _Harness([engine]), item: item);
      engine.emitPosition(const Duration(seconds: 100));
      await tester.pump();

      const right = Offset(720, 200);
      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('+10 s'), findsOneWidget);
      expect(engine.seeks.last, const Duration(seconds: 110));

      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('+20 s'), findsOneWidget);
      expect(engine.seeks.last, const Duration(seconds: 120));

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('+20 s'), findsNothing);
      await _unmount(tester);
    });
  });

  group('VID-18 lock', () {
    testWidgets('Back shows the lock instead of leaving; the lock fades after 3 s', (tester) async {
      final item = _video('a');
      await _open(tester, _Harness([_Engine()]), item: item);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock controls'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlock Controls'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(_stateOf(tester, item).showControls, isFalse, reason: 'the lock icon fades too');

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(_stateOf(tester, item).showControls, isTrue);
      await tester.pump(const Duration(seconds: 4));
      await _unmount(tester);
    });
  });

  group('the top row at 320 dp and 1.3x text', () {
    testWidgets('what does not fit goes into More; nothing overflows', (tester) async {
      tester.view.physicalSize = const Size(960, 2100);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final a = _video('a');
      final b = _video('b');
      await _open(tester, _Harness([_Engine()]), item: a, queue: VideoQueue(items: [a, b], index: 0));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Volume'), findsOneWidget);
      expect(find.byTooltip('Playback Speed'), findsNothing);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Playback speed'), findsOneWidget);
      expect(find.text('Play as audio'), findsOneWidget);
      expect(find.text('Lock controls'), findsOneWidget);
      await tester.tap(find.textContaining('Playback speed'));
      await tester.pumpAndSettle();
      expect(find.text('1.5x'), findsOneWidget);
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(_stateOf(tester, a).speed, 1.5);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });
}
