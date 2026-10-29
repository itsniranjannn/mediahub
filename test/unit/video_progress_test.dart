import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/video_progress_repository_impl.dart';

void main() {
  group('VideoProgress domain logic', () {
    test('calculateResumePosition returns 0 if within last 5 seconds of duration', () {
      const durationMs = 60000; // 60 seconds
      // 56 seconds in -> remaining 4s <= 5s -> should restart from 0
      final resumeMs1 = VideoProgress.calculateResumePosition(
        savedPositionMs: 56000,
        totalDurationMs: durationMs,
      );
      expect(resumeMs1, 0);

      // Exactly 55 seconds in -> remaining 5s <= 5s -> should restart from 0
      final resumeMs2 = VideoProgress.calculateResumePosition(
        savedPositionMs: 55000,
        totalDurationMs: durationMs,
      );
      expect(resumeMs2, 0);
    });

    test('calculateResumePosition returns saved position if more than 5s remaining', () {
      const durationMs = 60000;
      // 30 seconds in -> remaining 30s > 5s -> should resume at 30s (30000 ms)
      final resumeMs = VideoProgress.calculateResumePosition(
        savedPositionMs: 30000,
        totalDurationMs: durationMs,
      );
      expect(resumeMs, 30000);
    });

    test('calculateResumePosition returns 0 if position is non-positive or 0 duration', () {
      final zeroPos = VideoProgress.calculateResumePosition(
        savedPositionMs: 0,
        totalDurationMs: 60000,
      );
      expect(zeroPos, 0);

      final zeroDuration = VideoProgress.calculateResumePosition(
        savedPositionMs: 1000,
        totalDurationMs: 0,
      );
      expect(zeroDuration, 0);
    });
  });

  group('VideoProgress database persistence & mapping', () {
    late AppDatabase db;
    late VideoProgressRepositoryImpl repository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = VideoProgressRepositoryImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('saves and retrieves video progress correctly', () async {
      final now = DateTime.now();
      final progress = VideoProgress(
        mediaId: 'vid-123',
        positionMs: 45000,
        durationMs: 120000,
        updatedAt: now,
      );

      await repository.saveProgress(progress);

      final fetched = await repository.getProgress('vid-123');
      expect(fetched, isNotNull);
      expect(fetched!.mediaId, 'vid-123');
      expect(fetched.positionMs, 45000);
      expect(fetched.durationMs, 120000);

      // Upsert / update
      final updated = progress.copyWith(positionMs: 50000);
      await repository.saveProgress(updated);

      final fetchedUpdated = await repository.getProgress('vid-123');
      expect(fetchedUpdated!.positionMs, 50000);
    });

    test('watchAllProgress emits stream of all saved progress', () async {
      final p1 = VideoProgress(
        mediaId: 'vid-1',
        positionMs: 10000,
        durationMs: 50000,
        updatedAt: DateTime.now(),
      );
      final p2 = VideoProgress(
        mediaId: 'vid-2',
        positionMs: 20000,
        durationMs: 60000,
        updatedAt: DateTime.now(),
      );

      await repository.saveProgress(p1);
      await repository.saveProgress(p2);

      final allProgress = await repository.watchAllProgress().first;
      expect(allProgress.length, 2);
      expect(allProgress.any((p) => p.mediaId == 'vid-1'), isTrue);
      expect(allProgress.any((p) => p.mediaId == 'vid-2'), isTrue);

      await repository.deleteProgress('vid-1');
      final afterDelete = await repository.watchAllProgress().first;
      expect(afterDelete.length, 1);
      expect(afterDelete.first.mediaId, 'vid-2');
    });
  });
}
