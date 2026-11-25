// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';

enum MediaType { audio, video }

enum MediaAvailability { available, missing }

enum MediaSortOption {
  title,
  artist,
  dateAdded,
  duration,
}

/// The Music tab's song orders. The first four are the shared
/// [MediaSortOption]s; [album] (album, then disc and track) and [mostPlayed]
/// exist for songs only.
enum SongSortOption {
  title,
  artist,
  album,
  dateAdded,
  duration,
  mostPlayed;

  /// The shared option this one maps to, or null for the song-only ones.
  MediaSortOption? get mediaSort => switch (this) {
        SongSortOption.title => MediaSortOption.title,
        SongSortOption.artist => MediaSortOption.artist,
        SongSortOption.dateAdded => MediaSortOption.dateAdded,
        SongSortOption.duration => MediaSortOption.duration,
        SongSortOption.album || SongSortOption.mostPlayed => null,
      };

  /// Newest, longest and most played make sense first; names start at A.
  bool get startsDescending =>
      this == SongSortOption.dateAdded || this == SongSortOption.duration || this == SongSortOption.mostPlayed;
}

@immutable
class MediaItem {
  final String id;
  final String uri;
  final MediaType mediaType;
  final String title;
  final String? artist;
  final String? album;
  final int durationMs;
  final int sizeBytes;
  final String? format;
  final int? width;
  final int? height;
  final DateTime dateAdded;
  final DateTime? lastPlayed;
  final int playCount;
  final bool isFavorite;
  final MediaAvailability availability;
  final String source; // 'device', 'download' or 'online'
  final String? artworkPath; // local image file (downloaded items) or https thumbnail (online)

  // --- Optional library details (schema v8). All nullable, so every caller
  // that builds a MediaItem without them keeps compiling and behaving. ---

  /// MediaStore ALBUM_ID of a song on the phone: two albums with the same
  /// name stay apart, one compilation stays together.
  final String? albumId;

  /// The album's own artist tag ("Various Artists" on a compilation).
  final String? albumArtist;

  /// Track number within its disc (1-based), when tagged.
  final int? trackNumber;

  /// Disc number (1-based), when tagged.
  final int? discNumber;

  /// Release year, when tagged.
  final int? year;

  /// When the song was liked (null for songs liked before v8 or not liked).
  final DateTime? favoritedAt;

  /// Folder of the file on the phone ("Music/Albums/"), when known.
  final String? relativePath;

  /// Genre tag, when known (Android 11+).
  final String? genre;

  const MediaItem({
    required this.id,
    required this.uri,
    required this.mediaType,
    required this.title,
    this.artist,
    this.album,
    required this.durationMs,
    required this.sizeBytes,
    this.format,
    this.width,
    this.height,
    required this.dateAdded,
    this.lastPlayed,
    this.playCount = 0,
    this.isFavorite = false,
    this.availability = MediaAvailability.available,
    this.source = 'device',
    this.artworkPath,
    this.albumId,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.favoritedAt,
    this.relativePath,
    this.genre,
  });

  /// Streamed or saved from the Online tab (a YouTube watch link), not a file.
  bool get isOnline => source == 'online';

  MediaItem copyWith({
    String? id,
    String? uri,
    MediaType? mediaType,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    int? sizeBytes,
    String? format,
    int? width,
    int? height,
    DateTime? dateAdded,
    DateTime? lastPlayed,
    int? playCount,
    bool? isFavorite,
    MediaAvailability? availability,
    String? source,
    String? artworkPath,
    String? albumId,
    String? albumArtist,
    int? trackNumber,
    int? discNumber,
    int? year,
    DateTime? favoritedAt,
    String? relativePath,
    String? genre,
  }) {
    return MediaItem(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      format: format ?? this.format,
      width: width ?? this.width,
      height: height ?? this.height,
      dateAdded: dateAdded ?? this.dateAdded,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
      availability: availability ?? this.availability,
      source: source ?? this.source,
      artworkPath: artworkPath ?? this.artworkPath,
      albumId: albumId ?? this.albumId,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      favoritedAt: favoritedAt ?? this.favoritedAt,
      relativePath: relativePath ?? this.relativePath,
      genre: genre ?? this.genre,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          uri == other.uri &&
          mediaType == other.mediaType &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          durationMs == other.durationMs &&
          sizeBytes == other.sizeBytes &&
          format == other.format &&
          width == other.width &&
          height == other.height &&
          dateAdded == other.dateAdded &&
          lastPlayed == other.lastPlayed &&
          playCount == other.playCount &&
          isFavorite == other.isFavorite &&
          availability == other.availability &&
          source == other.source &&
          artworkPath == other.artworkPath &&
          albumId == other.albumId &&
          albumArtist == other.albumArtist &&
          trackNumber == other.trackNumber &&
          discNumber == other.discNumber &&
          year == other.year &&
          favoritedAt == other.favoritedAt &&
          relativePath == other.relativePath &&
          genre == other.genre;

  @override
  int get hashCode => Object.hashAll([
        id,
        uri,
        mediaType,
        title,
        artist,
        album,
        durationMs,
        sizeBytes,
        format,
        width,
        height,
        dateAdded,
        lastPlayed,
        playCount,
        isFavorite,
        availability,
        source,
        artworkPath,
        albumId,
        albumArtist,
        trackNumber,
        discNumber,
        year,
        favoritedAt,
        relativePath,
        genre,
      ]);

  Map<String, dynamic> toJsonMap() {
    return {
      'id': id,
      'uri': uri,
      'mediaType': mediaType.name,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'sizeBytes': sizeBytes,
      'format': format,
      'width': width,
      'height': height,
      'dateAdded': dateAdded.toIso8601String(),
      'lastPlayed': lastPlayed?.toIso8601String(),
      'playCount': playCount,
      'isFavorite': isFavorite,
      'availability': availability.name,
      'source': source,
      'artworkPath': artworkPath,
      if (albumId != null) 'albumId': albumId,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (discNumber != null) 'discNumber': discNumber,
      if (year != null) 'year': year,
      if (favoritedAt != null) 'favoritedAt': favoritedAt!.toIso8601String(),
      if (relativePath != null) 'relativePath': relativePath,
      if (genre != null) 'genre': genre,
    };
  }

  factory MediaItem.fromJsonMap(Map<String, dynamic> map) {
    final favoritedAt = map['favoritedAt'];
    return MediaItem(
      id: map['id'] as String,
      uri: map['uri'] as String,
      mediaType: MediaType.values.firstWhere((e) => e.name == map['mediaType'], orElse: () => MediaType.audio),
      title: map['title'] as String,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      durationMs: map['durationMs'] as int? ?? 0,
      sizeBytes: map['sizeBytes'] as int? ?? 0,
      format: map['format'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      dateAdded: map['dateAdded'] != null ? DateTime.parse(map['dateAdded'] as String) : DateTime.now(),
      lastPlayed: map['lastPlayed'] != null ? DateTime.parse(map['lastPlayed'] as String) : null,
      playCount: map['playCount'] as int? ?? 0,
      isFavorite: map['isFavorite'] as bool? ?? false,
      availability: MediaAvailability.values.firstWhere((e) => e.name == map['availability'], orElse: () => MediaAvailability.available),
      source: map['source'] as String? ?? 'device',
      artworkPath: map['artworkPath'] as String?,
      albumId: map['albumId'] as String?,
      albumArtist: map['albumArtist'] as String?,
      trackNumber: (map['trackNumber'] as num?)?.toInt(),
      discNumber: (map['discNumber'] as num?)?.toInt(),
      year: (map['year'] as num?)?.toInt(),
      favoritedAt: favoritedAt is String ? DateTime.tryParse(favoritedAt) : null,
      relativePath: map['relativePath'] as String?,
      genre: map['genre'] as String?,
    );
  }
}
