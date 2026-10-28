import 'package:flutter/foundation.dart';

enum MediaType { audio, video }

enum MediaAvailability { available, missing }

enum MediaSortOption {
  title,
  artist,
  dateAdded,
  duration,
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
  });

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
          availability == other.availability;

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
      ]);
}
