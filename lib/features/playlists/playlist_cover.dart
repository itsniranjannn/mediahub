import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/artwork_placeholder.dart';

/// Placeholder seed of a playlist's cover: its id, so a playlist keeps its
/// colours when it is renamed, and never shares them with an album or artist
/// of the same name.
String playlistSeed(String playlistId) => 'playlist:$playlistId';

/// Seed of the "Liked songs" cover (the same in every place it shows).
const String likedSongsSeed = 'liked:songs';

/// A playlist's cover (the same in the Music grid, the "Add to playlist"
/// sheet and the playlist page):
/// - four or more different covers among its first songs: a 2 x 2 mosaic of
///   them, like Spotify and YouTube Music;
/// - one to three: the first song's cover;
/// - none yet: one of the cover gradients picked from its id, with a queue
///   glyph.
///
/// Volt is never a cover colour (a white glyph on lime fails), and the
/// gradients keep their hue in both themes.
class PlaylistCover extends StatelessWidget {
  final String playlistId;
  final double size;
  final double borderRadius;

  /// Its first songs with a cover each ([Playlist.coverSongs]).
  final List<MediaItem> coverSongs;

  const PlaylistCover({
    super.key,
    required this.playlistId,
    required this.size,
    required this.borderRadius,
    this.coverSongs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final songs = coverSongs;
    if (songs.isEmpty) {
      return SizedBox.square(
        dimension: size,
        child: ArtworkPlaceholder(
          seed: playlistSeed(playlistId),
          icon: Icons.queue_music_rounded,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    }
    if (songs.length < 4) {
      final song = songs.first;
      return ArtworkThumbnail(
        uri: song.uri,
        artworkPath: song.artworkPath,
        size: size,
        borderRadius: borderRadius,
        placeholderIcon: Icons.queue_music_rounded,
        placeholderSeed: playlistSeed(playlistId),
      );
    }
    final half = size / 2;
    Widget tile(MediaItem song) => ArtworkThumbnail(
          uri: song.uri,
          artworkPath: song.artworkPath,
          size: half,
          borderRadius: 0,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: Column(
          children: [
            Row(children: [tile(songs[0]), tile(songs[1])]),
            Row(children: [tile(songs[2]), tile(songs[3])]),
          ],
        ),
      ),
    );
  }

  /// The tint behind a playlist's page header, from the same colours.
  static LinearGradient heroTint(String playlistId, AppPalette palette) =>
      ArtworkTint.surfaceGradient(playlistSeed(playlistId), palette);
}

/// The "Liked songs" cover: a cover gradient with a heart, pinned first among
/// the playlists and in the "Add to playlist" sheet.
class LikedSongsCover extends StatelessWidget {
  final double size;
  final double borderRadius;

  const LikedSongsCover({super.key, required this.size, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ArtworkPlaceholder(
        seed: likedSongsSeed,
        icon: Icons.favorite_rounded,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  /// The tint behind the Liked songs page header.
  static LinearGradient heroTint(AppPalette palette) => ArtworkTint.surfaceGradient(likedSongsSeed, palette);
}
