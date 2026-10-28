import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../../domain/models/media_item.dart';

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

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [MediaItemsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration strategy skeleton for future schema versions
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
    );
  }
}
