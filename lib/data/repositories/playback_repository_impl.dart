// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
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
    List<MediaItem> originalQueueItems = [];
    try {
      final decoded = jsonDecode(entry.queueJson);
      List<String> ids = [];
      List<String>? origIds;

      if (decoded is Map) {
        ids = (decoded['queue'] as List?)?.cast<String>() ?? [];
        origIds = (decoded['original'] as List?)?.cast<String>();
      } else if (decoded is List) {
        if (decoded.isNotEmpty && decoded.first is String) {
          ids = decoded.cast<String>();
        } else {
          queueItems = decoded
              .map((item) => MediaItem.fromJsonMap(Map<String, dynamic>.from(item as Map)))
              .toList();
          originalQueueItems = List.from(queueItems);
        }
      }

      if (ids.isNotEmpty) {
        final allNeededIds = Set<String>.from(ids)..addAll(origIds ?? []);
        final rows = await (db.select(db.mediaItemsTable)..where((tbl) => tbl.id.isIn(allNeededIds))).get();
        final map = {for (var r in rows) r.id: r.toDomain()};
        for (final id in ids) {
          if (map.containsKey(id)) {
            queueItems.add(map[id]!);
          }
        }
        for (final id in (origIds ?? ids)) {
          if (map.containsKey(id)) {
            originalQueueItems.add(map[id]!);
          }
        }
      }
    } catch (_) {}

    return PlaybackState(
      currentItemId: entry.currentItemId,
      queue: queueItems,
      originalQueue: originalQueueItems.isNotEmpty ? originalQueueItems : queueItems,
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
    // Persist queue and original order as media ids
    final idList = state.queue.map((m) => m.id).toList();
    final origIdList = state.originalQueue.map((m) => m.id).toList();
    final jsonString = jsonEncode({
      'queue': idList,
      'original': origIdList,
    });

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
