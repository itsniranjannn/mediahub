import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/playback_repository.dart';
import '../database/app_database.dart';

class PlaybackRepositoryImpl implements PlaybackRepository {
  final AppDatabase db;

  PlaybackRepositoryImpl(this.db);

  @override
  Future<PlaybackState?> loadLastPlaybackState() async {
    final query = db.select(db.playbackStatesTable)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(1);
    final entry = await query.getSingleOrNull();
    if (entry == null) return null;

    // Resolve queue from media ids or fallback to json if older format
    List<MediaItem> queueItems = [];
    try {
      final decoded = jsonDecode(entry.queueJson);
      if (decoded is List) {
        if (decoded.isNotEmpty && decoded.first is String) {
          // List of IDs
          final ids = decoded.cast<String>();
          final rows = await (db.select(db.mediaItemsTable)..where((tbl) => tbl.id.isIn(ids))).get();
          final map = {for (var r in rows) r.id: r.toDomain()};
          for (final id in ids) {
            if (map.containsKey(id)) {
              queueItems.add(map[id]!);
            }
          }
        } else {
          // Legacy full JSON map
          queueItems = decoded
              .map((item) => MediaItem.fromJsonMap(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (_) {}

    return PlaybackState(
      currentItemId: entry.currentItemId,
      queue: queueItems,
      queueIndex: entry.queueIndex,
      position: Duration(milliseconds: entry.positionMs),
      duration: Duration(milliseconds: entry.durationMs),
      repeatMode: PlaybackRepeatMode.values.firstWhere(
        (e) => e.name == entry.repeatMode,
        orElse: () => PlaybackRepeatMode.off,
      ),
      shuffle: entry.shuffle,
      speed: entry.speed,
      updatedAt: entry.updatedAt,
    );
  }

  @override
  Future<void> savePlaybackState(PlaybackState state) async {
    // Persist queue as media ids to save memory and avoid redundant json overhead
    final idList = state.queue.map((m) => m.id).toList();
    final jsonString = jsonEncode(idList);

    await db.into(db.playbackStatesTable).insertOnConflictUpdate(
          PlaybackStatesTableCompanion(
            id: const Value(1), // keep a single row for latest state
            currentItemId: Value(state.currentItemId),
            queueJson: Value(jsonString),
            queueIndex: Value(state.queueIndex),
            positionMs: Value(state.position.inMilliseconds),
            durationMs: Value(state.duration.inMilliseconds),
            repeatMode: Value(state.repeatMode.name),
            shuffle: Value(state.shuffle),
            speed: Value(state.speed),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
