// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import '../models/playback_state.dart';

abstract class PlaybackRepository {
  Future<PlaybackState?> loadLastPlaybackState();
  Future<void> savePlaybackState(PlaybackState state);
}

