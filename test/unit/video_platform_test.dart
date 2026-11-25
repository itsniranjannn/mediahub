// Probe tests for P3's platform pieces: the share channel (SEC-6), the video
// queue route (VID-11), the router's start location and the download
// notification's tap (SEC-9).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/router.dart';
import 'package:mediahub/core/platform/share_channel.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/services/download_service_controller.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/video_player/video_player_screen.dart';
import 'package:mediahub/features/video_player/video_queue.dart';

MediaItem _item(String id, {MediaType type = MediaType.video}) => MediaItem(
      id: id,
      title: id,
      artist: 'x',
      durationMs: 1000,
      uri: '/d/$id.mp4',
      mediaType: type,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

class _FakeDownloads implements DownloadServiceController {
  final events = StreamController<String>.broadcast();
  @override
  Stream<String> get actionEvents => events.stream;
  @override
  Future<void> startService({required int count, int percent = -1, String? fileName}) async {}
  @override
  Future<void> updateProgress({required int count, int percent = -1, String? fileName}) async {}
  @override
  Future<void> stopService() async {}
  @override
  Future<void> showPausedNotice(int count) async {}
  @override
  Future<void> hidePausedNotice() async {}
  @override
  void dispose() => events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(PlatformInfo.resetForTests);

  group('ShareChannel (SEC-6)', () {
    const channel = MethodChannel('mediahub/share');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      PlatformInfo.debugIsAndroid = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('a file goes to the native sheet with its type', () async {
      expect(
        await ShareChannel.shareFile(uriOrPath: 'content://media/external/audio/media/9', mimeType: 'audio/mpeg'),
        isTrue,
      );
      expect(calls.single.method, 'shareFile');
      expect(calls.single.arguments, {'uriOrPath': 'content://media/external/audio/media/9', 'mimeType': 'audio/mpeg'});
    });

    test('text is shared as text; blank text and empty paths are refused without a call', () async {
      expect(await ShareChannel.shareText('https://www.youtube.com/watch?v=abc', subject: 'A song'), isTrue);
      expect(calls.single.arguments, {'text': 'https://www.youtube.com/watch?v=abc', 'subject': 'A song'});
      calls.clear();
      expect(await ShareChannel.shareText('   '), isFalse);
      expect(await ShareChannel.shareFile(uriOrPath: '', mimeType: 'video/mp4'), isFalse);
      expect(calls, isEmpty);
    });

    test('off Android nothing is sent', () async {
      PlatformInfo.debugIsAndroid = false;
      expect(ShareChannel.available, isFalse);
      expect(await ShareChannel.shareText('hi'), isFalse);
      expect(calls, isEmpty);
    });

    test('a native failure is a false, never a throw', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'SHARE_FAILED'));
      expect(await ShareChannel.shareFile(uriOrPath: '/x/a.mp3', mimeType: 'audio/mpeg'), isFalse);
    });

    test('mimeTypeFor', () {
      expect(ShareChannel.mimeTypeFor('/d/Song.MP3'), 'audio/mpeg');
      expect(ShareChannel.mimeTypeFor('clip.webm'), 'video/webm');
      expect(ShareChannel.mimeTypeFor('noext', fallback: 'audio/*'), 'audio/*');
      expect(ShareChannel.mimeTypeFor('dot.'), '*/*');
    });
  });

  group('VideoQueue (VID-11)', () {
    test('the visible list, videos only, starting at the tapped one', () {
      final a = _item('a'), b = _item('b'), c = _item('c'), song = _item('s', type: MediaType.audio);
      final q = videoQueueFor(b, [a, song, b, c]);
      expect(q.items.map((m) => m.id), ['a', 'b', 'c']);
      expect(q.index, 1);
      expect(q.current.id, 'b');
      expect((q.hasPrevious, q.hasNext), (true, true));
    });

    test('unplayable neighbours are skipped, the tapped item never is', () {
      final a = _item('a'), b = _item('b'), c = _item('c');
      final q = videoQueueFor(b, [a, b, c], isPlayable: (m) => m.id != 'a' && m.id != 'b');
      expect(q.items.map((m) => m.id), ['b', 'c']);
      expect(q.index, 0);
    });

    test('an item missing from the list plays alone', () {
      final q = videoQueueFor(_item('z'), [_item('a')]);
      expect(q.items.map((m) => m.id), ['z']);
    });

    test('route extras: MediaItem, VideoQueue, nothing else', () {
      final a = _item('a');
      expect(VideoQueue.fromExtra(a)!.items, [a]);
      final q = VideoQueue(items: [a, _item('b')], index: 1);
      expect(VideoQueue.fromExtra(q), same(q));
      expect(VideoQueue.fromExtra(VideoQueue(items: const [], index: 0)), isNull);
      expect(VideoQueue.fromExtra('a'), isNull);
      expect(VideoQueue.fromExtra(null), isNull);
      expect(VideoQueue(items: [a], index: 5).index, 0, reason: 'clamped');
    });

    testWidgets('/video_player builds the player for a VideoQueue extra', (tester) async {
      final a = _item('a'), b = _item('b');
      late Widget built;
      await tester.pumpWidget(Builder(builder: (context) {
        built = videoPlayerRouteBuilder(
          context,
          GoRouterState(
            GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())]).configuration,
            uri: Uri.parse('/video_player'),
            matchedLocation: '/video_player',
            fullPath: '/video_player',
            pathParameters: const {},
            pageKey: const ValueKey('p'),
            extra: VideoQueue(items: [a, b], index: 1),
          ),
        );
        return const SizedBox();
      }));
      expect(built, isA<VideoPlayerScreen>());
      final screen = built as VideoPlayerScreen;
      expect(screen.item.id, 'b');
      expect(screen.queue!.items, [a, b]);
    });
  });

  group('router (SEC-9)', () {
    tearDown(() => tester().platformDispatcher.clearDefaultRouteNameTestValue());

    test("the platform's route (an intent extra another app chose) is ignored: the app starts Home", () {
      tester().platformDispatcher.defaultRouteNameTestValue = '/settings';
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      expect(router.routeInformationProvider.value.uri.path, '/home');
    });

    test("the download notification's tap opens the Downloads tab", () async {
      PlatformInfo.debugIsAndroid = true;
      final downloads = _FakeDownloads();
      final container = ProviderContainer(
        overrides: [downloadServiceControllerProvider.overrideWithValue(downloads)],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      downloads.events.add(DownloadServiceActions.pauseAll);
      await Future<void>.delayed(Duration.zero);
      expect(router.routeInformationProvider.value.uri.path, '/home');
      downloads.events.add(DownloadServiceActions.openDownloads);
      await Future<void>.delayed(Duration.zero);
      expect(router.routeInformationProvider.value.uri.path, '/downloads');
    });
  });

  group('AndroidDownloadServiceController openDownloads (SEC-9)', () {
    const channel = MethodChannel('mediahub/download_service');
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('a tap that came before Dart listened is picked up at start', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'takePendingActions') return ['openDownloads'];
        return true;
      });
      final controller = AndroidDownloadServiceController();
      addTearDown(controller.dispose);
      final events = <String>[];
      controller.actionEvents.listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, [DownloadServiceActions.openDownloads]);
    });

    test('a live tap arrives as an action event', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => <Object?>[]);
      final controller = AndroidDownloadServiceController();
      addTearDown(controller.dispose);
      final events = <String>[];
      controller.actionEvents.listen(events.add);
      await messenger.handlePlatformMessage(
        'mediahub/download_service',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('openDownloads')),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [DownloadServiceActions.openDownloads]);
    });
  });
}

TestWidgetsFlutterBinding tester() => TestWidgetsFlutterBinding.instance;
