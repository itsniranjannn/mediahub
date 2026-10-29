import 'dart:convert';
import 'package:drift/drift.dart';
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
    return entry?.toDomain();
  }

  @override
  Future<void> savePlaybackState(PlaybackState state) async {
    final jsonList = state.queue.map((m) => m.toJsonMap()).toList();
    final jsonString = jsonEncode(jsonList);

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

