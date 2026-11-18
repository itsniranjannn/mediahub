import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../shared/widgets/artwork_placeholder.dart';

/// Placeholder seed of a playlist's cover: its id, so a playlist keeps its
/// colours when it is renamed, and never shares them with an album or artist
/// of the same name.
String playlistSeed(String playlistId) => 'playlist:$playlistId';

/// A playlist's cover: playlists have no art of their own, so they wear one
/// of the cover gradients picked from their id (the same in the Music grid,
/// the "Add to playlist" sheet and the playlist page), with a queue glyph.
///
/// Volt is never a cover colour (a white glyph on lime fails), and the
/// gradients keep their hue in both themes.
class PlaylistCover extends StatelessWidget {
  final String playlistId;
  final double size;
  final double borderRadius;

  const PlaylistCover({
    super.key,
    required this.playlistId,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ArtworkPlaceholder(
        seed: playlistSeed(playlistId),
        icon: Icons.queue_music_rounded,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  /// The tint behind a playlist's page header, from the same colours.
  static LinearGradient heroTint(String playlistId, AppPalette palette) =>
      ArtworkTint.surfaceGradient(playlistSeed(playlistId), palette);
}
