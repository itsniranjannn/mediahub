import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/video_progress.dart';

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
  TextColumn get artworkPath => text().nullable()(); // local image file (downloads)

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
  int get schemaVersion => 7;

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
      },
    );
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
    };
  }

  static MediaItem fromJsonMap(Map<String, dynamic> map) {
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
