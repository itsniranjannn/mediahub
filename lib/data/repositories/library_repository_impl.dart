import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  static const MethodChannel _mediaStoreChannel = MethodChannel('mediahub/media_store');

  final AppDatabase _db;
  final MethodChannel _channel;

  LibraryRepositoryImpl(this._db, [MethodChannel? channel])
      : _channel = channel ?? _mediaStoreChannel;

  @override
  Future<void> scanDeviceMedia() async {
    final mediaToInsert = <MediaItemsTableCompanion>[];
    int audioFound = 0;
    int videoFound = 0;

    // 1. Scan Audio Songs via native MediaStore channel
    try {
      if (Platform.isAndroid) {
        debugPrint('[Scan] Calling native mediahub/media_store queryAudio...');
        final List<dynamic>? audioResult =
            await _channel.invokeListMethod<dynamic>('queryAudio');

        if (audioResult != null) {
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

            mediaToInsert.add(
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
              ),
            );
          }
        }
      }
      audioFound = mediaToInsert.length;
    } catch (e, stack) {
      debugPrint('[Scan] Error during native queryAudio: $e\n$stack');
    }

    debugPrint('[Scan] number of audio items found: $audioFound');

    // 2. Scan Video items via native MediaStore channel (or file fallback)
    try {
      if (Platform.isAndroid) {
        debugPrint('[Scan] Calling native mediahub/media_store queryVideo...');
        final List<dynamic>? videoResult =
            await _channel.invokeListMethod<dynamic>('queryVideo');

        if (videoResult != null && videoResult.isNotEmpty) {
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

            mediaToInsert.add(
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
              ),
            );
            videoFound++;
          }
        }
      }
    } catch (e, stack) {
      debugPrint('[Scan] Error during native queryVideo: $e\n$stack');
    }

    // Fallback: Scan filesystem video directories if needed
    if (videoFound == 0) {
      final videoExtensions = {'.mp4', '.mkv', '.webm', '.avi', '.mov', '.3gp', '.m4v'};
      final searchDirectories = [
        Directory('/storage/emulated/0/Movies'),
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/DCIM'),
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
              final dotIdx = path.lastIndexOf('.');
              if (dotIdx == -1) continue;
              final ext = path.substring(dotIdx).toLowerCase();
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
                    durationMs: 0,
                    sizeBytes: stat.size,
                    format: Value(ext.replaceAll('.', '')),
                    dateAdded: stat.modified,
                  ),
                );
                videoFound++;
              }
            }
          }
        } catch (dirErr) {
          debugPrint('[Scan] Skipping directory ${dir.path}: $dirErr');
        }
      }
    }

    debugPrint('[Scan] number of video items found: $videoFound');

    // 3. Insert or update batch in Drift database
    try {
      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.mediaItemsTable, mediaToInsert);
      });
      debugPrint('[Scan] DB write count: ${mediaToInsert.length}');
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

    final rows = await query.get();
    return rows.map((r) => _mapRowToModel(r)).toList();
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final item = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item != null) {
      await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
        MediaItemsTableCompanion(
          isFavorite: Value(!item.isFavorite),
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
