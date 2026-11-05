import 'package:flutter/foundation.dart';
import 'media_item.dart';

@immutable
class Playlist {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int songCount;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.songCount = 0,
  });

  Playlist copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? songCount,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      songCount: songCount ?? this.songCount,
    );
  }
}

@immutable
class AlbumGroup {
  final String album;
  final String artist;
  final int songCount;
  final int totalDurationMs;
  final List<MediaItem> songs;

  const AlbumGroup({
    required this.album,
    required this.artist,
    required this.songCount,
    required this.totalDurationMs,
    this.songs = const [],
  });
}

@immutable
class ArtistGroup {
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
}

