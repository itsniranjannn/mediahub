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
  final String source; // 'device' or 'download'

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
    String? source,
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
          source == other.source;

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
    };
  }

  factory MediaItem.fromJsonMap(Map<String, dynamic> map) {
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
    );
  }
}
