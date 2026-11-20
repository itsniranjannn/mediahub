// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// MediaHub patch (see third_party/video_player_android/README.md): new file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.C;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The ExoPlayer of each live player, by the player id the Dart side knows, so the host app can
 * attach an audio effect (MediaHub's video volume boost uses a LoudnessEnhancer) to that
 * player's own audio session. Read-only for the app: entries are added and removed by {@link
 * VideoPlayerPlugin} as players are created and disposed.
 */
public final class AudioSessions {
  private static final ConcurrentHashMap<Long, ExoPlayer> players = new ConcurrentHashMap<>();

  private AudioSessions() {}

  static void put(long playerId, @NonNull ExoPlayer player) {
    players.put(playerId, player);
  }

  static void remove(long playerId) {
    players.remove(playerId);
  }

  static void clear() {
    players.clear();
  }

  /**
   * The audio session id of player {@code playerId}, or {@link C#AUDIO_SESSION_ID_UNSET} (0) when
   * there is no such player. Call on the main thread (ExoPlayer's application thread).
   */
  @OptIn(markerClass = UnstableApi.class)
  public static int sessionIdFor(long playerId) {
    ExoPlayer player = players.get(playerId);
    if (player == null) {
      return C.AUDIO_SESSION_ID_UNSET;
    }
    try {
      return player.getAudioSessionId();
    } catch (RuntimeException e) {
      // Released or called off its thread: no session to offer.
      return C.AUDIO_SESSION_ID_UNSET;
    }
  }
}
