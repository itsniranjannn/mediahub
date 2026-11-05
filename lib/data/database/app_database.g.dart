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
          ..write('availability: $availability')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
  );
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
          other.availability == this.availability);
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
}
