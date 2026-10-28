import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../domain/models/media_item.dart';
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
  final AppDatabase _db;
  final OnAudioQuery _audioQuery;

  LibraryRepositoryImpl(this._db, [OnAudioQuery? audioQuery])
      : _audioQuery = audioQuery ?? OnAudioQuery();

  @override
  Future<void> scanDeviceMedia() async {
    final mediaToInsert = <MediaItemsTableCompanion>[];

    // 1. Scan Audio Songs via MediaStore
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      for (final song in songs) {
        final uri = song.data;
        if (uri.isEmpty) continue;

        mediaToInsert.add(
          MediaItemsTableCompanion.insert(
            id: 'audio_${song.id}',
            uri: uri,
            mediaType: MediaType.audio.name,
            title: song.title.trim().isNotEmpty ? song.title.trim() : 'Unknown Title',
            artist: Value(song.artist == '<unknown>' ? 'Unknown Artist' : song.artist),
            album: Value(song.album == '<unknown>' ? null : song.album),
            durationMs: song.duration ?? 0,
            sizeBytes: song.size,
            format: Value(song.fileExtension),
            dateAdded: song.dateAdded != null
                ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000)
                : DateTime.now(),
          ),
        );
      }
    } catch (_) {
      // MediaStore query fallback handled gracefully
    }

    // 2. Scan Video files from media storage directories
    final videoExtensions = {'.mp4', '.mkv', '.webm', '.avi', '.mov', '.3gp', '.m4v'};
    final searchDirectories = [
      Directory('/storage/emulated/0/Movies'),
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/DCIM'),
      Directory('/storage/emulated/0/Movies'),
      Directory('/sdcard/Movies'),
      Directory('/sdcard/Download'),
    ];

    for (final dir in searchDirectories) {
      if (!dir.existsSync()) continue;
      try {
        final files = dir.listSync(recursive: true);
        for (final file in files) {
          if (file is File) {
            final path = file.path;
            final ext = path.substring(path.lastIndexOf('.')).toLowerCase();
            if (videoExtensions.contains(ext)) {
              final fileName = path.split(Platform.pathSeparator).last;
              final stat = file.statSync();

              mediaToInsert.add(
                MediaItemsTableCompanion.insert(
                  id: 'video_${path.hashCode}',
                  uri: path,
                  mediaType: MediaType.video.name,
                  title: fileName,
                  artist: const Value('Local Video'),
                  album: const Value(null),
                  durationMs: 0, // Will be read during player load
                  sizeBytes: stat.size,
                  format: Value(ext.replaceAll('.', '')),
                  dateAdded: stat.modified,
                ),
              );
            }
          }
        }
      } catch (_) {
        // Skip inaccessible directories
      }
    }

    // Insert or update batch in database
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.mediaItemsTable, mediaToInsert);
    });
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
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.title, mode: mode)]);
        break;
      case MediaSortOption.artist:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.artist, mode: mode)]);
        break;
      case MediaSortOption.dateAdded:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: mode)]);
        break;
      case MediaSortOption.duration:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.durationMs, mode: mode)]);
        break;
    }

    return query.watch().map((entries) => entries.map((e) => e.toDomain()).toList());
  }

  @override
  Future<List<MediaItem>> getMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) async {
    final stream = watchMediaItems(
      mediaType: mediaType,
      searchQuery: searchQuery,
      sortBy: sortBy,
      ascending: ascending,
    );
    return stream.first;
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final item = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item != null) {
      await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
        MediaItemsTableCompanion(isFavorite: Value(!item.isFavorite)),
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
}
