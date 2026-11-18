import 'package:flutter/foundation.dart';

import '../../domain/models/media_item.dart';

/// What the video player plays: [items] in order, starting at [index]. The
/// Videos tab passes the list as it is shown (search and sort applied), so
/// Next and Previous follow what the user sees.
///
/// '/video_player' takes either a bare [MediaItem] (a queue of one) or a
/// [VideoQueue] as its `extra`.
@immutable
class VideoQueue {
  VideoQueue({required List<MediaItem> items, required int index})
      : items = List<MediaItem>.unmodifiable(items),
        index = items.isEmpty ? 0 : index.clamp(0, items.length - 1);

  /// A queue holding just [item].
  VideoQueue.single(MediaItem item) : this(items: [item], index: 0);

  /// Videos only, in the order given.
  final List<MediaItem> items;
  final int index;

  bool get isEmpty => items.isEmpty;

  MediaItem get current => items[index];

  bool get hasNext => index < items.length - 1;
  bool get hasPrevious => index > 0;

  /// The queue moved to [newIndex] (clamped).
  VideoQueue moveTo(int newIndex) => VideoQueue(items: items, index: newIndex);

  /// Reads a route `extra`: a [VideoQueue], or a [MediaItem] as a queue of
  /// one; null for anything else (or an empty queue).
  static VideoQueue? fromExtra(Object? extra) {
    if (extra is VideoQueue) return extra.isEmpty ? null : extra;
    if (extra is MediaItem) return VideoQueue.single(extra);
    return null;
  }
}

/// The queue for opening [item] from [list] (what the screen shows): the
/// videos of [list] that [isPlayable] accepts, in order, starting at [item].
/// [item] itself is always in it, even when [list] does not hold it.
VideoQueue videoQueueFor(
  MediaItem item,
  List<MediaItem> list, {
  bool Function(MediaItem item)? isPlayable,
}) {
  final ok = isPlayable ?? (_) => true;
  final items = <MediaItem>[];
  var index = -1;
  for (final m in list) {
    if (m.mediaType != MediaType.video) continue;
    if (m.id == item.id) {
      if (index >= 0) continue; // a duplicate row: keep the first
      index = items.length;
      items.add(m);
    } else if (ok(m)) {
      items.add(m);
    }
  }
  if (index < 0) return VideoQueue.single(item);
  return VideoQueue(items: items, index: index);
}
