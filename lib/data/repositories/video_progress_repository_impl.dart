// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:drift/drift.dart';
import '../../domain/models/video_progress.dart';
import '../../domain/repositories/video_progress_repository.dart';
import '../database/app_database.dart';

class VideoProgressRepositoryImpl implements VideoProgressRepository {
  final AppDatabase db;

  VideoProgressRepositoryImpl(this.db);

  @override
  Future<VideoProgress?> getProgress(String mediaId) async {
    final query = db.select(db.videoProgressTable)
      ..where((t) => t.mediaId.equals(mediaId));
    final entry = await query.getSingleOrNull();
    return entry?.toDomain();
  }

  @override
  Future<List<VideoProgress>> getAllProgress() async {
    final query = db.select(db.videoProgressTable)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    final entries = await query.get();
    return entries.map((e) => e.toDomain()).toList();
  }

  @override
  Stream<List<VideoProgress>> watchAllProgress() {
    final query = db.select(db.videoProgressTable)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map((entries) => entries.map((e) => e.toDomain()).toList());
  }

  @override
  Future<void> saveProgress(VideoProgress progress) async {
    await db.into(db.videoProgressTable).insertOnConflictUpdate(
          VideoProgressTableCompanion(
            mediaId: Value(progress.mediaId),
            positionMs: Value(progress.positionMs),
            durationMs: Value(progress.durationMs),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> deleteProgress(String mediaId) async {
    await (db.delete(db.videoProgressTable)..where((t) => t.mediaId.equals(mediaId))).go();
  }
}
