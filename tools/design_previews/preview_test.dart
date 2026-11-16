// Preview renders for design reviews (not part of the test suite).
// Real Inter + MaterialIcons, 360x800 dp at 3x, no artwork files so every
// cover shows its placeholder.
//
// Run from the repo root:
//   flutter test tools/design_previews/preview_test.dart
// PNGs land in build/design_previews/ (or $PREVIEW_OUT).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/features/explore/explore_screen.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/explore/online_source.dart';
import 'package:mediahub/features/home/home_screen.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/mini_player.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/music_screen.dart';
import 'package:mediahub/features/music_player/now_playing_sheet.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/music_player/queue_sheet.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/videos_screen.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mocktail/mocktail.dart';

final repoRoot = Directory.current.path.replaceAll(r'\', '/');
final outDir = Platform.environment['PREVIEW_OUT'] ?? '$repoRoot/build/design_previews';

/// The Flutter SDK folder, for the Material icon font.
String flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
}
final shotKey = GlobalKey();

class MockRepo extends Mock implements LibraryRepository {}

class MockPerm extends Mock implements MediaPermissionService {}

class MockAudioPlayer extends Mock implements AudioPlayer {}

class FakeAudioSource extends Fake implements AudioSource {}

class FakePlaybackState extends Fake implements domain.PlaybackState {}

class MockPlaybackRepository extends Mock implements PlaybackRepository {}

class FakePlayback extends PlaybackNotifier {
  final domain.PlaybackState s;
  FakePlayback(this.s);
  @override
  domain.PlaybackState build() => s;
}

class FakeVideoNotifier extends VideoLibraryNotifier {
  final LibraryState initial;
  FakeVideoNotifier(this.initial);
  @override
  LibraryState build() => initial;
}

class FakeOnlineSource implements OnlineSource {
  List<OnlineVideo> results = const [];
  @override
  Future<List<OnlineVideo>> search(String query) => Future.value(results);
  @override
  Future<OnlineStreams> streams(String videoId) =>
      Future.value(const OnlineStreams(audio: [], video: []));
  @override
  void dispose() {}
}

class HomeRepo implements LibraryRepository {
  final List<MediaItem> songs;
  final List<MediaItem> videos;
  HomeRepo(this.songs, this.videos);

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) =>
      Stream.value(mediaType == MediaType.audio ? songs : videos);
  @override
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20}) => Stream.value(songs.take(5).toList());
  @override
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20}) => Stream.value(songs.reversed.take(3).toList());
  @override
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType}) =>
      Stream.value(songs.skip(2).take(4).toList());
  @override
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10}) => Stream.value(videos);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MusicAudioHandler makeHandler() {
  final p = MockAudioPlayer();
  when(() => p.playbackEventStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playerStateStream).thenAnswer((_) => const Stream.empty());
  when(() => p.currentIndexStream).thenAnswer((_) => const Stream.empty());
  when(() => p.positionStream).thenAnswer((_) => const Stream.empty());
  when(() => p.durationStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playing).thenReturn(false);
  when(() => p.processingState).thenReturn(ProcessingState.ready);
  when(() => p.position).thenReturn(Duration.zero);
  when(() => p.bufferedPosition).thenReturn(Duration.zero);
  when(() => p.speed).thenReturn(1.0);
  when(() => p.duration).thenReturn(null);
  when(() => p.currentIndex).thenReturn(null);
  when(() => p.shuffleModeEnabled).thenReturn(false);
  when(() => p.hasNext).thenReturn(false);
  when(() => p.hasPrevious).thenReturn(false);
  when(() => p.setShuffleModeEnabled(any())).thenAnswer((_) async {});
  when(() => p.setLoopMode(any())).thenAnswer((_) async {});
  when(() => p.dispose()).thenAnswer((_) async {});
  return MusicAudioHandler(player: p);
}

Future<void> loadFonts() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'Medium', 'SemiBold']) {
    final bytes = File('$repoRoot/assets/fonts/Inter-$f.otf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await inter.load();
  final icons = FontLoader('MaterialIcons');
  final b = File('${flutterRoot()}/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
      .readAsBytesSync();
  icons.addFont(Future.value(ByteData.view(b.buffer)));
  await icons.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

const _songData = [
  ('Resham Firiri (Folk Medley)', 'Himal Sessions', 'Songs of the Hills', 245000),
  ('Sunrise Over Phewa Lake', 'Bipana Gurung', 'Pokhara Mornings', 213000),
  ('Midnight Drive - Extended Night Mix with Strings and Field Recordings', 'Neon Atlas Orchestra', 'After Hours', 512000),
  ('Lullaby for Aama', 'Family Recordings', 'Home Tapes', 158000),
  ('Monsoon Rain on Tin Roofs', 'Field Notes', 'Weather', 301000),
  ('Kathmandu Morning', 'Sajan & Friends', 'Valley Songs', 187000),
  ('The Long Way Home Through the Hills of Ilam, Pt. 2', 'The Ilam Collective feat. Riya Tamang', 'Tea Garden Stories', 389000),
  ('Dashain Kites', 'Kite Club', 'Festival', 176000),
];

final songs = [
  for (var i = 0; i < _songData.length; i++)
    MediaItem(
      id: 'song_$i',
      uri: 'content://media/external/audio/media/${1040 + i * 7}',
      mediaType: MediaType.audio,
      title: _songData[i].$1,
      artist: _songData[i].$2,
      album: _songData[i].$3,
      durationMs: _songData[i].$4,
      sizeBytes: 6000000,
      dateAdded: DateTime(2026, 10, 1 + i),
      source: i == 1 || i == 5 ? 'download' : 'device',
      isFavorite: i == 0 || i == 3,
    ),
];

const _videoData = [
  ('Grandma\'s 80th birthday - full party.mp4', 3723000, 1920, 1080),
  ('Trek to Poon Hill sunrise (drone).mp4', 742000, 3840, 2160),
  ('Bhai Tika 2025.mp4', 1265000, 1280, 720),
  ('School concert - Riya singing the folk song solo with the choir.mp4', 418000, 1920, 1080),
  ('Puppy first bath.mp4', 95000, 1080, 1920),
];

final videos = [
  for (var i = 0; i < _videoData.length; i++)
    MediaItem(
      id: 'video_$i',
      uri: 'content://media/external/video/media/${2210 + i * 5}',
      mediaType: MediaType.video,
      title: _videoData[i].$1,
      durationMs: _videoData[i].$2,
      sizeBytes: 250000000 + i * 91000000,
      width: _videoData[i].$3,
      height: _videoData[i].$4,
      dateAdded: DateTime.now().subtract(Duration(days: i * 3)),
      source: i == 2 ? 'download' : 'device',
    ),
];

domain.PlaybackState playing(int index, {bool isPlaying = true}) => domain.PlaybackState(
      currentItemId: songs[index].id,
      queue: songs,
      queueIndex: index,
      position: const Duration(seconds: 74),
      duration: Duration(milliseconds: songs[index].durationMs),
      isPlaying: isPlaying,
      updatedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockRepo repo;
  late MockPerm perm;
  late MockPlaybackRepository playbackRepo;
  late AppDatabase db;

  final albums = [
    const AlbumGroup(album: 'Songs of the Hills', artist: 'Himal Sessions', songCount: 12, totalDurationMs: 1),
    const AlbumGroup(album: 'After Hours', artist: 'Neon Atlas Orchestra', songCount: 8, totalDurationMs: 1),
    const AlbumGroup(album: 'Home Tapes', artist: 'Family Recordings', songCount: 31, totalDurationMs: 1),
    const AlbumGroup(album: 'Tea Garden Stories (Deluxe Edition)', artist: 'The Ilam Collective', songCount: 14, totalDurationMs: 1),
  ];

  setUpAll(() async {
    registerFallbackValue(MediaSortOption.title);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(FakeAudioSource());
    registerFallbackValue(LoopMode.off);
    registerFallbackValue(FakePlaybackState());
    await loadFonts();
    Directory(outDir).createSync(recursive: true);
    // ignore: avoid_print
    print('song palettes: ${songs.map((s) => ArtworkPlaceholder.paletteIndexFor(s.uri)).toList()}');
    // ignore: avoid_print
    print('video palettes: ${videos.map((s) => ArtworkPlaceholder.paletteIndexFor(s.uri)).toList()}');
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockRepo();
    perm = MockPerm();
    playbackRepo = MockPlaybackRepository();
    when(() => playbackRepo.loadLastPlaybackState()).thenAnswer((_) async => null);
    when(() => playbackRepo.savePlaybackState(any())).thenAnswer((_) async {});
    when(() => perm.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => perm.checkVideoPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => repo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => Stream.value(songs));
    when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(albums));
    when(() => repo.watchArtists(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchPlaylists()).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchFavorites(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(songs));
    when(() => repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value(songs.take(6).toList()));
    when(() => repo.watchArtistSongs(any())).thenAnswer((_) => Stream.value(songs));
  });

  tearDown(() async {
    await db.close();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {domain.PlaybackState? state, List overrides = const [], LibraryRepository? library}) => ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(library ?? repo),
          mediaPermissionServiceProvider.overrideWithValue(perm),
          appDatabaseProvider.overrideWithValue(db),
          audioHandlerProvider.overrideWithValue(makeHandler()),
          playbackRepositoryProvider.overrideWithValue(playbackRepo),
          if (state != null) playbackNotifierProvider.overrideWith(() => FakePlayback(state)),
          throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 74))),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(id == 'song_0' || id == 'song_3')),
          ...overrides.cast(),
        ],
        child: RepaintBoundary(
          key: shotKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            home: home,
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('music_list', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
    await settle(tester);
    await shot(tester, 'music_list');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('mini_player_and_list', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(
      const Scaffold(
        body: MusicScreen(),
        bottomNavigationBar: SafeArea(child: MiniPlayer()),
      ),
      state: playing(4),
    ));
    await settle(tester);
    await shot(tester, 'mini_player_and_list');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final (name, index) in [('now_playing_a', 0), ('now_playing_b', 2)]) {
    testWidgets(name, (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const NowPlayingSheet(), state: playing(index)));
      await settle(tester);
      await shot(tester, name);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('queue', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                clipBehavior: Clip.antiAlias,
                builder: (_) => const FractionallySizedBox(heightFactor: 0.7, child: QueueSheet()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      state: playing(2),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    await shot(tester, 'queue');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('home', (tester) async {
    phone(tester);
    tester.view.physicalSize = const Size(360 * 3, 1640 * 3);
    await tester.pumpWidget(app(
      const HomeScreen(),
      state: playing(1, isPlaying: false),
      library: HomeRepo(songs, videos),
    ));
    await settle(tester);
    await shot(tester, 'home');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('videos', (tester) async {
    phone(tester);
    tester.view.physicalSize = const Size(360 * 3, 1300 * 3);
    final state = LibraryState(
      permissionState: MediaPermissionState.granted,
      status: LibraryStatus.success,
      items: videos,
    );
    await tester.pumpWidget(app(
      const VideosScreen(),
      overrides: [
        videoLibraryProvider.overrideWith(() => FakeVideoNotifier(state)),
        allVideoProgressStreamProvider.overrideWith((ref) => Stream.value([
              VideoProgress(mediaId: 'video_0', positionMs: 1500000, durationMs: 3723000, updatedAt: DateTime.now()),
              VideoProgress(mediaId: 'video_3', positionMs: 120000, durationMs: 418000, updatedAt: DateTime.now()),
            ])),
      ],
    ));
    await settle(tester);
    await shot(tester, 'videos');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('explore_results', (tester) async {
    phone(tester);
    tester.view.physicalSize = const Size(360 * 3, 1200 * 3);
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = false;
    addTearDown(PlatformInfo.resetForTests);
    await SettingsStore.instance.setStringList('explore_history', const []);
    final source = FakeOnlineSource()
      ..results = const [
        OnlineVideo(
          id: 'dQw4w9WgXcQ',
          title: 'Midnight Drive Mix - 1 hour of calm synthwave for late night studying',
          author: 'Neon Atlas',
          duration: Duration(minutes: 58, seconds: 12),
          thumbnailUrl: '',
        ),
        OnlineVideo(
          id: '9bZkp7q19f0',
          title: 'Lofi Radio 24/7',
          author: 'Quiet Hours',
          duration: Duration.zero,
          thumbnailUrl: '',
          isLive: true,
        ),
        OnlineVideo(
          id: 'aqz-KE-bpKQ',
          title: 'Folk Fusion Session',
          author: 'Himal Sessions',
          duration: Duration(hours: 1, minutes: 2, seconds: 3),
          thumbnailUrl: '',
        ),
      ];
    await tester.pumpWidget(app(
      const ExploreScreen(),
      overrides: [onlineSourceProvider.overrideWithValue(source)],
    ));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'midnight');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await shot(tester, 'explore_results');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('album_detail', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(AlbumDetailScreen(album: albums.first), state: playing(3)));
    await settle(tester);
    await shot(tester, 'album_detail');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('albums_grid', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
    await settle(tester);
    await tester.tap(find.text('Albums'));
    await settle(tester);
    await shot(tester, 'albums_grid');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
