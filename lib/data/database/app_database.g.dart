// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MediaItemsTableTable extends MediaItemsTable
    with TableInfo<$MediaItemsTableTable, MediaItemEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
    'uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPlayedMeta = const VerificationMeta(
    'lastPlayed',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayed = GeneratedColumn<DateTime>(
    'last_played',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _availabilityMeta = const VerificationMeta(
    'availability',
  );
  @override
  late final GeneratedColumn<String> availability = GeneratedColumn<String>(
    'availability',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('available'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('device'),
  );
  static const VerificationMeta _artworkPathMeta = const VerificationMeta(
    'artworkPath',
  );
  @override
  late final GeneratedColumn<String> artworkPath = GeneratedColumn<String>(
    'artwork_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumArtistMeta = const VerificationMeta(
    'albumArtist',
  );
  @override
  late final GeneratedColumn<String> albumArtist = GeneratedColumn<String>(
    'album_artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discNumberMeta = const VerificationMeta(
    'discNumber',
  );
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
    'disc_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchKeyMeta = const VerificationMeta(
    'searchKey',
  );
  @override
  late final GeneratedColumn<String> searchKey = GeneratedColumn<String>(
    'search_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favoritedAtMeta = const VerificationMeta(
    'favoritedAt',
  );
  @override
  late final GeneratedColumn<DateTime> favoritedAt = GeneratedColumn<DateTime>(
    'favorited_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
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
    searchKey,
    favoritedAt,
    relativePath,
    genre,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_items_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaItemEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('uri')) {
      context.handle(
        _uriMeta,
        uri.isAcceptableOrUnknown(data['uri']!, _uriMeta),
      );
    } else if (isInserting) {
      context.missing(_uriMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    } else if (isInserting) {
      context.missing(_dateAddedMeta);
    }
    if (data.containsKey('last_played')) {
      context.handle(
        _lastPlayedMeta,
        lastPlayed.isAcceptableOrUnknown(data['last_played']!, _lastPlayedMeta),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('availability')) {
      context.handle(
        _availabilityMeta,
        availability.isAcceptableOrUnknown(
          data['availability']!,
          _availabilityMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('artwork_path')) {
      context.handle(
        _artworkPathMeta,
        artworkPath.isAcceptableOrUnknown(
          data['artwork_path']!,
          _artworkPathMeta,
        ),
      );
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('album_artist')) {
      context.handle(
        _albumArtistMeta,
        albumArtist.isAcceptableOrUnknown(
          data['album_artist']!,
          _albumArtistMeta,
        ),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    if (data.containsKey('disc_number')) {
      context.handle(
        _discNumberMeta,
        discNumber.isAcceptableOrUnknown(data['disc_number']!, _discNumberMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('search_key')) {
      context.handle(
        _searchKeyMeta,
        searchKey.isAcceptableOrUnknown(data['search_key']!, _searchKeyMeta),
      );
    }
    if (data.containsKey('favorited_at')) {
      context.handle(
        _favoritedAtMeta,
        favoritedAt.isAcceptableOrUnknown(
          data['favorited_at']!,
          _favoritedAtMeta,
        ),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaItemEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItemEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      uri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uri'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
      lastPlayed: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played'],
      ),
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      availability: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}availability'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      artworkPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_path'],
      ),
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      ),
      albumArtist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_artist'],
      ),
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
      discNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_number'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      searchKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_key'],
      ),
      favoritedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}favorited_at'],
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
    );
  }

  @override
  $MediaItemsTableTable createAlias(String alias) {
    return $MediaItemsTableTable(attachedDatabase, alias);
  }
}

class MediaItemEntry extends DataClass implements Insertable<MediaItemEntry> {
  final String id;
  final String uri;
  final String mediaType;
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
  final String availability;
  final String? source;
  final String? artworkPath;

  /// MediaStore ALBUM_ID (songs on the phone).
  final String? albumId;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;

  /// [librarySearchKey] of the row: folded title, artist and album.
  final String? searchKey;

  /// When the song was liked; null when not liked (or liked before v8).
  final DateTime? favoritedAt;
  final String? relativePath;
  final String? genre;
  const MediaItemEntry({
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
    required this.playCount,
    required this.isFavorite,
    required this.availability,
    this.source,
    this.artworkPath,
    this.albumId,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.searchKey,
    this.favoritedAt,
    this.relativePath,
    this.genre,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['uri'] = Variable<String>(uri);
    map['media_type'] = Variable<String>(mediaType);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    map['date_added'] = Variable<DateTime>(dateAdded);
    if (!nullToAbsent || lastPlayed != null) {
      map['last_played'] = Variable<DateTime>(lastPlayed);
    }
    map['play_count'] = Variable<int>(playCount);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['availability'] = Variable<String>(availability);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || artworkPath != null) {
      map['artwork_path'] = Variable<String>(artworkPath);
    }
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    if (!nullToAbsent || albumArtist != null) {
      map['album_artist'] = Variable<String>(albumArtist);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || searchKey != null) {
      map['search_key'] = Variable<String>(searchKey);
    }
    if (!nullToAbsent || favoritedAt != null) {
      map['favorited_at'] = Variable<DateTime>(favoritedAt);
    }
    if (!nullToAbsent || relativePath != null) {
      map['relative_path'] = Variable<String>(relativePath);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    return map;
  }

  MediaItemsTableCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsTableCompanion(
      id: Value(id),
      uri: Value(uri),
      mediaType: Value(mediaType),
      title: Value(title),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      durationMs: Value(durationMs),
      sizeBytes: Value(sizeBytes),
      format: format == null && nullToAbsent
          ? const Value.absent()
          : Value(format),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      dateAdded: Value(dateAdded),
      lastPlayed: lastPlayed == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayed),
      playCount: Value(playCount),
      isFavorite: Value(isFavorite),
      availability: Value(availability),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      artworkPath: artworkPath == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkPath),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      albumArtist: albumArtist == null && nullToAbsent
          ? const Value.absent()
          : Value(albumArtist),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      searchKey: searchKey == null && nullToAbsent
          ? const Value.absent()
          : Value(searchKey),
      favoritedAt: favoritedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(favoritedAt),
      relativePath: relativePath == null && nullToAbsent
          ? const Value.absent()
          : Value(relativePath),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
    );
  }

  factory MediaItemEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItemEntry(
      id: serializer.fromJson<String>(json['id']),
      uri: serializer.fromJson<String>(json['uri']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      format: serializer.fromJson<String?>(json['format']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
      lastPlayed: serializer.fromJson<DateTime?>(json['lastPlayed']),
      playCount: serializer.fromJson<int>(json['playCount']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      availability: serializer.fromJson<String>(json['availability']),
      source: serializer.fromJson<String?>(json['source']),
      artworkPath: serializer.fromJson<String?>(json['artworkPath']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      albumArtist: serializer.fromJson<String?>(json['albumArtist']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      year: serializer.fromJson<int?>(json['year']),
      searchKey: serializer.fromJson<String?>(json['searchKey']),
      favoritedAt: serializer.fromJson<DateTime?>(json['favoritedAt']),
      relativePath: serializer.fromJson<String?>(json['relativePath']),
      genre: serializer.fromJson<String?>(json['genre']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'uri': serializer.toJson<String>(uri),
      'mediaType': serializer.toJson<String>(mediaType),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'durationMs': serializer.toJson<int>(durationMs),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'format': serializer.toJson<String?>(format),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
      'lastPlayed': serializer.toJson<DateTime?>(lastPlayed),
      'playCount': serializer.toJson<int>(playCount),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'availability': serializer.toJson<String>(availability),
      'source': serializer.toJson<String?>(source),
      'artworkPath': serializer.toJson<String?>(artworkPath),
      'albumId': serializer.toJson<String?>(albumId),
      'albumArtist': serializer.toJson<String?>(albumArtist),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'year': serializer.toJson<int?>(year),
      'searchKey': serializer.toJson<String?>(searchKey),
      'favoritedAt': serializer.toJson<DateTime?>(favoritedAt),
      'relativePath': serializer.toJson<String?>(relativePath),
      'genre': serializer.toJson<String?>(genre),
    };
  }

  MediaItemEntry copyWith({
    String? id,
    String? uri,
    String? mediaType,
    String? title,
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    int? durationMs,
    int? sizeBytes,
    Value<String?> format = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    DateTime? dateAdded,
    Value<DateTime?> lastPlayed = const Value.absent(),
    int? playCount,
    bool? isFavorite,
    String? availability,
    Value<String?> source = const Value.absent(),
    Value<String?> artworkPath = const Value.absent(),
    Value<String?> albumId = const Value.absent(),
    Value<String?> albumArtist = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> searchKey = const Value.absent(),
    Value<DateTime?> favoritedAt = const Value.absent(),
    Value<String?> relativePath = const Value.absent(),
    Value<String?> genre = const Value.absent(),
  }) => MediaItemEntry(
    id: id ?? this.id,
    uri: uri ?? this.uri,
    mediaType: mediaType ?? this.mediaType,
    title: title ?? this.title,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    durationMs: durationMs ?? this.durationMs,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    format: format.present ? format.value : this.format,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    dateAdded: dateAdded ?? this.dateAdded,
    lastPlayed: lastPlayed.present ? lastPlayed.value : this.lastPlayed,
    playCount: playCount ?? this.playCount,
    isFavorite: isFavorite ?? this.isFavorite,
    availability: availability ?? this.availability,
    source: source.present ? source.value : this.source,
    artworkPath: artworkPath.present ? artworkPath.value : this.artworkPath,
    albumId: albumId.present ? albumId.value : this.albumId,
    albumArtist: albumArtist.present ? albumArtist.value : this.albumArtist,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
    discNumber: discNumber.present ? discNumber.value : this.discNumber,
    year: year.present ? year.value : this.year,
    searchKey: searchKey.present ? searchKey.value : this.searchKey,
    favoritedAt: favoritedAt.present ? favoritedAt.value : this.favoritedAt,
    relativePath: relativePath.present ? relativePath.value : this.relativePath,
    genre: genre.present ? genre.value : this.genre,
  );
  MediaItemEntry copyWithCompanion(MediaItemsTableCompanion data) {
    return MediaItemEntry(
      id: data.id.present ? data.id.value : this.id,
      uri: data.uri.present ? data.uri.value : this.uri,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      format: data.format.present ? data.format.value : this.format,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      lastPlayed: data.lastPlayed.present
          ? data.lastPlayed.value
          : this.lastPlayed,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      availability: data.availability.present
          ? data.availability.value
          : this.availability,
      source: data.source.present ? data.source.value : this.source,
      artworkPath: data.artworkPath.present
          ? data.artworkPath.value
          : this.artworkPath,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      albumArtist: data.albumArtist.present
          ? data.albumArtist.value
          : this.albumArtist,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
      discNumber: data.discNumber.present
          ? data.discNumber.value
          : this.discNumber,
      year: data.year.present ? data.year.value : this.year,
      searchKey: data.searchKey.present ? data.searchKey.value : this.searchKey,
      favoritedAt: data.favoritedAt.present
          ? data.favoritedAt.value
          : this.favoritedAt,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      genre: data.genre.present ? data.genre.value : this.genre,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemEntry(')
          ..write('id: $id, ')
          ..write('uri: $uri, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('format: $format, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('playCount: $playCount, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('availability: $availability, ')
          ..write('source: $source, ')
          ..write('artworkPath: $artworkPath, ')
          ..write('albumId: $albumId, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('searchKey: $searchKey, ')
          ..write('favoritedAt: $favoritedAt, ')
          ..write('relativePath: $relativePath, ')
          ..write('genre: $genre')
          ..write(')'))
        .toString();
  }

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
    searchKey,
    favoritedAt,
    relativePath,
    genre,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItemEntry &&
          other.id == this.id &&
          other.uri == this.uri &&
          other.mediaType == this.mediaType &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.durationMs == this.durationMs &&
          other.sizeBytes == this.sizeBytes &&
          other.format == this.format &&
          other.width == this.width &&
          other.height == this.height &&
          other.dateAdded == this.dateAdded &&
          other.lastPlayed == this.lastPlayed &&
          other.playCount == this.playCount &&
          other.isFavorite == this.isFavorite &&
          other.availability == this.availability &&
          other.source == this.source &&
          other.artworkPath == this.artworkPath &&
          other.albumId == this.albumId &&
          other.albumArtist == this.albumArtist &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.year == this.year &&
          other.searchKey == this.searchKey &&
          other.favoritedAt == this.favoritedAt &&
          other.relativePath == this.relativePath &&
          other.genre == this.genre);
}

class MediaItemsTableCompanion extends UpdateCompanion<MediaItemEntry> {
  final Value<String> id;
  final Value<String> uri;
  final Value<String> mediaType;
  final Value<String> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<int> durationMs;
  final Value<int> sizeBytes;
  final Value<String?> format;
  final Value<int?> width;
  final Value<int?> height;
  final Value<DateTime> dateAdded;
  final Value<DateTime?> lastPlayed;
  final Value<int> playCount;
  final Value<bool> isFavorite;
  final Value<String> availability;
  final Value<String?> source;
  final Value<String?> artworkPath;
  final Value<String?> albumId;
  final Value<String?> albumArtist;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<int?> year;
  final Value<String?> searchKey;
  final Value<DateTime?> favoritedAt;
  final Value<String?> relativePath;
  final Value<String?> genre;
  final Value<int> rowid;
  const MediaItemsTableCompanion({
    this.id = const Value.absent(),
    this.uri = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.format = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.lastPlayed = const Value.absent(),
    this.playCount = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.availability = const Value.absent(),
    this.source = const Value.absent(),
    this.artworkPath = const Value.absent(),
    this.albumId = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.searchKey = const Value.absent(),
    this.favoritedAt = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.genre = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaItemsTableCompanion.insert({
    required String id,
    required String uri,
    required String mediaType,
    required String title,
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    required int durationMs,
    required int sizeBytes,
    this.format = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    required DateTime dateAdded,
    this.lastPlayed = const Value.absent(),
    this.playCount = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.availability = const Value.absent(),
    this.source = const Value.absent(),
    this.artworkPath = const Value.absent(),
    this.albumId = const Value.absent(),
    this.albumArtist = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.searchKey = const Value.absent(),
    this.favoritedAt = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.genre = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       uri = Value(uri),
       mediaType = Value(mediaType),
       title = Value(title),
       durationMs = Value(durationMs),
       sizeBytes = Value(sizeBytes),
       dateAdded = Value(dateAdded);
  static Insertable<MediaItemEntry> custom({
    Expression<String>? id,
    Expression<String>? uri,
    Expression<String>? mediaType,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<int>? durationMs,
    Expression<int>? sizeBytes,
    Expression<String>? format,
    Expression<int>? width,
    Expression<int>? height,
    Expression<DateTime>? dateAdded,
    Expression<DateTime>? lastPlayed,
    Expression<int>? playCount,
    Expression<bool>? isFavorite,
    Expression<String>? availability,
    Expression<String>? source,
    Expression<String>? artworkPath,
    Expression<String>? albumId,
    Expression<String>? albumArtist,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<int>? year,
    Expression<String>? searchKey,
    Expression<DateTime>? favoritedAt,
    Expression<String>? relativePath,
    Expression<String>? genre,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uri != null) 'uri': uri,
      if (mediaType != null) 'media_type': mediaType,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (format != null) 'format': format,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (dateAdded != null) 'date_added': dateAdded,
      if (lastPlayed != null) 'last_played': lastPlayed,
      if (playCount != null) 'play_count': playCount,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (availability != null) 'availability': availability,
      if (source != null) 'source': source,
      if (artworkPath != null) 'artwork_path': artworkPath,
      if (albumId != null) 'album_id': albumId,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (year != null) 'year': year,
      if (searchKey != null) 'search_key': searchKey,
      if (favoritedAt != null) 'favorited_at': favoritedAt,
      if (relativePath != null) 'relative_path': relativePath,
      if (genre != null) 'genre': genre,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaItemsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? uri,
    Value<String>? mediaType,
    Value<String>? title,
    Value<String?>? artist,
    Value<String?>? album,
    Value<int>? durationMs,
    Value<int>? sizeBytes,
    Value<String?>? format,
    Value<int?>? width,
    Value<int?>? height,
    Value<DateTime>? dateAdded,
    Value<DateTime?>? lastPlayed,
    Value<int>? playCount,
    Value<bool>? isFavorite,
    Value<String>? availability,
    Value<String?>? source,
    Value<String?>? artworkPath,
    Value<String?>? albumId,
    Value<String?>? albumArtist,
    Value<int?>? trackNumber,
    Value<int?>? discNumber,
    Value<int?>? year,
    Value<String?>? searchKey,
    Value<DateTime?>? favoritedAt,
    Value<String?>? relativePath,
    Value<String?>? genre,
    Value<int>? rowid,
  }) {
    return MediaItemsTableCompanion(
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
      searchKey: searchKey ?? this.searchKey,
      favoritedAt: favoritedAt ?? this.favoritedAt,
      relativePath: relativePath ?? this.relativePath,
      genre: genre ?? this.genre,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    if (lastPlayed.present) {
      map['last_played'] = Variable<DateTime>(lastPlayed.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (availability.present) {
      map['availability'] = Variable<String>(availability.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (artworkPath.present) {
      map['artwork_path'] = Variable<String>(artworkPath.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (albumArtist.present) {
      map['album_artist'] = Variable<String>(albumArtist.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (searchKey.present) {
      map['search_key'] = Variable<String>(searchKey.value);
    }
    if (favoritedAt.present) {
      map['favorited_at'] = Variable<DateTime>(favoritedAt.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsTableCompanion(')
          ..write('id: $id, ')
          ..write('uri: $uri, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('format: $format, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('lastPlayed: $lastPlayed, ')
          ..write('playCount: $playCount, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('availability: $availability, ')
          ..write('source: $source, ')
          ..write('artworkPath: $artworkPath, ')
          ..write('albumId: $albumId, ')
          ..write('albumArtist: $albumArtist, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('searchKey: $searchKey, ')
          ..write('favoritedAt: $favoritedAt, ')
          ..write('relativePath: $relativePath, ')
          ..write('genre: $genre, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaybackStatesTableTable extends PlaybackStatesTable
    with TableInfo<$PlaybackStatesTableTable, PlaybackStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackStatesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _currentItemIdMeta = const VerificationMeta(
    'currentItemId',
  );
  @override
  late final GeneratedColumn<String> currentItemId = GeneratedColumn<String>(
    'current_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _queueJsonMeta = const VerificationMeta(
    'queueJson',
  );
  @override
  late final GeneratedColumn<String> queueJson = GeneratedColumn<String>(
    'queue_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queueIndexMeta = const VerificationMeta(
    'queueIndex',
  );
  @override
  late final GeneratedColumn<int> queueIndex = GeneratedColumn<int>(
    'queue_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _repeatModeMeta = const VerificationMeta(
    'repeatMode',
  );
  @override
  late final GeneratedColumn<String> repeatMode = GeneratedColumn<String>(
    'repeat_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('off'),
  );
  static const VerificationMeta _shuffleMeta = const VerificationMeta(
    'shuffle',
  );
  @override
  late final GeneratedColumn<bool> shuffle = GeneratedColumn<bool>(
    'shuffle',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shuffle" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1.0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    currentItemId,
    queueJson,
    queueIndex,
    positionMs,
    durationMs,
    repeatMode,
    shuffle,
    speed,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_states_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('current_item_id')) {
      context.handle(
        _currentItemIdMeta,
        currentItemId.isAcceptableOrUnknown(
          data['current_item_id']!,
          _currentItemIdMeta,
        ),
      );
    }
    if (data.containsKey('queue_json')) {
      context.handle(
        _queueJsonMeta,
        queueJson.isAcceptableOrUnknown(data['queue_json']!, _queueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_queueJsonMeta);
    }
    if (data.containsKey('queue_index')) {
      context.handle(
        _queueIndexMeta,
        queueIndex.isAcceptableOrUnknown(data['queue_index']!, _queueIndexMeta),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('repeat_mode')) {
      context.handle(
        _repeatModeMeta,
        repeatMode.isAcceptableOrUnknown(data['repeat_mode']!, _repeatModeMeta),
      );
    }
    if (data.containsKey('shuffle')) {
      context.handle(
        _shuffleMeta,
        shuffle.isAcceptableOrUnknown(data['shuffle']!, _shuffleMeta),
      );
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaybackStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackStateEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      currentItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_item_id'],
      ),
      queueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_json'],
      )!,
      queueIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queue_index'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      repeatMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repeat_mode'],
      )!,
      shuffle: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shuffle'],
      )!,
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlaybackStatesTableTable createAlias(String alias) {
    return $PlaybackStatesTableTable(attachedDatabase, alias);
  }
}

class PlaybackStateEntry extends DataClass
    implements Insertable<PlaybackStateEntry> {
  final int id;
  final String? currentItemId;
  final String queueJson;
  final int queueIndex;
  final int positionMs;
  final int durationMs;
  final String repeatMode;
  final bool shuffle;
  final double speed;
  final DateTime updatedAt;
  const PlaybackStateEntry({
    required this.id,
    this.currentItemId,
    required this.queueJson,
    required this.queueIndex,
    required this.positionMs,
    required this.durationMs,
    required this.repeatMode,
    required this.shuffle,
    required this.speed,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || currentItemId != null) {
      map['current_item_id'] = Variable<String>(currentItemId);
    }
    map['queue_json'] = Variable<String>(queueJson);
    map['queue_index'] = Variable<int>(queueIndex);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['repeat_mode'] = Variable<String>(repeatMode);
    map['shuffle'] = Variable<bool>(shuffle);
    map['speed'] = Variable<double>(speed);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlaybackStatesTableCompanion toCompanion(bool nullToAbsent) {
    return PlaybackStatesTableCompanion(
      id: Value(id),
      currentItemId: currentItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentItemId),
      queueJson: Value(queueJson),
      queueIndex: Value(queueIndex),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      repeatMode: Value(repeatMode),
      shuffle: Value(shuffle),
      speed: Value(speed),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlaybackStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackStateEntry(
      id: serializer.fromJson<int>(json['id']),
      currentItemId: serializer.fromJson<String?>(json['currentItemId']),
      queueJson: serializer.fromJson<String>(json['queueJson']),
      queueIndex: serializer.fromJson<int>(json['queueIndex']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      repeatMode: serializer.fromJson<String>(json['repeatMode']),
      shuffle: serializer.fromJson<bool>(json['shuffle']),
      speed: serializer.fromJson<double>(json['speed']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'currentItemId': serializer.toJson<String?>(currentItemId),
      'queueJson': serializer.toJson<String>(queueJson),
      'queueIndex': serializer.toJson<int>(queueIndex),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'repeatMode': serializer.toJson<String>(repeatMode),
      'shuffle': serializer.toJson<bool>(shuffle),
      'speed': serializer.toJson<double>(speed),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlaybackStateEntry copyWith({
    int? id,
    Value<String?> currentItemId = const Value.absent(),
    String? queueJson,
    int? queueIndex,
    int? positionMs,
    int? durationMs,
    String? repeatMode,
    bool? shuffle,
    double? speed,
    DateTime? updatedAt,
  }) => PlaybackStateEntry(
    id: id ?? this.id,
    currentItemId: currentItemId.present
        ? currentItemId.value
        : this.currentItemId,
    queueJson: queueJson ?? this.queueJson,
    queueIndex: queueIndex ?? this.queueIndex,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    repeatMode: repeatMode ?? this.repeatMode,
    shuffle: shuffle ?? this.shuffle,
    speed: speed ?? this.speed,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlaybackStateEntry copyWithCompanion(PlaybackStatesTableCompanion data) {
    return PlaybackStateEntry(
      id: data.id.present ? data.id.value : this.id,
      currentItemId: data.currentItemId.present
          ? data.currentItemId.value
          : this.currentItemId,
      queueJson: data.queueJson.present ? data.queueJson.value : this.queueJson,
      queueIndex: data.queueIndex.present
          ? data.queueIndex.value
          : this.queueIndex,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      repeatMode: data.repeatMode.present
          ? data.repeatMode.value
          : this.repeatMode,
      shuffle: data.shuffle.present ? data.shuffle.value : this.shuffle,
      speed: data.speed.present ? data.speed.value : this.speed,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackStateEntry(')
          ..write('id: $id, ')
          ..write('currentItemId: $currentItemId, ')
          ..write('queueJson: $queueJson, ')
          ..write('queueIndex: $queueIndex, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('repeatMode: $repeatMode, ')
          ..write('shuffle: $shuffle, ')
          ..write('speed: $speed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    currentItemId,
    queueJson,
    queueIndex,
    positionMs,
    durationMs,
    repeatMode,
    shuffle,
    speed,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackStateEntry &&
          other.id == this.id &&
          other.currentItemId == this.currentItemId &&
          other.queueJson == this.queueJson &&
          other.queueIndex == this.queueIndex &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.repeatMode == this.repeatMode &&
          other.shuffle == this.shuffle &&
          other.speed == this.speed &&
          other.updatedAt == this.updatedAt);
}

class PlaybackStatesTableCompanion extends UpdateCompanion<PlaybackStateEntry> {
  final Value<int> id;
  final Value<String?> currentItemId;
  final Value<String> queueJson;
  final Value<int> queueIndex;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<String> repeatMode;
  final Value<bool> shuffle;
  final Value<double> speed;
  final Value<DateTime> updatedAt;
  const PlaybackStatesTableCompanion({
    this.id = const Value.absent(),
    this.currentItemId = const Value.absent(),
    this.queueJson = const Value.absent(),
    this.queueIndex = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.repeatMode = const Value.absent(),
    this.shuffle = const Value.absent(),
    this.speed = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PlaybackStatesTableCompanion.insert({
    this.id = const Value.absent(),
    this.currentItemId = const Value.absent(),
    required String queueJson,
    this.queueIndex = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.repeatMode = const Value.absent(),
    this.shuffle = const Value.absent(),
    this.speed = const Value.absent(),
    required DateTime updatedAt,
  }) : queueJson = Value(queueJson),
       updatedAt = Value(updatedAt);
  static Insertable<PlaybackStateEntry> custom({
    Expression<int>? id,
    Expression<String>? currentItemId,
    Expression<String>? queueJson,
    Expression<int>? queueIndex,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<String>? repeatMode,
    Expression<bool>? shuffle,
    Expression<double>? speed,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currentItemId != null) 'current_item_id': currentItemId,
      if (queueJson != null) 'queue_json': queueJson,
      if (queueIndex != null) 'queue_index': queueIndex,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (repeatMode != null) 'repeat_mode': repeatMode,
      if (shuffle != null) 'shuffle': shuffle,
      if (speed != null) 'speed': speed,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PlaybackStatesTableCompanion copyWith({
    Value<int>? id,
    Value<String?>? currentItemId,
    Value<String>? queueJson,
    Value<int>? queueIndex,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<String>? repeatMode,
    Value<bool>? shuffle,
    Value<double>? speed,
    Value<DateTime>? updatedAt,
  }) {
    return PlaybackStatesTableCompanion(
      id: id ?? this.id,
      currentItemId: currentItemId ?? this.currentItemId,
      queueJson: queueJson ?? this.queueJson,
      queueIndex: queueIndex ?? this.queueIndex,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffle: shuffle ?? this.shuffle,
      speed: speed ?? this.speed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (currentItemId.present) {
      map['current_item_id'] = Variable<String>(currentItemId.value);
    }
    if (queueJson.present) {
      map['queue_json'] = Variable<String>(queueJson.value);
    }
    if (queueIndex.present) {
      map['queue_index'] = Variable<int>(queueIndex.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (repeatMode.present) {
      map['repeat_mode'] = Variable<String>(repeatMode.value);
    }
    if (shuffle.present) {
      map['shuffle'] = Variable<bool>(shuffle.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackStatesTableCompanion(')
          ..write('id: $id, ')
          ..write('currentItemId: $currentItemId, ')
          ..write('queueJson: $queueJson, ')
          ..write('queueIndex: $queueIndex, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('repeatMode: $repeatMode, ')
          ..write('shuffle: $shuffle, ')
          ..write('speed: $speed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $VideoProgressTableTable extends VideoProgressTable
    with TableInfo<$VideoProgressTableTable, VideoProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VideoProgressTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaId,
    positionMs,
    durationMs,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'video_progress_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<VideoProgressEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  VideoProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VideoProgressEntry(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $VideoProgressTableTable createAlias(String alias) {
    return $VideoProgressTableTable(attachedDatabase, alias);
  }
}

class VideoProgressEntry extends DataClass
    implements Insertable<VideoProgressEntry> {
  final String mediaId;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  const VideoProgressEntry({
    required this.mediaId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  VideoProgressTableCompanion toCompanion(bool nullToAbsent) {
    return VideoProgressTableCompanion(
      mediaId: Value(mediaId),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      updatedAt: Value(updatedAt),
    );
  }

  factory VideoProgressEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VideoProgressEntry(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  VideoProgressEntry copyWith({
    String? mediaId,
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
  }) => VideoProgressEntry(
    mediaId: mediaId ?? this.mediaId,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  VideoProgressEntry copyWithCompanion(VideoProgressTableCompanion data) {
    return VideoProgressEntry(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VideoProgressEntry(')
          ..write('mediaId: $mediaId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, positionMs, durationMs, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VideoProgressEntry &&
          other.mediaId == this.mediaId &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.updatedAt == this.updatedAt);
}

class VideoProgressTableCompanion extends UpdateCompanion<VideoProgressEntry> {
  final Value<String> mediaId;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const VideoProgressTableCompanion({
    this.mediaId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VideoProgressTableCompanion.insert({
    required String mediaId,
    required int positionMs,
    required int durationMs,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs),
       updatedAt = Value(updatedAt);
  static Insertable<VideoProgressEntry> custom({
    Expression<String>? mediaId,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VideoProgressTableCompanion copyWith({
    Value<String>? mediaId,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return VideoProgressTableCompanion(
      mediaId: mediaId ?? this.mediaId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VideoProgressTableCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTableTable extends PlaylistsTable
    with TableInfo<$PlaylistsTableTable, PlaylistEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlaylistsTableTable createAlias(String alias) {
    return $PlaylistsTableTable(attachedDatabase, alias);
  }
}

class PlaylistEntry extends DataClass implements Insertable<PlaylistEntry> {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PlaylistEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlaylistsTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsTableCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlaylistEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlaylistEntry copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PlaylistEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlaylistEntry copyWithCompanion(PlaylistsTableCompanion data) {
    return PlaylistEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlaylistsTableCompanion extends UpdateCompanion<PlaylistEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlaylistsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsTableCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlaylistEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlaylistsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistItemsTableTable extends PlaylistItemsTable
    with TableInfo<$PlaylistItemsTableTable, PlaylistItemEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistItemsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    mediaId,
    position,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_items_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistItemEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {playlistId, mediaId, position},
  ];
  @override
  PlaylistItemEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistItemEntry(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $PlaylistItemsTableTable createAlias(String alias) {
    return $PlaylistItemsTableTable(attachedDatabase, alias);
  }
}

class PlaylistItemEntry extends DataClass
    implements Insertable<PlaylistItemEntry> {
  final String playlistId;
  final String mediaId;
  final int position;
  final DateTime addedAt;
  const PlaylistItemEntry({
    required this.playlistId,
    required this.mediaId,
    required this.position,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['media_id'] = Variable<String>(mediaId);
    map['position'] = Variable<int>(position);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  PlaylistItemsTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistItemsTableCompanion(
      playlistId: Value(playlistId),
      mediaId: Value(mediaId),
      position: Value(position),
      addedAt: Value(addedAt),
    );
  }

  factory PlaylistItemEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistItemEntry(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      position: serializer.fromJson<int>(json['position']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'mediaId': serializer.toJson<String>(mediaId),
      'position': serializer.toJson<int>(position),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  PlaylistItemEntry copyWith({
    String? playlistId,
    String? mediaId,
    int? position,
    DateTime? addedAt,
  }) => PlaylistItemEntry(
    playlistId: playlistId ?? this.playlistId,
    mediaId: mediaId ?? this.mediaId,
    position: position ?? this.position,
    addedAt: addedAt ?? this.addedAt,
  );
  PlaylistItemEntry copyWithCompanion(PlaylistItemsTableCompanion data) {
    return PlaylistItemEntry(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      position: data.position.present ? data.position.value : this.position,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemEntry(')
          ..write('playlistId: $playlistId, ')
          ..write('mediaId: $mediaId, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(playlistId, mediaId, position, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistItemEntry &&
          other.playlistId == this.playlistId &&
          other.mediaId == this.mediaId &&
          other.position == this.position &&
          other.addedAt == this.addedAt);
}

class PlaylistItemsTableCompanion extends UpdateCompanion<PlaylistItemEntry> {
  final Value<String> playlistId;
  final Value<String> mediaId;
  final Value<int> position;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const PlaylistItemsTableCompanion({
    this.playlistId = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.position = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistItemsTableCompanion.insert({
    required String playlistId,
    required String mediaId,
    required int position,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       mediaId = Value(mediaId),
       position = Value(position),
       addedAt = Value(addedAt);
  static Insertable<PlaylistItemEntry> custom({
    Expression<String>? playlistId,
    Expression<String>? mediaId,
    Expression<int>? position,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (mediaId != null) 'media_id': mediaId,
      if (position != null) 'position': position,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistItemsTableCompanion copyWith({
    Value<String>? playlistId,
    Value<String>? mediaId,
    Value<int>? position,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return PlaylistItemsTableCompanion(
      playlistId: playlistId ?? this.playlistId,
      mediaId: mediaId ?? this.mediaId,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemsTableCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('mediaId: $mediaId, ')
          ..write('position: $position, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadsTableTable extends DownloadsTable
    with TableInfo<$DownloadsTableTable, DownloadEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedBytesMeta = const VerificationMeta(
    'receivedBytes',
  );
  @override
  late final GeneratedColumn<int> receivedBytes = GeneratedColumn<int>(
    'received_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<String> lastModified = GeneratedColumn<String>(
    'last_modified',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supportsRangeMeta = const VerificationMeta(
    'supportsRange',
  );
  @override
  late final GeneratedColumn<bool> supportsRange = GeneratedColumn<bool>(
    'supports_range',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("supports_range" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finalPathMeta = const VerificationMeta(
    'finalPath',
  );
  @override
  late final GeneratedColumn<String> finalPath = GeneratedColumn<String>(
    'final_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _engineMeta = const VerificationMeta('engine');
  @override
  late final GeneratedColumn<String> engine = GeneratedColumn<String>(
    'engine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('http'),
  );
  static const VerificationMeta _thumbnailUrlMeta = const VerificationMeta(
    'thumbnailUrl',
  );
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
    'thumbnail_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _qualityLabelMeta = const VerificationMeta(
    'qualityLabel',
  );
  @override
  late final GeneratedColumn<String> qualityLabel = GeneratedColumn<String>(
    'quality_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatSelectorMeta = const VerificationMeta(
    'formatSelector',
  );
  @override
  late final GeneratedColumn<String> formatSelector = GeneratedColumn<String>(
    'format_selector',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioFormatMeta = const VerificationMeta(
    'audioFormat',
  );
  @override
  late final GeneratedColumn<String> audioFormat = GeneratedColumn<String>(
    'audio_format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractorArgsMeta = const VerificationMeta(
    'extractorArgs',
  );
  @override
  late final GeneratedColumn<String> extractorArgs = GeneratedColumn<String>(
    'extractor_args',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploaderMeta = const VerificationMeta(
    'uploader',
  );
  @override
  late final GeneratedColumn<String> uploader = GeneratedColumn<String>(
    'uploader',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _streamSizesMeta = const VerificationMeta(
    'streamSizes',
  );
  @override
  late final GeneratedColumn<String> streamSizes = GeneratedColumn<String>(
    'stream_sizes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorDetailMeta = const VerificationMeta(
    'errorDetail',
  );
  @override
  late final GeneratedColumn<String> errorDetail = GeneratedColumn<String>(
    'error_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    url,
    host,
    displayName,
    fileName,
    state,
    receivedBytes,
    totalBytes,
    etag,
    lastModified,
    supportsRange,
    mimeType,
    errorCode,
    createdAt,
    updatedAt,
    finalPath,
    mediaId,
    kind,
    engine,
    thumbnailUrl,
    thumbnailPath,
    qualityLabel,
    formatSelector,
    audioFormat,
    extractorArgs,
    uploader,
    durationSec,
    streamSizes,
    errorDetail,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('received_bytes')) {
      context.handle(
        _receivedBytesMeta,
        receivedBytes.isAcceptableOrUnknown(
          data['received_bytes']!,
          _receivedBytesMeta,
        ),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    }
    if (data.containsKey('supports_range')) {
      context.handle(
        _supportsRangeMeta,
        supportsRange.isAcceptableOrUnknown(
          data['supports_range']!,
          _supportsRangeMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('final_path')) {
      context.handle(
        _finalPathMeta,
        finalPath.isAcceptableOrUnknown(data['final_path']!, _finalPathMeta),
      );
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('engine')) {
      context.handle(
        _engineMeta,
        engine.isAcceptableOrUnknown(data['engine']!, _engineMeta),
      );
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
        _thumbnailUrlMeta,
        thumbnailUrl.isAcceptableOrUnknown(
          data['thumbnail_url']!,
          _thumbnailUrlMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('quality_label')) {
      context.handle(
        _qualityLabelMeta,
        qualityLabel.isAcceptableOrUnknown(
          data['quality_label']!,
          _qualityLabelMeta,
        ),
      );
    }
    if (data.containsKey('format_selector')) {
      context.handle(
        _formatSelectorMeta,
        formatSelector.isAcceptableOrUnknown(
          data['format_selector']!,
          _formatSelectorMeta,
        ),
      );
    }
    if (data.containsKey('audio_format')) {
      context.handle(
        _audioFormatMeta,
        audioFormat.isAcceptableOrUnknown(
          data['audio_format']!,
          _audioFormatMeta,
        ),
      );
    }
    if (data.containsKey('extractor_args')) {
      context.handle(
        _extractorArgsMeta,
        extractorArgs.isAcceptableOrUnknown(
          data['extractor_args']!,
          _extractorArgsMeta,
        ),
      );
    }
    if (data.containsKey('uploader')) {
      context.handle(
        _uploaderMeta,
        uploader.isAcceptableOrUnknown(data['uploader']!, _uploaderMeta),
      );
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    }
    if (data.containsKey('stream_sizes')) {
      context.handle(
        _streamSizesMeta,
        streamSizes.isAcceptableOrUnknown(
          data['stream_sizes']!,
          _streamSizesMeta,
        ),
      );
    }
    if (data.containsKey('error_detail')) {
      context.handle(
        _errorDetailMeta,
        errorDetail.isAcceptableOrUnknown(
          data['error_detail']!,
          _errorDetailMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DownloadEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      receivedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_bytes'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified'],
      ),
      supportsRange: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_range'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      finalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}final_path'],
      ),
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      engine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine'],
      )!,
      thumbnailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_url'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      qualityLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality_label'],
      ),
      formatSelector: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format_selector'],
      ),
      audioFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_format'],
      ),
      extractorArgs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extractor_args'],
      ),
      uploader: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploader'],
      ),
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      ),
      streamSizes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_sizes'],
      ),
      errorDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_detail'],
      ),
    );
  }

  @override
  $DownloadsTableTable createAlias(String alias) {
    return $DownloadsTableTable(attachedDatabase, alias);
  }
}

class DownloadEntry extends DataClass implements Insertable<DownloadEntry> {
  final String id;
  final String url;
  final String host;
  final String displayName;
  final String fileName;
  final String state;
  final int receivedBytes;
  final int? totalBytes;
  final String? etag;
  final String? lastModified;
  final bool supportsRange;
  final String? mimeType;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? finalPath;
  final String? mediaId;

  /// 'audio' | 'video' (null = not known yet, e.g. direct link before sniffing)
  final String? kind;

  /// 'http' (direct link engine) | 'extractor' (yt-dlp web link downloader)
  final String engine;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final String? qualityLabel;
  final String? formatSelector;
  final String? audioFormat;
  final String? extractorArgs;
  final String? uploader;
  final int? durationSec;

  /// JSON list of expected stream sizes in bytes (e.g. [video, audio]); used
  /// to turn yt-dlp's per-stream percentages into one overall progress value.
  final String? streamSizes;

  /// Short, sanitized reason reported by the downloader (shown under the error).
  final String? errorDetail;
  const DownloadEntry({
    required this.id,
    required this.url,
    required this.host,
    required this.displayName,
    required this.fileName,
    required this.state,
    required this.receivedBytes,
    this.totalBytes,
    this.etag,
    this.lastModified,
    required this.supportsRange,
    this.mimeType,
    this.errorCode,
    required this.createdAt,
    required this.updatedAt,
    this.finalPath,
    this.mediaId,
    this.kind,
    required this.engine,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.qualityLabel,
    this.formatSelector,
    this.audioFormat,
    this.extractorArgs,
    this.uploader,
    this.durationSec,
    this.streamSizes,
    this.errorDetail,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['url'] = Variable<String>(url);
    map['host'] = Variable<String>(host);
    map['display_name'] = Variable<String>(displayName);
    map['file_name'] = Variable<String>(fileName);
    map['state'] = Variable<String>(state);
    map['received_bytes'] = Variable<int>(receivedBytes);
    if (!nullToAbsent || totalBytes != null) {
      map['total_bytes'] = Variable<int>(totalBytes);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || lastModified != null) {
      map['last_modified'] = Variable<String>(lastModified);
    }
    map['supports_range'] = Variable<bool>(supportsRange);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || finalPath != null) {
      map['final_path'] = Variable<String>(finalPath);
    }
    if (!nullToAbsent || mediaId != null) {
      map['media_id'] = Variable<String>(mediaId);
    }
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    map['engine'] = Variable<String>(engine);
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || qualityLabel != null) {
      map['quality_label'] = Variable<String>(qualityLabel);
    }
    if (!nullToAbsent || formatSelector != null) {
      map['format_selector'] = Variable<String>(formatSelector);
    }
    if (!nullToAbsent || audioFormat != null) {
      map['audio_format'] = Variable<String>(audioFormat);
    }
    if (!nullToAbsent || extractorArgs != null) {
      map['extractor_args'] = Variable<String>(extractorArgs);
    }
    if (!nullToAbsent || uploader != null) {
      map['uploader'] = Variable<String>(uploader);
    }
    if (!nullToAbsent || durationSec != null) {
      map['duration_sec'] = Variable<int>(durationSec);
    }
    if (!nullToAbsent || streamSizes != null) {
      map['stream_sizes'] = Variable<String>(streamSizes);
    }
    if (!nullToAbsent || errorDetail != null) {
      map['error_detail'] = Variable<String>(errorDetail);
    }
    return map;
  }

  DownloadsTableCompanion toCompanion(bool nullToAbsent) {
    return DownloadsTableCompanion(
      id: Value(id),
      url: Value(url),
      host: Value(host),
      displayName: Value(displayName),
      fileName: Value(fileName),
      state: Value(state),
      receivedBytes: Value(receivedBytes),
      totalBytes: totalBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalBytes),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      lastModified: lastModified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModified),
      supportsRange: Value(supportsRange),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      finalPath: finalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(finalPath),
      mediaId: mediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaId),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      engine: Value(engine),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      qualityLabel: qualityLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(qualityLabel),
      formatSelector: formatSelector == null && nullToAbsent
          ? const Value.absent()
          : Value(formatSelector),
      audioFormat: audioFormat == null && nullToAbsent
          ? const Value.absent()
          : Value(audioFormat),
      extractorArgs: extractorArgs == null && nullToAbsent
          ? const Value.absent()
          : Value(extractorArgs),
      uploader: uploader == null && nullToAbsent
          ? const Value.absent()
          : Value(uploader),
      durationSec: durationSec == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSec),
      streamSizes: streamSizes == null && nullToAbsent
          ? const Value.absent()
          : Value(streamSizes),
      errorDetail: errorDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(errorDetail),
    );
  }

  factory DownloadEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadEntry(
      id: serializer.fromJson<String>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      host: serializer.fromJson<String>(json['host']),
      displayName: serializer.fromJson<String>(json['displayName']),
      fileName: serializer.fromJson<String>(json['fileName']),
      state: serializer.fromJson<String>(json['state']),
      receivedBytes: serializer.fromJson<int>(json['receivedBytes']),
      totalBytes: serializer.fromJson<int?>(json['totalBytes']),
      etag: serializer.fromJson<String?>(json['etag']),
      lastModified: serializer.fromJson<String?>(json['lastModified']),
      supportsRange: serializer.fromJson<bool>(json['supportsRange']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      finalPath: serializer.fromJson<String?>(json['finalPath']),
      mediaId: serializer.fromJson<String?>(json['mediaId']),
      kind: serializer.fromJson<String?>(json['kind']),
      engine: serializer.fromJson<String>(json['engine']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      qualityLabel: serializer.fromJson<String?>(json['qualityLabel']),
      formatSelector: serializer.fromJson<String?>(json['formatSelector']),
      audioFormat: serializer.fromJson<String?>(json['audioFormat']),
      extractorArgs: serializer.fromJson<String?>(json['extractorArgs']),
      uploader: serializer.fromJson<String?>(json['uploader']),
      durationSec: serializer.fromJson<int?>(json['durationSec']),
      streamSizes: serializer.fromJson<String?>(json['streamSizes']),
      errorDetail: serializer.fromJson<String?>(json['errorDetail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'url': serializer.toJson<String>(url),
      'host': serializer.toJson<String>(host),
      'displayName': serializer.toJson<String>(displayName),
      'fileName': serializer.toJson<String>(fileName),
      'state': serializer.toJson<String>(state),
      'receivedBytes': serializer.toJson<int>(receivedBytes),
      'totalBytes': serializer.toJson<int?>(totalBytes),
      'etag': serializer.toJson<String?>(etag),
      'lastModified': serializer.toJson<String?>(lastModified),
      'supportsRange': serializer.toJson<bool>(supportsRange),
      'mimeType': serializer.toJson<String?>(mimeType),
      'errorCode': serializer.toJson<String?>(errorCode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'finalPath': serializer.toJson<String?>(finalPath),
      'mediaId': serializer.toJson<String?>(mediaId),
      'kind': serializer.toJson<String?>(kind),
      'engine': serializer.toJson<String>(engine),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'qualityLabel': serializer.toJson<String?>(qualityLabel),
      'formatSelector': serializer.toJson<String?>(formatSelector),
      'audioFormat': serializer.toJson<String?>(audioFormat),
      'extractorArgs': serializer.toJson<String?>(extractorArgs),
      'uploader': serializer.toJson<String?>(uploader),
      'durationSec': serializer.toJson<int?>(durationSec),
      'streamSizes': serializer.toJson<String?>(streamSizes),
      'errorDetail': serializer.toJson<String?>(errorDetail),
    };
  }

  DownloadEntry copyWith({
    String? id,
    String? url,
    String? host,
    String? displayName,
    String? fileName,
    String? state,
    int? receivedBytes,
    Value<int?> totalBytes = const Value.absent(),
    Value<String?> etag = const Value.absent(),
    Value<String?> lastModified = const Value.absent(),
    bool? supportsRange,
    Value<String?> mimeType = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> finalPath = const Value.absent(),
    Value<String?> mediaId = const Value.absent(),
    Value<String?> kind = const Value.absent(),
    String? engine,
    Value<String?> thumbnailUrl = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    Value<String?> qualityLabel = const Value.absent(),
    Value<String?> formatSelector = const Value.absent(),
    Value<String?> audioFormat = const Value.absent(),
    Value<String?> extractorArgs = const Value.absent(),
    Value<String?> uploader = const Value.absent(),
    Value<int?> durationSec = const Value.absent(),
    Value<String?> streamSizes = const Value.absent(),
    Value<String?> errorDetail = const Value.absent(),
  }) => DownloadEntry(
    id: id ?? this.id,
    url: url ?? this.url,
    host: host ?? this.host,
    displayName: displayName ?? this.displayName,
    fileName: fileName ?? this.fileName,
    state: state ?? this.state,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes.present ? totalBytes.value : this.totalBytes,
    etag: etag.present ? etag.value : this.etag,
    lastModified: lastModified.present ? lastModified.value : this.lastModified,
    supportsRange: supportsRange ?? this.supportsRange,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    finalPath: finalPath.present ? finalPath.value : this.finalPath,
    mediaId: mediaId.present ? mediaId.value : this.mediaId,
    kind: kind.present ? kind.value : this.kind,
    engine: engine ?? this.engine,
    thumbnailUrl: thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    qualityLabel: qualityLabel.present ? qualityLabel.value : this.qualityLabel,
    formatSelector: formatSelector.present
        ? formatSelector.value
        : this.formatSelector,
    audioFormat: audioFormat.present ? audioFormat.value : this.audioFormat,
    extractorArgs: extractorArgs.present
        ? extractorArgs.value
        : this.extractorArgs,
    uploader: uploader.present ? uploader.value : this.uploader,
    durationSec: durationSec.present ? durationSec.value : this.durationSec,
    streamSizes: streamSizes.present ? streamSizes.value : this.streamSizes,
    errorDetail: errorDetail.present ? errorDetail.value : this.errorDetail,
  );
  DownloadEntry copyWithCompanion(DownloadsTableCompanion data) {
    return DownloadEntry(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      host: data.host.present ? data.host.value : this.host,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      state: data.state.present ? data.state.value : this.state,
      receivedBytes: data.receivedBytes.present
          ? data.receivedBytes.value
          : this.receivedBytes,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      etag: data.etag.present ? data.etag.value : this.etag,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      supportsRange: data.supportsRange.present
          ? data.supportsRange.value
          : this.supportsRange,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      finalPath: data.finalPath.present ? data.finalPath.value : this.finalPath,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      kind: data.kind.present ? data.kind.value : this.kind,
      engine: data.engine.present ? data.engine.value : this.engine,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      qualityLabel: data.qualityLabel.present
          ? data.qualityLabel.value
          : this.qualityLabel,
      formatSelector: data.formatSelector.present
          ? data.formatSelector.value
          : this.formatSelector,
      audioFormat: data.audioFormat.present
          ? data.audioFormat.value
          : this.audioFormat,
      extractorArgs: data.extractorArgs.present
          ? data.extractorArgs.value
          : this.extractorArgs,
      uploader: data.uploader.present ? data.uploader.value : this.uploader,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      streamSizes: data.streamSizes.present
          ? data.streamSizes.value
          : this.streamSizes,
      errorDetail: data.errorDetail.present
          ? data.errorDetail.value
          : this.errorDetail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadEntry(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('host: $host, ')
          ..write('displayName: $displayName, ')
          ..write('fileName: $fileName, ')
          ..write('state: $state, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('supportsRange: $supportsRange, ')
          ..write('mimeType: $mimeType, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('finalPath: $finalPath, ')
          ..write('mediaId: $mediaId, ')
          ..write('kind: $kind, ')
          ..write('engine: $engine, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('qualityLabel: $qualityLabel, ')
          ..write('formatSelector: $formatSelector, ')
          ..write('audioFormat: $audioFormat, ')
          ..write('extractorArgs: $extractorArgs, ')
          ..write('uploader: $uploader, ')
          ..write('durationSec: $durationSec, ')
          ..write('streamSizes: $streamSizes, ')
          ..write('errorDetail: $errorDetail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    url,
    host,
    displayName,
    fileName,
    state,
    receivedBytes,
    totalBytes,
    etag,
    lastModified,
    supportsRange,
    mimeType,
    errorCode,
    createdAt,
    updatedAt,
    finalPath,
    mediaId,
    kind,
    engine,
    thumbnailUrl,
    thumbnailPath,
    qualityLabel,
    formatSelector,
    audioFormat,
    extractorArgs,
    uploader,
    durationSec,
    streamSizes,
    errorDetail,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadEntry &&
          other.id == this.id &&
          other.url == this.url &&
          other.host == this.host &&
          other.displayName == this.displayName &&
          other.fileName == this.fileName &&
          other.state == this.state &&
          other.receivedBytes == this.receivedBytes &&
          other.totalBytes == this.totalBytes &&
          other.etag == this.etag &&
          other.lastModified == this.lastModified &&
          other.supportsRange == this.supportsRange &&
          other.mimeType == this.mimeType &&
          other.errorCode == this.errorCode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.finalPath == this.finalPath &&
          other.mediaId == this.mediaId &&
          other.kind == this.kind &&
          other.engine == this.engine &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.thumbnailPath == this.thumbnailPath &&
          other.qualityLabel == this.qualityLabel &&
          other.formatSelector == this.formatSelector &&
          other.audioFormat == this.audioFormat &&
          other.extractorArgs == this.extractorArgs &&
          other.uploader == this.uploader &&
          other.durationSec == this.durationSec &&
          other.streamSizes == this.streamSizes &&
          other.errorDetail == this.errorDetail);
}

class DownloadsTableCompanion extends UpdateCompanion<DownloadEntry> {
  final Value<String> id;
  final Value<String> url;
  final Value<String> host;
  final Value<String> displayName;
  final Value<String> fileName;
  final Value<String> state;
  final Value<int> receivedBytes;
  final Value<int?> totalBytes;
  final Value<String?> etag;
  final Value<String?> lastModified;
  final Value<bool> supportsRange;
  final Value<String?> mimeType;
  final Value<String?> errorCode;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> finalPath;
  final Value<String?> mediaId;
  final Value<String?> kind;
  final Value<String> engine;
  final Value<String?> thumbnailUrl;
  final Value<String?> thumbnailPath;
  final Value<String?> qualityLabel;
  final Value<String?> formatSelector;
  final Value<String?> audioFormat;
  final Value<String?> extractorArgs;
  final Value<String?> uploader;
  final Value<int?> durationSec;
  final Value<String?> streamSizes;
  final Value<String?> errorDetail;
  final Value<int> rowid;
  const DownloadsTableCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.host = const Value.absent(),
    this.displayName = const Value.absent(),
    this.fileName = const Value.absent(),
    this.state = const Value.absent(),
    this.receivedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.supportsRange = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.finalPath = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.kind = const Value.absent(),
    this.engine = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.qualityLabel = const Value.absent(),
    this.formatSelector = const Value.absent(),
    this.audioFormat = const Value.absent(),
    this.extractorArgs = const Value.absent(),
    this.uploader = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.streamSizes = const Value.absent(),
    this.errorDetail = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsTableCompanion.insert({
    required String id,
    required String url,
    required String host,
    required String displayName,
    required String fileName,
    required String state,
    this.receivedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.etag = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.supportsRange = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.errorCode = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.finalPath = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.kind = const Value.absent(),
    this.engine = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.qualityLabel = const Value.absent(),
    this.formatSelector = const Value.absent(),
    this.audioFormat = const Value.absent(),
    this.extractorArgs = const Value.absent(),
    this.uploader = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.streamSizes = const Value.absent(),
    this.errorDetail = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       url = Value(url),
       host = Value(host),
       displayName = Value(displayName),
       fileName = Value(fileName),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DownloadEntry> custom({
    Expression<String>? id,
    Expression<String>? url,
    Expression<String>? host,
    Expression<String>? displayName,
    Expression<String>? fileName,
    Expression<String>? state,
    Expression<int>? receivedBytes,
    Expression<int>? totalBytes,
    Expression<String>? etag,
    Expression<String>? lastModified,
    Expression<bool>? supportsRange,
    Expression<String>? mimeType,
    Expression<String>? errorCode,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? finalPath,
    Expression<String>? mediaId,
    Expression<String>? kind,
    Expression<String>? engine,
    Expression<String>? thumbnailUrl,
    Expression<String>? thumbnailPath,
    Expression<String>? qualityLabel,
    Expression<String>? formatSelector,
    Expression<String>? audioFormat,
    Expression<String>? extractorArgs,
    Expression<String>? uploader,
    Expression<int>? durationSec,
    Expression<String>? streamSizes,
    Expression<String>? errorDetail,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (host != null) 'host': host,
      if (displayName != null) 'display_name': displayName,
      if (fileName != null) 'file_name': fileName,
      if (state != null) 'state': state,
      if (receivedBytes != null) 'received_bytes': receivedBytes,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'last_modified': lastModified,
      if (supportsRange != null) 'supports_range': supportsRange,
      if (mimeType != null) 'mime_type': mimeType,
      if (errorCode != null) 'error_code': errorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (finalPath != null) 'final_path': finalPath,
      if (mediaId != null) 'media_id': mediaId,
      if (kind != null) 'kind': kind,
      if (engine != null) 'engine': engine,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (qualityLabel != null) 'quality_label': qualityLabel,
      if (formatSelector != null) 'format_selector': formatSelector,
      if (audioFormat != null) 'audio_format': audioFormat,
      if (extractorArgs != null) 'extractor_args': extractorArgs,
      if (uploader != null) 'uploader': uploader,
      if (durationSec != null) 'duration_sec': durationSec,
      if (streamSizes != null) 'stream_sizes': streamSizes,
      if (errorDetail != null) 'error_detail': errorDetail,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? url,
    Value<String>? host,
    Value<String>? displayName,
    Value<String>? fileName,
    Value<String>? state,
    Value<int>? receivedBytes,
    Value<int?>? totalBytes,
    Value<String?>? etag,
    Value<String?>? lastModified,
    Value<bool>? supportsRange,
    Value<String?>? mimeType,
    Value<String?>? errorCode,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? finalPath,
    Value<String?>? mediaId,
    Value<String?>? kind,
    Value<String>? engine,
    Value<String?>? thumbnailUrl,
    Value<String?>? thumbnailPath,
    Value<String?>? qualityLabel,
    Value<String?>? formatSelector,
    Value<String?>? audioFormat,
    Value<String?>? extractorArgs,
    Value<String?>? uploader,
    Value<int?>? durationSec,
    Value<String?>? streamSizes,
    Value<String?>? errorDetail,
    Value<int>? rowid,
  }) {
    return DownloadsTableCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      host: host ?? this.host,
      displayName: displayName ?? this.displayName,
      fileName: fileName ?? this.fileName,
      state: state ?? this.state,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      supportsRange: supportsRange ?? this.supportsRange,
      mimeType: mimeType ?? this.mimeType,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      finalPath: finalPath ?? this.finalPath,
      mediaId: mediaId ?? this.mediaId,
      kind: kind ?? this.kind,
      engine: engine ?? this.engine,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      formatSelector: formatSelector ?? this.formatSelector,
      audioFormat: audioFormat ?? this.audioFormat,
      extractorArgs: extractorArgs ?? this.extractorArgs,
      uploader: uploader ?? this.uploader,
      durationSec: durationSec ?? this.durationSec,
      streamSizes: streamSizes ?? this.streamSizes,
      errorDetail: errorDetail ?? this.errorDetail,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (receivedBytes.present) {
      map['received_bytes'] = Variable<int>(receivedBytes.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<String>(lastModified.value);
    }
    if (supportsRange.present) {
      map['supports_range'] = Variable<bool>(supportsRange.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (finalPath.present) {
      map['final_path'] = Variable<String>(finalPath.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (engine.present) {
      map['engine'] = Variable<String>(engine.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (qualityLabel.present) {
      map['quality_label'] = Variable<String>(qualityLabel.value);
    }
    if (formatSelector.present) {
      map['format_selector'] = Variable<String>(formatSelector.value);
    }
    if (audioFormat.present) {
      map['audio_format'] = Variable<String>(audioFormat.value);
    }
    if (extractorArgs.present) {
      map['extractor_args'] = Variable<String>(extractorArgs.value);
    }
    if (uploader.present) {
      map['uploader'] = Variable<String>(uploader.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (streamSizes.present) {
      map['stream_sizes'] = Variable<String>(streamSizes.value);
    }
    if (errorDetail.present) {
      map['error_detail'] = Variable<String>(errorDetail.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsTableCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('host: $host, ')
          ..write('displayName: $displayName, ')
          ..write('fileName: $fileName, ')
          ..write('state: $state, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('etag: $etag, ')
          ..write('lastModified: $lastModified, ')
          ..write('supportsRange: $supportsRange, ')
          ..write('mimeType: $mimeType, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('finalPath: $finalPath, ')
          ..write('mediaId: $mediaId, ')
          ..write('kind: $kind, ')
          ..write('engine: $engine, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('qualityLabel: $qualityLabel, ')
          ..write('formatSelector: $formatSelector, ')
          ..write('audioFormat: $audioFormat, ')
          ..write('extractorArgs: $extractorArgs, ')
          ..write('uploader: $uploader, ')
          ..write('durationSec: $durationSec, ')
          ..write('streamSizes: $streamSizes, ')
          ..write('errorDetail: $errorDetail, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MediaItemsTableTable mediaItemsTable = $MediaItemsTableTable(
    this,
  );
  late final $PlaybackStatesTableTable playbackStatesTable =
      $PlaybackStatesTableTable(this);
  late final $VideoProgressTableTable videoProgressTable =
      $VideoProgressTableTable(this);
  late final $PlaylistsTableTable playlistsTable = $PlaylistsTableTable(this);
  late final $PlaylistItemsTableTable playlistItemsTable =
      $PlaylistItemsTableTable(this);
  late final $DownloadsTableTable downloadsTable = $DownloadsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    mediaItemsTable,
    playbackStatesTable,
    videoProgressTable,
    playlistsTable,
    playlistItemsTable,
    downloadsTable,
  ];
}

typedef $$MediaItemsTableTableCreateCompanionBuilder =
    MediaItemsTableCompanion Function({
      required String id,
      required String uri,
      required String mediaType,
      required String title,
      Value<String?> artist,
      Value<String?> album,
      required int durationMs,
      required int sizeBytes,
      Value<String?> format,
      Value<int?> width,
      Value<int?> height,
      required DateTime dateAdded,
      Value<DateTime?> lastPlayed,
      Value<int> playCount,
      Value<bool> isFavorite,
      Value<String> availability,
      Value<String?> source,
      Value<String?> artworkPath,
      Value<String?> albumId,
      Value<String?> albumArtist,
      Value<int?> trackNumber,
      Value<int?> discNumber,
      Value<int?> year,
      Value<String?> searchKey,
      Value<DateTime?> favoritedAt,
      Value<String?> relativePath,
      Value<String?> genre,
      Value<int> rowid,
    });
typedef $$MediaItemsTableTableUpdateCompanionBuilder =
    MediaItemsTableCompanion Function({
      Value<String> id,
      Value<String> uri,
      Value<String> mediaType,
      Value<String> title,
      Value<String?> artist,
      Value<String?> album,
      Value<int> durationMs,
      Value<int> sizeBytes,
      Value<String?> format,
      Value<int?> width,
      Value<int?> height,
      Value<DateTime> dateAdded,
      Value<DateTime?> lastPlayed,
      Value<int> playCount,
      Value<bool> isFavorite,
      Value<String> availability,
      Value<String?> source,
      Value<String?> artworkPath,
      Value<String?> albumId,
      Value<String?> albumArtist,
      Value<int?> trackNumber,
      Value<int?> discNumber,
      Value<int?> year,
      Value<String?> searchKey,
      Value<DateTime?> favoritedAt,
      Value<String?> relativePath,
      Value<String?> genre,
      Value<int> rowid,
    });

class $$MediaItemsTableTableFilterComposer
    extends Composer<_$AppDatabase, $MediaItemsTableTable> {
  $$MediaItemsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkPath => $composableBuilder(
    column: $table.artworkPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchKey => $composableBuilder(
    column: $table.searchKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get favoritedAt => $composableBuilder(
    column: $table.favoritedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaItemsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaItemsTableTable> {
  $$MediaItemsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkPath => $composableBuilder(
    column: $table.artworkPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchKey => $composableBuilder(
    column: $table.searchKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get favoritedAt => $composableBuilder(
    column: $table.favoritedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaItemsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaItemsTableTable> {
  $$MediaItemsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayed => $composableBuilder(
    column: $table.lastPlayed,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get artworkPath => $composableBuilder(
    column: $table.artworkPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get albumArtist => $composableBuilder(
    column: $table.albumArtist,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get searchKey =>
      $composableBuilder(column: $table.searchKey, builder: (column) => column);

  GeneratedColumn<DateTime> get favoritedAt => $composableBuilder(
    column: $table.favoritedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);
}

class $$MediaItemsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaItemsTableTable,
          MediaItemEntry,
          $$MediaItemsTableTableFilterComposer,
          $$MediaItemsTableTableOrderingComposer,
          $$MediaItemsTableTableAnnotationComposer,
          $$MediaItemsTableTableCreateCompanionBuilder,
          $$MediaItemsTableTableUpdateCompanionBuilder,
          (
            MediaItemEntry,
            BaseReferences<
              _$AppDatabase,
              $MediaItemsTableTable,
              MediaItemEntry
            >,
          ),
          MediaItemEntry,
          PrefetchHooks Function()
        > {
  $$MediaItemsTableTableTableManager(
    _$AppDatabase db,
    $MediaItemsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaItemsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaItemsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaItemsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> uri = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
                Value<DateTime?> lastPlayed = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> artworkPath = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<String?> albumArtist = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> searchKey = const Value.absent(),
                Value<DateTime?> favoritedAt = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaItemsTableCompanion(
                id: id,
                uri: uri,
                mediaType: mediaType,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                format: format,
                width: width,
                height: height,
                dateAdded: dateAdded,
                lastPlayed: lastPlayed,
                playCount: playCount,
                isFavorite: isFavorite,
                availability: availability,
                source: source,
                artworkPath: artworkPath,
                albumId: albumId,
                albumArtist: albumArtist,
                trackNumber: trackNumber,
                discNumber: discNumber,
                year: year,
                searchKey: searchKey,
                favoritedAt: favoritedAt,
                relativePath: relativePath,
                genre: genre,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String uri,
                required String mediaType,
                required String title,
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                required int durationMs,
                required int sizeBytes,
                Value<String?> format = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                required DateTime dateAdded,
                Value<DateTime?> lastPlayed = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> artworkPath = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<String?> albumArtist = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> searchKey = const Value.absent(),
                Value<DateTime?> favoritedAt = const Value.absent(),
                Value<String?> relativePath = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaItemsTableCompanion.insert(
                id: id,
                uri: uri,
                mediaType: mediaType,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                format: format,
                width: width,
                height: height,
                dateAdded: dateAdded,
                lastPlayed: lastPlayed,
                playCount: playCount,
                isFavorite: isFavorite,
                availability: availability,
                source: source,
                artworkPath: artworkPath,
                albumId: albumId,
                albumArtist: albumArtist,
                trackNumber: trackNumber,
                discNumber: discNumber,
                year: year,
                searchKey: searchKey,
                favoritedAt: favoritedAt,
                relativePath: relativePath,
                genre: genre,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaItemsTableTable, MediaItemEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MediaItemsTableTable,
                    MediaItemEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaItemsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaItemsTableTable,
      MediaItemEntry,
      $$MediaItemsTableTableFilterComposer,
      $$MediaItemsTableTableOrderingComposer,
      $$MediaItemsTableTableAnnotationComposer,
      $$MediaItemsTableTableCreateCompanionBuilder,
      $$MediaItemsTableTableUpdateCompanionBuilder,
      (
        MediaItemEntry,
        BaseReferences<_$AppDatabase, $MediaItemsTableTable, MediaItemEntry>,
      ),
      MediaItemEntry,
      PrefetchHooks Function()
    >;
typedef $$PlaybackStatesTableTableCreateCompanionBuilder =
    PlaybackStatesTableCompanion Function({
      Value<int> id,
      Value<String?> currentItemId,
      required String queueJson,
      Value<int> queueIndex,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<String> repeatMode,
      Value<bool> shuffle,
      Value<double> speed,
      required DateTime updatedAt,
    });
typedef $$PlaybackStatesTableTableUpdateCompanionBuilder =
    PlaybackStatesTableCompanion Function({
      Value<int> id,
      Value<String?> currentItemId,
      Value<String> queueJson,
      Value<int> queueIndex,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<String> repeatMode,
      Value<bool> shuffle,
      Value<double> speed,
      Value<DateTime> updatedAt,
    });

class $$PlaybackStatesTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackStatesTableTable> {
  $$PlaybackStatesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentItemId => $composableBuilder(
    column: $table.currentItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queueJson => $composableBuilder(
    column: $table.queueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queueIndex => $composableBuilder(
    column: $table.queueIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repeatMode => $composableBuilder(
    column: $table.repeatMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shuffle => $composableBuilder(
    column: $table.shuffle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackStatesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackStatesTableTable> {
  $$PlaybackStatesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentItemId => $composableBuilder(
    column: $table.currentItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queueJson => $composableBuilder(
    column: $table.queueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queueIndex => $composableBuilder(
    column: $table.queueIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeatMode => $composableBuilder(
    column: $table.repeatMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shuffle => $composableBuilder(
    column: $table.shuffle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackStatesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackStatesTableTable> {
  $$PlaybackStatesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get currentItemId => $composableBuilder(
    column: $table.currentItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get queueJson =>
      $composableBuilder(column: $table.queueJson, builder: (column) => column);

  GeneratedColumn<int> get queueIndex => $composableBuilder(
    column: $table.queueIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repeatMode => $composableBuilder(
    column: $table.repeatMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get shuffle =>
      $composableBuilder(column: $table.shuffle, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlaybackStatesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackStatesTableTable,
          PlaybackStateEntry,
          $$PlaybackStatesTableTableFilterComposer,
          $$PlaybackStatesTableTableOrderingComposer,
          $$PlaybackStatesTableTableAnnotationComposer,
          $$PlaybackStatesTableTableCreateCompanionBuilder,
          $$PlaybackStatesTableTableUpdateCompanionBuilder,
          (
            PlaybackStateEntry,
            BaseReferences<
              _$AppDatabase,
              $PlaybackStatesTableTable,
              PlaybackStateEntry
            >,
          ),
          PlaybackStateEntry,
          PrefetchHooks Function()
        > {
  $$PlaybackStatesTableTableTableManager(
    _$AppDatabase db,
    $PlaybackStatesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackStatesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackStatesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaybackStatesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> currentItemId = const Value.absent(),
                Value<String> queueJson = const Value.absent(),
                Value<int> queueIndex = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> repeatMode = const Value.absent(),
                Value<bool> shuffle = const Value.absent(),
                Value<double> speed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlaybackStatesTableCompanion(
                id: id,
                currentItemId: currentItemId,
                queueJson: queueJson,
                queueIndex: queueIndex,
                positionMs: positionMs,
                durationMs: durationMs,
                repeatMode: repeatMode,
                shuffle: shuffle,
                speed: speed,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> currentItemId = const Value.absent(),
                required String queueJson,
                Value<int> queueIndex = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> repeatMode = const Value.absent(),
                Value<bool> shuffle = const Value.absent(),
                Value<double> speed = const Value.absent(),
                required DateTime updatedAt,
              }) => PlaybackStatesTableCompanion.insert(
                id: id,
                currentItemId: currentItemId,
                queueJson: queueJson,
                queueIndex: queueIndex,
                positionMs: positionMs,
                durationMs: durationMs,
                repeatMode: repeatMode,
                shuffle: shuffle,
                speed: speed,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaybackStatesTableTable, PlaybackStateEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaybackStatesTableTable,
                    PlaybackStateEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackStatesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackStatesTableTable,
      PlaybackStateEntry,
      $$PlaybackStatesTableTableFilterComposer,
      $$PlaybackStatesTableTableOrderingComposer,
      $$PlaybackStatesTableTableAnnotationComposer,
      $$PlaybackStatesTableTableCreateCompanionBuilder,
      $$PlaybackStatesTableTableUpdateCompanionBuilder,
      (
        PlaybackStateEntry,
        BaseReferences<
          _$AppDatabase,
          $PlaybackStatesTableTable,
          PlaybackStateEntry
        >,
      ),
      PlaybackStateEntry,
      PrefetchHooks Function()
    >;
typedef $$VideoProgressTableTableCreateCompanionBuilder =
    VideoProgressTableCompanion Function({
      required String mediaId,
      required int positionMs,
      required int durationMs,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$VideoProgressTableTableUpdateCompanionBuilder =
    VideoProgressTableCompanion Function({
      Value<String> mediaId,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$VideoProgressTableTableFilterComposer
    extends Composer<_$AppDatabase, $VideoProgressTableTable> {
  $$VideoProgressTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VideoProgressTableTableOrderingComposer
    extends Composer<_$AppDatabase, $VideoProgressTableTable> {
  $$VideoProgressTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VideoProgressTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $VideoProgressTableTable> {
  $$VideoProgressTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VideoProgressTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VideoProgressTableTable,
          VideoProgressEntry,
          $$VideoProgressTableTableFilterComposer,
          $$VideoProgressTableTableOrderingComposer,
          $$VideoProgressTableTableAnnotationComposer,
          $$VideoProgressTableTableCreateCompanionBuilder,
          $$VideoProgressTableTableUpdateCompanionBuilder,
          (
            VideoProgressEntry,
            BaseReferences<
              _$AppDatabase,
              $VideoProgressTableTable,
              VideoProgressEntry
            >,
          ),
          VideoProgressEntry,
          PrefetchHooks Function()
        > {
  $$VideoProgressTableTableTableManager(
    _$AppDatabase db,
    $VideoProgressTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VideoProgressTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VideoProgressTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VideoProgressTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VideoProgressTableCompanion(
                mediaId: mediaId,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required int positionMs,
                required int durationMs,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => VideoProgressTableCompanion.insert(
                mediaId: mediaId,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VideoProgressTableTable, VideoProgressEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $VideoProgressTableTable,
                    VideoProgressEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VideoProgressTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VideoProgressTableTable,
      VideoProgressEntry,
      $$VideoProgressTableTableFilterComposer,
      $$VideoProgressTableTableOrderingComposer,
      $$VideoProgressTableTableAnnotationComposer,
      $$VideoProgressTableTableCreateCompanionBuilder,
      $$VideoProgressTableTableUpdateCompanionBuilder,
      (
        VideoProgressEntry,
        BaseReferences<
          _$AppDatabase,
          $VideoProgressTableTable,
          VideoProgressEntry
        >,
      ),
      VideoProgressEntry,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableTableCreateCompanionBuilder =
    PlaylistsTableCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlaylistsTableTableUpdateCompanionBuilder =
    PlaylistsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PlaylistsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlaylistsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTableTable,
          PlaylistEntry,
          $$PlaylistsTableTableFilterComposer,
          $$PlaylistsTableTableOrderingComposer,
          $$PlaylistsTableTableAnnotationComposer,
          $$PlaylistsTableTableCreateCompanionBuilder,
          $$PlaylistsTableTableUpdateCompanionBuilder,
          (
            PlaylistEntry,
            BaseReferences<_$AppDatabase, $PlaylistsTableTable, PlaylistEntry>,
          ),
          PlaylistEntry,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableTableManager(
    _$AppDatabase db,
    $PlaylistsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsTableCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsTableCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistsTableTable, PlaylistEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaylistsTableTable,
                    PlaylistEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTableTable,
      PlaylistEntry,
      $$PlaylistsTableTableFilterComposer,
      $$PlaylistsTableTableOrderingComposer,
      $$PlaylistsTableTableAnnotationComposer,
      $$PlaylistsTableTableCreateCompanionBuilder,
      $$PlaylistsTableTableUpdateCompanionBuilder,
      (
        PlaylistEntry,
        BaseReferences<_$AppDatabase, $PlaylistsTableTable, PlaylistEntry>,
      ),
      PlaylistEntry,
      PrefetchHooks Function()
    >;
typedef $$PlaylistItemsTableTableCreateCompanionBuilder =
    PlaylistItemsTableCompanion Function({
      required String playlistId,
      required String mediaId,
      required int position,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$PlaylistItemsTableTableUpdateCompanionBuilder =
    PlaylistItemsTableCompanion Function({
      Value<String> playlistId,
      Value<String> mediaId,
      Value<int> position,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$PlaylistItemsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistItemsTableTable> {
  $$PlaylistItemsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistItemsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistItemsTableTable> {
  $$PlaylistItemsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistItemsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistItemsTableTable> {
  $$PlaylistItemsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$PlaylistItemsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistItemsTableTable,
          PlaylistItemEntry,
          $$PlaylistItemsTableTableFilterComposer,
          $$PlaylistItemsTableTableOrderingComposer,
          $$PlaylistItemsTableTableAnnotationComposer,
          $$PlaylistItemsTableTableCreateCompanionBuilder,
          $$PlaylistItemsTableTableUpdateCompanionBuilder,
          (
            PlaylistItemEntry,
            BaseReferences<
              _$AppDatabase,
              $PlaylistItemsTableTable,
              PlaylistItemEntry
            >,
          ),
          PlaylistItemEntry,
          PrefetchHooks Function()
        > {
  $$PlaylistItemsTableTableTableManager(
    _$AppDatabase db,
    $PlaylistItemsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistItemsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistItemsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistItemsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<String> mediaId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistItemsTableCompanion(
                playlistId: playlistId,
                mediaId: mediaId,
                position: position,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required String mediaId,
                required int position,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistItemsTableCompanion.insert(
                playlistId: playlistId,
                mediaId: mediaId,
                position: position,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistItemsTableTable, PlaylistItemEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaylistItemsTableTable,
                    PlaylistItemEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistItemsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistItemsTableTable,
      PlaylistItemEntry,
      $$PlaylistItemsTableTableFilterComposer,
      $$PlaylistItemsTableTableOrderingComposer,
      $$PlaylistItemsTableTableAnnotationComposer,
      $$PlaylistItemsTableTableCreateCompanionBuilder,
      $$PlaylistItemsTableTableUpdateCompanionBuilder,
      (
        PlaylistItemEntry,
        BaseReferences<
          _$AppDatabase,
          $PlaylistItemsTableTable,
          PlaylistItemEntry
        >,
      ),
      PlaylistItemEntry,
      PrefetchHooks Function()
    >;
typedef $$DownloadsTableTableCreateCompanionBuilder =
    DownloadsTableCompanion Function({
      required String id,
      required String url,
      required String host,
      required String displayName,
      required String fileName,
      required String state,
      Value<int> receivedBytes,
      Value<int?> totalBytes,
      Value<String?> etag,
      Value<String?> lastModified,
      Value<bool> supportsRange,
      Value<String?> mimeType,
      Value<String?> errorCode,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> finalPath,
      Value<String?> mediaId,
      Value<String?> kind,
      Value<String> engine,
      Value<String?> thumbnailUrl,
      Value<String?> thumbnailPath,
      Value<String?> qualityLabel,
      Value<String?> formatSelector,
      Value<String?> audioFormat,
      Value<String?> extractorArgs,
      Value<String?> uploader,
      Value<int?> durationSec,
      Value<String?> streamSizes,
      Value<String?> errorDetail,
      Value<int> rowid,
    });
typedef $$DownloadsTableTableUpdateCompanionBuilder =
    DownloadsTableCompanion Function({
      Value<String> id,
      Value<String> url,
      Value<String> host,
      Value<String> displayName,
      Value<String> fileName,
      Value<String> state,
      Value<int> receivedBytes,
      Value<int?> totalBytes,
      Value<String?> etag,
      Value<String?> lastModified,
      Value<bool> supportsRange,
      Value<String?> mimeType,
      Value<String?> errorCode,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> finalPath,
      Value<String?> mediaId,
      Value<String?> kind,
      Value<String> engine,
      Value<String?> thumbnailUrl,
      Value<String?> thumbnailPath,
      Value<String?> qualityLabel,
      Value<String?> formatSelector,
      Value<String?> audioFormat,
      Value<String?> extractorArgs,
      Value<String?> uploader,
      Value<int?> durationSec,
      Value<String?> streamSizes,
      Value<String?> errorDetail,
      Value<int> rowid,
    });

class $$DownloadsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadsTableTable> {
  $$DownloadsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsRange => $composableBuilder(
    column: $table.supportsRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalPath => $composableBuilder(
    column: $table.finalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qualityLabel => $composableBuilder(
    column: $table.qualityLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formatSelector => $composableBuilder(
    column: $table.formatSelector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioFormat => $composableBuilder(
    column: $table.audioFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extractorArgs => $composableBuilder(
    column: $table.extractorArgs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploader => $composableBuilder(
    column: $table.uploader,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamSizes => $composableBuilder(
    column: $table.streamSizes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorDetail => $composableBuilder(
    column: $table.errorDetail,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadsTableTable> {
  $$DownloadsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsRange => $composableBuilder(
    column: $table.supportsRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalPath => $composableBuilder(
    column: $table.finalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qualityLabel => $composableBuilder(
    column: $table.qualityLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formatSelector => $composableBuilder(
    column: $table.formatSelector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioFormat => $composableBuilder(
    column: $table.audioFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractorArgs => $composableBuilder(
    column: $table.extractorArgs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploader => $composableBuilder(
    column: $table.uploader,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamSizes => $composableBuilder(
    column: $table.streamSizes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorDetail => $composableBuilder(
    column: $table.errorDetail,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadsTableTable> {
  $$DownloadsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get supportsRange => $composableBuilder(
    column: $table.supportsRange,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get finalPath =>
      $composableBuilder(column: $table.finalPath, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get engine =>
      $composableBuilder(column: $table.engine, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get qualityLabel => $composableBuilder(
    column: $table.qualityLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get formatSelector => $composableBuilder(
    column: $table.formatSelector,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioFormat => $composableBuilder(
    column: $table.audioFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extractorArgs => $composableBuilder(
    column: $table.extractorArgs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get uploader =>
      $composableBuilder(column: $table.uploader, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<String> get streamSizes => $composableBuilder(
    column: $table.streamSizes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorDetail => $composableBuilder(
    column: $table.errorDetail,
    builder: (column) => column,
  );
}

class $$DownloadsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadsTableTable,
          DownloadEntry,
          $$DownloadsTableTableFilterComposer,
          $$DownloadsTableTableOrderingComposer,
          $$DownloadsTableTableAnnotationComposer,
          $$DownloadsTableTableCreateCompanionBuilder,
          $$DownloadsTableTableUpdateCompanionBuilder,
          (
            DownloadEntry,
            BaseReferences<_$AppDatabase, $DownloadsTableTable, DownloadEntry>,
          ),
          DownloadEntry,
          PrefetchHooks Function()
        > {
  $$DownloadsTableTableTableManager(
    _$AppDatabase db,
    $DownloadsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> receivedBytes = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<bool> supportsRange = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> finalPath = const Value.absent(),
                Value<String?> mediaId = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String> engine = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> qualityLabel = const Value.absent(),
                Value<String?> formatSelector = const Value.absent(),
                Value<String?> audioFormat = const Value.absent(),
                Value<String?> extractorArgs = const Value.absent(),
                Value<String?> uploader = const Value.absent(),
                Value<int?> durationSec = const Value.absent(),
                Value<String?> streamSizes = const Value.absent(),
                Value<String?> errorDetail = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsTableCompanion(
                id: id,
                url: url,
                host: host,
                displayName: displayName,
                fileName: fileName,
                state: state,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                etag: etag,
                lastModified: lastModified,
                supportsRange: supportsRange,
                mimeType: mimeType,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                finalPath: finalPath,
                mediaId: mediaId,
                kind: kind,
                engine: engine,
                thumbnailUrl: thumbnailUrl,
                thumbnailPath: thumbnailPath,
                qualityLabel: qualityLabel,
                formatSelector: formatSelector,
                audioFormat: audioFormat,
                extractorArgs: extractorArgs,
                uploader: uploader,
                durationSec: durationSec,
                streamSizes: streamSizes,
                errorDetail: errorDetail,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String url,
                required String host,
                required String displayName,
                required String fileName,
                required String state,
                Value<int> receivedBytes = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> lastModified = const Value.absent(),
                Value<bool> supportsRange = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> finalPath = const Value.absent(),
                Value<String?> mediaId = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String> engine = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> qualityLabel = const Value.absent(),
                Value<String?> formatSelector = const Value.absent(),
                Value<String?> audioFormat = const Value.absent(),
                Value<String?> extractorArgs = const Value.absent(),
                Value<String?> uploader = const Value.absent(),
                Value<int?> durationSec = const Value.absent(),
                Value<String?> streamSizes = const Value.absent(),
                Value<String?> errorDetail = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsTableCompanion.insert(
                id: id,
                url: url,
                host: host,
                displayName: displayName,
                fileName: fileName,
                state: state,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                etag: etag,
                lastModified: lastModified,
                supportsRange: supportsRange,
                mimeType: mimeType,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                finalPath: finalPath,
                mediaId: mediaId,
                kind: kind,
                engine: engine,
                thumbnailUrl: thumbnailUrl,
                thumbnailPath: thumbnailPath,
                qualityLabel: qualityLabel,
                formatSelector: formatSelector,
                audioFormat: audioFormat,
                extractorArgs: extractorArgs,
                uploader: uploader,
                durationSec: durationSec,
                streamSizes: streamSizes,
                errorDetail: errorDetail,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadsTableTable, DownloadEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DownloadsTableTable,
                    DownloadEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadsTableTable,
      DownloadEntry,
      $$DownloadsTableTableFilterComposer,
      $$DownloadsTableTableOrderingComposer,
      $$DownloadsTableTableAnnotationComposer,
      $$DownloadsTableTableCreateCompanionBuilder,
      $$DownloadsTableTableUpdateCompanionBuilder,
      (
        DownloadEntry,
        BaseReferences<_$AppDatabase, $DownloadsTableTable, DownloadEntry>,
      ),
      DownloadEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MediaItemsTableTableTableManager get mediaItemsTable =>
      $$MediaItemsTableTableTableManager(_db, _db.mediaItemsTable);
  $$PlaybackStatesTableTableTableManager get playbackStatesTable =>
      $$PlaybackStatesTableTableTableManager(_db, _db.playbackStatesTable);
  $$VideoProgressTableTableTableManager get videoProgressTable =>
      $$VideoProgressTableTableTableManager(_db, _db.videoProgressTable);
  $$PlaylistsTableTableTableManager get playlistsTable =>
      $$PlaylistsTableTableTableManager(_db, _db.playlistsTable);
  $$PlaylistItemsTableTableTableManager get playlistItemsTable =>
      $$PlaylistItemsTableTableTableManager(_db, _db.playlistItemsTable);
  $$DownloadsTableTableTableManager get downloadsTable =>
      $$DownloadsTableTableTableManager(_db, _db.downloadsTable);
}
