import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/explore/explore_screen.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/explore/online_source.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

/// Key the explore notifier persists its history under.
const String _historyKey = 'explore_history';

/// In-memory [OnlineSource]: no network. Answers with [results] unless
/// [onSearch] / [onStreams] say otherwise.
class FakeOnlineSource implements OnlineSource {
  final List<String> queries = [];
  final List<String> streamCalls = [];
  List<OnlineVideo> results = const [];
  Future<List<OnlineVideo>> Function(String query)? onSearch;
  Future<OnlineStreams> Function(String videoId)? onStreams;

  @override
  Future<List<OnlineVideo>> search(String query) {
    queries.add(query);
    final handler = onSearch;
    return handler != null ? handler(query) : Future.value(results);
  }

  @override
  Future<OnlineStreams> streams(String videoId) {
    streamCalls.add(videoId);
    final handler = onStreams;
    return handler != null
        ? handler(videoId)
        : Future.value(const OnlineStreams(audio: [], video: []));
  }

  @override
  void dispose() {}
}

/// Records what the screen asks the download engine to queue.
class FakeDownloadEngine extends Fake implements DownloadEngine {
  final List<Map<String, Object?>> enqueued = [];
  Object? failWith;

  @override
  Future<void> enqueueDownload({
    required String id,
    required Uri url,
    required String displayName,
    required String suggestedFileName,
    String? kind,
    String? thumbnailUrl,
    String? qualityLabel,
    String? uploader,
    int? durationSec,
    int? totalBytes,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    enqueued.add({
      'url': url.toString(),
      'displayName': displayName,
      'suggestedFileName': suggestedFileName,
      'kind': kind,
      'qualityLabel': qualityLabel,
      'uploader': uploader,
      'durationSec': durationSec,
      'totalBytes': totalBytes,
    });
  }
}

/// Playback that records the queues it is asked to play (no audio handler).
class FakePlaybackNotifier extends PlaybackNotifier {
  final List<List<MediaItem>> loaded = [];

  @override
  PlaybackState build() => PlaybackState(updatedAt: DateTime(2026));

  @override
  Future<void> loadQueue(
    List<MediaItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) async {
    loaded.add(items);
  }
}

/// Queue coordinator that only counts how often it was poked.
class FakeQueueCoordinator extends DownloadQueueCoordinatorNotifier {
  int triggers = 0;

  @override
  void build() {}

  @override
  Future<void> trigger() async => triggers++;
}

const _midnight = OnlineVideo(
  id: 'dQw4w9WgXcQ',
  title: 'Midnight Drive Mix',
  author: 'Neon Atlas',
  duration: Duration(minutes: 58, seconds: 12),
  thumbnailUrl: '',
);
const _folk = OnlineVideo(
  id: 'aqz-KE-bpKQ',
  title: 'Folk Fusion Session',
  author: 'Himal Sessions',
  duration: Duration(hours: 1, minutes: 2, seconds: 3),
  thumbnailUrl: '',
);
const _live = OnlineVideo(
  id: '9bZkp7q19f0',
  title: 'Lofi Radio 24/7',
  author: 'Quiet Hours',
  duration: Duration.zero,
  thumbnailUrl: '',
  isLive: true,
);
const _noDuration = OnlineVideo(
  id: 'jNQXAC9IVRw',
  title: 'Mountain Bridges',
  author: 'Engineering Stories',
  thumbnailUrl: '',
);

const _googleAudio = OnlineStream(
  url: 'https://rr3---sn-a5mekn7s.googlevideo.com/videoplayback?id=a',
  kind: OnlineStreamKind.audio,
  label: '128 kbps',
  container: 'mp4',
  sizeBytes: 3 * 1024 * 1024,
  bitrateKbps: 128,
);
const _google720 = OnlineStream(
  url: 'https://rr3---sn-a5mekn7s.googlevideo.com/videoplayback?id=v',
  kind: OnlineStreamKind.video,
  label: '720p',
  container: 'mp4',
  sizeBytes: 0,
  height: 720,
);
const _evil360 = OnlineStream(
  url: 'https://evil.example.com/v.mp4',
  kind: OnlineStreamKind.video,
  label: '360p',
  container: 'mp4',
  sizeBytes: 1024,
  height: 360,
);

void main() {
  late FakeOnlineSource source;

  setUp(() async {
    // Not Android: downloads use the in-app quality sheet, never yt-dlp.
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = false;
    await SettingsStore.instance.setStringList(_historyKey, const []);
    source = FakeOnlineSource();
  });
  tearDown(PlatformInfo.resetForTests);

  /// A phone-width surface tall enough that every result card is on screen.
  void usePhone(WidgetTester tester, {double width = 412, double height = 2000}) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpExplore(
    WidgetTester tester, {
    List<Override> overrides = const [],
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [onlineSourceProvider.overrideWithValue(source), ...overrides],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ExploreScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Lets sheets, dialogs and snack bars animate in or out. (No pumpAndSettle:
  /// the busy spinner on a card keeps animating while a sheet is open.)
  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> submitSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  Finder card(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(SurfaceCard)).first;

  Finder inCard(String title, Finder matching) =>
      find.descendant(of: card(title), matching: matching);

  final skeleton = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SkeletonCard');

  testWidgets('shows the header and the initial empty hint', (tester) async {
    usePhone(tester);
    await pumpExplore(tester);

    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Search, play and save without leaving MediaHub.'), findsOneWidget);
    expect(find.text('Search videos, songs, channels'), findsOneWidget);
    expect(find.text('Find anything to watch or listen to'), findsOneWidget);
    expect(find.text('Search YouTube, then play it right here or save it for offline.'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing, reason: 'no history yet');
    expect(source.queries, isEmpty);

    await unmount(tester);
  });

  testWidgets('typing and submitting shows a skeleton, then titles, authors and duration badges',
      (tester) async {
    usePhone(tester);
    final pending = Completer<List<OnlineVideo>>();
    source.onSearch = (_) => pending.future;
    await pumpExplore(tester);

    await submitSearch(tester, '  lofi mix ');
    expect(source.queries, ['lofi mix']);
    expect(skeleton, findsWidgets);
    expect(find.text('Find anything to watch or listen to'), findsNothing);

    pending.complete([_midnight, _folk, _noDuration]);
    await tester.pump();

    expect(skeleton, findsNothing);
    expect(find.text('Midnight Drive Mix'), findsOneWidget);
    expect(find.text('Neon Atlas'), findsOneWidget);
    expect(find.text('Folk Fusion Session'), findsOneWidget);
    expect(find.text('Himal Sessions'), findsOneWidget);
    expect(find.text('Mountain Bridges'), findsOneWidget);
    expect(find.text('Engineering Stories'), findsOneWidget);
    expect(inCard('Midnight Drive Mix', find.text('58:12')), findsOneWidget);
    expect(inCard('Folk Fusion Session', find.text('1:02:03')), findsOneWidget);
    expect(inCard('Mountain Bridges', find.textContaining(':')), findsNothing,
        reason: 'no badge without a duration');
    expect(find.text('LIVE'), findsNothing);
    // Every card offers the three actions.
    expect(find.text('Listen'), findsNWidgets(3));
    expect(find.text('Watch'), findsNWidgets(3));
    expect(find.byTooltip('Download'), findsNWidgets(3));

    await unmount(tester);
  });

  testWidgets('the clear button empties the search field', (tester) async {
    usePhone(tester);
    await pumpExplore(tester);

    expect(find.byTooltip('Clear'), findsNothing);
    await tester.enterText(find.byType(TextField), 'jazz');
    await tester.pump();
    expect(find.byTooltip('Clear'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.byTooltip('Clear'), findsNothing);
    expect(source.queries, isEmpty, reason: 'clearing does not search');

    await unmount(tester);
  });

  testWidgets('a whitespace-only search does nothing', (tester) async {
    usePhone(tester);
    await pumpExplore(tester);

    await submitSearch(tester, '    ');
    expect(source.queries, isEmpty);
    expect(find.text('Find anything to watch or listen to'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a search without matches shows the no-results hint', (tester) async {
    usePhone(tester);
    source.results = const [];
    await pumpExplore(tester);

    await submitSearch(tester, 'qwertyuiop');
    expect(find.text('No results'), findsOneWidget);
    expect(find.text('Try different words or a shorter search.'), findsOneWidget);
    expect(find.text('Find anything to watch or listen to'), findsNothing);

    await unmount(tester);
  });

  testWidgets('the error state shows the message and Try again re-runs the search',
      (tester) async {
    usePhone(tester);
    var calls = 0;
    source.onSearch = (_) async {
      calls++;
      if (calls == 1) throw const OnlineException('No internet connection.');
      return [_midnight];
    };
    await pumpExplore(tester);

    await submitSearch(tester, 'synthwave');
    expect(find.text('Could not search'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Midnight Drive Mix'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(source.queries, ['synthwave', 'synthwave']);
    expect(find.text('Could not search'), findsNothing);
    expect(find.text('No internet connection.'), findsNothing);
    expect(find.text('Midnight Drive Mix'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('LIVE results show the LIVE tag and a disabled download button', (tester) async {
    usePhone(tester);
    source.results = const [_live, _midnight];
    await pumpExplore(tester);

    await submitSearch(tester, 'lofi radio');

    expect(inCard('Lofi Radio 24/7', find.text('LIVE')), findsOneWidget);
    expect(inCard('Midnight Drive Mix', find.text('LIVE')), findsNothing);
    // Matched by widget, not by text, so the check does not depend on the
    // clock format.
    expect(inCard('Lofi Radio 24/7', find.byWidgetPredicate((w) => w is DurationBadge && !w.isLive)), findsNothing,
        reason: 'a live stream has no duration badge');
    expect(inCard('Lofi Radio 24/7', find.text('0:00')), findsNothing);
    expect(inCard('Midnight Drive Mix', find.byWidgetPredicate((w) => w is DurationBadge && !w.isLive)),
        findsOneWidget, reason: 'the predicate does find a normal badge');

    final liveDownload = inCard('Lofi Radio 24/7', find.byType(IconButton));
    final normalDownload = inCard('Midnight Drive Mix', find.byType(IconButton));
    expect(tester.widget<IconButton>(liveDownload).tooltip, 'Download');
    expect(tester.widget<IconButton>(liveDownload).onPressed, isNull);
    expect(tester.widget<IconButton>(normalDownload).onPressed, isNotNull);

    await tester.tap(liveDownload, warnIfMissed: false);
    await tester.pump();
    expect(source.streamCalls, isEmpty);

    // Listening to a live stream is still allowed.
    expect(inCard('Lofi Radio 24/7', find.text('Listen')), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a result card keeps one 16 dp gutter, 48 dp actions and a badge on the 8-pt grid',
      (tester) async {
    usePhone(tester);
    source.results = const [_midnight];
    await pumpExplore(tester);
    await submitSearch(tester, 'midnight');

    // Inside SurfaceCard's 1 dp border (Ink pads its child by the border).
    final cardRect = tester.getRect(card('Midnight Drive Mix')).deflate(1);
    final title = tester.getRect(find.text('Midnight Drive Mix'));
    final listen = tester.getRect(inCard('Midnight Drive Mix', find.byWidgetPredicate((w) => w is FilledButton)).first);
    final download = tester.getRect(inCard('Midnight Drive Mix', find.byType(IconButton)));

    expect(title.left - cardRect.left, 16);
    expect(listen.left, title.left, reason: 'Listen starts under the title');
    expect(cardRect.right - download.right, 16);
    expect(download.height, 48, reason: 'as tall as the Listen and Watch pills');
    expect(download.width, 48);
    expect(listen.height, 48);

    // The 16:9 thumbnail is the card's full width, so its corner is the card's.
    final badge = tester.getRect(inCard('Midnight Drive Mix', find.byType(DurationBadge)));
    final thumbBottom = cardRect.top + cardRect.width * 9 / 16;
    expect(cardRect.right - badge.right, closeTo(12, 0.5));
    expect(thumbBottom - badge.bottom, closeTo(12, 0.5));

    await unmount(tester);
  });

  testWidgets('history chips appear and tapping one searches', (tester) async {
    usePhone(tester);
    await SettingsStore.instance.setStringList(_historyKey, ['lofi beats', 'jazz']);
    source.results = const [_midnight];
    await pumpExplore(tester);

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'lofi beats'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'jazz'), findsOneWidget);
    expect(find.text('Find anything to watch or listen to'), findsOneWidget);

    await tester.tap(find.widgetWithText(InputChip, 'lofi beats'));
    await tester.pump();

    expect(source.queries, ['lofi beats']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'lofi beats');
    expect(find.text('Midnight Drive Mix'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing, reason: 'history hides once a search ran');
    expect(SettingsStore.instance.getStringList(_historyKey), ['lofi beats', 'jazz']);

    await unmount(tester);
  });

  testWidgets('a history chip can be deleted and Clear removes all of them', (tester) async {
    usePhone(tester);
    await SettingsStore.instance.setStringList(_historyKey, ['lofi beats', 'jazz', 'rock']);
    await pumpExplore(tester);

    final jazzDelete = find.descendant(
      of: find.widgetWithText(InputChip, 'jazz'),
      matching: find.byTooltip('Delete'),
    );
    expect(jazzDelete, findsOneWidget);
    await tester.tap(jazzDelete);
    await tester.pump();

    expect(find.widgetWithText(InputChip, 'jazz'), findsNothing);
    expect(find.widgetWithText(InputChip, 'lofi beats'), findsOneWidget);
    expect(SettingsStore.instance.getStringList(_historyKey), ['lofi beats', 'rock']);
    expect(source.queries, isEmpty, reason: 'deleting a chip does not search');

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();

    expect(find.text('Recent searches'), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    expect(SettingsStore.instance.getStringList(_historyKey), isEmpty);
    expect(find.text('Find anything to watch or listen to'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Listen shows a spinner on that card, then a friendly error', (tester) async {
    usePhone(tester);
    source.results = const [_midnight, _folk];
    final pending = Completer<OnlineStreams>();
    source.onStreams = (_) => pending.future;
    await pumpExplore(tester);
    await submitSearch(tester, 'mix');

    await tester.tap(inCard('Midnight Drive Mix', find.text('Listen')));
    await tester.pump();

    expect(source.streamCalls, ['dQw4w9WgXcQ']);
    expect(inCard('Midnight Drive Mix', find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(inCard('Midnight Drive Mix', find.text('Listen')), findsNothing);
    expect(inCard('Folk Fusion Session', find.text('Listen')), findsOneWidget,
        reason: 'only the busy card changes');

    // A second action while busy is ignored.
    await tester.tap(inCard('Folk Fusion Session', find.text('Watch')));
    await tester.pump();
    expect(source.streamCalls, hasLength(1));

    pending.completeError(const OnlineException(
        'This video cannot be played here (private, age-restricted or unavailable).'));
    await animate(tester);

    expect(find.text('This video cannot be played here (private, age-restricted or unavailable).'),
        findsOneWidget);
    expect(inCard('Midnight Drive Mix', find.byType(CircularProgressIndicator)), findsNothing);
    expect(inCard('Midnight Drive Mix', find.text('Listen')), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Watch without a video stream explains why', (tester) async {
    usePhone(tester);
    source.results = const [_midnight];
    source.onStreams = (_) async => const OnlineStreams(audio: [_googleAudio], video: []);
    await pumpExplore(tester);
    await submitSearch(tester, 'mix');

    await tester.tap(find.text('Watch'));
    await animate(tester);

    expect(find.text('No video stream found for this video.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Listen without an audio stream explains why', (tester) async {
    usePhone(tester);
    source.results = const [_midnight];
    source.onStreams = (_) async => const OnlineStreams(audio: [], video: [_google720]);
    await pumpExplore(tester);
    await submitSearch(tester, 'mix');

    await tester.tap(find.text('Listen'));
    await animate(tester);

    expect(find.text('No audio stream found for this video.'), findsOneWidget);

    await unmount(tester);
  });

  group('Listen and Watch only play YouTube media hosts over https', () {
    late FakePlaybackNotifier playback;

    setUp(() {
      playback = FakePlaybackNotifier();
      source.results = const [_midnight];
    });

    /// Explore inside a router, so Watch can really navigate to the player.
    Future<GoRouter> pumpRouted(WidgetTester tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ExploreScreen()),
          GoRoute(
            path: '/video_player',
            builder: (_, state) => Scaffold(
              body: Text('PLAYER ${(state.extra as MediaItem).uri}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineSourceProvider.overrideWithValue(source),
            playbackNotifierProvider.overrideWith(() => playback),
          ],
          child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
        ),
      );
      await tester.pump();
      return router;
    }

    for (final (name, url) in [
      ('another host', 'https://evil.example.com/a.m4a'),
      ('a look-alike host', 'https://googlevideo.com.evil.example/a.m4a'),
      ('plain http', 'http://rr3---sn-a5mekn7s.googlevideo.com/videoplayback?id=a'),
      ('not a URL', 'file:///storage/emulated/0/a.m4a'),
    ]) {
      testWidgets('Listen refuses $name', (tester) async {
        usePhone(tester);
        source.onStreams = (_) async => OnlineStreams(
              audio: [OnlineStream(url: url, kind: OnlineStreamKind.audio, label: '128 kbps', container: 'mp4', sizeBytes: 1, bitrateKbps: 128)],
              video: const [_google720],
            );
        await pumpRouted(tester);
        await submitSearch(tester, 'mix');

        await tester.tap(find.text('Listen'));
        await animate(tester);

        expect(find.text('Unexpected stream address. Playback cancelled.'), findsOneWidget);
        expect(playback.loaded, isEmpty);
        expect(inCard('Midnight Drive Mix', find.text('Listen')), findsOneWidget,
            reason: 'the card is usable again');

        await unmount(tester);
      });

      testWidgets('Watch refuses $name', (tester) async {
        usePhone(tester);
        source.onStreams = (_) async => OnlineStreams(
              audio: const [_googleAudio],
              video: [OnlineStream(url: url, kind: OnlineStreamKind.video, label: '720p', container: 'mp4', sizeBytes: 1, height: 720)],
            );
        await pumpRouted(tester);
        await submitSearch(tester, 'mix');

        await tester.tap(find.text('Watch'));
        await animate(tester);

        expect(find.text('Unexpected stream address. Playback cancelled.'), findsOneWidget);
        expect(find.textContaining('PLAYER'), findsNothing);

        await unmount(tester);
      });
    }

    testWidgets('Listen plays a googlevideo.com stream', (tester) async {
      usePhone(tester);
      source.onStreams = (_) async => const OnlineStreams(audio: [_googleAudio], video: [_google720]);
      await pumpRouted(tester);
      await submitSearch(tester, 'mix');

      await tester.tap(find.text('Listen'));
      await animate(tester);

      expect(playback.loaded, hasLength(1));
      final item = playback.loaded.single.single;
      expect(item.uri, _googleAudio.url);
      expect(item.mediaType, MediaType.audio);
      expect(item.source, 'online');
      expect(find.text('Unexpected stream address. Playback cancelled.'), findsNothing);

      await unmount(tester);
    });

    // Dart reads a backslash as a path separator, while the native players
    // parse the raw text themselves; they must get the form that was checked.
    const rawAudio = r'https://R1.GoogleVideo.com\evil.example/videoplayback?id=a';
    const checkedAudio = 'https://r1.googlevideo.com/evil.example/videoplayback?id=a';

    testWidgets('Listen hands the player the checked address, not the raw text',
        (tester) async {
      usePhone(tester);
      source.onStreams = (_) async => OnlineStreams(
            audio: [OnlineStream(url: rawAudio, kind: OnlineStreamKind.audio, label: '128 kbps', container: 'mp4', sizeBytes: 1, bitrateKbps: 128)],
            video: const [_google720],
          );
      await pumpRouted(tester);
      await submitSearch(tester, 'mix');

      await tester.tap(find.text('Listen'));
      await animate(tester);

      expect(playback.loaded.single.single.uri, checkedAudio);

      await unmount(tester);
    });

    testWidgets('Watch hands the player the checked address, not the raw text',
        (tester) async {
      usePhone(tester);
      source.onStreams = (_) async => OnlineStreams(
            audio: const [_googleAudio],
            video: [OnlineStream(url: rawAudio, kind: OnlineStreamKind.video, label: '720p', container: 'mp4', sizeBytes: 1, height: 720)],
          );
      await pumpRouted(tester);
      await submitSearch(tester, 'mix');

      await tester.tap(find.text('Watch'));
      await animate(tester);

      expect(find.text('PLAYER $checkedAudio'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('Watch opens the player with a googlevideo.com stream', (tester) async {
      usePhone(tester);
      source.onStreams = (_) async => const OnlineStreams(audio: [_googleAudio], video: [_google720]);
      await pumpRouted(tester);
      await submitSearch(tester, 'mix');

      await tester.tap(find.text('Watch'));
      await animate(tester);

      expect(find.text('PLAYER ${_google720.url}'), findsOneWidget);
      expect(find.text('Unexpected stream address. Playback cancelled.'), findsNothing);

      await unmount(tester);
    });
  });

  group('download from the quality sheet', () {
    late FakeDownloadEngine engine;
    late FakeQueueCoordinator coordinator;

    setUp(() {
      engine = FakeDownloadEngine();
      coordinator = FakeQueueCoordinator();
      source.results = const [_midnight];
      source.onStreams = (_) async =>
          const OnlineStreams(audio: [_googleAudio], video: [_evil360, _google720]);
    });

    List<Override> downloadOverrides() => [
          downloadEngineProvider.overrideWithValue(engine),
          downloadQueueCoordinatorProvider.overrideWith(() => coordinator),
        ];

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Download'));
      await animate(tester);
    }

    testWidgets('lists the qualities, highest first, plus best audio', (tester) async {
      usePhone(tester);
      await pumpExplore(tester, overrides: downloadOverrides());
      await submitSearch(tester, 'mix');
      await openSheet(tester);

      expect(source.streamCalls, ['dQw4w9WgXcQ']);
      expect(find.text('Video (with sound)'), findsOneWidget);
      expect(find.text('Audio only'), findsOneWidget);
      expect(find.text('Best audio (128 kbps)'), findsOneWidget);
      expect(find.text('MP4 • size unknown'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('720p')).dy,
        lessThan(tester.getTopLeft(find.text('360p')).dy),
      );

      // Close the sheet without picking anything.
      await tester.tapAt(const Offset(20, 20));
      await animate(tester);
      expect(find.text('Video (with sound)'), findsNothing);
      expect(engine.enqueued, isEmpty);

      await unmount(tester);
    });

    testWidgets('a stream outside YouTube media hosts is refused', (tester) async {
      usePhone(tester);
      await pumpExplore(tester, overrides: downloadOverrides());
      await submitSearch(tester, 'mix');
      await openSheet(tester);

      await tester.tap(find.text('360p'));
      await animate(tester);

      expect(find.text('Unexpected download address. Download cancelled.'), findsOneWidget);
      expect(find.text('Download Notice'), findsNothing);
      expect(engine.enqueued, isEmpty);
      expect(coordinator.triggers, 0);

      await unmount(tester);
    });

    testWidgets('a googlevideo.com stream over plain http is refused too', (tester) async {
      usePhone(tester);
      source.onStreams = (_) async => const OnlineStreams(
            audio: [],
            video: [
              OnlineStream(
                url: 'http://rr3---sn-a5mekn7s.googlevideo.com/videoplayback?id=h',
                kind: OnlineStreamKind.video,
                label: '480p',
                container: 'mp4',
                sizeBytes: 1024,
                height: 480,
              ),
            ],
          );
      await pumpExplore(tester, overrides: downloadOverrides());
      await submitSearch(tester, 'mix');
      await openSheet(tester);

      await tester.tap(find.text('480p'));
      await animate(tester);

      expect(find.text('Unexpected download address. Download cancelled.'), findsOneWidget);
      expect(find.text('Download Notice'), findsNothing);
      expect(engine.enqueued, isEmpty);

      await unmount(tester);
    });

    testWidgets('cancelling the notice queues nothing; agreeing queues the stream',
        (tester) async {
      usePhone(tester);
      await pumpExplore(tester, overrides: downloadOverrides());
      await submitSearch(tester, 'mix');

      await openSheet(tester);
      await tester.tap(find.text('Best audio (128 kbps)'));
      await animate(tester);
      expect(find.text('Download Notice'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await animate(tester);
      expect(engine.enqueued, isEmpty);
      expect(coordinator.triggers, 0);

      await openSheet(tester);
      await tester.tap(find.text('Best audio (128 kbps)'));
      await animate(tester);
      await tester.tap(find.text('Agree'));
      await animate(tester);

      expect(engine.enqueued, hasLength(1));
      final job = engine.enqueued.single;
      expect(job['url'], _googleAudio.url);
      expect(job['displayName'], 'Midnight Drive Mix');
      expect(job['suggestedFileName'], 'Midnight Drive Mix.m4a', reason: 'mp4 audio is saved as m4a');
      expect(job['kind'], 'audio');
      expect(job['qualityLabel'], '128 kbps');
      expect(job['uploader'], 'Neon Atlas');
      expect(job['durationSec'], 58 * 60 + 12);
      expect(job['totalBytes'], 3 * 1024 * 1024);
      expect(coordinator.triggers, 1);
      expect(find.text('Added to Downloads: Midnight Drive Mix (128 kbps)'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('an engine failure is reported instead of being lost', (tester) async {
      usePhone(tester);
      engine.failWith = const FileSystemException('disk full');
      await pumpExplore(tester, overrides: [
        ...downloadOverrides(),
        downloadNoticeAgreedProvider.overrideWithBuild((ref, notifier) => true),
      ]);
      await submitSearch(tester, 'mix');
      await openSheet(tester);

      await tester.tap(find.text('720p'));
      await animate(tester);

      expect(find.text('Download Notice'), findsNothing, reason: 'notice was agreed before');
      expect(find.text('Could not add the download. Please try again.'), findsOneWidget);
      expect(coordinator.triggers, 0);

      await unmount(tester);
    });
  });

  testWidgets('no overflow on a 360 dp phone at 1.3x text scale', (tester) async {
    usePhone(tester, width: 360, height: 740);
    final longQuery = 'very long search words ' * 5;
    await SettingsStore.instance.setStringList(_historyKey, [longQuery.trim(), 'jazz', 'lofi']);
    source.results = [
      const OnlineVideo(
        id: 'dQw4w9WgXcQ',
        title: 'An extremely long video title that keeps going and going well past two lines of text '
            'on any phone screen you could possibly imagine',
        author: 'A channel with a remarkably long name that cannot fit on one line at all',
        duration: Duration(hours: 10, minutes: 4, seconds: 5),
        thumbnailUrl: '',
      ),
      _live,
      _folk,
    ];
    await pumpExplore(tester, textScale: 1.3);

    // Layout errors (RenderFlex overflow) are reported as exceptions.
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Clear'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await submitSearch(tester, 'long');
    expect(find.text('10:04:05'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
    }
    expect(find.text('Folk Fusion Session'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });
}
