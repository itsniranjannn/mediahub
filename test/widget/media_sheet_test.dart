// The media sheet ("media dropdown", docs/DESIGN.md 7.10): every action it
// offers does what it says, in both themes, as a bottom sheet on a phone and
// as an anchored popup menu on a wide screen.
import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/media_context_menu.dart';
import 'package:mediahub/features/library/media_song_row.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements LibraryRepository {}

/// Records what the sheet asks of playback.
class _FakePlayback extends PlaybackNotifier {
  _FakePlayback(this._initial);

  final domain.PlaybackState _initial;
  final List<String> calls = [];

  @override
  domain.PlaybackState build() => _initial;

  @override
  void playNext(MediaItem item) => calls.add('playNext:${item.id}');

  @override
  void addToQueue(MediaItem item) {
    calls.add('addToQueue:${item.id}');
    state = state.copyWith(queue: [...state.queue, item]);
  }

  @override
  Future<void> loadQueue(List<MediaItem> items, {int startIndex = 0, bool autoPlay = true, bool shuffle = false}) async {
    calls.add('loadQueue:${items.map((m) => m.id).join(',')}');
  }

  @override
  Future<void> removeQueueItemAt(int index) async => calls.add('remove:$index');
}

class _FakePlatform extends MediaMenuPlatform {
  bool pipSupported = true;
  bool pipWorks = true;
  int pipEntered = 0;
  final List<String> openedVideos = [];
  final List<String> tabs = [];
  final List<String> copied = [];

  @override
  Future<bool> isPipSupported() async => pipSupported;

  @override
  Future<bool> enterPip() async {
    pipEntered++;
    return pipWorks;
  }

  @override
  void openVideo(BuildContext context, MediaItem item) => openedVideos.add(item.id);

  @override
  void openTab(BuildContext context, String location) => tabs.add(location);

  @override
  Future<void> copyText(String text) async => copied.add(text);
}

class _FakeDeleter implements MediaFileDeleter {
  final List<String> deleted = [];
  bool fails = false;

  @override
  bool canDelete(MediaItem item) => item.source == 'download';

  @override
  Future<void> delete(MediaItem item) async {
    if (fails) throw const FileSystemException('busy');
    deleted.add(item.id);
  }
}

const _artChannel = MethodChannel('mediahub/media_store');

MediaItem _song({
  String id = 'song_1',
  String title = 'Resham Firiri',
  String? artist = 'Bipana Thapa',
  String? album = 'Lok Geet',
  String source = 'device',
  bool isFavorite = false,
}) =>
    MediaItem(
      id: id,
      uri: source == 'download' ? '/data/user/0/app/files/$id.mp3' : 'content://media/external/audio/media/$id',
      mediaType: MediaType.audio,
      title: title,
      artist: artist,
      album: album,
      durationMs: 245000,
      sizeBytes: 4200000,
      format: 'mpeg',
      dateAdded: DateTime(2026, 3, 14),
      playCount: 7,
      isFavorite: isFavorite,
      source: source,
    );

MediaItem _video({String source = 'device'}) => MediaItem(
      id: 'video_1',
      uri: 'content://media/external/video/media/1',
      mediaType: MediaType.video,
      title: 'Family_Trip_to_Pokhara.mp4',
      artist: 'Local Video',
      durationMs: 768000,
      sizeBytes: 52000000,
      width: 1920,
      height: 1080,
      dateAdded: DateTime(2026, 5, 2),
      source: source,
    );

class _Harness {
  _Harness(this.playback);

  final _MockRepo repo = _MockRepo();
  final _FakePlayback playback;
  final _FakePlatform platform = _FakePlatform();
  final _FakeDeleter deleter = _FakeDeleter();
  bool favorite = false;
}

Future<_Harness> _pump(
  WidgetTester tester,
  MediaItem item, {
  ThemeData? theme,
  Size size = const Size(360, 800),
  bool favorite = false,
  MediaItem? playing,
  bool inkWrapper = false,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final queue = playing == null ? <MediaItem>[] : [playing];
  final h = _Harness(_FakePlayback(domain.PlaybackState(
    queue: queue,
    queueIndex: queue.isEmpty ? -1 : 0,
    currentItemId: playing?.id,
    updatedAt: DateTime(2026),
  )))
    ..favorite = favorite;

  when(() => h.repo.toggleFavorite(any())).thenAnswer((_) async {});
  when(() => h.repo.watchPlaylists()).thenAnswer((_) => Stream.value([
        Playlist(id: 'pl_1', name: 'Road trip', createdAt: DateTime(2026), updatedAt: DateTime(2026), songCount: 3),
      ]));
  when(() => h.repo.addSongToPlaylist(any(), any())).thenAnswer((_) async {});
  when(() => h.repo.createPlaylist(any())).thenAnswer(
    (inv) async => Playlist(
      id: 'pl_new',
      name: inv.positionalArguments.first as String,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );
  when(() => h.repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer(
    (_) => Stream.value([
      const AlbumGroup(album: 'Lok Geet', artist: 'Bipana Thapa', songCount: 1, totalDurationMs: 245000),
    ]),
  );
  when(() => h.repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value([item]));
  when(() => h.repo.watchArtistSongs(any())).thenAnswer((_) => Stream.value([item]));

  // The Consumer's context is the button's box: the wide-screen popup hangs
  // from it, as it hangs from a row's ⋮.
  Widget opener = Center(
    child: Consumer(
      builder: (context, ref, _) => TextButton(
        onPressed: () => MediaContextMenu.show(context, ref, item),
        child: const Text('open'),
      ),
    ),
  );
  // Now Playing is always ink; the sheet it opens follows the app theme.
  if (inkWrapper) opener = Theme(data: AppTheme.darkTheme, child: opener);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(h.repo),
        playbackNotifierProvider.overrideWith(() => h.playback),
        isFavoriteProvider.overrideWith((ref, id) => Stream.value(h.favorite)),
        mediaMenuPlatformProvider.overrideWithValue(h.platform),
        mediaFileDeleterProvider.overrideWithValue(h.deleter),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Scaffold(body: opener),
      ),
    ),
  );
  await tester.pump();
  return h;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The visible action labels of the open sheet, top to bottom.
List<String> _sheetLabels(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      )))
        (tile.title! as Text).data!,
    ];

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(MediaSortOption.title);
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_artChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, null);
    ArtworkService.instance.clearCache();
  });

  group('which actions an item gets', () {
    test('a song on the phone: queue, playlist, favourite, album, artist, details; no delete, no share', () {
      expect(
        MediaContextMenu.actionsFor(_song(), canDelete: false, pipSupported: true),
        [
          MediaAction.playNext,
          MediaAction.addToQueue,
          MediaAction.addToPlaylist,
          MediaAction.favorite,
          MediaAction.goToAlbum,
          MediaAction.goToArtist,
          MediaAction.details,
        ],
      );
    });

    test('a download can be deleted; an unknown artist and no album hide the "Go to" rows', () {
      final song = _song(source: 'download', artist: 'Unknown Artist', album: null);
      expect(
        MediaContextMenu.actionsFor(song, canDelete: true, pipSupported: false),
        [
          MediaAction.playNext,
          MediaAction.addToQueue,
          MediaAction.addToPlaylist,
          MediaAction.favorite,
          MediaAction.details,
          MediaAction.delete,
        ],
      );
    });

    test('a video: play, as audio, picture-in-picture where supported, details', () {
      expect(
        MediaContextMenu.actionsFor(_video(), canDelete: false, pipSupported: true),
        [MediaAction.play, MediaAction.playAsAudio, MediaAction.pictureInPicture, MediaAction.details],
      );
      expect(
        MediaContextMenu.actionsFor(_video(), canDelete: false, pipSupported: false),
        isNot(contains(MediaAction.pictureInPicture)),
      );
    });

    test('an online item: download, copy link, details', () {
      final online = _song().copyWith(source: 'online', uri: 'https://youtu.be/abc123');
      expect(
        MediaContextMenu.actionsFor(online, canDelete: false, pipSupported: false),
        [MediaAction.download, MediaAction.copyLink, MediaAction.details],
      );
      expect(
        MediaContextMenu.actionsFor(online, canDelete: false, pipSupported: false, downloadsSupported: false),
        [MediaAction.copyLink, MediaAction.details],
      );
    });

    test('details list the figures in DM Mono rows', () {
      final rows = MediaContextMenu.detailRows(_song(source: 'download'));
      expect(rows, contains(('Length', '4:05', true)));
      expect(rows, contains(('Size', '4.0 MB', true)));
      expect(rows, contains(('Plays', '7', true)));
      expect(rows, contains(('Saved', 'Downloaded to this phone', false)));
      expect(rows.map((r) => r.$1), contains('File'));
      expect(
        MediaContextMenu.detailRows(_video()),
        contains(('Resolution', '1920 × 1080', true)),
      );
    });
  });

  group('song sheet', () {
    testWidgets('header, rows in order, and the favourite row follows the database', (tester) async {
      await _pump(tester, _song(), favorite: true);
      await _open(tester);

      expect(find.text('Resham Firiri'), findsOneWidget);
      expect(find.text('Bipana Thapa · Lok Geet'), findsOneWidget);
      expect(_sheetLabels(tester), [
        'Play next',
        'Add to queue',
        'Add to playlist…',
        'Remove from favorites',
        'Go to album',
        'Go to artist',
        'Details',
      ]);
      final heart = tester.widget<Icon>(find.byIcon(Icons.favorite_rounded));
      expect(heart.color, AppPalette.dark.favorite);
      expect(find.text('Share'), findsNothing, reason: 'no share sheet in the app yet');
      expect(find.text('Delete from phone'), findsNothing, reason: 'only downloads can be deleted');
    });

    testWidgets('Play next queues the song after the current one', (tester) async {
      final song = _song();
      final h = await _pump(tester, song);
      await _open(tester);
      await _choose(tester, 'Play next');

      expect(find.byType(BottomSheet), findsNothing, reason: 'the sheet closes first');
      expect(h.playback.calls, ['playNext:song_1']);
      expect(find.text('Playing next: Resham Firiri'), findsOneWidget);
    });

    testWidgets('Add to queue appends it, and Undo takes that copy out again', (tester) async {
      final current = _song(id: 'song_0', title: 'Playing');
      final h = await _pump(tester, _song(), playing: current);
      await _open(tester);
      await _choose(tester, 'Add to queue');

      expect(h.playback.calls, ['addToQueue:song_1']);
      expect(find.text('Added to queue: Resham Firiri'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.playback.calls, ['addToQueue:song_1', 'remove:1'], reason: 'by id, not by the old queue length');
    });

    testWidgets('Add to playlist… lists the playlists and adds the song to the chosen one', (tester) async {
      final h = await _pump(tester, _song());
      await _open(tester);
      await _choose(tester, 'Add to playlist…');

      expect(find.text('Add to playlist'), findsOneWidget);
      expect(find.text('Road trip'), findsOneWidget);
      expect(find.text('3 songs'), findsOneWidget);
      await _choose(tester, 'Road trip');
      verify(() => h.repo.addSongToPlaylist('pl_1', 'song_1')).called(1);
      expect(find.text('Added to Road trip'), findsOneWidget);
    });

    testWidgets('"New playlist" creates one with the song in it', (tester) async {
      final h = await _pump(tester, _song());
      await _open(tester);
      await _choose(tester, 'Add to playlist…');
      await _choose(tester, 'New playlist');

      await tester.enterText(find.byType(TextField), 'Dashain');
      await _choose(tester, 'Create');
      verify(() => h.repo.createPlaylist('Dashain')).called(1);
      verify(() => h.repo.addSongToPlaylist('pl_new', 'song_1')).called(1);
      expect(find.text('Created playlist "Dashain"'), findsOneWidget);
    });

    testWidgets('Add to favorites toggles it, and Undo toggles it back', (tester) async {
      final h = await _pump(tester, _song());
      await _open(tester);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await _choose(tester, 'Add to favorites');

      verify(() => h.repo.toggleFavorite('song_1')).called(1);
      expect(find.text('Added to Favorites'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      verify(() => h.repo.toggleFavorite('song_1')).called(1);
    });

    testWidgets('Remove from favorites says so', (tester) async {
      final h = await _pump(tester, _song(isFavorite: true), favorite: true);
      await _open(tester);
      await _choose(tester, 'Remove from favorites');
      verify(() => h.repo.toggleFavorite('song_1')).called(1);
      expect(find.text('Removed from Favorites'), findsOneWidget);
    });

    testWidgets('Go to album opens the album page', (tester) async {
      await _pump(tester, _song());
      await _open(tester);
      await _choose(tester, 'Go to album');

      final page = tester.widget<AlbumDetailScreen>(find.byType(AlbumDetailScreen));
      expect(page.album.album, 'Lok Geet');
      expect(find.text('Play all'), findsOneWidget);
    });

    testWidgets('Go to artist opens the artist page', (tester) async {
      await _pump(tester, _song());
      await _open(tester);
      await _choose(tester, 'Go to artist');

      final page = tester.widget<ArtistDetailScreen>(find.byType(ArtistDetailScreen));
      expect(page.artist.artist, 'Bipana Thapa');
    });

    testWidgets('Details shows what the app knows, and closes', (tester) async {
      await _pump(tester, _song());
      await _open(tester);
      await _choose(tester, 'Details');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Length'), findsOneWidget);
      expect(find.text('4:05'), findsOneWidget);
      expect(find.text('On this phone'), findsOneWidget);
      await _choose(tester, 'Close');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Delete from phone asks first; Cancel keeps the file, Delete removes it', (tester) async {
      final h = await _pump(tester, _song(source: 'download'));
      await _open(tester);
      expect(_sheetLabels(tester).last, 'Delete from phone');
      final label = tester.widget<Text>(find.text('Delete from phone'));
      expect(label.style?.color, AppPalette.dark.error);

      await _choose(tester, 'Delete from phone');
      expect(find.text('Delete from phone?'), findsOneWidget);
      await _choose(tester, 'Cancel');
      expect(h.deleter.deleted, isEmpty);

      await _open(tester);
      await _choose(tester, 'Delete from phone');
      await _choose(tester, 'Delete');
      expect(h.deleter.deleted, ['song_1']);
      expect(find.text('Deleted "Resham Firiri"'), findsOneWidget);
    });

    testWidgets('a failed delete says so', (tester) async {
      final h = await _pump(tester, _song(source: 'download'));
      h.deleter.fails = true;
      await _open(tester);
      await _choose(tester, 'Delete from phone');
      await _choose(tester, 'Delete');
      expect(find.text('Could not delete "Resham Firiri".'), findsOneWidget);
    });

    testWidgets('the song that is playing is not deleted from under the player', (tester) async {
      final song = _song(source: 'download');
      final h = await _pump(tester, song, playing: song);
      await _open(tester);
      await _choose(tester, 'Delete from phone');
      expect(find.text('Delete from phone?'), findsNothing);
      expect(find.textContaining('This is playing now'), findsOneWidget);
      expect(h.deleter.deleted, isEmpty);
    });

    testWidgets('a long press on a song row opens the sheet too', (tester) async {
      final song = _song();
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = _MockRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryRepositoryProvider.overrideWithValue(repo),
            currentMediaItemProvider.overrideWith((ref) => null),
            isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
            mediaMenuPlatformProvider.overrideWithValue(_FakePlatform()),
            mediaFileDeleterProvider.overrideWithValue(_FakeDeleter()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: ListView(children: [MediaSongRow(item: song, onTap: () {})])),
          ),
        ),
      );
      await tester.longPress(find.text('Resham Firiri'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Play next'), findsOneWidget);

      Navigator.of(tester.element(find.text('Play next'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Add to queue'), findsOneWidget, reason: 'and from the ⋮');
    });
  });

  group('video sheet', () {
    testWidgets('Play opens the player', (tester) async {
      final h = await _pump(tester, _video());
      await _open(tester);
      expect(_sheetLabels(tester), ['Play', 'Play as audio', 'Picture-in-picture', 'Details']);
      expect(find.text('12:48 · 49.6 MB'), findsOneWidget, reason: 'the meta line');
      await _choose(tester, 'Play');
      expect(h.platform.openedVideos, ['video_1']);
    });

    testWidgets('Play as audio plays the sound through the music player', (tester) async {
      final h = await _pump(tester, _video());
      await _open(tester);
      await _choose(tester, 'Play as audio');
      expect(h.playback.calls, ['loadQueue:video_1']);
      expect(find.textContaining('Playing as audio'), findsOneWidget);
    });

    testWidgets('Picture-in-picture opens the player and shrinks it into the window', (tester) async {
      final h = await _pump(tester, _video());
      await _open(tester);
      await _choose(tester, 'Picture-in-picture');
      expect(h.platform.openedVideos, ['video_1']);
      expect(h.platform.pipEntered, 1);
      expect(find.textContaining('not available'), findsNothing);
    });

    testWidgets('Picture-in-picture that the phone refuses says so', (tester) async {
      final h = await _pump(tester, _video());
      h.platform.pipWorks = false;
      await _open(tester);
      await _choose(tester, 'Picture-in-picture');
      expect(find.text('Picture-in-picture is not available on this device.'), findsOneWidget);
    });

    testWidgets('no picture-in-picture row where the phone has none', (tester) async {
      final h = await _pump(tester, _video());
      h.platform.pipSupported = false;
      await _open(tester);
      expect(find.text('Picture-in-picture'), findsNothing);
    });

    testWidgets('a downloaded video can be deleted', (tester) async {
      final video = _video(source: 'download').copyWith(uri: '/data/user/0/app/files/v.mp4');
      final h = await _pump(tester, video);
      await _open(tester);
      await _choose(tester, 'Delete from phone');
      await _choose(tester, 'Delete');
      expect(h.deleter.deleted, ['video_1']);
    });
  });

  group('online item', () {
    testWidgets('Copy link copies the link', (tester) async {
      final online = _song().copyWith(source: 'online', uri: 'https://youtu.be/abc123');
      final h = await _pump(tester, online);
      await _open(tester);
      await _choose(tester, 'Copy link');
      expect(h.platform.copied, ['https://youtu.be/abc123']);
      expect(find.text('Link copied'), findsOneWidget);
    });
  });

  group('themes and layouts', () {
    testWidgets('in the light theme the sheet is paper, even when opened from the ink stage', (tester) async {
      await _pump(tester, _song(source: 'download'), theme: AppTheme.lightTheme, inkWrapper: true);
      await _open(tester);

      final sheetContext = tester.element(find.text('Play next'));
      expect(Theme.of(sheetContext).brightness, Brightness.light);
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first,
      );
      expect(material.color, AppPalette.light.surface);
      final icon = tester.widget<Icon>(find.byIcon(Icons.playlist_play_rounded));
      expect(icon.color, AppPalette.light.textSecondary);
      expect(tester.widget<Text>(find.text('Delete from phone')).style?.color, AppPalette.light.error);
    });

    testWidgets('rows are 56 dp and nothing overflows at 1.3x text on 320 dp', (tester) async {
      await _pump(tester, _song(title: 'Audit_Long_Tone_5min_Very_Long_File_Name_Recording'), size: const Size(320, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await _open(tester);
      expect(tester.takeException(), isNull);
      for (final tile in find.descendant(of: find.byType(BottomSheet), matching: find.byType(ListTile)).evaluate()) {
        expect(tile.size!.height, greaterThanOrEqualTo(MediaContextMenu.rowHeight));
      }
    });

    testWidgets('on a wide screen a popup menu anchored to the button replaces the sheet', (tester) async {
      final h = await _pump(tester, _song(), size: const Size(900, 600));
      await _open(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PopupMenuItem<MediaAction>), findsNWidgets(7));
      final button = tester.getRect(find.text('open'));
      final first = tester.getRect(find.widgetWithText(PopupMenuItem<MediaAction>, 'Play next'));
      expect((first.center - button.center).distance, lessThan(300), reason: 'next to the button, not a sheet');

      await _choose(tester, 'Play next');
      expect(h.playback.calls, ['playNext:song_1']);
    });
  });

  group('deleting a download for real', () {
    late AppDatabase db;
    late Directory dir;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dir = Directory.systemTemp.createTempSync('media_sheet_delete');
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(LibraryRepositoryImpl(db)),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<void> insertSong(String id, String uri, {String source = 'download', String? artworkPath}) {
      return db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
            id: id,
            uri: uri,
            mediaType: 'audio',
            title: id,
            durationMs: 1000,
            sizeBytes: 10,
            dateAdded: DateTime(2026),
            source: d.Value(source),
            artworkPath: d.Value(artworkPath),
          ));
    }

    test('removes the file, its cover, its rows, and renumbers the playlists it was in', () async {
      final file = File('${dir.path}/song.mp3')..writeAsStringSync('audio');
      final cover = File('${dir.path}/song.jpg')..writeAsStringSync('jpg');
      await insertSong('dl_1', file.path, artworkPath: cover.path);
      await insertSong('other', 'content://media/external/audio/media/9', source: 'device');
      final repo = container.read(libraryRepositoryProvider);
      final pl = await repo.createPlaylist('Mix');
      await repo.addSongToPlaylist(pl.id, 'other');
      await repo.addSongToPlaylist(pl.id, 'dl_1');
      await repo.addSongToPlaylist(pl.id, 'other');
      await db.into(db.videoProgressTable).insert(VideoProgressTableCompanion.insert(
            mediaId: 'dl_1',
            positionMs: 10,
            durationMs: 1000,
            updatedAt: DateTime(2026),
          ));
      final now = DateTime(2026);
      await db.into(db.downloadsTable).insert(DownloadsTableCompanion.insert(
            id: 'task_1',
            url: 'https://example.com/song.mp3',
            host: 'example.com',
            displayName: 'song',
            fileName: 'song.mp3',
            state: 'completed',
            finalPath: d.Value(file.path),
            mediaId: const d.Value('dl_1'),
            createdAt: now,
            updatedAt: now,
          ));

      final deleter = container.read(mediaFileDeleterProvider);
      final item = MediaItem(
        id: 'dl_1',
        uri: file.path,
        mediaType: MediaType.audio,
        title: 'dl_1',
        durationMs: 1000,
        sizeBytes: 10,
        dateAdded: DateTime(2026),
        source: 'download',
        artworkPath: cover.path,
      );
      expect(deleter.canDelete(item), isTrue);
      expect(deleter.canDelete(item.copyWith(source: 'device', uri: 'content://media/1')), isFalse);

      await deleter.delete(item);

      expect(file.existsSync(), isFalse);
      expect(cover.existsSync(), isFalse);
      expect(await db.select(db.mediaItemsTable).get(), hasLength(1));
      expect(await db.select(db.videoProgressTable).get(), isEmpty);
      expect(await db.select(db.downloadsTable).get(), isEmpty);
      final entries = await (db.select(db.playlistItemsTable)
            ..orderBy([(t) => d.OrderingTerm(expression: t.position)]))
          .get();
      expect([for (final e in entries) (e.mediaId, e.position)], [('other', 0), ('other', 1)]);
    });
  });
}
