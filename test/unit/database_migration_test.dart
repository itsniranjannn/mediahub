import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';

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
}

class _V3Database extends AppDatabase {
  _V3Database(super.executor);

  @override
  int get schemaVersion => 3;
}
