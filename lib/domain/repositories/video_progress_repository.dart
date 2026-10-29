import '../models/video_progress.dart';

abstract class VideoProgressRepository {
  Future<VideoProgress?> getProgress(String mediaId);
  Future<List<VideoProgress>> getAllProgress();
  Future<void> saveProgress(VideoProgress progress);
  Future<void> deleteProgress(String mediaId);
  Stream<List<VideoProgress>> watchAllProgress();
}
