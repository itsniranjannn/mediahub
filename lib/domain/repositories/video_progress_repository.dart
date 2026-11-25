// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import '../models/video_progress.dart';

abstract class VideoProgressRepository {
  Future<VideoProgress?> getProgress(String mediaId);
  Future<List<VideoProgress>> getAllProgress();
  Future<void> saveProgress(VideoProgress progress);
  Future<void> deleteProgress(String mediaId);
  Stream<List<VideoProgress>> watchAllProgress();
}
