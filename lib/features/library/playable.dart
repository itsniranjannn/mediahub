// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media_item.dart';
import '../music_player/playback_notifier.dart';
import '../online/online_open_request.dart';

/// The items of [items] the music player can play: files that are there.
///
/// Every list hands its songs through this before `loadQueue` / `playTrack`:
/// - a missing file would only fail in the player;
/// - an Online item's uri is a YouTube watch link, which the player would
///   take for a stream URL. Those open in the Online tab instead
///   ([openOnlineItem]).
List<MediaItem> playableOnly(Iterable<MediaItem> items) => [
      for (final item in items)
        if (!item.isOnline && item.availability == MediaAvailability.available) item,
    ];

/// Plays [items] (only the playable ones) from [start], or shuffled from a
/// random song with shuffle mode on, so Next keeps shuffling and the player's
/// shuffle button shows it. Does nothing when none can play.
///
/// Shuffle mode is a sticky toggle, as in Spotify and YT Music: while it is
/// on, a tapped song plays first and the rest of the list follows shuffled,
/// and Play (no [start]) starts from a random song.
Future<void> playCollection(
  PlaybackNotifier playback,
  List<MediaItem> items, {
  MediaItem? start,
  bool shuffle = false,
  int Function(int max)? randomIndex,
}) async {
  final playable = playableOnly(items);
  if (playable.isEmpty) return;
  final sticky = playback.shuffleMode;
  if (shuffle || (sticky && start == null)) {
    final pick = randomIndex ?? _random;
    await playback.loadQueue(playable, startIndex: pick(playable.length), autoPlay: true, shuffle: true);
    return;
  }
  final index = start == null ? 0 : playable.indexWhere((m) => m.id == start.id);
  if (start != null && index < 0) {
    // The tapped song itself cannot play (a missing file or an Online item);
    // the row handles that before calling here.
    return;
  }
  await playback.loadQueue(playable, startIndex: index < 0 ? 0 : index, autoPlay: true, shuffle: sticky);
}

final Random _rng = Random();
int _random(int max) => _rng.nextInt(max);

/// Opens an Online (YouTube) item in the Online tab: the tab loads its watch
/// page. Returns false when its link is not a YouTube page.
bool openOnlineItem(BuildContext context, ProviderContainer container, MediaItem item) {
  final ok = container.read(onlineOpenRequestProvider.notifier).openLink(item.uri);
  if (ok && context.mounted) GoRouter.maybeOf(context)?.go('/online');
  return ok;
}

/// Takes [mediaId] out of the play queue (a deleted song), every copy; the
/// playback package moves on from it when it is the current song.
///
/// Nothing to do while the player has not started (nothing is queued then).
Future<void> removeFromPlayQueue(ProviderContainer container, String mediaId) async {
  if (!container.exists(playbackNotifierProvider)) return;
  await container.read(playbackNotifierProvider.notifier).removeFromQueueById(mediaId);
}
