import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';

void main() {
  test('AppDatabase v3 to v4 migration creates playlists and playlist_items without altering existing data', () async {
    final tempDir = await Directory.systemTemp.createTemp('drift_mig_test');
    final dbFile = File('${tempDir.path}/test_v3_to_v4.db');

    // 1. Create a database at schema version 3 using _V3Database
    final v3Db = _V3Database(NativeDatabase(dbFile));
    await v3Db.into(v3Db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'media_1',
        uri: 'file:///track1.mp3',
        mediaType: 'audio',
        title: 'Bohemian Rhapsody',
        artist: const Value('Queen'),
        album: const Value('A Night at the Opera'),
        durationMs: 354000,
        sizeBytes: 5000000,
        dateAdded: DateTime.now(),
        playCount: const Value(5),
        isFavorite: const Value(true),
      ),
    );
    await v3Db.close();

    // 2. Open via AppDatabase (schemaVersion 4) to trigger onUpgrade
    final db = AppDatabase(NativeDatabase(dbFile));

    // Verify v3 data survived
    final mediaItems = await db.select(db.mediaItemsTable).get();
    expect(mediaItems.length, equals(1));
    expect(mediaItems.first.title, equals('Bohemian Rhapsody'));
    expect(mediaItems.first.artist, equals('Queen'));
    expect(mediaItems.first.isFavorite, isTrue);
    expect(mediaItems.first.playCount, equals(5));

    // Verify new tables are created and usable in v4
    final now = DateTime.now();
    await db.into(db.playlistsTable).insert(
      PlaylistsTableCompanion.insert(
        id: 'pl_1',
        name: 'My Rock Favorites',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.playlistItemsTable).insert(
      PlaylistItemsTableCompanion.insert(
        playlistId: 'pl_1',
        mediaId: 'media_1',
        position: 0,
        addedAt: now,
      ),
    );

    final playlists = await db.select(db.playlistsTable).get();
    expect(playlists.length, equals(1));
    expect(playlists.first.name, equals('My Rock Favorites'));

    final playlistItems = await db.select(db.playlistItemsTable).get();
    expect(playlistItems.length, equals(1));
    expect(playlistItems.first.mediaId, equals('media_1'));
    expect(playlistItems.first.position, equals(0));

    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('AppDatabase v4 to v5 migration creates downloads table and source column without altering existing data', () async {
    final tempDir = await Directory.systemTemp.createTemp('drift_mig_v4_v5');
    final dbFile = File('${tempDir.path}/test_v4_to_v5.db');

    // 1. Create a database at schema version 4 using _V4Database
    final v4Db = _V4Database(NativeDatabase(dbFile));
    await v4Db.into(v4Db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'media_v4',
        uri: 'file:///song.mp3',
        mediaType: 'audio',
        title: 'Song Title',
        durationMs: 120000,
        sizeBytes: 1000000,
        dateAdded: DateTime.now(),
      ),
    );
    await v4Db.close();

    // 2. Open via AppDatabase (schemaVersion 5) to trigger onUpgrade
    final db = AppDatabase(NativeDatabase(dbFile));

    // Verify v4 data survived and default source is 'device'
    final mediaItems = await db.select(db.mediaItemsTable).get();
    expect(mediaItems.length, equals(1));
    expect(mediaItems.first.title, equals('Song Title'));
    expect(mediaItems.first.source, equals('device'));

    // Verify downloads table exists and can be inserted into
    final now = DateTime.now();
    await db.into(db.downloadsTable).insert(
      DownloadsTableCompanion.insert(
        id: 'dl_test_1',
        url: 'https://example.com/audio.mp3',
        host: 'example.com',
        displayName: 'Audio Track',
        fileName: 'audio.mp3',
        state: 'downloading',
        createdAt: now,
        updatedAt: now,
        receivedBytes: const Value(1024),
        totalBytes: const Value(2048),
      ),
    );

    final downloads = await db.select(db.downloadsTable).get();
    expect(downloads.length, equals(1));
    expect(downloads.first.id, equals('dl_test_1'));
    expect(downloads.first.fileName, equals('audio.mp3'));
    expect(downloads.first.receivedBytes, equals(1024));

    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
  // v7 -> v8 (fix plan P2): new library columns, every list working on an
  // existing install straight after the update.
  test('AppDatabase v7 to v8 adds the library columns, fills search keys, clears placeholders and orphan entries',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('drift_mig_v7_v8');
    final dbFile = File('${tempDir.path}/test_v7_to_v8.db');

    final v7 = _V7Database(NativeDatabase(dbFile));
    // Any query opens (and creates) the v7 file.
    await v7.customSelect('SELECT 1').get();
    final added = DateTime(2025, 5, 1).millisecondsSinceEpoch ~/ 1000;
    Future<void> song(String id, String title, String? artist, {String? album, String source = 'device', int fav = 0}) =>
        v7.customStatement(
          'INSERT INTO media_items_table (id, uri, media_type, title, artist, album, duration_ms, size_bytes, '
          'date_added, play_count, is_favorite, availability, source) '
          "VALUES (?, ?, 'audio', ?, ?, ?, 200000, 1000, ?, 3, ?, 'available', ?)",
          [id, 'content://media/external/audio/media/$id', title, artist, album, added, fav, source],
        );
    await song('a', 'Beyoncé Halo', 'Beyoncé', album: 'I Am', fav: 1);
    await song('b', 'रेशम फिरिरी', 'Unknown Artist');
    await song('c', 'Old tag', '<unknown>');
    await song('d', 'Blank', '  ');
    await song('e', 'Download', 'Uploader', source: 'download');
    await v7.customStatement(
      "INSERT INTO playlists_table (id, name, created_at, updated_at) VALUES ('pl_1', 'Mix', ?, ?)",
      [added, added],
    );
    // Entries at 0..3, the one at 1 for a download deleted by the old app.
    var position = 0;
    for (final id in ['a', 'gone_download', 'b', 'e']) {
      await v7.customStatement(
        'INSERT INTO playlist_items_table (playlist_id, media_id, position, added_at) VALUES (?, ?, ?, ?)',
        ['pl_1', id, position++, added],
      );
    }
    await v7.customStatement(
      'INSERT INTO downloads_table (id, url, host, display_name, file_name, state, created_at, updated_at, error_detail) '
      "VALUES ('dl_1', 'https://example.com/a.mp3', 'example.com', 'A', 'a.mp3', 'completed', ?, ?, 'ok')",
      [added, added],
    );
    await v7.close();

    final db = AppDatabase(NativeDatabase(dbFile));
    final rows = {for (final r in await db.select(db.mediaItemsTable).get()) r.id: r};

    // The old data survived, the new columns are there (empty until the next scan).
    expect(rows.keys, unorderedEquals(['a', 'b', 'c', 'd', 'e']));
    expect(rows['a']!.isFavorite, isTrue);
    expect(rows['a']!.playCount, 3);
    expect(rows['a']!.albumId, isNull);
    expect(rows['a']!.trackNumber, isNull);
    expect(rows['a']!.favoritedAt, isNull);

    // Placeholders became NULL, so one "Unknown artist" tile holds them.
    expect([rows['b']!.artist, rows['c']!.artist, rows['d']!.artist], [null, null, null]);
    expect(rows['e']!.artist, 'Uploader');

    // Search keys are filled: accents folded, Devanagari kept.
    expect(rows['a']!.searchKey, contains('beyonce'));
    expect(rows['b']!.searchKey, contains('रेशम'));

    // The orphan entry is gone and the playlist is numbered 0, 1, 2 again.
    final entries = await (db.select(db.playlistItemsTable)..orderBy([(t) => OrderingTerm(expression: t.position)])).get();
    expect([for (final e in entries) (e.mediaId, e.position)], [('a', 0), ('b', 1), ('e', 2)]);

    // Downloads are untouched.
    final downloads = await db.select(db.downloadsTable).get();
    expect(downloads.single.errorDetail, 'ok');

    // And every list works on it.
    final repo = LibraryRepositoryImpl(db);
    expect((await repo.watchPlaylists().first).single.songCount, 3);
    expect(
      (await repo.watchMediaItems(mediaType: MediaType.audio, searchQuery: 'beyonce halo').first).map((m) => m.id),
      ['a'],
    );
    expect((await repo.watchArtists().first).where((a) => a.isUnknown).single.songCount, 3);
    expect((await repo.watchFavorites().first).single.id, 'a');
    expect(await repo.watchAlbums().first, isNotEmpty);

    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
}

class _V4Database extends AppDatabase {
  _V4Database(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await customStatement('''
          CREATE TABLE "media_items_table" (
            "id" TEXT NOT NULL PRIMARY KEY,
            "uri" TEXT NOT NULL,
            "media_type" TEXT NOT NULL,
            "title" TEXT NOT NULL,
            "artist" TEXT NULL,
            "album" TEXT NULL,
            "duration_ms" INTEGER NOT NULL,
            "size_bytes" INTEGER NOT NULL,
            "format" TEXT NULL,
            "width" INTEGER NULL,
            "height" INTEGER NULL,
            "date_added" INTEGER NOT NULL,
            "last_played" INTEGER NULL,
            "play_count" INTEGER NOT NULL DEFAULT 0,
            "is_favorite" INTEGER NOT NULL DEFAULT 0,
            "availability" TEXT NOT NULL DEFAULT 'available'
          );
        ''');
        await customStatement('''
          CREATE TABLE "playback_states_table" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "current_item_id" TEXT NULL,
            "queue_json" TEXT NOT NULL,
            "queue_index" INTEGER NOT NULL DEFAULT -1,
            "position_ms" INTEGER NOT NULL DEFAULT 0,
            "duration_ms" INTEGER NOT NULL DEFAULT 0,
            "repeat_mode" TEXT NOT NULL DEFAULT 'off',
            "shuffle" INTEGER NOT NULL DEFAULT 0,
            "speed" REAL NOT NULL DEFAULT 1.0,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "video_progress_table" (
            "media_id" TEXT NOT NULL PRIMARY KEY,
            "position_ms" INTEGER NOT NULL,
            "duration_ms" INTEGER NOT NULL,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "playlists_table" (
            "id" TEXT NOT NULL PRIMARY KEY,
            "name" TEXT NOT NULL,
            "created_at" INTEGER NOT NULL,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "playlist_items_table" (
            "playlist_id" TEXT NOT NULL,
            "media_id" TEXT NOT NULL,
            "position" INTEGER NOT NULL,
            "added_at" INTEGER NOT NULL,
            UNIQUE ("playlist_id", "media_id", "position")
          );
        ''');
      },
    );
  }
}

class _V3Database extends AppDatabase {
  _V3Database(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await customStatement('''
          CREATE TABLE "media_items_table" (
            "id" TEXT NOT NULL PRIMARY KEY,
            "uri" TEXT NOT NULL,
            "media_type" TEXT NOT NULL,
            "title" TEXT NOT NULL,
            "artist" TEXT NULL,
            "album" TEXT NULL,
            "duration_ms" INTEGER NOT NULL,
            "size_bytes" INTEGER NOT NULL,
            "format" TEXT NULL,
            "width" INTEGER NULL,
            "height" INTEGER NULL,
            "date_added" INTEGER NOT NULL,
            "last_played" INTEGER NULL,
            "play_count" INTEGER NOT NULL DEFAULT 0,
            "is_favorite" INTEGER NOT NULL DEFAULT 0,
            "availability" TEXT NOT NULL DEFAULT 'available'
          );
        ''');
        await customStatement('''
          CREATE TABLE "playback_states_table" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "current_item_id" TEXT NULL,
            "queue_json" TEXT NOT NULL,
            "queue_index" INTEGER NOT NULL DEFAULT -1,
            "position_ms" INTEGER NOT NULL DEFAULT 0,
            "duration_ms" INTEGER NOT NULL DEFAULT 0,
            "repeat_mode" TEXT NOT NULL DEFAULT 'off',
            "shuffle" INTEGER NOT NULL DEFAULT 0,
            "speed" REAL NOT NULL DEFAULT 1.0,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "video_progress_table" (
            "media_id" TEXT NOT NULL PRIMARY KEY,
            "position_ms" INTEGER NOT NULL,
            "duration_ms" INTEGER NOT NULL,
            "updated_at" INTEGER NOT NULL
          );
        ''');
      },
    );
  }
}

/// The schema as v7 left it (raw SQL, so it never follows later changes).
class _V7Database extends AppDatabase {
  _V7Database(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await customStatement('''
          CREATE TABLE "media_items_table" (
            "id" TEXT NOT NULL PRIMARY KEY,
            "uri" TEXT NOT NULL,
            "media_type" TEXT NOT NULL,
            "title" TEXT NOT NULL,
            "artist" TEXT NULL,
            "album" TEXT NULL,
            "duration_ms" INTEGER NOT NULL,
            "size_bytes" INTEGER NOT NULL,
            "format" TEXT NULL,
            "width" INTEGER NULL,
            "height" INTEGER NULL,
            "date_added" INTEGER NOT NULL,
            "last_played" INTEGER NULL,
            "play_count" INTEGER NOT NULL DEFAULT 0,
            "is_favorite" INTEGER NOT NULL DEFAULT 0,
            "availability" TEXT NOT NULL DEFAULT 'available',
            "source" TEXT NULL DEFAULT 'device',
            "artwork_path" TEXT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "playback_states_table" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            "current_item_id" TEXT NULL,
            "queue_json" TEXT NOT NULL,
            "queue_index" INTEGER NOT NULL DEFAULT -1,
            "position_ms" INTEGER NOT NULL DEFAULT 0,
            "duration_ms" INTEGER NOT NULL DEFAULT 0,
            "repeat_mode" TEXT NOT NULL DEFAULT 'off',
            "shuffle" INTEGER NOT NULL DEFAULT 0,
            "speed" REAL NOT NULL DEFAULT 1.0,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "video_progress_table" (
            "media_id" TEXT NOT NULL PRIMARY KEY,
            "position_ms" INTEGER NOT NULL,
            "duration_ms" INTEGER NOT NULL,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "playlists_table" (
            "id" TEXT NOT NULL PRIMARY KEY,
            "name" TEXT NOT NULL,
            "created_at" INTEGER NOT NULL,
            "updated_at" INTEGER NOT NULL
          );
        ''');
        await customStatement('''
          CREATE TABLE "playlist_items_table" (
            "playlist_id" TEXT NOT NULL,
            "media_id" TEXT NOT NULL,
            "position" INTEGER NOT NULL,
            "added_at" INTEGER NOT NULL,
            UNIQUE ("playlist_id", "media_id", "position")
          );
        ''');
        await customStatement('''
          CREATE TABLE "downloads_table" (
            "id" TEXT NOT NULL PRIMARY KEY,
            "url" TEXT NOT NULL,
            "host" TEXT NOT NULL,
            "display_name" TEXT NOT NULL,
            "file_name" TEXT NOT NULL,
            "state" TEXT NOT NULL,
            "received_bytes" INTEGER NOT NULL DEFAULT 0,
            "total_bytes" INTEGER NULL,
            "etag" TEXT NULL,
            "last_modified" TEXT NULL,
            "supports_range" INTEGER NOT NULL DEFAULT 0,
            "mime_type" TEXT NULL,
            "error_code" TEXT NULL,
            "created_at" INTEGER NOT NULL,
            "updated_at" INTEGER NOT NULL,
            "final_path" TEXT NULL,
            "media_id" TEXT NULL,
            "kind" TEXT NULL,
            "engine" TEXT NOT NULL DEFAULT 'http',
            "thumbnail_url" TEXT NULL,
            "thumbnail_path" TEXT NULL,
            "quality_label" TEXT NULL,
            "format_selector" TEXT NULL,
            "audio_format" TEXT NULL,
            "extractor_args" TEXT NULL,
            "uploader" TEXT NULL,
            "duration_sec" INTEGER NULL,
            "stream_sizes" TEXT NULL,
            "error_detail" TEXT NULL
          );
        ''');
      },
    );
  }
}
