import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';

class MockMethodChannel implements MethodChannel {
  List<dynamic>? queryAudioResult;
  List<dynamic>? queryVideoResult = [];
  bool throwError = false;

  @override
  String get name => 'mediahub/media_store';

  @override
  MethodCodec get codec => const StandardMethodCodec();

  @override
  BinaryMessenger get binaryMessenger => throw UnimplementedError();

  @override
  Future<List<T>?> invokeListMethod<T>(String method, [dynamic arguments]) async {
    if (throwError) {
      throw PlatformException(code: 'ERROR', message: 'Channel failed');
    }
    if (method == 'queryAudio') {
      return queryAudioResult?.cast<T>();
    }
    if (method == 'queryVideo') {
      return queryVideoResult?.cast<T>();
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('toggleFavorite updates isFavorite state and emits in watchFavorites', () async {
    final now = DateTime.now();
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'song_1',
        uri: 'file:///song1.mp3',
        mediaType: MediaType.audio.name,
        title: 'Song One',
        durationMs: 180000,
        sizeBytes: 3000000,
        dateAdded: now,
      ),
    );

    // Initial check: not favorite
    var favs = await repo.watchFavorites().first;
    expect(favs, isEmpty);

    // Toggle on
    await repo.toggleFavorite('song_1');
    favs = await repo.watchFavorites().first;
    expect(favs.length, equals(1));
    expect(favs.first.id, equals('song_1'));
    expect(favs.first.isFavorite, isTrue);

    // Toggle off
    await repo.toggleFavorite('song_1');
    favs = await repo.watchFavorites().first;
    expect(favs, isEmpty);
  });

  test('Playlist creation, adding songs, reordering, and removal', () async {
    final now = DateTime.now();
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'song_a',
        uri: 'file:///a.mp3',
        mediaType: MediaType.audio.name,
        title: 'Song A',
        durationMs: 100000,
        sizeBytes: 1000,
        dateAdded: now,
      ),
    );
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'song_b',
        uri: 'file:///b.mp3',
        mediaType: MediaType.audio.name,
        title: 'Song B',
        durationMs: 100000,
        sizeBytes: 1000,
        dateAdded: now,
      ),
    );

    // 1. Create playlist
    final pl = await repo.createPlaylist('Favorites Mix');
    expect(pl.name, 'Favorites Mix');
    expect(pl.songCount, 0);

    // 2. Add songs
    await repo.addSongToPlaylist(pl.id, 'song_a');
    await repo.addSongToPlaylist(pl.id, 'song_b');

    var songs = await repo.watchPlaylistSongs(pl.id).first;
    expect(songs.length, 2);
    expect(songs[0].id, 'song_a');
    expect(songs[1].id, 'song_b');

    // 3. Reorder songs
    await repo.reorderPlaylist(pl.id, 0, 1);
    songs = await repo.watchPlaylistSongs(pl.id).first;
    expect(songs[0].id, 'song_b');
    expect(songs[1].id, 'song_a');

    // 4. Remove song
    await repo.removeSongFromPlaylist(pl.id, 'song_a', 1);
    songs = await repo.watchPlaylistSongs(pl.id).first;
    expect(songs.length, 1);
    expect(songs[0].id, 'song_b');

    // 5. Delete playlist
    await repo.deletePlaylist(pl.id);
    final playlists = await repo.watchPlaylists().first;
    expect(playlists.any((p) => p.id == pl.id), isFalse);
  });

  test('Albums and Artists grouping queries', () async {
    final now = DateTime.now();
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'track_1',
        uri: 'file:///t1.mp3',
        mediaType: MediaType.audio.name,
        title: 'Track 1',
        artist: const Value('Queen'),
        album: const Value('A Night at the Opera'),
        durationMs: 200000,
        sizeBytes: 2000000,
        dateAdded: now,
      ),
    );
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'track_2',
        uri: 'file:///t2.mp3',
        mediaType: MediaType.audio.name,
        title: 'Track 2',
        artist: const Value('Queen'),
        album: const Value('A Night at the Opera'),
        durationMs: 300000,
        sizeBytes: 3000000,
        dateAdded: now,
      ),
    );

    final albums = await repo.watchAlbums().first;
    expect(albums.length, equals(1));
    expect(albums.first.album, equals('A Night at the Opera'));
    expect(albums.first.songCount, equals(2));
    expect(albums.first.totalDurationMs, equals(500000));
    expect(albums.first.coverUri, equals('file:///t1.mp3'));

    final artists = await repo.watchArtists().first;
    expect(artists.length, equals(1));
    expect(artists.first.artist, equals('Queen'));
    expect(artists.first.songCount, equals(2));
  });

  test('watchAlbums picks one stable cover song per album, from that album only', () async {
    final now = DateTime.now();
    Future<void> insert(String id, String uri, String? album, {String artist = 'Himal Sessions', String type = 'audio'}) {
      return db.into(db.mediaItemsTable).insert(
            MediaItemsTableCompanion.insert(
              id: id,
              uri: uri,
              mediaType: type,
              title: 'Track $id',
              artist: Value(artist),
              album: Value(album),
              durationMs: 1000,
              sizeBytes: 1,
              dateAdded: now,
            ),
          );
    }

    // Inserted out of uri order; the smallest uri of each album wins.
    await insert('h3', 'content://media/external/audio/media/30', 'Songs of the Hills');
    await insert('h1', 'content://media/external/audio/media/12', 'Songs of the Hills');
    await insert('h2', 'content://media/external/audio/media/21', 'Songs of the Hills');
    await insert('a1', 'content://media/external/audio/media/05', 'After Hours', artist: 'Neon Atlas');
    // A video with the album tag never stands in for the album cover.
    await insert('v1', 'content://media/external/video/media/01', 'Songs of the Hills', type: 'video');

    final albums = await repo.watchAlbums().first;
    final byName = {for (final a in albums) a.album: a};
    expect(byName.keys, containsAll(['Songs of the Hills', 'After Hours']));
    expect(byName['Songs of the Hills']!.coverUri, 'content://media/external/audio/media/12');
    expect(byName['Songs of the Hills']!.songCount, 3);
    expect(byName['After Hours']!.coverUri, 'content://media/external/audio/media/05');

    // The cover song is one of the album's own songs (the detail header picks it from these).
    final hillSongs = await repo.watchAlbumSongs('Songs of the Hills').first;
    expect(hillSongs.map((s) => s.uri), contains(byName['Songs of the Hills']!.coverUri));

    // Still stable after a search and after another song joins with a larger uri.
    await insert('h4', 'content://media/external/audio/media/99', 'Songs of the Hills');
    final searched = await repo.watchAlbums(searchQuery: 'Hills').first;
    expect(searched.single.coverUri, 'content://media/external/audio/media/12');
    expect(searched.single.coverArtworkPath, equals(null), reason: 'device songs carry their art embedded');
  });

  test('watchAlbums carries the cover song\'s saved thumbnail, for downloads', () async {
    final now = DateTime.now();
    Future<void> insert(String id, String uri, {String? artworkPath}) {
      return db.into(db.mediaItemsTable).insert(
            MediaItemsTableCompanion.insert(
              id: id,
              uri: uri,
              mediaType: 'audio',
              title: 'Track $id',
              artist: const Value('Mountain Bridges'),
              // Downloads are saved without an album tag.
              album: const Value(null),
              durationMs: 1000,
              sizeBytes: 1,
              dateAdded: now,
              source: const Value('download'),
              artworkPath: Value(artworkPath),
            ),
          );
    }

    // The thumbnail must come from the min(uri) row, not from whichever row
    // SQLite met first or last.
    await insert('d2', 'file:///music/b.m4a', artworkPath: '/thumbs/b.jpg');
    await insert('d1', 'file:///music/a.m4a', artworkPath: '/thumbs/a.jpg');
    await insert('d3', 'file:///music/c.m4a', artworkPath: '/thumbs/c.jpg');

    final unknown = (await repo.watchAlbums().first).single;
    expect(unknown.album, 'Unknown Album');
    expect(unknown.coverUri, 'file:///music/a.m4a');
    expect(unknown.coverArtworkPath, '/thumbs/a.jpg');

    // The album page finds that same song, with that same thumbnail.
    final songs = await repo.watchAlbumSongs('Unknown Album').first;
    final cover = songs.singleWhere((s) => s.uri == unknown.coverUri);
    expect(cover.artworkPath, unknown.coverArtworkPath);
  });

  test('Playlist remove sequential items: add A,B,C; remove A; remove B; C remains', () async {
    final now = DateTime.now();
    for (final id in ['seq_a', 'seq_b', 'seq_c']) {
      await db.into(db.mediaItemsTable).insert(
        MediaItemsTableCompanion.insert(
          id: id,
          uri: 'file:///$id.mp3',
          mediaType: MediaType.audio.name,
          title: 'Song $id',
          durationMs: 100000,
          sizeBytes: 1000,
          dateAdded: now,
        ),
      );
    }
    final pl = await repo.createPlaylist('Sequential Test');
    await repo.addSongToPlaylist(pl.id, 'seq_a'); // A (pos 0)
    await repo.addSongToPlaylist(pl.id, 'seq_b'); // B (pos 1)
    await repo.addSongToPlaylist(pl.id, 'seq_c'); // C (pos 2)

    // Remove A (was at pos 0)
    await repo.removeSongFromPlaylist(pl.id, 'seq_a', 0);

    // Remaining items are renumbered: B is now at pos 0, C is at pos 1
    var current = await repo.watchPlaylistSongs(pl.id).first;
    expect(current.length, 2);
    expect(current[0].id, 'seq_b');
    expect(current[1].id, 'seq_c');

    // Remove B (now at pos 0)
    await repo.removeSongFromPlaylist(pl.id, 'seq_b', 0);

    // Only C remains at pos 0
    current = await repo.watchPlaylistSongs(pl.id).first;
    expect(current.length, 1);
    expect(current[0].id, 'seq_c');
  });

  test('Availability updates: updateAvailability marks missing and available', () async {
    final now = DateTime.now();
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'avail_test_1',
        uri: 'file:///avail1.mp3',
        mediaType: MediaType.audio.name,
        title: 'Avail Track',
        durationMs: 100000,
        sizeBytes: 1000,
        dateAdded: now,
      ),
    );

    // Initial state is available
    var item = await (db.select(db.mediaItemsTable)..where((tbl) => tbl.id.equals('avail_test_1'))).getSingle();
    expect(item.availability, 'available');

    // Mark as missing
    await repo.updateAvailability('avail_test_1', MediaAvailability.missing);
    item = await (db.select(db.mediaItemsTable)..where((tbl) => tbl.id.equals('avail_test_1'))).getSingle();
    expect(item.availability, 'missing');

    // Mark back as available
    await repo.updateAvailability('avail_test_1', MediaAvailability.available);
    item = await (db.select(db.mediaItemsTable)..where((tbl) => tbl.id.equals('avail_test_1'))).getSingle();
    expect(item.availability, 'available');
  });

  test('scanDeviceMedia availability tracking and error handling with mock channel', () async {
    final mockChannel = MockMethodChannel();
    final scanRepo = LibraryRepositoryImpl(db, mockChannel);

    // Initial scan with songs A, B, C
    mockChannel.queryAudioResult = [
      {'id': 'A', 'uri': 'file:///a.mp3', 'title': 'Song A'},
      {'id': 'B', 'uri': 'file:///b.mp3', 'title': 'Song B'},
      {'id': 'C', 'uri': 'file:///c.mp3', 'title': 'Song C'},
    ];
    await scanRepo.scanDeviceMedia();

    var items = await scanRepo.watchMediaItems(mediaType: MediaType.audio).first;
    expect(items.length, 3);
    expect(items.every((i) => i.availability == MediaAvailability.available), isTrue);

    // Rescan with A, B (C becomes missing)
    mockChannel.queryAudioResult = [
      {'id': 'A', 'uri': 'file:///a.mp3', 'title': 'Song A'},
      {'id': 'B', 'uri': 'file:///b.mp3', 'title': 'Song B'},
    ];
    await scanRepo.scanDeviceMedia();

    items = await scanRepo.watchMediaItems(mediaType: MediaType.audio).first;
    expect(items.length, 3);
    expect(items.firstWhere((i) => i.id == 'audio_A').availability, MediaAvailability.available);
    expect(items.firstWhere((i) => i.id == 'audio_B').availability, MediaAvailability.available);
    expect(items.firstWhere((i) => i.id == 'audio_C').availability, MediaAvailability.missing);

    // Rescan with A, B, C (C is available again)
    mockChannel.queryAudioResult = [
      {'id': 'A', 'uri': 'file:///a.mp3', 'title': 'Song A'},
      {'id': 'B', 'uri': 'file:///b.mp3', 'title': 'Song B'},
      {'id': 'C', 'uri': 'file:///c.mp3', 'title': 'Song C'},
    ];
    await scanRepo.scanDeviceMedia();

    items = await scanRepo.watchMediaItems(mediaType: MediaType.audio).first;
    expect(items.length, 3);
    expect(items.firstWhere((i) => i.id == 'audio_C').availability, MediaAvailability.available);

    // Rescan with thrown channel error (nothing changes, C remains available)
    mockChannel.throwError = true;
    await scanRepo.scanDeviceMedia();

    items = await scanRepo.watchMediaItems(mediaType: MediaType.audio).first;
    expect(items.length, 3);
    expect(items.every((i) => i.availability == MediaAvailability.available), isTrue);
  });

  test('scanDeviceMedia skips missing pass if scan result is empty while DB has rows', () async {
    final mockChannel = MockMethodChannel();
    final scanRepo = LibraryRepositoryImpl(db, mockChannel);

    // Initial scan with song A
    mockChannel.queryAudioResult = [
      {'id': 'A', 'uri': 'file:///a.mp3', 'title': 'Song A'},
    ];
    await scanRepo.scanDeviceMedia();

    var items = await scanRepo.watchMediaItems(mediaType: MediaType.audio).first;
    expect(items.length, 1);
    expect(items.first.availability, MediaAvailability.available);

    // Rescan with empty result list (empty scan on non-empty DB)
    mockChannel.queryAudioResult = [];
    await scanRepo.scanDeviceMedia();

    // Guard ensures Song A does NOT become missing
    items = await scanRepo.watchMediaItems(mediaType: MediaType.audio).first;
    expect(items.length, 1);
    expect(items.first.availability, MediaAvailability.available);
  });

  test("rescan carries favourites, plays, playlists and video progress to a file's new id", () async {
    final mockChannel = MockMethodChannel();
    final scanRepo = LibraryRepositoryImpl(db, mockChannel);

    Map<String, Object> song(String id, String title, int size, int ms) =>
        {'id': id, 'uri': 'content://media/external/audio/media/$id', 'title': title, 'sizeBytes': size, 'durationMs': ms};
    Map<String, Object> video(String id, String title, int size, int ms) =>
        {'id': id, 'uri': 'content://media/external/video/media/$id', 'title': title, 'sizeBytes': size, 'durationMs': ms};

    mockChannel.queryAudioResult = [song('1', 'Morning Raga', 4000000, 240000), song('2', 'Other', 123, 1000)];
    mockChannel.queryVideoResult = [video('7', 'Trip', 9000000, 60000)];
    await scanRepo.scanDeviceMedia();

    await scanRepo.toggleFavorite('audio_1');
    await scanRepo.recordPlay('audio_1');
    await scanRepo.recordPlay('audio_1');
    final playlist = await scanRepo.createPlaylist('Road trip');
    await scanRepo.addSongToPlaylist(playlist.id, 'audio_1');
    await db.into(db.videoProgressTable).insert(VideoProgressTableCompanion.insert(
        mediaId: 'video_7', positionMs: 30000, durationMs: 60000, updatedAt: DateTime.now()));

    // The same files come back with new MediaStore ids (e.g. after moving to a new phone);
    // the second song did not change at all.
    mockChannel.queryAudioResult = [song('101', 'Morning Raga', 4000000, 240500), song('2', 'Other', 123, 1000)];
    mockChannel.queryVideoResult = [video('207', 'Trip', 9000000, 60000)];
    await scanRepo.scanDeviceMedia();

    final rows = await db.select(db.mediaItemsTable).get();
    expect(rows.map((r) => r.id).toSet(), {'audio_101', 'audio_2', 'video_207'},
        reason: 'old rows are replaced, not duplicated');
    final moved = rows.firstWhere((r) => r.id == 'audio_101');
    expect(moved.isFavorite, isTrue);
    expect(moved.playCount, 2);
    expect(moved.lastPlayed != null, isTrue);
    final entries = await db.select(db.playlistItemsTable).get();
    expect(entries.single.mediaId, 'audio_101');
    final progress = await db.select(db.videoProgressTable).get();
    expect(progress.single.mediaId, 'video_207');
    expect(progress.single.positionMs, 30000);
  });

  test('rescan does not carry data over when the match is ambiguous', () async {
    final mockChannel = MockMethodChannel();
    final scanRepo = LibraryRepositoryImpl(db, mockChannel);
    mockChannel.queryAudioResult = [
      {'id': '1', 'uri': 'content://a/1', 'title': 'Same', 'sizeBytes': 500, 'durationMs': 1000},
    ];
    await scanRepo.scanDeviceMedia();
    await scanRepo.toggleFavorite('audio_1');

    // Two new files look identical to the missing one: do not guess.
    mockChannel.queryAudioResult = [
      {'id': '2', 'uri': 'content://a/2', 'title': 'Same', 'sizeBytes': 500, 'durationMs': 1000},
      {'id': '3', 'uri': 'content://a/3', 'title': 'Same', 'sizeBytes': 500, 'durationMs': 1000},
    ];
    await scanRepo.scanDeviceMedia();

    final rows = await db.select(db.mediaItemsTable).get();
    final old = rows.firstWhere((r) => r.id == 'audio_1');
    expect(old.isFavorite, isTrue, reason: 'kept on the old (missing) row');
    expect(old.availability, 'missing');
    expect(rows.where((r) => r.id != 'audio_1').every((r) => !r.isFavorite), isTrue);
  });
}
