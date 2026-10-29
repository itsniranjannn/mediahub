import '../models/playback_state.dart';

abstract class PlaybackRepository {
  Future<PlaybackState?> loadLastPlaybackState();
  Future<void> savePlaybackState(PlaybackState state);
}

