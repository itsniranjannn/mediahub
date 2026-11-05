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

    final artists = await repo.watchArtists().first;
    expect(artists.length, equals(1));
    expect(artists.first.artist, equals('Queen'));
    expect(artists.first.songCount, equals(2));
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
}
