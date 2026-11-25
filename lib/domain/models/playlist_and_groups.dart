// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';
import 'media_item.dart';

@immutable
class Playlist {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Songs in it that are on the phone (or saved from Online) right now.
  final int songCount;

  /// Up to four of its first songs, each with a different cover, for the
  /// 2 x 2 mosaic cover (empty: the playlist's own gradient).
  final List<MediaItem> coverSongs;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.songCount = 0,
    this.coverSongs = const [],
  });

  Playlist copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? songCount,
    List<MediaItem>? coverSongs,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      songCount: songCount ?? this.songCount,
      coverSongs: coverSongs ?? this.coverSongs,
    );
  }
}

/// One entry of a playlist: the song and its stored position. The position
/// is what remove and reorder act on; it can differ from the row's index on
/// screen when songs in between are hidden (a file that has gone missing).
@immutable
class PlaylistTrack {
  final int position;
  final MediaItem item;

  const PlaylistTrack({required this.position, required this.item});
}

@immutable
class AlbumGroup {
  /// What an album without an album tag is called.
  static const String unknownAlbum = 'Unknown album';

  /// The artist line of an album whose songs have several artists and no
  /// album-artist tag.
  static const String variousArtists = 'Various artists';

  final String album;
  final String artist;
  final int songCount;
  final int totalDurationMs;
  final List<MediaItem> songs;

  /// Uri of the song whose cover stands for the album (the same song on its
  /// tile and on its detail screen); null when unknown.
  final String? coverUri;

  /// Saved thumbnail of that same song (downloads keep their cover as a
  /// separate file, not embedded in the audio); null when it has none.
  final String? coverArtworkPath;

  /// Stable identity of the album, for [LibraryRepository.watchAlbumSongs]:
  /// the phone's album id for songs on the phone, else its album name and
  /// album artist. Empty for a group built by hand (then the album name is
  /// used, see [lookupKey]).
  final String key;

  /// Release year, when tagged.
  final int? year;

  const AlbumGroup({
    required this.album,
    required this.artist,
    required this.songCount,
    required this.totalDurationMs,
    this.songs = const [],
    this.coverUri,
    this.coverArtworkPath,
    this.key = '',
    this.year,
  });

  /// What to look the album's songs up by: [key], or the album name for a
  /// group without one.
  String get lookupKey => key.isNotEmpty ? key : album;
}

@immutable
class ArtistGroup {
  /// The one tile for every song without an artist tag.
  static const String unknownArtist = 'Unknown artist';

  final String artist;
  final int songCount;
  final int albumCount;
  final List<MediaItem> songs;

  const ArtistGroup({
    required this.artist,
    required this.songCount,
    this.albumCount = 0,
    this.songs = const [],
  });

  bool get isUnknown => isUnknownArtistName(artist);
}

/// Whether [name] means "no artist": missing, empty, or one of the
/// placeholders the phone or older versions of the app stored.
bool isUnknownArtistName(String? name) {
  if (name == null) return true;
  final lower = name.trim().toLowerCase();
  return lower.isEmpty || lower == 'unknown artist' || lower == '<unknown>';
}
