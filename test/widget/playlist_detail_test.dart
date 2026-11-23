// The album, artist, playlist and Favourites pages (fix plan P2): Shuffle
// really turns shuffle on, a rename shows at once, the page closes when its
// playlist goes, a playlist row has its menu and drag handle, a removal can
// be undone, "Add songs" adds several at once, and the page menu acts on the
// whole list.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/playable.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements LibraryRepository {}

/// Records what the pages ask of playback, including the shuffle flag.
class _FakePlayback extends PlaybackNotifier {
  final List<String> calls = [];
  bool? lastShuffle;
  List<String> lastQueue = const [];
  int? lastStart;

  @override
  domain.PlaybackState build() => domain.PlaybackState(updatedAt: DateTime(2026));

  @override
  Future<void> loadQueue(List<MediaItem> items, {int startIndex = 0, bool autoPlay = true, bool shuffle = false}) async {
    lastShuffle = shuffle;
    lastQueue = [for (final i in items) i.id];
    lastStart = startIndex;
    calls.add('loadQueue');
  }

  @override
  Future<void> playNextAll(List<MediaItem> items) async => calls.add('playNextAll:${items.map((i) => i.id).join(',')}');

  @override
  Future<void> addAllToQueue(List<MediaItem> items) async =>
      calls.add('addAllToQueue:${items.map((i) => i.id).join(',')}');
}

const _artChannel = MethodChannel('mediahub/media_store');

MediaItem _song(int n, {String source = 'device', MediaAvailability availability = MediaAvailability.available, int? track, int? year}) =>
    MediaItem(
      id: source == 'online' ? 'yt_dQw4w9WgXcQ' : 'song_$n',
      uri: source == 'online' ? 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' : 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: 'Song $n',
      artist: 'Test Artist',
      album: 'Album',
      durationMs: 240000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      source: source,
      availability: availability,
      trackNumber: track,
      year: year,
    );

final _songs = [_song(1), _song(2), _song(3)];
Playlist _playlist(String name) => Playlist(
      id: 'pl_1',
      name: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      songCount: 3,
    );

List<PlaylistTrack> _tracks(List<MediaItem> songs) =>
    [for (var i = 0; i < songs.length; i++) PlaylistTrack(position: i * 2, item: songs[i])];

void main() {
  late _MockRepo repo;
  late _FakePlayback playback;
  late StreamController<Playlist?> playlistStream;

  setUp(() {
    ArtworkService.instance.clearCache();
    repo = _MockRepo();
    playback = _FakePlayback();
    playlistStream = StreamController<Playlist?>.broadcast();
    // Positions 0, 2, 4: the stored positions, not the row index.
    when(() => repo.watchPlaylistTracks('pl_1')).thenAnswer((_) => Stream.value(_tracks(_songs)));
    when(() => repo.watchPlaylist('pl_1')).thenAnswer((_) async* {
      yield _playlist('Road trip');
      yield* playlistStream.stream;
    });
    when(() => repo.removeSongFromPlaylist(any(), any(), any())).thenAnswer((_) async {});
    when(() => repo.insertSongIntoPlaylist(any(), any(), any())).thenAnswer((_) async {});
    when(() => repo.reorderPlaylist(any(), any(), any())).thenAnswer((_) async {});
    when(() => repo.renamePlaylist(any(), any())).thenAnswer((_) async {});
    when(() => repo.addSongsToPlaylist(any(), any())).thenAnswer((inv) async => (inv.positionalArguments[1] as List).length);
    when(() => repo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => Stream.value([_song(1), _song(7), _song(8)]));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_artChannel, (call) async => null);
  });

  setUpAll(() => registerFallbackValue(MediaSortOption.title));

  tearDown(() async {
    await playlistStream.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, null);
    ArtworkService.instance.clearCache();
  });

  Future<void> pump(WidgetTester tester, Widget page, {Size size = const Size(360, 800)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          playbackNotifierProvider.overrideWith(() => playback),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  group('Shuffle turns shuffle mode on (LIB-03)', () {
    testWidgets('on a playlist', (tester) async {
      await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(playback.lastShuffle, isTrue, reason: 'it used to pre-shuffle the list and leave shuffle off');
      expect(playback.lastQueue, ['song_1', 'song_2', 'song_3']);
      expect(playback.lastStart, inInclusiveRange(0, 2));
    });

    testWidgets('on an album, only with the songs that can play', (tester) async {
      when(() => repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value([
            _song(1),
            _song(2, availability: MediaAvailability.missing),
            _song(3),
          ]));
      await pump(
        tester,
        const AlbumDetailScreen(
          album: AlbumGroup(album: 'Album', artist: 'Test Artist', songCount: 3, totalDurationMs: 0, key: 'id:1'),
        ),
      );
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(playback.lastShuffle, isTrue);
      expect(playback.lastQueue, ['song_1', 'song_3'], reason: 'a missing file never goes into the queue');
    });

    testWidgets('on an artist', (tester) async {
      when(() => repo.watchArtistSongs(any())).thenAnswer((_) => Stream.value(_songs));
      await pump(tester, const ArtistDetailScreen(artist: ArtistGroup(artist: 'Test Artist', songCount: 3)));
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(playback.lastShuffle, isTrue);
    });

    testWidgets('on Favourites, leaving the online video out of the queue', (tester) async {
      when(() => repo.watchFavorites(searchQuery: any(named: 'searchQuery')))
          .thenAnswer((_) => Stream.value([_song(1), _song(9, source: 'online'), _song(2)]));
      await pump(tester, const LikedSongsScreen());
      expect(find.byIcon(Icons.smart_display_rounded), findsOneWidget, reason: 'the online video is marked');
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(playback.lastShuffle, isTrue);
      expect(playback.lastQueue, ['song_1', 'song_2'], reason: 'a watch link is not a stream URL');

      await tester.tap(find.text('Play all'));
      await tester.pump();
      expect(playback.lastShuffle, isFalse);
    });
  });

  testWidgets('playCollection plays from the tapped song, among the playable ones', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    final notifier = playback;
    await playCollection(notifier, [_song(1), _song(9, source: 'online'), _song(3)], start: _song(3));
    expect(notifier.lastQueue, ['song_1', 'song_3']);
    expect(notifier.lastStart, 1);
  });

  testWidgets('a rename shows on the open page at once (LIB-04)', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    expect(find.text('Road trip'), findsWidgets);

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Dashain mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => repo.renamePlaylist('pl_1', 'Dashain mix')).called(1);

    playlistStream.add(_playlist('Dashain mix'));
    await tester.pumpAndSettle();
    expect(find.text('Dashain mix'), findsWidgets, reason: 'the page used to keep the old name');
    expect(find.text('Road trip'), findsNothing);
  });

  testWidgets('the page closes when its playlist is deleted', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    expect(find.byType(PlaylistDetailScreen), findsOneWidget);
    playlistStream.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistDetailScreen), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('every playlist row has its menu before the drag handle (LIB-08)', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    expect(find.byTooltip('More actions'), findsNWidgets(3));
    final menu = tester.getCenter(find.byTooltip('More actions').first);
    final handle = tester.getCenter(find.byIcon(Icons.drag_handle_rounded).first);
    expect(menu.dx, lessThan(handle.dx), reason: 'menu first, then the grip');
    expect(menu.dy, closeTo(handle.dy, 1));
  });

  testWidgets('a swiped-away song can be put back with Undo, at its stored position', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    await tester.drag(find.text('Song 2'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    verify(() => repo.removeSongFromPlaylist('pl_1', 'song_2', 2)).called(1);
    expect(find.text('Song 2'), findsNothing);
    expect(find.text('Removed from Road trip'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    verify(() => repo.insertSongIntoPlaylist('pl_1', 'song_2', 2)).called(1);
  });

  testWidgets('a drag reorders by stored positions and shows the new order at once', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    final handle = find.byIcon(Icons.drag_handle_rounded).at(2);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    final captured = verify(() => repo.reorderPlaylist('pl_1', captureAny(), captureAny())).captured;
    expect(captured.first, 4, reason: 'the stored position of row 3');
    expect([0, 2], contains(captured.last));
  });

  testWidgets('"Add songs" picks several songs and adds them in one go (LIB-10)', (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    await tester.tap(find.text('Add songs'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Road trip'), findsOneWidget);
    expect(find.text('In this playlist'), findsOneWidget, reason: 'song 1 is there already');

    await tester.tap(find.text('Song 7'));
    await tester.tap(find.text('Song 8'));
    await tester.pump();
    await tester.tap(find.text('Add 2 songs'));
    await tester.pumpAndSettle();
    verify(() => repo.addSongsToPlaylist('pl_1', ['song_7', 'song_8'])).called(1);
    expect(find.text('Added 2 songs to Road trip'), findsOneWidget);
  });

  testWidgets('the album menu acts on every song, not just the first (LIB-09)', (tester) async {
    when(() => repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value(_songs));
    await pump(
      tester,
      const AlbumDetailScreen(
        album: AlbumGroup(album: 'Album', artist: 'Test Artist', songCount: 3, totalDurationMs: 0, key: 'id:1'),
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to queue'));
    await tester.pumpAndSettle();
    expect(playback.calls, ['addAllToQueue:song_1,song_2,song_3'], reason: 'it used to act on songs.first');
    expect(find.text('Added 3 songs to the queue'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    expect(playback.calls.last, 'playNextAll:song_1,song_2,song_3');
  });

  // Emulator QA: a playlist's own menu offered "Add to playlist…".
  testWidgets("a playlist's own menu has no Add to playlist", (tester) async {
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('Road trip')));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Delete playlist'), findsOneWidget);
    expect(find.text('Add to playlist…'), findsNothing);
  });

  testWidgets("an album's menu still offers Add to playlist", (tester) async {
    when(() => repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value(_songs));
    await pump(
      tester,
      const AlbumDetailScreen(
        album: AlbumGroup(album: 'Album', artist: 'Test Artist', songCount: 3, totalDurationMs: 0, key: 'id:1'),
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Add to playlist…'), findsOneWidget);
  });

  testWidgets('an album shows its track numbers and its year (LIB-02)', (tester) async {
    when(() => repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value([
          _song(1, track: 3, year: 2019),
          _song(2, track: 7, year: 2019),
        ]));
    await pump(
      tester,
      const AlbumDetailScreen(
        album: AlbumGroup(album: 'Album', artist: 'Test Artist', songCount: 2, totalDurationMs: 0, key: 'id:1'),
      ),
    );
    expect(find.text('2019 · 2 songs · 8 min'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('07'), findsOneWidget);
  });

  testWidgets('nothing overflows at 1.3x text on 320 dp, in the light theme too', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, PlaylistDetailScreen(playlist: _playlist('A rather long playlist name')), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Delete playlist'), findsOneWidget);
  });
}
