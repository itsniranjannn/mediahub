import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../domain/repositories/library_repository.dart';
import '../database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return LibraryRepositoryImpl(db);
});

class LibraryRepositoryImpl implements LibraryRepository {
  static const MethodChannel _mediaStoreChannel = MethodChannel('mediahub/media_store');

  final AppDatabase _db;
  final MethodChannel _channel;

  LibraryRepositoryImpl(this._db, [MethodChannel? channel])
      : _channel = channel ?? _mediaStoreChannel;

  @override
  Future<void> scanDeviceMedia() async {
    final audioToInsert = <MediaItemsTableCompanion>[];
    final videoToInsert = <MediaItemsTableCompanion>[];
    bool audioQuerySucceeded = false;
    bool videoQuerySucceeded = false;

    // 1. Scan Audio Songs via native MediaStore channel
    try {
      if (Platform.isAndroid || _channel != _mediaStoreChannel) {
        debugPrint('[Scan] Calling native mediahub/media_store queryAudio...');
        final List<dynamic>? audioResult =
            await _channel.invokeListMethod<dynamic>('queryAudio');

        if (audioResult != null) {
          audioQuerySucceeded = true;
          for (final raw in audioResult) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final id = map['id']?.toString() ?? '';
            final uri = map['uri']?.toString() ?? '';
            if (id.isEmpty || uri.isEmpty) continue;

            final title = map['title']?.toString().trim();
            final artist = map['artist']?.toString();
            final album = map['album']?.toString();
            final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
            final sizeBytes = (map['sizeBytes'] as num?)?.toInt() ?? 0;
            final dateAddedSec = (map['dateAdded'] as num?)?.toInt();
            final mimeType = map['mimeType']?.toString();

            audioToInsert.add(
              MediaItemsTableCompanion.insert(
                id: 'audio_$id',
                uri: uri,
                mediaType: MediaType.audio.name,
                title: (title != null && title.isNotEmpty) ? title : 'Unknown Title',
                artist: Value(artist == null || artist == '<unknown>' ? 'Unknown Artist' : artist),
                album: Value(album == '<unknown>' ? null : album),
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                format: Value(mimeType?.split('/').last),
                dateAdded: dateAddedSec != null
                    ? DateTime.fromMillisecondsSinceEpoch(dateAddedSec * 1000)
                    : DateTime.now(),
                availability: const Value('available'),
              ),
            );
          }
        }
      }
    } catch (e, stack) {
      debugPrint('[Scan] Error during native queryAudio: $e\n$stack');
    }

    debugPrint('[Scan] number of audio items found: ${audioToInsert.length}');

    // 2. Scan Video items via native MediaStore channel (or file fallback)
    try {
      if (Platform.isAndroid || _channel != _mediaStoreChannel) {
        debugPrint('[Scan] Calling native mediahub/media_store queryVideo...');
        final List<dynamic>? videoResult =
            await _channel.invokeListMethod<dynamic>('queryVideo');

        if (videoResult != null) {
          videoQuerySucceeded = true;
          for (final raw in videoResult) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final id = map['id']?.toString() ?? '';
            final uri = map['uri']?.toString() ?? '';
            if (id.isEmpty || uri.isEmpty) continue;

            final title = map['title']?.toString().trim();
            final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
            final sizeBytes = (map['sizeBytes'] as num?)?.toInt() ?? 0;
            final dateAddedSec = (map['dateAdded'] as num?)?.toInt();
            final mimeType = map['mimeType']?.toString();
            final width = (map['width'] as num?)?.toInt();
            final height = (map['height'] as num?)?.toInt();

            videoToInsert.add(
              MediaItemsTableCompanion.insert(
                id: 'video_$id',
                uri: uri,
                mediaType: MediaType.video.name,
                title: (title != null && title.isNotEmpty) ? title : 'Unknown Video',
                artist: const Value('Local Video'),
                album: const Value(null),
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                format: Value(mimeType?.split('/').last),
                width: Value(width),
                height: Value(height),
                dateAdded: dateAddedSec != null
                    ? DateTime.fromMillisecondsSinceEpoch(dateAddedSec * 1000)
                    : DateTime.now(),
                availability: const Value('available'),
              ),
            );
          }
        }
      }
    } catch (e, stack) {
      debugPrint('[Scan] Error during native queryVideo: $e\n$stack');
    }

// Native MediaStore channel is the single source of truth for video scanning

    debugPrint('[Scan] number of video items found: ${videoToInsert.length}');

    // 3. Atomically update DB in one transaction with availability tracking
    try {
      await _db.transaction(() async {
        // A. Insert/update all scanned items setting availability='available'
        final allScanned = [...audioToInsert, ...videoToInsert];
        if (allScanned.isNotEmpty) {
          await _db.batch((batch) {
            batch.insertAllOnConflictUpdate(_db.mediaItemsTable, allScanned);
          });
        }

        // B. Audio missing pass: only if audio query succeeded AND not an empty scan on non-empty DB (guard)
        if (audioQuerySucceeded) {
          final existingAudio = await (_db.select(_db.mediaItemsTable)
                ..where((tbl) => tbl.mediaType.equals(MediaType.audio.name)))
              .get();

          // Guard: skip missing pass if scan returned 0 items but DB already has rows of that type
          final shouldRunAudioMissingPass = audioToInsert.isNotEmpty || existingAudio.isEmpty;

          if (shouldRunAudioMissingPass) {
            final scannedAudioIds = audioToInsert.map((e) => e.id.value).toSet();
            for (final row in existingAudio) {
              if (!scannedAudioIds.contains(row.id)) {
                if (row.availability != 'missing') {
                  await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
                    const MediaItemsTableCompanion(availability: Value('missing')),
                  );
                }
              } else if (row.availability != 'available') {
                await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
                  const MediaItemsTableCompanion(availability: Value('available')),
                );
              }
            }
          }
        }

        // C. Video missing pass: only if video query succeeded AND not an empty scan on non-empty DB (guard)
        if (videoQuerySucceeded) {
          final existingVideo = await (_db.select(_db.mediaItemsTable)
                ..where((tbl) => tbl.mediaType.equals(MediaType.video.name)))
              .get();

          // Guard: skip missing pass if scan returned 0 items but DB already has rows of that type
          final shouldRunVideoMissingPass = videoToInsert.isNotEmpty || existingVideo.isEmpty;

          if (shouldRunVideoMissingPass) {
            final scannedVideoIds = videoToInsert.map((e) => e.id.value).toSet();
            for (final row in existingVideo) {
              if (!scannedVideoIds.contains(row.id)) {
                if (row.availability != 'missing') {
                  await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
                    const MediaItemsTableCompanion(availability: Value('missing')),
                  );
                }
              } else if (row.availability != 'available') {
                await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
                  const MediaItemsTableCompanion(availability: Value('available')),
                );
              }
            }
          }
        }
      });
      debugPrint('[Scan] DB write completed successfully');
    } catch (dbErr, dbStack) {
      debugPrint('[Scan] Drift DB write error: $dbErr\n$dbStack');
      rethrow;
    }
  }

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.mediaType.equals(mediaType.name));

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(
        (tbl) =>
            tbl.title.like(term) |
            tbl.artist.like(term) |
            tbl.album.like(term),
      );
    }

    final mode = ascending ? OrderingMode.asc : OrderingMode.desc;
    switch (sortBy) {
      case MediaSortOption.title:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.title.collate(Collate.noCase), mode: mode)]);
        break;
      case MediaSortOption.artist:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.artist.collate(Collate.noCase), mode: mode)]);
        break;
      case MediaSortOption.dateAdded:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: mode)]);
        break;
      case MediaSortOption.duration:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.durationMs, mode: mode)]);
        break;
    }

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Future<List<MediaItem>> getMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) async {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.mediaType.equals(mediaType.name));

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(
        (tbl) =>
            tbl.title.like(term) |
            tbl.artist.like(term) |
            tbl.album.like(term),
      );
    }

    final mode = ascending ? OrderingMode.asc : OrderingMode.desc;
    switch (sortBy) {
      case MediaSortOption.title:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.title.collate(Collate.noCase), mode: mode)]);
        break;
      case MediaSortOption.artist:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.artist.collate(Collate.noCase), mode: mode)]);
        break;
      case MediaSortOption.dateAdded:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: mode)]);
        break;
      case MediaSortOption.duration:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.durationMs, mode: mode)]);
        break;
    }

    final rows = await query.get();
    return rows.map((r) => _mapRowToModel(r)).toList();
  }

  @override
  Stream<List<MediaItem>> watchFavorites({String? searchQuery}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.isFavorite.equals(true) & tbl.mediaType.equals(MediaType.audio.name));

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(
        (tbl) =>
            tbl.title.like(term) |
            tbl.artist.like(term) |
            tbl.album.like(term),
      );
    }
    query.orderBy([(tbl) => OrderingTerm(expression: tbl.title, mode: OrderingMode.asc)]);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final item = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item != null) {
      final newFav = !item.isFavorite;
      DiagnosticsService.instance.logEvent('favorite_toggled', {'id': id, 'isFavorite': newFav});
      await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
        MediaItemsTableCompanion(
          isFavorite: Value(newFav),
        ),
      );
    }
  }

  @override
  Future<void> recordPlay(String id) async {
    final item = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item != null) {
      await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
        MediaItemsTableCompanion(
          lastPlayed: Value(DateTime.now()),
          playCount: Value(item.playCount + 1),
        ),
      );
    }
  }

  @override
  Future<void> updateAvailability(String id, MediaAvailability availability) async {
    await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
      MediaItemsTableCompanion(
        availability: Value(availability.name),
      ),
    );
  }

  @override
  Stream<List<Playlist>> watchPlaylists() {
    final query = _db.select(_db.playlistsTable)
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.name, mode: OrderingMode.asc)]);

    return query.watch().asyncMap((playlistRows) async {
      final results = <Playlist>[];
      for (final pl in playlistRows) {
        final countQuery = _db.selectOnly(_db.playlistItemsTable)
          ..addColumns([_db.playlistItemsTable.mediaId.count()])
          ..where(_db.playlistItemsTable.playlistId.equals(pl.id));
        final count = await countQuery.map((r) => r.read(_db.playlistItemsTable.mediaId.count())).getSingleOrNull() ?? 0;
        results.add(
          Playlist(
            id: pl.id,
            name: pl.name,
            createdAt: pl.createdAt,
            updatedAt: pl.updatedAt,
            songCount: count,
          ),
        );
      }
      return results;
    });
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final now = DateTime.now();
    final id = 'pl_${now.millisecondsSinceEpoch}';
    DiagnosticsService.instance.logEvent('playlist_created', {'name': name});
    await _db.into(_db.playlistsTable).insert(
      PlaylistsTableCompanion.insert(
        id: id,
        name: name.trim().isEmpty ? 'Untitled Playlist' : name.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return Playlist(
      id: id,
      name: name.trim().isEmpty ? 'Untitled Playlist' : name.trim(),
      createdAt: now,
      updatedAt: now,
      songCount: 0,
    );
  }

  @override
  Future<void> renamePlaylist(String id, String newName) async {
    DiagnosticsService.instance.logEvent('playlist_renamed', {'id': id});
    await (_db.update(_db.playlistsTable)..where((tbl) => tbl.id.equals(id))).write(
      PlaylistsTableCompanion(
        name: Value(newName.trim().isEmpty ? 'Untitled Playlist' : newName.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deletePlaylist(String id) async {
    DiagnosticsService.instance.logEvent('playlist_deleted', {'id': id});
    await (_db.delete(_db.playlistItemsTable)..where((tbl) => tbl.playlistId.equals(id))).go();
    await (_db.delete(_db.playlistsTable)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<void> addSongToPlaylist(String playlistId, String mediaId) async {
    DiagnosticsService.instance.logEvent('playlist_song_added', {'playlistId': playlistId, 'mediaId': mediaId});
    await _db.transaction(() async {
      final maxPosQuery = _db.selectOnly(_db.playlistItemsTable)
        ..addColumns([_db.playlistItemsTable.position.max()])
        ..where(_db.playlistItemsTable.playlistId.equals(playlistId));
      final currentMax = await maxPosQuery.map((r) => r.read(_db.playlistItemsTable.position.max())).getSingleOrNull();
      final nextPos = (currentMax ?? -1) + 1;

      await _db.into(_db.playlistItemsTable).insert(
        PlaylistItemsTableCompanion.insert(
          playlistId: playlistId,
          mediaId: mediaId,
          position: nextPos,
          addedAt: DateTime.now(),
        ),
      );
      await (_db.update(_db.playlistsTable)..where((tbl) => tbl.id.equals(playlistId))).write(
        PlaylistsTableCompanion(updatedAt: Value(DateTime.now())),
      );
    });
  }

  @override
  Future<void> removeSongFromPlaylist(String playlistId, String mediaId, int position) async {
    DiagnosticsService.instance.logEvent('playlist_song_removed', {'playlistId': playlistId, 'mediaId': mediaId});
    await _db.transaction(() async {
      // 1. Delete matching row
      await (_db.delete(_db.playlistItemsTable)
            ..where((tbl) =>
                tbl.playlistId.equals(playlistId) &
                tbl.mediaId.equals(mediaId) &
                tbl.position.equals(position)))
          .go();

      // 2. Fetch remaining items ordered by position and renumber cleanly with no gaps
      final remaining = await (_db.select(_db.playlistItemsTable)
            ..where((tbl) => tbl.playlistId.equals(playlistId))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.position, mode: OrderingMode.asc)]))
          .get();

      for (int i = 0; i < remaining.length; i++) {
        if (remaining[i].position != i) {
          await (_db.update(_db.playlistItemsTable)
                ..where((tbl) =>
                    tbl.playlistId.equals(playlistId) &
                    tbl.mediaId.equals(remaining[i].mediaId) &
                    tbl.position.equals(remaining[i].position)))
              .write(PlaylistItemsTableCompanion(position: Value(i)));
        }
      }

      await (_db.update(_db.playlistsTable)..where((tbl) => tbl.id.equals(playlistId))).write(
        PlaylistsTableCompanion(updatedAt: Value(DateTime.now())),
      );
    });
  }

  @override
  Future<void> reorderPlaylist(String playlistId, int oldPosition, int newPosition) async {
    DiagnosticsService.instance.logEvent('playlist_reordered', {'playlistId': playlistId});
    final items = await (_db.select(_db.playlistItemsTable)
          ..where((tbl) => tbl.playlistId.equals(playlistId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.position, mode: OrderingMode.asc)]))
        .get();

    if (oldPosition < 0 || oldPosition >= items.length) return;
    if (newPosition < 0 || newPosition >= items.length) return;

    final mutable = List<PlaylistItemEntry>.from(items);
    final moved = mutable.removeAt(oldPosition);
    mutable.insert(newPosition, moved);

    await _db.transaction(() async {
      await (_db.delete(_db.playlistItemsTable)..where((tbl) => tbl.playlistId.equals(playlistId))).go();
      for (int i = 0; i < mutable.length; i++) {
        await _db.into(_db.playlistItemsTable).insert(
          PlaylistItemsTableCompanion.insert(
            playlistId: playlistId,
            mediaId: mutable[i].mediaId,
            position: i,
            addedAt: mutable[i].addedAt,
          ),
        );
      }
      await (_db.update(_db.playlistsTable)..where((tbl) => tbl.id.equals(playlistId))).write(
        PlaylistsTableCompanion(updatedAt: Value(DateTime.now())),
      );
    });
  }

  @override
  Stream<List<MediaItem>> watchPlaylistSongs(String playlistId) {
    final query = _db.select(_db.playlistItemsTable).join([
      innerJoin(
        _db.mediaItemsTable,
        _db.mediaItemsTable.id.equalsExp(_db.playlistItemsTable.mediaId),
      ),
    ])
      ..where(_db.playlistItemsTable.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm(expression: _db.playlistItemsTable.position, mode: OrderingMode.asc)]);

    return query.watch().map((rows) {
      return rows.map((r) => _mapRowToModel(r.readTable(_db.mediaItemsTable))).toList();
    });
  }

  @override
  Stream<List<AlbumGroup>> watchAlbums({String? searchQuery}) {
    final countCol = _db.mediaItemsTable.id.count();
    final durationCol = _db.mediaItemsTable.durationMs.sum();

    final query = _db.selectOnly(_db.mediaItemsTable)
      ..addColumns([
        _db.mediaItemsTable.album,
        _db.mediaItemsTable.artist,
        countCol,
        durationCol,
      ])
      ..where(_db.mediaItemsTable.mediaType.equals(MediaType.audio.name))
      ..groupBy([_db.mediaItemsTable.album, _db.mediaItemsTable.artist]);

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(_db.mediaItemsTable.album.like(term) | _db.mediaItemsTable.artist.like(term));
    }
    query.orderBy([
      OrderingTerm(expression: _db.mediaItemsTable.album.collate(Collate.noCase), mode: OrderingMode.asc),
      OrderingTerm(expression: _db.mediaItemsTable.artist.collate(Collate.noCase), mode: OrderingMode.asc),
    ]);

    return query.watch().map((rows) {
      return rows.map((r) {
        final rawAlbum = r.read(_db.mediaItemsTable.album);
        final rawArtist = r.read(_db.mediaItemsTable.artist);
        final songCount = r.read(countCol) ?? 0;
        final totalDuration = r.read(durationCol) ?? 0;

        return AlbumGroup(
          album: (rawAlbum != null && rawAlbum.isNotEmpty) ? rawAlbum : 'Unknown Album',
          artist: (rawArtist != null && rawArtist.isNotEmpty) ? rawArtist : 'Unknown Artist',
          songCount: songCount,
          totalDurationMs: totalDuration,
        );
      }).toList();
    });
  }

  @override
  Stream<List<MediaItem>> watchAlbumSongs(String album) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) =>
          tbl.mediaType.equals(MediaType.audio.name) &
          (album == 'Unknown Album'
              ? (tbl.album.isNull() | tbl.album.equals(''))
              : tbl.album.equals(album)))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.title, mode: OrderingMode.asc)]);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Stream<List<ArtistGroup>> watchArtists({String? searchQuery}) {
    final countCol = _db.mediaItemsTable.id.count();

    final query = _db.selectOnly(_db.mediaItemsTable)
      ..addColumns([
        _db.mediaItemsTable.artist,
        countCol,
      ])
      ..where(_db.mediaItemsTable.mediaType.equals(MediaType.audio.name))
      ..groupBy([_db.mediaItemsTable.artist]);

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      query.where(_db.mediaItemsTable.artist.like(term));
    }
    query.orderBy([OrderingTerm(expression: _db.mediaItemsTable.artist, mode: OrderingMode.asc)]);

    return query.watch().map((rows) {
      return rows.map((r) {
        final rawArtist = r.read(_db.mediaItemsTable.artist);
        final songCount = r.read(countCol) ?? 0;

        return ArtistGroup(
          artist: (rawArtist != null && rawArtist.isNotEmpty) ? rawArtist : 'Unknown Artist',
          songCount: songCount,
        );
      }).toList();
    });
  }

  @override
  Stream<List<MediaItem>> watchArtistSongs(String artist) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) =>
          tbl.mediaType.equals(MediaType.audio.name) &
          (artist == 'Unknown Artist'
              ? (tbl.artist.isNull() | tbl.artist.equals(''))
              : tbl.artist.equals(artist)))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.title, mode: OrderingMode.asc)]);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.lastPlayed.isNotNull() & tbl.mediaType.equals(MediaType.audio.name))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.lastPlayed, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.playCount.isBiggerThanValue(0) & tbl.mediaType.equals(MediaType.audio.name))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.playCount, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType = MediaType.audio}) {
    final query = _db.select(_db.mediaItemsTable);
    if (mediaType != null) {
      query.where((tbl) => tbl.mediaType.equals(mediaType.name));
    }
    query
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  @override
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.mediaType.equals(MediaType.video.name))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map((r) => _mapRowToModel(r)).toList());
  }

  MediaItem _mapRowToModel(MediaItemEntry row) {
    return MediaItem(
      id: row.id,
      uri: row.uri,
      mediaType: MediaType.values.byName(row.mediaType),
      title: row.title,
      artist: row.artist,
      album: row.album,
      durationMs: row.durationMs,
      sizeBytes: row.sizeBytes,
      format: row.format,
      width: row.width,
      height: row.height,
      dateAdded: row.dateAdded,
      lastPlayed: row.lastPlayed,
      playCount: row.playCount,
      isFavorite: row.isFavorite,
      availability: MediaAvailability.values.byName(row.availability),
    );
  }
}
