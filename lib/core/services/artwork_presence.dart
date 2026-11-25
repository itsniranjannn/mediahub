// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import '../../domain/models/media_item.dart';
import 'artwork_service.dart';

/// True when [item] has a real cover: a saved thumbnail file (downloads) or
/// embedded artwork that is already loaded. Screens that tint their
/// background use this to fall back to neutral brand colours instead of the
/// hash palette, so a red cover never sits on a teal card.
bool hasRealArtwork(MediaItem? item) {
  if (item == null) return false;
  final path = item.artworkPath;
  if (path != null && path.isNotEmpty) return true;
  return ArtworkService.instance.hasCached(item.uri);
}
