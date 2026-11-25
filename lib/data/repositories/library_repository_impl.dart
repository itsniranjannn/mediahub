// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../domain/repositories/library_repository.dart';
import '../../features/music_player/playback_notifier.dart' show appDatabaseProvider;
import '../database/app_database.dart';
import '../database/search_text.dart';

/// The library's database: the app's one database ([appDatabaseProvider]),
/// so the library, playback, downloads and the media sheet always read and
/// write the same rows (a test that overrides the app database gets a library
/// on it too).
final databaseProvider = Provider<AppDatabase>((ref) => ref.watch(appDatabaseProvider));

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return LibraryRepositoryImpl(db);
});

class LibraryRepositoryImpl implements LibraryRepository {
  static const MethodChannel _mediaStoreChannel = MethodChannel('mediahub/media_store');

  /// How many covers a playlist's mosaic shows.
  static const int playlistCoverCount = 4;

  final AppDatabase _db;
  final MethodChannel _channel;
  final Random _random;

  int? _lastScanNewSongCount;

  LibraryRepositoryImpl(this._db, [MethodChannel? channel, Random? random])
      : _channel = channel ?? _mediaStoreChannel,
        _random = random ?? Random.secure();

  bool get _canQueryMediaStore => Platform.isAndroid || _channel != _mediaStoreChannel;

  @override
  int? get lastScanNewSongCount => _lastScanNewSongCount;

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  /// A tag value worth keeping: trimmed, and null for MediaStore's
  /// `<unknown>` placeholder or an empty string.
  static String? _tag(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty || value == '<unknown>') return null;
    return value;
  }

  /// An artist tag, null when it only says "unknown".
  static String? _artistTag(Object? raw) {
    final value = _tag(raw);
    return isUnknownArtistName(value) ? null : value;
  }

  static int? _positiveInt(Object? raw) {
    final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return (value == null || value <= 0) ? null : value;
  }

  /// MediaStore's TRACK packs the disc in the thousands: 2005 is disc 2,
  /// track 5; 5 is track 5 of a single disc.
  @visibleForTesting
  static (int? disc, int? track) splitTrackNumber(Object? raw) {
    final value = _positiveInt(raw);
    if (value == null) return (null, null);
    final track = value % 1000;
    final disc = value ~/ 1000;
    return (disc > 0 ? disc : null, track > 0 ? track : null);
  }

  @override
  Future<void> scanDeviceMedia() async {
    final audioToInsert = <MediaItemsTableCompanion>[];
    final videoToInsert = <MediaItemsTableCompanion>[];
    bool audioQuerySucceeded = false;
    bool videoQuerySucceeded = false;

    // 1. Scan Audio Songs via native MediaStore channel
    try {
      if (_canQueryMediaStore) {
        debugPrint('[Scan] Calling native mediahub/media_store queryAudio...');
        final List<dynamic>? audioResult = await _channel.invokeListMethod<dynamic>('queryAudio');

        if (audioResult != null) {
          audioQuerySucceeded = true;
          for (final raw in audioResult) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final id = map['id']?.toString() ?? '';
            final uri = map['uri']?.toString() ?? '';
            if (id.isEmpty || uri.isEmpty) continue;

            final rawTitle = map['title']?.toString().trim();
            final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : 'Unknown Title';
            // Unknown artists are stored as NULL: one "Unknown artist" in the UI.
            final artist = _artistTag(map['artist']);
            final album = _tag(map['album']);
            final albumArtist = _artistTag(map['albumArtist']);
            final (disc, track) = splitTrackNumber(map['track']);
            final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
            final sizeBytes = (map['sizeBytes'] as num?)?.toInt() ?? 0;
            final dateAddedSec = (map['dateAdded'] as num?)?.toInt();
            final mimeType = map['mimeType']?.toString();

            audioToInsert.add(
              MediaItemsTableCompanion.insert(
                id: 'audio_$id',
                uri: uri,
                mediaType: MediaType.audio.name,
                title: title,
                artist: Value(artist),
                album: Value(album),
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                format: Value(mimeType?.split('/').last),
                dateAdded: dateAddedSec != null
                    ? DateTime.fromMillisecondsSinceEpoch(dateAddedSec * 1000)
                    : DateTime.now(),
                availability: const Value('available'),
                albumId: Value(_tag(map['albumId'])),
                albumArtist: Value(albumArtist),
                trackNumber: Value(track),
                discNumber: Value(disc),
                year: Value(_positiveInt(map['year'])),
                searchKey: Value(librarySearchKey(title: title, artist: artist, album: album, albumArtist: albumArtist)),
                relativePath: Value(_tag(map['relativePath'])),
                genre: Value(_tag(map['genre'])),
              ),
            );
          }
        }
      }
    } catch (e, stack) {
      debugPrint('[Scan] Error during native queryAudio: $e\n$stack');
    }

    debugPrint('[Scan] number of audio items found: ${audioToInsert.length}');

    // 2. Scan Video items via native MediaStore channel (or file fallback)
    try {
      if (_canQueryMediaStore) {
        debugPrint('[Scan] Calling native mediahub/media_store queryVideo...');
        final List<dynamic>? videoResult = await _channel.invokeListMethod<dynamic>('queryVideo');

        if (videoResult != null) {
          videoQuerySucceeded = true;
          for (final raw in videoResult) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final id = map['id']?.toString() ?? '';
            final uri = map['uri']?.toString() ?? '';
            if (id.isEmpty || uri.isEmpty) continue;

            final rawTitle = map['title']?.toString().trim();
            final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : 'Unknown Video';
            final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
            final sizeBytes = (map['sizeBytes'] as num?)?.toInt() ?? 0;
            final dateAddedSec = (map['dateAdded'] as num?)?.toInt();
            final mimeType = map['mimeType']?.toString();
            final width = (map['width'] as num?)?.toInt();
            final height = (map['height'] as num?)?.toInt();

            videoToInsert.add(
              MediaItemsTableCompanion.insert(
                id: 'video_$id',
                uri: uri,
                mediaType: MediaType.video.name,
                title: title,
                artist: const Value('Local Video'),
                album: const Value(null),
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                format: Value(mimeType?.split('/').last),
                width: Value(width),
                height: Value(height),
                dateAdded: dateAddedSec != null
                    ? DateTime.fromMillisecondsSinceEpoch(dateAddedSec * 1000)
                    : DateTime.now(),
                availability: const Value('available'),
                searchKey: Value(librarySearchKey(title: title)),
                relativePath: Value(_tag(map['relativePath'])),
              ),
            );
          }
        }
      }
    } catch (e, stack) {
      debugPrint('[Scan] Error during native queryVideo: $e\n$stack');
    }

    debugPrint('[Scan] number of video items found: ${videoToInsert.length}');

    // 3. Atomically update DB in one transaction with availability tracking
    try {
      await _db.transaction(() async {
        // Ids known before this scan, to spot rows that are new in this scan (step D).
        final idsBefore = (await (_db.selectOnly(_db.mediaItemsTable)..addColumns([_db.mediaItemsTable.id]))
                .map((r) => r.read(_db.mediaItemsTable.id)!)
                .get())
            .toSet();

        // A. Insert new items; refresh the tags of known ones. A rescan keeps
        //    the first date a file was seen ("Recently added" does not
        //    reshuffle) and never touches likes, plays or the source.
        final allScanned = [...audioToInsert, ...videoToInsert];
        if (allScanned.isNotEmpty) {
          await _db.batch((batch) {
            batch.insertAll(
              _db.mediaItemsTable,
              allScanned,
              onConflict: DoUpdate<$MediaItemsTableTable, MediaItemEntry>.withExcluded(
                (old, excluded) => MediaItemsTableCompanion.custom(
                  uri: excluded.uri,
                  mediaType: excluded.mediaType,
                  title: excluded.title,
                  artist: excluded.artist,
                  album: excluded.album,
                  durationMs: excluded.durationMs,
                  sizeBytes: excluded.sizeBytes,
                  format: excluded.format,
                  width: excluded.width,
                  height: excluded.height,
                  availability: excluded.availability,
                  albumId: excluded.albumId,
                  albumArtist: excluded.albumArtist,
                  trackNumber: excluded.trackNumber,
                  discNumber: excluded.discNumber,
                  year: excluded.year,
                  searchKey: excluded.searchKey,
                  relativePath: excluded.relativePath,
                  genre: excluded.genre,
                ),
              ),
            );
          });
        }

        // B. Audio missing pass: only if audio query succeeded AND not an empty scan on non-empty DB (guard)
        if (audioQuerySucceeded) {
          await _missingPass(MediaType.audio, audioToInsert);
        }

        // C. Video missing pass: only if video query succeeded AND not an empty scan on non-empty DB (guard)
        if (videoQuerySucceeded) {
          await _missingPass(MediaType.video, videoToInsert);
        }

        // D. Same file, new MediaStore id (file deleted and added back, phone restored
        //    or moved to a new phone, SD card re-mounted): carry the user's data over.
        final newIds = allScanned.map((c) => c.id.value).where((id) => !idsBefore.contains(id)).toSet();
        var moved = const <String>{};
        if (newIds.isNotEmpty) {
          moved = await _carryOverUserData(newIds);
        }
        if (audioQuerySucceeded) {
          _lastScanNewSongCount =
              audioToInsert.map((c) => c.id.value).where((id) => newIds.contains(id) && !moved.contains(id)).length;
        }
      });
      debugPrint('[Scan] DB write completed successfully');
    } catch (dbErr, dbStack) {
      debugPrint('[Scan] Drift DB write error: $dbErr\n$dbStack');
      rethrow;
    }

    // Downloads and older rows get their search key too.
    try {
      await _backfillSearchKeys();
    } catch (e) {
      debugPrint('[Scan] search key backfill failed: $e');
    }
  }

  Future<void> _missingPass(MediaType type, List<MediaItemsTableCompanion> scanned) async {
    final existing = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.mediaType.equals(type.name))).get();

    // Guard: skip missing pass if scan returned 0 items but DB already has rows of that type
    final shouldRun = scanned.isNotEmpty || existing.isEmpty;
    if (!shouldRun) return;

    final scannedIds = scanned.map((e) => e.id.value).toSet();
    for (final row in existing) {
      // Downloads and Online items are never marked missing by a device MediaStore scan
      if (row.source == 'download' || row.source == 'online') continue;

      if (!scannedIds.contains(row.id)) {
        if (row.availability != 'missing') {
          await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
            const MediaItemsTableCompanion(availability: Value('missing')),
          );
        }
      } else if (row.availability != 'available') {
        await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
          const MediaItemsTableCompanion(availability: Value('available')),
        );
      }
    }
  }

  /// Moves favourites, play history, playlist entries and video progress from a
  /// "missing" row to the new row of the same file, then removes the old row.
  ///
  /// A pair is only matched when it is unambiguous: same media type, same title
  /// (ignoring case), same size in bytes, durations within 2 seconds, and exactly
  /// one missing row and one new row share that identity. Downloads are never touched.
  /// Must run inside the scan transaction. Returns the new ids that took over
  /// an old row.
  Future<Set<String>> _carryOverUserData(Set<String> newIds) async {
    final t = _db.mediaItemsTable;
    final missing = await (_db.select(t)
          ..where((r) => r.availability.equals('missing') & (r.source.isNull() | r.source.equals('device'))))
        .get();
    if (missing.isEmpty) return const {};
    final fresh = await (_db.select(t)..where((r) => r.id.isIn(newIds))).get();

    String identity(MediaItemEntry r) => '${r.mediaType}|${r.title.trim().toLowerCase()}|${r.sizeBytes}';
    final missingByKey = <String, List<MediaItemEntry>>{};
    for (final r in missing) {
      if (r.sizeBytes <= 0) continue; // size unknown: not safe to match
      missingByKey.putIfAbsent(identity(r), () => []).add(r);
    }
    final freshByKey = <String, List<MediaItemEntry>>{};
    for (final r in fresh) {
      if (r.sizeBytes <= 0) continue;
      freshByKey.putIfAbsent(identity(r), () => []).add(r);
    }

    final moved = <String>{};
    for (final entry in freshByKey.entries) {
      final olds = missingByKey[entry.key];
      if (olds == null || olds.length != 1 || entry.value.length != 1) continue;
      final old = olds.single;
      final neu = entry.value.single;
      if ((old.durationMs - neu.durationMs).abs() > 2000) continue;

      final lastPlayed = switch ((old.lastPlayed, neu.lastPlayed)) {
        (null, final b) => b,
        (final a, null) => a,
        (final a?, final b?) => a.isAfter(b) ? a : b,
      };
      await (_db.update(t)..where((r) => r.id.equals(neu.id))).write(MediaItemsTableCompanion(
        isFavorite: Value(old.isFavorite || neu.isFavorite),
        favoritedAt: Value(old.favoritedAt ?? neu.favoritedAt),
        playCount: Value(old.playCount + neu.playCount),
        lastPlayed: Value(lastPlayed),
        // Keep its place in "Recently added" instead of jumping to the top.
        dateAdded: Value(old.dateAdded.isBefore(neu.dateAdded) ? old.dateAdded : neu.dateAdded),
        artworkPath: Value(neu.artworkPath ?? old.artworkPath),
      ));
      await (_db.update(_db.playlistItemsTable)..where((r) => r.mediaId.equals(old.id)))
          .write(PlaylistItemsTableCompanion(mediaId: Value(neu.id)));
      final hasProgress =
          await (_db.select(_db.videoProgressTable)..where((r) => r.mediaId.equals(neu.id))).getSingleOrNull();
      if (hasProgress == null) {
        await (_db.update(_db.videoProgressTable)..where((r) => r.mediaId.equals(old.id)))
            .write(VideoProgressTableCompanion(mediaId: Value(neu.id)));
      } else {
        await (_db.delete(_db.videoProgressTable)..where((r) => r.mediaId.equals(old.id))).go();
      }
      await (_db.delete(t)..where((r) => r.id.equals(old.id))).go();
      moved.add(neu.id);
    }
    if (moved.isNotEmpty) {
      DiagnosticsService.instance.logEvent('library_identity_carried_over', {'count': moved.length});
    }
    return moved;
  }

  /// Gives every row without a current search key one: rows written by the
  /// download engines (which do not fill it), rows from before v8, and keys
  /// made by older folding rules (no [searchKeyVersionTag] at the end).
  Future<void> _backfillSearchKeys() async {
    final t = _db.mediaItemsTable;
    final rows = await (_db.select(t)
          ..where((r) => r.searchKey.isNull() | r.searchKey.like('%$searchKeyVersionTag').not()))
        .get();
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.update(
          t,
          MediaItemsTableCompanion(
            searchKey: Value(
              librarySearchKey(title: r.title, artist: r.artist, album: r.album, albumArtist: r.albumArtist),
            ),
          ),
          where: (tbl) => tbl.id.equals(r.id),
        );
      }
    });
  }

  /// [build] after rows missing a search key got one, when a search needs it.
  Stream<T> _afterSearchKeys<T>(List<String> terms, Stream<T> Function() build) {
    if (terms.isEmpty) return build();
    return Stream<void>.fromFuture(_backfillSearchKeys().catchError((Object _) {})).asyncExpand((_) => build());
  }

  @override
  Future<String?> mediaStoreGeneration() async {
    if (!_canQueryMediaStore) return null;
    try {
      return (await _channel.invokeMethod<Object?>('mediaGeneration'))?.toString();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Filters shared by the lists
  // ---------------------------------------------------------------------------

  /// Rows whose file is there (missing files stay in the database, so their
  /// likes and playlist entries come back with the file, but no list shows
  /// them).
  static Expression<bool> _available($MediaItemsTableTable tbl) => tbl.availability.equals('available');

  /// Not an Online (YouTube) row: those are not files and only show in Liked
  /// songs and playlists.
  static Expression<bool> _notOnline($MediaItemsTableTable tbl) =>
      tbl.source.isNull() | tbl.source.equals('online').not();

  /// Every one of [terms] in the title, artist or album. Rows without a
  /// search key yet (just inserted by a download) fall back to the raw
  /// fields, compared case-insensitively. A Latin word also finds a title
  /// written in Devanagari through the key's romanised fields
  /// ([romanTermPattern]: "resham" finds "रेशम").
  static Expression<bool> _matchesTerms($MediaItemsTableTable tbl, List<String> terms) {
    Expression<bool> all = const Constant(true);
    for (final term in terms) {
      final pattern = likeContainsPattern(term);
      var keyed = tbl.searchKey.like(pattern, escapeChar: r'\');
      final roman = romanTermPattern(term);
      if (roman != null) keyed = keyed | tbl.searchKey.like('%$roman%');
      final raw = tbl.title.lower().like(pattern, escapeChar: r'\') |
          tbl.artist.lower().like(pattern, escapeChar: r'\') |
          tbl.album.lower().like(pattern, escapeChar: r'\');
      all = all & (keyed | (tbl.searchKey.isNull() & raw));
    }
    return all;
  }

  SimpleSelectStatement<$MediaItemsTableTable, MediaItemEntry> _listQuery({
    required MediaType mediaType,
    required List<String> terms,
  }) {
    return _db.select(_db.mediaItemsTable)
      ..where((tbl) =>
          tbl.mediaType.equals(mediaType.name) & _available(tbl) & _notOnline(tbl) & _matchesTerms(tbl, terms));
  }

  static OrderingTerm _byTitle($MediaItemsTableTable tbl, [OrderingMode mode = OrderingMode.asc]) =>
      OrderingTerm(expression: tbl.title.collate(Collate.noCase), mode: mode);

  void _applySort(
    SimpleSelectStatement<$MediaItemsTableTable, MediaItemEntry> query,
    SongSortOption sortBy,
    bool ascending,
  ) {
    final mode = ascending ? OrderingMode.asc : OrderingMode.desc;
    switch (sortBy) {
      case SongSortOption.title:
        query.orderBy([(tbl) => _byTitle(tbl, mode)]);
      case SongSortOption.artist:
        query.orderBy([
          (tbl) => OrderingTerm(expression: tbl.artist.collate(Collate.noCase), mode: mode, nulls: NullsOrder.last),
          (tbl) => _byTitle(tbl),
        ]);
      case SongSortOption.album:
        query.orderBy([
          (tbl) => OrderingTerm(expression: tbl.album.collate(Collate.noCase), mode: mode, nulls: NullsOrder.last),
          (tbl) => OrderingTerm(expression: tbl.discNumber, nulls: NullsOrder.first),
          (tbl) => OrderingTerm(expression: tbl.trackNumber, nulls: NullsOrder.last),
          (tbl) => _byTitle(tbl),
        ]);
      case SongSortOption.dateAdded:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: mode), (tbl) => _byTitle(tbl)]);
      case SongSortOption.duration:
        query.orderBy([(tbl) => OrderingTerm(expression: tbl.durationMs, mode: mode), (tbl) => _byTitle(tbl)]);
      case SongSortOption.mostPlayed:
        query.orderBy([
          (tbl) => OrderingTerm(expression: tbl.playCount, mode: mode),
          (tbl) => OrderingTerm(expression: tbl.lastPlayed, mode: OrderingMode.desc, nulls: NullsOrder.last),
          (tbl) => _byTitle(tbl),
        ]);
    }
  }

  static SongSortOption _songSortOf(MediaSortOption sort) => switch (sort) {
        MediaSortOption.title => SongSortOption.title,
        MediaSortOption.artist => SongSortOption.artist,
        MediaSortOption.dateAdded => SongSortOption.dateAdded,
        MediaSortOption.duration => SongSortOption.duration,
      };

  static List<MediaItem> _toItems(List<MediaItemEntry> rows) => [for (final r in rows) r.toDomain()];

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) {
    final terms = searchTerms(searchQuery);
    return _afterSearchKeys(terms, () {
      final query = _listQuery(mediaType: mediaType, terms: terms);
      _applySort(query, _songSortOf(sortBy), ascending);
      return query.watch().map(_toItems);
    });
  }

  @override
  Stream<List<MediaItem>> watchSongs({
    String? searchQuery,
    SongSortOption sortBy = SongSortOption.title,
    bool ascending = true,
  }) {
    final terms = searchTerms(searchQuery);
    return _afterSearchKeys(terms, () {
      final query = _listQuery(mediaType: MediaType.audio, terms: terms);
      _applySort(query, sortBy, ascending);
      return query.watch().map(_toItems);
    });
  }

  @override
  Future<List<MediaItem>> getMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) async {
    final terms = searchTerms(searchQuery);
    if (terms.isNotEmpty) {
      try {
        await _backfillSearchKeys();
      } catch (_) {}
    }
    final query = _listQuery(mediaType: mediaType, terms: terms);
    _applySort(query, _songSortOf(sortBy), ascending);
    return _toItems(await query.get());
  }

  // ---------------------------------------------------------------------------
  // Liked songs
  // ---------------------------------------------------------------------------

  @override
  Stream<List<MediaItem>> watchFavorites({String? searchQuery}) {
    final terms = searchTerms(searchQuery);
    return _afterSearchKeys(terms, () {
      final query = _db.select(_db.mediaItemsTable)
        ..where((tbl) =>
            tbl.isFavorite.equals(true) &
            (tbl.mediaType.equals(MediaType.audio.name) | tbl.source.equals('online')) &
            _available(tbl) &
            _matchesTerms(tbl, terms))
        ..orderBy([
          (tbl) => OrderingTerm(expression: tbl.favoritedAt, mode: OrderingMode.desc, nulls: NullsOrder.last),
          (tbl) => _byTitle(tbl),
        ]);
      return query.watch().map(_toItems);
    });
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final item = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item != null) {
      final newFav = !item.isFavorite;
      DiagnosticsService.instance.logEvent('favorite_toggled', {'id': id, 'isFavorite': newFav});
      await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
        MediaItemsTableCompanion(
          isFavorite: Value(newFav),
          favoritedAt: Value(newFav ? DateTime.now() : null),
        ),
      );
    }
  }

  @override
  Future<void> recordPlay(String id) async {
    final item = await (_db.select(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (item != null) {
      await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
        MediaItemsTableCompanion(
          lastPlayed: Value(DateTime.now()),
          playCount: Value(item.playCount + 1),
        ),
      );
    }
  }

  @override
  Future<void> updateAvailability(String id, MediaAvailability availability) async {
    await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id))).write(
      MediaItemsTableCompanion(
        availability: Value(availability.name),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Removal and Online items
  // ---------------------------------------------------------------------------

  @override
  Future<void> deleteMediaCompletely(String mediaId) async {
    await _db.transaction(() async {
      final entries =
          await (_db.select(_db.playlistItemsTable)..where((t) => t.mediaId.equals(mediaId))).get();
      final playlists = {for (final e in entries) e.playlistId};
      await (_db.delete(_db.playlistItemsTable)..where((t) => t.mediaId.equals(mediaId))).go();
      final now = DateTime.now();
      for (final playlistId in playlists) {
        await _db.renumberAllPlaylists(playlistId: playlistId);
        await (_db.update(_db.playlistsTable)..where((t) => t.id.equals(playlistId)))
            .write(PlaylistsTableCompanion(updatedAt: Value(now)));
      }
      await (_db.delete(_db.videoProgressTable)..where((t) => t.mediaId.equals(mediaId))).go();
      await (_db.delete(_db.mediaItemsTable)..where((t) => t.id.equals(mediaId))).go();
    });
  }

  static bool _isWebLink(String? s) => s != null && (s.startsWith('https://') || s.startsWith('http://'));

  @override
  Future<MediaItem> saveOnlineItem(MediaItem item) async {
    if (!item.uri.startsWith('https://')) {
      throw ArgumentError.value(item.uri, 'item.uri', 'an Online item is saved by its https watch link');
    }
    final artwork = _isWebLink(item.artworkPath) ? item.artworkPath : null;
    final key = librarySearchKey(title: item.title, artist: item.artist, album: item.album);
    final t = _db.mediaItemsTable;
    await _db.into(t).insert(
          MediaItemsTableCompanion.insert(
            id: item.id,
            uri: item.uri,
            mediaType: item.mediaType.name,
            title: item.title,
            artist: Value(item.artist),
            album: Value(item.album),
            durationMs: item.durationMs < 0 ? 0 : item.durationMs,
            sizeBytes: 0,
            dateAdded: DateTime.now(),
            availability: const Value('available'),
            source: const Value('online'),
            artworkPath: Value(artwork),
            searchKey: Value(key),
          ),
          onConflict: DoUpdate(
            (old) => MediaItemsTableCompanion.custom(
              uri: Constant(item.uri),
              title: Constant(item.title),
              artist: Constant(item.artist),
              source: const Constant('online'),
              availability: const Constant('available'),
              searchKey: Constant(key),
              artworkPath: artwork == null ? old.artworkPath : Constant(artwork),
              durationMs: item.durationMs > 0 ? Constant(item.durationMs) : old.durationMs,
            ),
          ),
        );
    final row = await (_db.select(t)..where((r) => r.id.equals(item.id))).getSingle();
    return row.toDomain();
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  static const String _playlistColumns = '''
    SELECT p.id AS id, p.name AS name, p.created_at AS created_at, p.updated_at AS updated_at,
      (SELECT COUNT(*) FROM playlist_items_table i
         JOIN media_items_table m ON m.id = i.media_id
        WHERE i.playlist_id = p.id AND m.availability = 'available') AS song_count
    FROM playlists_table p''';

  Set<ResultSetImplementation> get _playlistTables =>
      {_db.playlistsTable, _db.playlistItemsTable, _db.mediaItemsTable};

  /// The first songs of [playlistIds] (or of every playlist), up to
  /// [playlistCoverCount] different covers each.
  Future<Map<String, List<MediaItem>>> _coverSongs([List<String>? playlistIds]) async {
    final filter = playlistIds == null ? '' : 'AND i.playlist_id IN (${List.filled(playlistIds.length, '?').join(', ')})';
    final rows = await _db.customSelect(
      '''
      SELECT c.pid AS pid, m.* FROM (
        SELECT i.playlist_id AS pid, i.media_id AS mid, i.position AS pos,
               ROW_NUMBER() OVER (PARTITION BY i.playlist_id ORDER BY i.position) AS rn
          FROM playlist_items_table i
          JOIN media_items_table m2 ON m2.id = i.media_id AND m2.availability = 'available'
         WHERE 1 = 1 $filter
      ) c JOIN media_items_table m ON m.id = c.mid
      WHERE c.rn <= 16
      ORDER BY c.pid, c.pos''',
      variables: [for (final id in playlistIds ?? const <String>[]) Variable.withString(id)],
      readsFrom: _playlistTables,
    ).get();
    final result = <String, List<MediaItem>>{};
    final seen = <String, Set<String>>{};
    for (final row in rows) {
      final pid = row.read<String>('pid');
      final list = result.putIfAbsent(pid, () => []);
      if (list.length >= playlistCoverCount) continue;
      final entry = _db.mediaItemsTable.map(row.data);
      // One tile per cover: the same album twice would repeat its art.
      final coverKey = entry.artworkPath ?? entry.albumId ?? entry.uri;
      if (!seen.putIfAbsent(pid, () => <String>{}).add(coverKey)) continue;
      list.add(entry.toDomain());
    }
    return result;
  }

  Playlist _playlistFromRow(QueryRow row, Map<String, List<MediaItem>> covers) {
    final id = row.read<String>('id');
    return Playlist(
      id: id,
      name: row.read<String>('name'),
      createdAt: row.read<DateTime>('created_at'),
      updatedAt: row.read<DateTime>('updated_at'),
      songCount: row.read<int>('song_count'),
      coverSongs: covers[id] ?? const [],
    );
  }

  @override
  Stream<List<Playlist>> watchPlaylists() {
    return _db
        .customSelect('$_playlistColumns ORDER BY p.name COLLATE NOCASE, p.created_at', readsFrom: _playlistTables)
        .watch()
        .asyncMap((rows) async {
      final covers = rows.isEmpty ? const <String, List<MediaItem>>{} : await _coverSongs();
      return [for (final row in rows) _playlistFromRow(row, covers)];
    });
  }

  @override
  Stream<Playlist?> watchPlaylist(String id) {
    return _db
        .customSelect('$_playlistColumns WHERE p.id = ?', variables: [Variable.withString(id)], readsFrom: _playlistTables)
        .watch()
        .asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final covers = await _coverSongs([id]);
      return _playlistFromRow(rows.first, covers);
    });
  }

  /// A playlist id that cannot collide even when two are made in the same
  /// millisecond: the time plus 48 random bits.
  String _newPlaylistId(DateTime now) {
    final suffix = List<String>.generate(6, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'pl_${now.millisecondsSinceEpoch}_$suffix';
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final now = DateTime.now();
    final id = _newPlaylistId(now);
    final shownName = name.trim().isEmpty ? 'Untitled Playlist' : name.trim();
    DiagnosticsService.instance.logEvent('playlist_created', {'id': id});
    await _db.into(_db.playlistsTable).insert(
          PlaylistsTableCompanion.insert(
            id: id,
            name: shownName,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return Playlist(
      id: id,
      name: shownName,
      createdAt: now,
      updatedAt: now,
      songCount: 0,
    );
  }

  @override
  Future<void> renamePlaylist(String id, String newName) async {
    DiagnosticsService.instance.logEvent('playlist_renamed', {'id': id});
    await (_db.update(_db.playlistsTable)..where((tbl) => tbl.id.equals(id))).write(
      PlaylistsTableCompanion(
        name: Value(newName.trim().isEmpty ? 'Untitled Playlist' : newName.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deletePlaylist(String id) async {
    DiagnosticsService.instance.logEvent('playlist_deleted', {'id': id});
    await _db.transaction(() async {
      await (_db.delete(_db.playlistItemsTable)..where((tbl) => tbl.playlistId.equals(id))).go();
      await (_db.delete(_db.playlistsTable)..where((tbl) => tbl.id.equals(id))).go();
    });
  }

  Future<void> _touchPlaylist(String playlistId) {
    return (_db.update(_db.playlistsTable)..where((tbl) => tbl.id.equals(playlistId)))
        .write(PlaylistsTableCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<int> _nextPosition(String playlistId) async {
    final maxPosQuery = _db.selectOnly(_db.playlistItemsTable)
      ..addColumns([_db.playlistItemsTable.position.max()])
      ..where(_db.playlistItemsTable.playlistId.equals(playlistId));
    final currentMax =
        await maxPosQuery.map((r) => r.read(_db.playlistItemsTable.position.max())).getSingleOrNull();
    return (currentMax ?? -1) + 1;
  }

  Future<Set<String>> _songIdsIn(String playlistId) async {
    final rows = await (_db.selectOnly(_db.playlistItemsTable)
          ..addColumns([_db.playlistItemsTable.mediaId])
          ..where(_db.playlistItemsTable.playlistId.equals(playlistId)))
        .map((r) => r.read(_db.playlistItemsTable.mediaId)!)
        .get();
    return rows.toSet();
  }

  @override
  Future<bool> addSongToPlaylist(String playlistId, String mediaId, {bool allowDuplicate = false}) async {
    DiagnosticsService.instance.logEvent('playlist_song_added', {'playlistId': playlistId, 'mediaId': mediaId});
    return _db.transaction(() async {
      if (!allowDuplicate && (await _songIdsIn(playlistId)).contains(mediaId)) return false;
      await _db.into(_db.playlistItemsTable).insert(
            PlaylistItemsTableCompanion.insert(
              playlistId: playlistId,
              mediaId: mediaId,
              position: await _nextPosition(playlistId),
              addedAt: DateTime.now(),
            ),
          );
      await _touchPlaylist(playlistId);
      return true;
    });
  }

  @override
  Future<int> addSongsToPlaylist(String playlistId, List<String> mediaIds) async {
    if (mediaIds.isEmpty) return 0;
    final added = await _db.transaction(() async {
      final present = await _songIdsIn(playlistId);
      var position = await _nextPosition(playlistId);
      final now = DateTime.now();
      var count = 0;
      for (final id in mediaIds) {
        if (!present.add(id)) continue;
        await _db.into(_db.playlistItemsTable).insert(
              PlaylistItemsTableCompanion.insert(
                playlistId: playlistId,
                mediaId: id,
                position: position++,
                addedAt: now,
              ),
            );
        count++;
      }
      if (count > 0) await _touchPlaylist(playlistId);
      return count;
    });
    DiagnosticsService.instance.logEvent('playlist_songs_added', {'playlistId': playlistId, 'count': added});
    return added;
  }

  @override
  Future<void> insertSongIntoPlaylist(String playlistId, String mediaId, int position) async {
    await _db.transaction(() async {
      final items = await (_db.select(_db.playlistItemsTable)
            ..where((tbl) => tbl.playlistId.equals(playlistId))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.position, mode: OrderingMode.desc)]))
          .get();
      final at = position.clamp(0, items.length);
      // Highest first, so a shifted entry never lands on one not moved yet.
      for (final e in items) {
        if (e.position < at) continue;
        await (_db.update(_db.playlistItemsTable)
              ..where((tbl) =>
                  tbl.playlistId.equals(playlistId) & tbl.mediaId.equals(e.mediaId) & tbl.position.equals(e.position)))
            .write(PlaylistItemsTableCompanion(position: Value(e.position + 1)));
      }
      await _db.into(_db.playlistItemsTable).insert(
            PlaylistItemsTableCompanion.insert(
              playlistId: playlistId,
              mediaId: mediaId,
              position: at,
              addedAt: DateTime.now(),
            ),
          );
      await _db.renumberAllPlaylists(playlistId: playlistId);
      await _touchPlaylist(playlistId);
    });
  }

  @override
  Future<void> removeSongFromPlaylist(String playlistId, String mediaId, int position) async {
    DiagnosticsService.instance.logEvent('playlist_song_removed', {'playlistId': playlistId, 'mediaId': mediaId});
    await _db.transaction(() async {
      final removed = await (_db.delete(_db.playlistItemsTable)
            ..where((tbl) =>
                tbl.playlistId.equals(playlistId) & tbl.mediaId.equals(mediaId) & tbl.position.equals(position)))
          .go();
      if (removed == 0) {
        // A stale position (the list moved under the caller): the entry of
        // that song nearest to it.
        final entries = await (_db.select(_db.playlistItemsTable)
              ..where((tbl) => tbl.playlistId.equals(playlistId) & tbl.mediaId.equals(mediaId)))
            .get();
        if (entries.isEmpty) return;
        entries.sort((a, b) => (a.position - position).abs().compareTo((b.position - position).abs()));
        final nearest = entries.first;
        await (_db.delete(_db.playlistItemsTable)
              ..where((tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.mediaId.equals(mediaId) &
                  tbl.position.equals(nearest.position)))
            .go();
      }
      await _db.renumberAllPlaylists(playlistId: playlistId);
      await _touchPlaylist(playlistId);
    });
  }

  @override
  Future<void> reorderPlaylist(String playlistId, int oldPosition, int newPosition) async {
    DiagnosticsService.instance.logEvent('playlist_reordered', {'playlistId': playlistId});
    await _db.transaction(() async {
      // Read inside the transaction: a song added meanwhile is not lost.
      final items = await (_db.select(_db.playlistItemsTable)
            ..where((tbl) => tbl.playlistId.equals(playlistId))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.position, mode: OrderingMode.asc)]))
          .get();
      final from = items.indexWhere((e) => e.position == oldPosition);
      if (from < 0) return;
      var to = items.indexWhere((e) => e.position == newPosition);
      if (to < 0) {
        if (newPosition < 0) return;
        to = items.length - 1;
      }
      if (from == to) return;

      final mutable = List<PlaylistItemEntry>.from(items);
      final moved = mutable.removeAt(from);
      mutable.insert(to, moved);

      await (_db.delete(_db.playlistItemsTable)..where((tbl) => tbl.playlistId.equals(playlistId))).go();
      for (int i = 0; i < mutable.length; i++) {
        await _db.into(_db.playlistItemsTable).insert(
              PlaylistItemsTableCompanion.insert(
                playlistId: playlistId,
                mediaId: mutable[i].mediaId,
                position: i,
                addedAt: mutable[i].addedAt,
              ),
            );
      }
      await _touchPlaylist(playlistId);
    });
  }

  @override
  Stream<List<PlaylistTrack>> watchPlaylistTracks(String playlistId) {
    final query = _db.select(_db.playlistItemsTable).join([
      innerJoin(
        _db.mediaItemsTable,
        _db.mediaItemsTable.id.equalsExp(_db.playlistItemsTable.mediaId),
      ),
    ])
      ..where(_db.playlistItemsTable.playlistId.equals(playlistId) & _available(_db.mediaItemsTable))
      ..orderBy([OrderingTerm(expression: _db.playlistItemsTable.position, mode: OrderingMode.asc)]);

    return query.watch().map((rows) {
      return [
        for (final r in rows)
          PlaylistTrack(
            position: r.readTable(_db.playlistItemsTable).position,
            item: r.readTable(_db.mediaItemsTable).toDomain(),
          ),
      ];
    });
  }

  @override
  Stream<List<MediaItem>> watchPlaylistSongs(String playlistId) {
    return watchPlaylistTracks(playlistId).map((tracks) => [for (final t in tracks) t.item]);
  }

  @override
  Stream<Set<String>> watchPlaylistIdsContaining(String mediaId) {
    final query = _db.selectOnly(_db.playlistItemsTable, distinct: true)
      ..addColumns([_db.playlistItemsTable.playlistId])
      ..where(_db.playlistItemsTable.mediaId.equals(mediaId));
    return query.watch().map((rows) => {for (final r in rows) r.read(_db.playlistItemsTable.playlistId)!});
  }

  // ---------------------------------------------------------------------------
  // Albums and artists
  // ---------------------------------------------------------------------------

  /// The album key of a song: `id:<album id>` for a song on the phone that
  /// has one (one album even when another has the same name, one compilation
  /// even with many artists), else `tag:<album>|<album artist or artist>`,
  /// both folded (downloads, and rows scanned before v8).
  static String albumKeyOf({
    required String? albumId,
    required String? album,
    required String? albumArtist,
    required String? artist,
    required String? source,
  }) {
    if (albumId != null && albumId.isNotEmpty && source != 'download' && source != 'online') return 'id:$albumId';
    final albumPart = foldForSearch(album ?? '');
    final artistPart = isUnknownArtistName(albumArtist)
        ? (isUnknownArtistName(artist) ? '' : foldForSearch(artist!))
        : foldForSearch(albumArtist!);
    return 'tag:$albumPart|$artistPart';
  }

  static String albumKeyOfItem(MediaItem item) => albumKeyOf(
        albumId: item.albumId,
        album: item.album,
        albumArtist: item.albumArtist,
        artist: item.artist,
        source: item.source,
      );

  static String _albumKeyOfRow(MediaItemEntry r) => albumKeyOf(
        albumId: r.albumId,
        album: r.album,
        albumArtist: r.albumArtist,
        artist: r.artist,
        source: r.source,
      );

  /// Songs on the phone and downloads that are there (what albums and
  /// artists are made of).
  Stream<List<MediaItemEntry>> _watchLibrarySongs() {
    return (_db.select(_db.mediaItemsTable)
          ..where((tbl) => tbl.mediaType.equals(MediaType.audio.name) & _available(tbl) & _notOnline(tbl)))
        .watch();
  }

  /// The most common of [values] (the first seen on a tie), or null.
  static String? _mostCommon(Iterable<String> values) {
    final counts = <String, int>{};
    String? best;
    var bestCount = 0;
    for (final v in values) {
      final c = (counts[v] ?? 0) + 1;
      counts[v] = c;
      if (c > bestCount) {
        best = v;
        bestCount = c;
      }
    }
    return best;
  }

  static int _compareNoCase(String a, String b) {
    final c = a.toLowerCase().compareTo(b.toLowerCase());
    return c != 0 ? c : a.compareTo(b);
  }

  /// Albums out of [rows], with the fields every album screen shows.
  @visibleForTesting
  static List<AlbumGroup> groupAlbums(List<MediaItemEntry> rows) {
    final byKey = <String, List<MediaItemEntry>>{};
    for (final r in rows) {
      byKey.putIfAbsent(_albumKeyOfRow(r), () => []).add(r);
    }
    final albums = <AlbumGroup>[];
    byKey.forEach((key, songs) {
      // The cover song: the smallest uri, so it does not change as songs are
      // added or played.
      songs.sort((a, b) => a.uri.compareTo(b.uri));
      final cover = songs.first;
      final name = _mostCommon([for (final s in songs) if (s.album != null && s.album!.trim().isNotEmpty) s.album!]);
      final albumArtist = _mostCommon([
        for (final s in songs)
          if (!isUnknownArtistName(s.albumArtist)) s.albumArtist!,
      ]);
      final String artist;
      if (albumArtist != null) {
        artist = albumArtist;
      } else {
        final artists = <String, String>{};
        for (final s in songs) {
          if (!isUnknownArtistName(s.artist)) artists.putIfAbsent(foldForSearch(s.artist!), () => s.artist!);
        }
        artist = switch (artists.length) {
          0 => ArtistGroup.unknownArtist,
          1 => artists.values.single,
          _ => AlbumGroup.variousArtists,
        };
      }
      var total = 0;
      int? year;
      for (final s in songs) {
        if (s.durationMs > 0) total += s.durationMs;
        final y = s.year;
        if (y != null && (year == null || y > year)) year = y;
      }
      albums.add(AlbumGroup(
        album: name ?? AlbumGroup.unknownAlbum,
        artist: artist,
        songCount: songs.length,
        totalDurationMs: total,
        coverUri: cover.uri,
        coverArtworkPath: cover.artworkPath,
        key: key,
        year: year,
      ));
    });
    albums.sort((a, b) {
      final unknownA = a.album == AlbumGroup.unknownAlbum;
      final unknownB = b.album == AlbumGroup.unknownAlbum;
      if (unknownA != unknownB) return unknownA ? 1 : -1;
      final byName = _compareNoCase(a.album, b.album);
      return byName != 0 ? byName : _compareNoCase(a.artist, b.artist);
    });
    return albums;
  }

  @override
  Stream<List<AlbumGroup>> watchAlbums({String? searchQuery}) {
    final terms = searchTerms(searchQuery);
    return _watchLibrarySongs().map((rows) {
      final albums = groupAlbums(rows);
      if (terms.isEmpty) return albums;
      return albums
          .where((a) => matchesAllTerms(terms, [foldForSearch(a.album), foldForSearch(a.artist)]))
          .toList();
    });
  }

  /// Disc (a tagged track without a disc is on the first), then track, then
  /// title; songs with no track tag at all come last.
  static int _discKey(MediaItemEntry r) => r.discNumber ?? (r.trackNumber == null ? 1 << 30 : 1);

  static int _compareTrackOrder(MediaItemEntry a, MediaItemEntry b) {
    final disc = _discKey(a).compareTo(_discKey(b));
    if (disc != 0) return disc;
    final ta = a.trackNumber;
    final tb = b.trackNumber;
    if (ta != tb) {
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    }
    return _compareNoCase(a.title, b.title);
  }

  @override
  Stream<List<MediaItem>> watchAlbumSongs(String albumKey) {
    final bool Function(MediaItemEntry) belongs;
    if (albumKey.startsWith('id:') || albumKey.startsWith('tag:')) {
      belongs = (r) => _albumKeyOfRow(r) == albumKey;
    } else {
      // A plain album name (a group made by hand).
      final unknown = albumKey == AlbumGroup.unknownAlbum || albumKey == 'Unknown Album';
      belongs = (r) {
        final album = r.album?.trim() ?? '';
        return unknown ? album.isEmpty : r.album == albumKey;
      };
    }
    return _watchLibrarySongs().map((rows) {
      final songs = rows.where(belongs).toList()..sort(_compareTrackOrder);
      return _toItems(songs);
    });
  }

  @override
  Future<AlbumGroup?> findAlbumOf(MediaItem item) async {
    if (item.isOnline || item.mediaType != MediaType.audio) return null;
    final key = albumKeyOfItem(item);
    final rows = await (_db.select(_db.mediaItemsTable)
          ..where((tbl) => tbl.mediaType.equals(MediaType.audio.name) & _available(tbl) & _notOnline(tbl)))
        .get();
    final songs = rows.where((r) => _albumKeyOfRow(r) == key).toList();
    if (songs.isEmpty) return null;
    return groupAlbums(songs).firstOrNull;
  }

  static String _artistKey(String? artist) => isUnknownArtistName(artist) ? '' : foldForSearch(artist!);

  @override
  Stream<List<ArtistGroup>> watchArtists({String? searchQuery}) {
    final terms = searchTerms(searchQuery);
    return _watchLibrarySongs().map((rows) {
      final byKey = <String, List<MediaItemEntry>>{};
      for (final r in rows) {
        byKey.putIfAbsent(_artistKey(r.artist), () => []).add(r);
      }
      final artists = <ArtistGroup>[];
      byKey.forEach((key, songs) {
        if (terms.isNotEmpty && !matchesAllTerms(terms, [key.isEmpty ? foldForSearch(ArtistGroup.unknownArtist) : key])) {
          return;
        }
        final name = key.isEmpty
            ? ArtistGroup.unknownArtist
            : _mostCommon([for (final s in songs) s.artist!.trim()]) ?? ArtistGroup.unknownArtist;
        artists.add(ArtistGroup(
          artist: name,
          songCount: songs.length,
          albumCount: {
            for (final s in songs)
              if (s.album != null && s.album!.trim().isNotEmpty) _albumKeyOfRow(s),
          }.length,
        ));
      });
      artists.sort((a, b) {
        if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
        return _compareNoCase(a.artist, b.artist);
      });
      return artists;
    });
  }

  @override
  Stream<List<MediaItem>> watchArtistSongs(String artist) {
    final key = _artistKey(artist);
    return _watchLibrarySongs().map((rows) {
      final songs = rows.where((r) => _artistKey(r.artist) == key).toList()
        ..sort((a, b) => _compareNoCase(a.title, b.title));
      return _toItems(songs);
    });
  }

  // ---------------------------------------------------------------------------
  // Home
  // ---------------------------------------------------------------------------

  @override
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) =>
          tbl.lastPlayed.isNotNull() & tbl.mediaType.equals(MediaType.audio.name) & _available(tbl) & _notOnline(tbl))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.lastPlayed, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map(_toItems);
  }

  @override
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) =>
          tbl.playCount.isBiggerThanValue(0) &
          tbl.mediaType.equals(MediaType.audio.name) &
          _available(tbl) &
          _notOnline(tbl))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.playCount, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map(_toItems);
  }

  @override
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType = MediaType.audio}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) {
        final kept = _available(tbl) & _notOnline(tbl);
        return mediaType == null ? kept : kept & tbl.mediaType.equals(mediaType.name);
      })
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map(_toItems);
  }

  @override
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10}) {
    final query = _db.select(_db.mediaItemsTable)
      ..where((tbl) => tbl.mediaType.equals(MediaType.video.name) & _available(tbl) & _notOnline(tbl))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.dateAdded, mode: OrderingMode.desc)])
      ..limit(limit);

    return query.watch().map(_toItems);
  }

  /// Downloaded files are inserted with an unknown (0) duration. Once a player
  /// has opened the file and learned the real duration we persist it so lists
  /// stop showing 00:00.
  Future<void> updateDurationIfUnknown(String id, int durationMs) async {
    if (durationMs <= 0) return;
    await (_db.update(_db.mediaItemsTable)..where((tbl) => tbl.id.equals(id) & tbl.durationMs.equals(0)))
        .write(MediaItemsTableCompanion(durationMs: Value(durationMs)));
  }
}
