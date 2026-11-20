// The Music tab and Home after the library work (fix plan P2): the chip
// order with Liked songs second, Liked songs pinned first among the
// playlists, the search reaching playlists, no notification prompt before a
// song plays, friendly permission states, the refresh result, and Home's
// "Liked" tile, in both themes and at 1.3x text on 320 dp.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/home/home_screen.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements LibraryRepository {}

class _MockPermissions extends Mock implements MediaPermissionService {}

class _FakePlayback extends PlaybackNotifier {
  final List<String> loaded = [];
  bool? shuffle;

  /// The player's shuffle mode when the screen opens.
  bool shuffleOn = false;

  @override
  domain.PlaybackState build() => domain.PlaybackState(updatedAt: DateTime(2026), shuffle: shuffleOn);

  @override
  Future<void> loadQueue(List<MediaItem> items, {int startIndex = 0, bool autoPlay = true, bool shuffle = false}) async {
    loaded.add('${items.map((i) => i.id).join(',')}@$startIndex');
    this.shuffle = shuffle;
  }
}

const _artChannel = MethodChannel('mediahub/media_store');
const _permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

MediaItem _song(int n) => MediaItem(
      id: 'song_$n',
      uri: 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: 'Song $n',
      artist: 'Artist $n',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

Playlist _pl(String id, String name) =>
    Playlist(id: id, name: name, createdAt: DateTime(2026), updatedAt: DateTime(2026), songCount: 2);

void main() {
  late _MockRepo repo;
  late _MockPermissions permissions;
  late _FakePlayback playback;
  late List<String> permissionCalls;

  setUpAll(() => registerFallbackValue(MediaSortOption.title));

  setUp(() {
    ArtworkService.instance.clearCache();
    repo = _MockRepo();
    permissions = _MockPermissions();
    playback = _FakePlayback();
    permissionCalls = [];
    when(() => permissions.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => permissions.checkVideoPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => repo.scanDeviceMedia()).thenAnswer((_) async {});
    when(() => repo.mediaStoreGeneration()).thenAnswer((_) async => null);
    when(() => repo.lastScanNewSongCount).thenReturn(3);
    when(() => repo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => Stream.value([_song(1), _song(2)]));
    when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchArtists(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchFavorites(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value([_song(1)]));
    when(() => repo.watchFavorites()).thenAnswer((_) => Stream.value([_song(1)]));
    when(() => repo.watchPlaylists()).thenAnswer((_) => Stream.value([_pl('pl_1', 'Road trip'), _pl('pl_2', 'Dashain')]));
    when(() => repo.watchRecentlyPlayed(limit: any(named: 'limit'))).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchMostPlayed(limit: any(named: 'limit'))).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchRecentlyAdded(limit: any(named: 'limit'), mediaType: any(named: 'mediaType')))
        .thenAnswer((_) => Stream.value([]));
    when(() => repo.watchRecentVideos(limit: any(named: 'limit'))).thenAnswer((_) => Stream.value([]));
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_artChannel, (call) async => null);
    messenger.setMockMethodCallHandler(_permissionChannel, (call) async {
      permissionCalls.add(call.method);
      return call.method == 'requestPermissions' ? <int, int>{} : 1;
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_artChannel, null);
    messenger.setMockMethodCallHandler(_permissionChannel, null);
    ArtworkService.instance.clearCache();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(360, 800),
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          mediaPermissionServiceProvider.overrideWithValue(permissions),
          playbackNotifierProvider.overrideWith(() => playback),
          currentMediaItemProvider.overrideWith((ref) => null),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openChip(WidgetTester tester, String label) async {
    final chipRow = find.ancestor(of: find.text('Songs'), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text(label), 120, scrollable: chipRow);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('the chips read Songs, Liked songs, Playlists, Albums, Artists, and fade at the end', (tester) async {
    expect(MusicScreen.tabs, ['Songs', 'Liked songs', 'Playlists', 'Albums', 'Artists']);
    await pump(tester, const MusicScreen());
    expect(find.text('Liked songs'), findsOneWidget, reason: 'second, so it is on screen without scrolling');
    final chips = find.ancestor(of: find.text('Songs'), matching: find.byType(ShaderMask));
    expect(chips, findsOneWidget, reason: 'the 24 dp end fade (DESIGN.md 7.13)');
  });

  // SEC-3 probe: the first song tap used to wait on a notification prompt.
  testWidgets('tapping a song plays it straight away, with no permission prompt', (tester) async {
    await pump(tester, const MusicScreen());
    await tester.tap(find.text('Song 2'));
    await tester.pump();
    expect(playback.loaded, ['song_1,song_2@1']);
    expect(permissionCalls, isNot(contains('requestPermissions')));
  });

  testWidgets('with shuffle on, a tapped song plays first and shuffle stays on (Spotify)', (tester) async {
    playback.shuffleOn = true;
    await pump(tester, const MusicScreen());
    await tester.tap(find.text('Song 2'));
    await tester.pump();
    expect(playback.loaded, ['song_1,song_2@1']);
    expect(playback.shuffle, isTrue, reason: 'tapping a song must not switch shuffle off');
  });

  testWidgets('with shuffle off, a tapped song plays in list order', (tester) async {
    await pump(tester, const MusicScreen());
    await tester.tap(find.text('Song 2'));
    await tester.pump();
    expect(playback.shuffle, isFalse);
  });

  testWidgets('Shuffle all turns shuffle on', (tester) async {
    await pump(tester, const MusicScreen());
    await tester.tap(find.text('Shuffle all'));
    await tester.pump();
    expect(playback.shuffle, isTrue);
  });

  testWidgets('Liked songs is pinned first among the playlists and opens its page', (tester) async {
    await pump(tester, const MusicScreen());
    await openChip(tester, 'Playlists');
    final liked = tester.getTopLeft(find.bySemanticsLabel(RegExp('^Playlist Liked songs')));
    final road = tester.getTopLeft(find.bySemanticsLabel(RegExp('^Playlist Road trip')));
    expect(liked.dx, lessThan(road.dx), reason: 'first tile of the grid');
    await tester.tap(find.bySemanticsLabel(RegExp('^Playlist Liked songs')));
    await tester.pumpAndSettle();
    expect(find.byType(LikedSongsScreen), findsOneWidget);
  });

  testWidgets('the search reaches the playlists tab', (tester) async {
    await pump(tester, const MusicScreen());
    await tester.enterText(find.byType(TextField), 'dash');
    await tester.pump();
    await openChip(tester, 'Playlists');
    expect(find.bySemanticsLabel(RegExp('^Playlist Dashain')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Playlist Road trip')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Playlist Liked songs')), findsNothing);
  });

  testWidgets('the refresh button says how many new songs it found', (tester) async {
    await pump(tester, const MusicScreen());
    await tester.tap(find.byTooltip('Scan device media'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('3 new songs'), findsOneWidget);
  });

  testWidgets('Music fits 360 x 690 at 1.3x text in dark and light, hero band included', (tester) async {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      await pump(tester, const MusicScreen(), size: const Size(360, 690), theme: theme, textScale: 1.3);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byType(HeroBand), findsOneWidget);
    }
  });

  testWidgets('a grid that fails to load says so and can retry', (tester) async {
    var calls = 0;
    when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) {
      calls++;
      return calls == 1 ? Stream.error(StateError('db')) : Stream.value(const <AlbumGroup>[]);
    });
    await pump(tester, const MusicScreen());
    await openChip(tester, 'Albums');
    expect(find.text("Couldn't load your albums"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No albums found'), findsOneWidget);
  });

  testWidgets('music access off: friendly words and Open settings', (tester) async {
    when(() => permissions.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.permanentlyDenied);
    await pump(tester, const MusicScreen());
    expect(find.text('Music access is off'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);
  });

  testWidgets('no access yet: "Allow access to your music"', (tester) async {
    when(() => permissions.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.denied);
    await pump(tester, const MusicScreen());
    expect(find.text('Allow access to your music'), findsOneWidget);
    expect(find.text('Allow access'), findsOneWidget);
  });

  for (final light in [false, true]) {
    testWidgets('nothing overflows at 1.3x text on 320 dp (${light ? 'paper' : 'ink'})', (tester) async {
      await pump(
        tester,
        const MusicScreen(),
        size: const Size(320, 640),
        textScale: 1.3,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      );
      expect(tester.takeException(), isNull);
      await openChip(tester, 'Playlists');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home has a "Liked" quick tile that opens Liked songs', (tester) async {
    await pump(tester, const HomeScreen());
    expect(find.bySemanticsLabel('Open Liked songs'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Open Liked songs'));
    await tester.pumpAndSettle();
    expect(find.byType(LikedSongsScreen), findsOneWidget);
  });

  testWidgets('Home quick tiles hold at 1.3x text on 320 dp', (tester) async {
    await pump(tester, const HomeScreen(), size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Open Liked songs'), findsOneWidget);
  });
}
