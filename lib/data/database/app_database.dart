import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/video_progress.dart';
import 'search_text.dart';

part 'app_database.g.dart';

@DataClassName('MediaItemEntry')
class MediaItemsTable extends Table {
  TextColumn get id => text()();
  TextColumn get uri => text()();
  TextColumn get mediaType => text()(); // 'audio' or 'video'
  TextColumn get title => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get format => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get lastPlayed => dateTime().nullable()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get availability =>
      text().withDefault(const Constant('available'))(); // 'available' or 'missing'
  TextColumn get source =>
      text().nullable().withDefault(const Constant('device'))(); // 'device' or 'download'
  TextColumn get artworkPath => text().nullable()(); // local image file (downloads) or https thumbnail (online)

  // --- v8: album identity, track order, search, liked time ----------------
  /// MediaStore ALBUM_ID (songs on the phone).
  TextColumn get albumId => text().nullable()();
  TextColumn get albumArtist => text().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();

  /// [librarySearchKey] of the row: folded title, artist and album.
  TextColumn get searchKey => text().nullable()();

  /// When the song was liked; null when not liked (or liked before v8).
  DateTimeColumn get favoritedAt => dateTime().nullable()();
  TextColumn get relativePath => text().nullable()();
  TextColumn get genre => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DownloadEntry')
class DownloadsTable extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get host => text()();
  TextColumn get displayName => text()();
  TextColumn get fileName => text()();
  TextColumn get state => text()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  BoolColumn get supportsRange => boolean().withDefault(const Constant(false))();
  TextColumn get mimeType => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get finalPath => text().nullable()();
  TextColumn get mediaId => text().nullable()();

  // --- v6: richer download metadata -------------------------------------
  /// 'audio' | 'video' (null = not known yet, e.g. direct link before sniffing)
  TextColumn get kind => text().nullable()();

  /// 'http' (direct link engine) | 'extractor' (yt-dlp web link downloader)
  TextColumn get engine => text().withDefault(const Constant('http'))();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get qualityLabel => text().nullable()();
  TextColumn get formatSelector => text().nullable()();
  TextColumn get audioFormat => text().nullable()();
  TextColumn get extractorArgs => text().nullable()();
  TextColumn get uploader => text().nullable()();
  IntColumn get durationSec => integer().nullable()();

  /// JSON list of expected stream sizes in bytes (e.g. [video, audio]); used
  /// to turn yt-dlp's per-stream percentages into one overall progress value.
  TextColumn get streamSizes => text().nullable()();

  // --- v7 ---------------------------------------------------------------
  /// Short, sanitized reason reported by the downloader (shown under the error).
  TextColumn get errorDetail => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlaybackStateEntry')
class PlaybackStatesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get currentItemId => text().nullable()();
  TextColumn get queueJson => text()(); // JSON list of MediaItem serializations
  IntColumn get queueIndex => integer().withDefault(const Constant(-1))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get repeatMode =>
      text().withDefault(const Constant('off'))(); // 'off', 'all', 'one'
  BoolColumn get shuffle => boolean().withDefault(const Constant(false))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('VideoProgressEntry')
class VideoProgressTable extends Table {
  TextColumn get mediaId => text()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {mediaId};
}

@DataClassName('PlaylistEntry')
class PlaylistsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlaylistItemEntry')
class PlaylistItemsTable extends Table {
  TextColumn get playlistId => text()();
  TextColumn get mediaId => text()();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {playlistId, mediaId, position},
      ];
}

@DriftDatabase(tables: [
  MediaItemsTable,
  PlaybackStatesTable,
  VideoProgressTable,
  PlaylistsTable,
  PlaylistItemsTable,
  DownloadsTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(playbackStatesTable);
        }
        if (from < 3) {
          await m.createTable(videoProgressTable);
        }
        if (from < 4) {
          await m.createTable(playlistsTable);
          await m.createTable(playlistItemsTable);
        }
        if (from < 5) {
          await m.createTable(downloadsTable);
          await m.addColumn(mediaItemsTable, mediaItemsTable.source);
        }
        if (from < 6) {
          await m.addColumn(mediaItemsTable, mediaItemsTable.artworkPath);
        }
        if (from == 5) {
          // Only a v5 database has the old downloads table; older ones just got
          // the current table from the `from < 5` step above.
          await m.addColumn(downloadsTable, downloadsTable.kind);
          await m.addColumn(downloadsTable, downloadsTable.engine);
          await m.addColumn(downloadsTable, downloadsTable.thumbnailUrl);
          await m.addColumn(downloadsTable, downloadsTable.thumbnailPath);
          await m.addColumn(downloadsTable, downloadsTable.qualityLabel);
          await m.addColumn(downloadsTable, downloadsTable.formatSelector);
          await m.addColumn(downloadsTable, downloadsTable.audioFormat);
          await m.addColumn(downloadsTable, downloadsTable.extractorArgs);
          await m.addColumn(downloadsTable, downloadsTable.uploader);
          await m.addColumn(downloadsTable, downloadsTable.durationSec);
          await m.addColumn(downloadsTable, downloadsTable.streamSizes);
        }
        if (from >= 5 && from < 7) {
          // v5/v6 databases have a downloads table without this column; older ones
          // just got the current table from the `from < 5` step.
          await m.addColumn(downloadsTable, downloadsTable.errorDetail);
        }
        if (from < 8) {
          final t = mediaItemsTable;
          for (final column in <GeneratedColumn>[
            t.albumId,
            t.albumArtist,
            t.trackNumber,
            t.discNumber,
            t.year,
            t.searchKey,
            t.favoritedAt,
            t.relativePath,
            t.genre,
          ]) {
            await m.addColumn(t, column);
          }
          await migrateLibraryToV8();
        }
      },
    );
  }

  /// The data half of the v7 -> v8 step, so every list works on an existing
  /// install straight after the update (the next scan fills album ids, track
  /// numbers and years):
  /// - an artist stored as "Unknown Artist", `<unknown>` or "" becomes NULL,
  ///   so one "Unknown artist" tile holds every untagged song;
  /// - playlist entries whose song row is gone (a deleted download) are
  ///   removed, and each playlist is numbered 0, 1, 2... again, so the song
  ///   count is right and remove / reorder find their entry;
  /// - every row gets its search key.
  ///
  /// Raw SQL with explicit columns only, so it keeps working whatever later
  /// versions add to the tables.
  @visibleForTesting
  Future<void> migrateLibraryToV8() async {
    await customStatement(
      "UPDATE media_items_table SET artist = NULL "
      "WHERE artist IS NOT NULL AND (TRIM(artist) = '' OR LOWER(TRIM(artist)) IN ('unknown artist', '<unknown>'))",
    );

    await customStatement(
      'DELETE FROM playlist_items_table WHERE media_id NOT IN (SELECT id FROM media_items_table)',
    );
    await renumberAllPlaylists();

    final rows = await customSelect(
      'SELECT id, title, artist, album, album_artist FROM media_items_table',
    ).get();
    for (final row in rows) {
      final key = librarySearchKey(
        title: row.read<String>('title'),
        artist: row.readNullable<String>('artist'),
        album: row.readNullable<String>('album'),
        albumArtist: row.readNullable<String>('album_artist'),
      );
      await customStatement('UPDATE media_items_table SET search_key = ? WHERE id = ?', [key, row.read<String>('id')]);
    }
  }

  /// Numbers the entries of every playlist (or only [playlistId]) 0, 1, 2...
  /// in their current order, closing gaps left by removed entries.
  ///
  /// Two passes through negative numbers, so no intermediate state can collide
  /// with the (playlist, song, position) unique key, even when two entries
  /// share a position. Call it inside a transaction.
  Future<void> renumberAllPlaylists({String? playlistId}) async {
    final entries = await customSelect(
      playlistId == null
          ? 'SELECT rowid AS rid, playlist_id, position FROM playlist_items_table ORDER BY playlist_id, position, rowid'
          : 'SELECT rowid AS rid, playlist_id, position FROM playlist_items_table WHERE playlist_id = ? '
              'ORDER BY position, rowid',
      variables: [if (playlistId != null) Variable.withString(playlistId)],
    ).get();
    final byPlaylist = <String, List<(int, int)>>{};
    for (final row in entries) {
      byPlaylist
          .putIfAbsent(row.read<String>('playlist_id'), () => [])
          .add((row.read<int>('rid'), row.read<int>('position')));
    }
    for (final list in byPlaylist.values) {
      var inOrder = true;
      for (var i = 0; i < list.length; i++) {
        if (list[i].$2 != i) inOrder = false;
      }
      if (inOrder) continue;
      for (var i = 0; i < list.length; i++) {
        await customStatement('UPDATE playlist_items_table SET position = ? WHERE rowid = ?', [-1 - i, list[i].$1]);
      }
      for (final (rid, _) in list) {
        await customStatement('UPDATE playlist_items_table SET position = -1 - position WHERE rowid = ?', [rid]);
      }
    }
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'media_hub_db');
  }
}

extension MediaItemEntryMapper on MediaItemEntry {
  MediaItem toDomain() {
    return MediaItem(
      id: id,
      uri: uri,
      mediaType: mediaType == 'video' ? MediaType.video : MediaType.audio,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      format: format,
      width: width,
      height: height,
      dateAdded: dateAdded,
      lastPlayed: lastPlayed,
      playCount: playCount,
      isFavorite: isFavorite,
      availability: availability == 'missing'
          ? MediaAvailability.missing
          : MediaAvailability.available,
      source: source ?? 'device',
      artworkPath: artworkPath,
      albumId: albumId,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      favoritedAt: favoritedAt,
      relativePath: relativePath,
      genre: genre,
    );
  }
}

extension MediaItemMapper on MediaItem {
  MediaItemsTableCompanion toCompanion() {
    return MediaItemsTableCompanion.insert(
      id: id,
      uri: uri,
      mediaType: mediaType.name,
      title: title,
      artist: Value(artist),
      album: Value(album),
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      format: Value(format),
      width: Value(width),
      height: Value(height),
      dateAdded: dateAdded,
      lastPlayed: Value(lastPlayed),
      playCount: Value(playCount),
      isFavorite: Value(isFavorite),
      availability: Value(availability.name),
      source: Value(source),
      artworkPath: Value(artworkPath),
      albumId: Value(albumId),
      albumArtist: Value(albumArtist),
      trackNumber: Value(trackNumber),
      discNumber: Value(discNumber),
      year: Value(year),
      searchKey: Value(librarySearchKey(title: title, artist: artist, album: album, albumArtist: albumArtist)),
      favoritedAt: Value(favoritedAt),
      relativePath: Value(relativePath),
      genre: Value(genre),
    );
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'id': id,
      'uri': uri,
      'mediaType': mediaType.name,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'sizeBytes': sizeBytes,
      'format': format,
      'width': width,
      'height': height,
      'dateAdded': dateAdded.toIso8601String(),
      'lastPlayed': lastPlayed?.toIso8601String(),
      'playCount': playCount,
      'isFavorite': isFavorite,
      'availability': availability.name,
      'source': source,
      'artworkPath': artworkPath,
      if (albumId != null) 'albumId': albumId,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (discNumber != null) 'discNumber': discNumber,
      if (year != null) 'year': year,
      if (favoritedAt != null) 'favoritedAt': favoritedAt!.toIso8601String(),
      if (relativePath != null) 'relativePath': relativePath,
      if (genre != null) 'genre': genre,
    };
  }

  static MediaItem fromJsonMap(Map<String, dynamic> map) {
    final favoritedAt = map['favoritedAt'];
    return MediaItem(
      id: map['id'] as String,
      uri: map['uri'] as String,
      mediaType: map['mediaType'] == 'video' ? MediaType.video : MediaType.audio,
      title: map['title'] as String,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      durationMs: (map['durationMs'] as num).toInt(),
      sizeBytes: (map['sizeBytes'] as num).toInt(),
      format: map['format'] as String?,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      dateAdded: DateTime.parse(map['dateAdded'] as String),
      lastPlayed: map['lastPlayed'] != null
          ? DateTime.parse(map['lastPlayed'] as String)
          : null,
      playCount: (map['playCount'] as num?)?.toInt() ?? 0,
      isFavorite: map['isFavorite'] as bool? ?? false,
      availability: map['availability'] == 'missing'
          ? MediaAvailability.missing
          : MediaAvailability.available,
      source: map['source'] as String? ?? 'device',
      artworkPath: map['artworkPath'] as String?,
      albumId: map['albumId'] as String?,
      albumArtist: map['albumArtist'] as String?,
      trackNumber: (map['trackNumber'] as num?)?.toInt(),
      discNumber: (map['discNumber'] as num?)?.toInt(),
      year: (map['year'] as num?)?.toInt(),
      favoritedAt: favoritedAt is String ? DateTime.tryParse(favoritedAt) : null,
      relativePath: map['relativePath'] as String?,
      genre: map['genre'] as String?,
    );
  }
}

extension PlaybackStateEntryMapper on PlaybackStateEntry {
  PlaybackState toDomain() {
    List<MediaItem> queue = [];
    try {
      final List<dynamic> decoded = jsonDecode(queueJson) as List<dynamic>;
      queue = decoded
          .map((e) => MediaItemMapper.fromJsonMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      queue = [];
    }

    PlaybackRepeatMode repeat = PlaybackRepeatMode.off;
    if (repeatMode == 'all') {
      repeat = PlaybackRepeatMode.all;
    } else if (repeatMode == 'one') {
      repeat = PlaybackRepeatMode.one;
    }

    return PlaybackState(
      currentItemId: currentItemId,
      queue: queue,
      queueIndex: queueIndex,
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      isPlaying: false, // restore in paused state
      repeatMode: repeat,
      shuffle: shuffle,
      speed: speed,
      updatedAt: updatedAt,
    );
  }
}

extension VideoProgressEntryMapper on VideoProgressEntry {
  VideoProgress toDomain() {
    return VideoProgress(
      mediaId: mediaId,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: updatedAt,
    );
  }
}

extension VideoProgressMapper on VideoProgress {
  VideoProgressTableCompanion toCompanion() {
    return VideoProgressTableCompanion.insert(
      mediaId: mediaId,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: updatedAt,
    );
  }
}
