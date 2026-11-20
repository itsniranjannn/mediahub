// The library on iPhone (iOS parity P3, tasks 1 and 3). There is nothing on
// an iPhone for MediaHub to scan: its songs and videos are what you download
// in MediaHub. So the empty Songs, Videos, Albums and Artists tabs say that
// and offer Open Downloads, and the refresh ("Scan device media") buttons
// are gone. Android keeps its wording and buttons. The library search
// fields type plain quotes and dashes and do not autocorrect (both phones).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/videos_screen.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements LibraryRepository {}

class _MockPermissions extends Mock implements MediaPermissionService {}

class _FakePlayback extends PlaybackNotifier {
  @override
  domain.PlaybackState build() => domain.PlaybackState(updatedAt: DateTime(2026));
}

const _artChannel = MethodChannel('mediahub/media_store');

void main() {
  late _MockRepo repo;
  late _MockPermissions permissions;

  setUpAll(() => registerFallbackValue(MediaSortOption.title));

  setUp(() {
    ArtworkService.instance.clearCache();
    repo = _MockRepo();
    permissions = _MockPermissions();
    when(() => permissions.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => permissions.checkVideoPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => repo.scanDeviceMedia()).thenAnswer((_) async {});
    when(() => repo.mediaStoreGeneration()).thenAnswer((_) async => null);
    when(() => repo.lastScanNewSongCount).thenReturn(null);
    for (final type in MediaType.values) {
      when(() => repo.watchMediaItems(
            mediaType: type,
            searchQuery: any(named: 'searchQuery'),
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
          )).thenAnswer((_) => Stream.value(const []));
    }
    when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchArtists(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchFavorites(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchFavorites()).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchPlaylists()).thenAnswer((_) => Stream.value(const []));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_artChannel, (call) async => null);
  });

  tearDown(() {
    PlatformInfo.resetForTests();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, null);
    ArtworkService.instance.clearCache();
  });

  /// The app's routes that matter here: a library tab and the Downloads tab.
  Future<void> pump(
    WidgetTester tester,
    String start, {
    Size size = const Size(360, 800),
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(path: '/music', builder: (_, _) => const MusicScreen()),
        GoRoute(path: '/videos', builder: (_, _) => const VideosScreen()),
        GoRoute(path: '/downloads', builder: (_, _) => const Scaffold(body: Text('Downloads page'))),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          mediaPermissionServiceProvider.overrideWithValue(permissions),
          playbackNotifierProvider.overrideWith(() => _FakePlayback()),
          currentMediaItemProvider.overrideWith((ref) => null),
          allVideoProgressStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp.router(
          theme: theme ?? AppTheme.darkTheme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Videos fits 360 x 690 at 1.3x text in dark and light', (tester) async {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      await pump(tester, '/videos', size: const Size(360, 690), theme: theme, textScale: 1.3);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Videos'), findsWidgets);
    }
  });

  group('Sindur v2 Videos', () {
    final clips = [
      for (var i = 0; i < 5; i++)
        MediaItem(
          id: 'clip_$i',
          uri: 'content://media/external/video/media/${200 + i}',
          mediaType: MediaType.video,
          title: 'Clip number $i.mp4',
          durationMs: 90000,
          sizeBytes: 1,
          dateAdded: DateTime(2026),
          source: i.isEven ? 'download' : 'device',
        ),
    ];

    void withClips() {
      when(() => repo.watchMediaItems(
            mediaType: MediaType.video,
            searchQuery: any(named: 'searchQuery'),
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
          )).thenAnswer((_) => Stream.value(clips));
    }

    testWidgets('a two-column grid of 16:9 cards under filter chips', (tester) async {
      withClips();
      await pump(tester, '/videos', size: const Size(360, 1400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('On this phone'), findsOneWidget);
      final a = tester.getRect(find.bySemanticsLabel(RegExp(r'^Video: Clip number 0')));
      final b = tester.getRect(find.bySemanticsLabel(RegExp(r'^Video: Clip number 1')));
      expect(a.top, moreOrLessEquals(b.top, epsilon: 0.5), reason: 'two across');
      expect(b.left, greaterThan(a.right));
      await tester.tap(find.text('Downloaded'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.bySemanticsLabel(RegExp(r'^Video: Clip number 1')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Video: Clip number 2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the grid fits 360 x 690 at 1.3x text in dark and light', (tester) async {
      withClips();
      for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        await pump(tester, '/videos', size: const Size(360, 690), theme: theme, textScale: 1.3);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      }
    });
  });

  /// Taps the [label] chip; [from] is a chip on screen now.
  Future<void> openChip(WidgetTester tester, String label, {String from = 'Songs'}) async {
    final chipRow = find.ancestor(of: find.text(from), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text(label), 120, scrollable: chipRow);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  void expectPlainTyping(TextField field) {
    expect(field.autocorrect, isFalse);
    expect(field.smartQuotesType, SmartQuotesType.disabled, reason: 'the iPhone would type ’ for an apostrophe');
    expect(field.smartDashesType, SmartDashesType.disabled);
  }

  group('iPhone', () {
    setUp(() => PlatformInfo.debugIsIOS = true);

    testWidgets('the empty Songs tab: downloads show up here, Open Downloads, no refresh button', (tester) async {
      await pump(tester, '/music');
      expect(find.text('No songs yet'), findsOneWidget);
      expect(find.text('Songs you download in MediaHub show up here.'), findsOneWidget);
      expect(find.text('Find the songs saved on this phone.'), findsNothing);
      expect(find.text('Scan device'), findsNothing);
      expect(find.byTooltip('Scan device media'), findsNothing, reason: 'nothing on an iPhone to scan');
      expect(find.byTooltip('Sort songs'), findsOneWidget, reason: 'sorting stays');

      clearInteractions(repo);
      await tester.tap(find.text('Open Downloads'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads page'), findsOneWidget);
      verifyNever(() => repo.scanDeviceMedia());
    });

    testWidgets('the empty Albums and Artists tabs talk about downloads, not scanning', (tester) async {
      await pump(tester, '/music');
      await openChip(tester, 'Albums');
      expect(find.text('Albums from your downloads show up here.'), findsOneWidget);
      expect(find.text('Albums appear here once your songs are scanned.'), findsNothing);
      expect(find.text('Open Downloads'), findsOneWidget);

      await openChip(tester, 'Artists', from: 'Albums');
      expect(find.text('Artists from your downloads show up here.'), findsOneWidget);
      expect(find.text('Artists appear here once your songs are scanned.'), findsNothing);
      await tester.tap(find.text('Open Downloads'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads page'), findsOneWidget);
    });

    testWidgets('the empty Videos tab: downloads show up here, Open Downloads, no refresh button', (tester) async {
      await pump(tester, '/videos');
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.text('Videos you download in MediaHub show up here.'), findsOneWidget);
      expect(find.text('Find the videos saved on this phone.'), findsNothing);
      expect(find.text('Scan device'), findsNothing, reason: 'it used to only spin');
      expect(find.byTooltip('Scan device media'), findsNothing);
      expect(find.byTooltip('Sort video library'), findsOneWidget);

      clearInteractions(repo);
      await tester.tap(find.text('Open Downloads'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads page'), findsOneWidget);
      verifyNever(() => repo.scanDeviceMedia());
    });

    testWidgets('a search with no match still says so', (tester) async {
      await pump(tester, '/videos');
      await tester.enterText(find.byType(TextField), 'dashain');
      await tester.pump();
      expect(find.text('No matching videos'), findsOneWidget);
      expect(find.text('Open Downloads'), findsNothing);
    });
  });

  group('Android keeps its wording and buttons', () {
    setUp(() => PlatformInfo.debugIsAndroid = true);

    testWidgets('Songs, Albums and Artists', (tester) async {
      await pump(tester, '/music');
      expect(find.text('Find the songs saved on this phone.'), findsOneWidget);
      expect(find.text('Scan device'), findsOneWidget);
      expect(find.byTooltip('Scan device media'), findsOneWidget);
      expect(find.text('Open Downloads'), findsNothing);
      await openChip(tester, 'Albums');
      expect(find.text('Albums appear here once your songs are scanned.'), findsOneWidget);
      expect(find.text('Open Downloads'), findsNothing);
      await openChip(tester, 'Artists', from: 'Albums');
      expect(find.text('Artists appear here once your songs are scanned.'), findsOneWidget);
    });

    testWidgets('Videos', (tester) async {
      await pump(tester, '/videos');
      expect(find.text('Find the videos saved on this phone.'), findsOneWidget);
      expect(find.byTooltip('Scan device media'), findsOneWidget);
      clearInteractions(repo);
      await tester.tap(find.text('Scan device'));
      await tester.pump();
      verify(() => repo.scanDeviceMedia()).called(1);
    });
  });

  group('the search fields type plain quotes and dashes and do not autocorrect', () {
    testWidgets('Music and Videos', (tester) async {
      await pump(tester, '/music');
      expectPlainTyping(tester.widget<TextField>(find.byType(TextField)));
      await pump(tester, '/videos');
      expectPlainTyping(tester.widget<TextField>(find.byType(TextField)));
    });

    for (final ios in [true, false]) {
      testWidgets('Add songs to a playlist (${ios ? 'iPhone' : 'Android'})', (tester) async {
        if (ios) PlatformInfo.debugIsIOS = true;
        final playlist =
            Playlist(id: 'pl_1', name: 'Road trip', createdAt: DateTime(2026), updatedAt: DateTime(2026), songCount: 0);
        when(() => repo.watchPlaylist('pl_1')).thenAnswer((_) => Stream.value(playlist));
        when(() => repo.watchPlaylistTracks('pl_1')).thenAnswer((_) => Stream.value(const []));
        tester.view.physicalSize = const Size(360, 800) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              libraryRepositoryProvider.overrideWithValue(repo),
              playbackNotifierProvider.overrideWith(() => _FakePlayback()),
              isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
            ],
            child: MaterialApp(theme: AppTheme.darkTheme, home: PlaylistDetailScreen(playlist: playlist)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add songs'));
        await tester.pumpAndSettle();
        expect(find.text('Add to Road trip'), findsOneWidget);
        expectPlainTyping(tester.widget<TextField>(find.byType(TextField)));
        expect(find.text('No songs yet'), findsOneWidget);
        expect(find.text('Songs you download in MediaHub show up here.'), ios ? findsOneWidget : findsNothing);
        expect(find.text('Songs on this phone show up here.'), ios ? findsNothing : findsOneWidget);
      });
    }
  });
}
