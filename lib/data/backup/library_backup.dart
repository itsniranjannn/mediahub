import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/storage/settings_store.dart';
import '../database/app_database.dart';

/// Library backup and restore: favourites, playlists, play history, video
/// resume positions and the plain settings, as one versioned JSON file.
///
/// What is never in a backup: cookies, keys, file paths, download rows, the
/// yt-dlp state. Songs and videos are named the way the library rescan
/// recognises a file again (`LibraryRepositoryImpl._carryOverUserData`):
/// media type, title (ignoring case) and size in bytes, with durations within
/// 2 seconds; the row id is tried first (same phone, same library).
class LibraryBackup {
  LibraryBackup._();

  static const String appId = 'com.mediahub.app';
  static const int schemaVersion = 1;

  /// Larger files are refused before they are read.
  static const int maxBytes = 5 * 1024 * 1024;

  static const int _maxItems = 100000;
  static const int _maxPlaylists = 5000;
  static const int _maxText = 2000;

  /// Settings a backup carries, with their type. Nothing secret, nothing that
  /// switches a feature with side effects (the web link downloader stays as
  /// it is on this phone).
  static const Map<String, Type> settingKeys = {
    'appearance_theme_mode': List<String>,
    'user_name': List<String>,
    'resume_on_headphones_reconnect': bool,
    'resume_after_other_apps': bool,
    'online_background_play': bool,
    'online_auto_pip': bool,
    'online_block_ads': bool,
    'ask_big_downloads_mobile_data': bool,
  };

  /// `mediahub-backup-2026-11-23.json`.
  static String fileNameFor(DateTime now) =>
      'mediahub-backup-${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}.json';
}

/// A backup file that is not one MediaHub can read; [message] is for the user.
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => 'BackupFormatException: $message';
}

/// One song or video as the backup names it.
class BackupItem {
  final String id;
  final String mediaType; // 'audio' or 'video'
  final String title;
  final int sizeBytes;
  final int durationMs;
  final bool favorite;
  final DateTime? favoritedAt;
  final int playCount;
  final DateTime? lastPlayed;

  const BackupItem({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.sizeBytes,
    required this.durationMs,
    this.favorite = false,
    this.favoritedAt,
    this.playCount = 0,
    this.lastPlayed,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'type': mediaType,
        'title': title,
        'size': sizeBytes,
        'durationMs': durationMs,
        if (favorite) 'favorite': true,
        if (favoritedAt != null) 'favoritedAt': favoritedAt!.toUtc().toIso8601String(),
        if (playCount > 0) 'playCount': playCount,
        if (lastPlayed != null) 'lastPlayed': lastPlayed!.toUtc().toIso8601String(),
      };
}

class BackupPlaylist {
  final String name;
  final DateTime? createdAt;

  /// Item ids ([BackupItem.id]) in playlist order.
  final List<String> itemIds;

  const BackupPlaylist({required this.name, this.createdAt, required this.itemIds});

  Map<String, Object?> toJson() => {
        'name': name,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        'items': itemIds,
      };
}

class BackupVideoPosition {
  final String itemId;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const BackupVideoPosition({
    required this.itemId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() => {
        'item': itemId,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

/// The parsed contents of a backup file.
class BackupData {
  final DateTime createdAt;
  final List<BackupItem> items;
  final List<BackupPlaylist> playlists;
  final List<BackupVideoPosition> videoPositions;
  final Map<String, Object> settings;

  const BackupData({
    required this.createdAt,
    required this.items,
    required this.playlists,
    required this.videoPositions,
    required this.settings,
  });

  int get favoriteCount => items.where((i) => i.favorite).length;

  Map<String, Object?> toJson() => {
        'app': LibraryBackup.appId,
        'schemaVersion': LibraryBackup.schemaVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        'playlists': [for (final p in playlists) p.toJson()],
        'videoPositions': [for (final v in videoPositions) v.toJson()],
        'settings': settings,
      };

  List<int> encode() => utf8.encode(const JsonEncoder.withIndent(' ').convert(toJson()));

  /// Reads and strictly checks a backup file. Throws [BackupFormatException].
  static BackupData decode(List<int> bytes) {
    if (bytes.length > LibraryBackup.maxBytes) {
      throw const BackupFormatException('This file is too large to be a MediaHub backup.');
    }
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupFormatException('This file is not a MediaHub backup.');
    }
    if (root is! Map<String, dynamic> || root['app'] != LibraryBackup.appId) {
      throw const BackupFormatException('This file is not a MediaHub backup.');
    }
    final version = root['schemaVersion'];
    if (version is! int || version < 1) {
      throw const BackupFormatException('This backup is damaged.');
    }
    if (version > LibraryBackup.schemaVersion) {
      throw const BackupFormatException('This backup was made by a newer MediaHub. Update the app first.');
    }
    try {
      final createdAt = _date(root['createdAt'], required: true)!;
      final items = <BackupItem>[];
      final ids = <String>{};
      for (final raw in _list(root['items'], LibraryBackup._maxItems)) {
        final m = _map(raw);
        final type = _text(m['type']);
        if (type != 'audio' && type != 'video') throw const FormatException('type');
        final item = BackupItem(
          id: _text(m['id']),
          mediaType: type,
          title: _text(m['title'], allowEmpty: true),
          sizeBytes: _int(m['size']),
          durationMs: _int(m['durationMs']),
          favorite: _bool(m['favorite']),
          favoritedAt: _date(m['favoritedAt']),
          playCount: _int(m['playCount'] ?? 0),
          lastPlayed: _date(m['lastPlayed']),
        );
        if (!ids.add(item.id)) throw const FormatException('duplicate id');
        items.add(item);
      }
      final playlists = <BackupPlaylist>[];
      for (final raw in _list(root['playlists'], LibraryBackup._maxPlaylists)) {
        final m = _map(raw);
        final refs = [for (final r in _list(m['items'], LibraryBackup._maxItems)) _text(r)];
        if (refs.any((r) => !ids.contains(r))) throw const FormatException('unknown item');
        playlists.add(BackupPlaylist(name: _text(m['name'], allowEmpty: true), createdAt: _date(m['createdAt']), itemIds: refs));
      }
      final positions = <BackupVideoPosition>[];
      for (final raw in _list(root['videoPositions'], LibraryBackup._maxItems)) {
        final m = _map(raw);
        final ref = _text(m['item']);
        if (!ids.contains(ref)) throw const FormatException('unknown item');
        positions.add(BackupVideoPosition(
          itemId: ref,
          positionMs: _int(m['positionMs']),
          durationMs: _int(m['durationMs']),
          updatedAt: _date(m['updatedAt'], required: true)!,
        ));
      }
      final settings = <String, Object>{};
      final rawSettings = root['settings'] == null ? const <String, dynamic>{} : _map(root['settings']);
      for (final e in rawSettings.entries) {
        final type = LibraryBackup.settingKeys[e.key];
        if (type == null) continue; // a setting this version does not know: ignored
        if (type == bool) {
          if (e.value is! bool) throw const FormatException('setting');
          settings[e.key] = e.value as bool;
        } else {
          final list = [for (final v in _list(e.value, 10)) _text(v, allowEmpty: true)];
          settings[e.key] = list;
        }
      }
      return BackupData(
        createdAt: createdAt,
        items: items,
        playlists: playlists,
        videoPositions: positions,
        settings: settings,
      );
    } on FormatException {
      throw const BackupFormatException('This backup is damaged.');
    } on TypeError {
      throw const BackupFormatException('This backup is damaged.');
    }
  }

  static List<dynamic> _list(Object? v, int max) {
    if (v == null) return const [];
    if (v is! List || v.length > max) throw const FormatException('list');
    return v;
  }

  static Map<String, dynamic> _map(Object? v) {
    if (v is! Map<String, dynamic>) throw const FormatException('object');
    return v;
  }

  static String _text(Object? v, {bool allowEmpty = false}) {
    if (v is! String || v.length > LibraryBackup._maxText || (!allowEmpty && v.isEmpty)) {
      throw const FormatException('text');
    }
    return v;
  }

  static int _int(Object? v) {
    if (v is! int || v < 0) throw const FormatException('number');
    return v;
  }

  static bool _bool(Object? v) {
    if (v == null) return false;
    if (v is! bool) throw const FormatException('bool');
    return v;
  }

  static DateTime? _date(Object? v, {bool required = false}) {
    if (v == null && !required) return null;
    if (v is! String) throw const FormatException('date');
    return DateTime.parse(v);
  }
}

/// What a restore brought back, for "12 of 14 favourites restored".
class RestoreReport {
  final int favoritesTotal;
  final int favoritesRestored;
  final int playlistsTotal;
  final int playlistSongsTotal;
  final int playlistSongsRestored;
  final int historyTotal;
  final int historyRestored;
  final int positionsTotal;
  final int positionsRestored;
  final int settingsRestored;

  const RestoreReport({
    required this.favoritesTotal,
    required this.favoritesRestored,
    required this.playlistsTotal,
    required this.playlistSongsTotal,
    required this.playlistSongsRestored,
    required this.historyTotal,
    required this.historyRestored,
    required this.positionsTotal,
    required this.positionsRestored,
    required this.settingsRestored,
  });

  /// One line per part that was in the backup.
  List<String> get lines => [
        if (favoritesTotal > 0) '$favoritesRestored of $favoritesTotal favourites restored',
        if (playlistsTotal > 0)
          '$playlistsTotal ${playlistsTotal == 1 ? 'playlist' : 'playlists'}: '
              '$playlistSongsRestored of $playlistSongsTotal songs found',
        if (historyTotal > 0) '$historyRestored of $historyTotal play counts restored',
        if (positionsTotal > 0) '$positionsRestored of $positionsTotal video positions restored',
        if (settingsRestored > 0) '$settingsRestored ${settingsRestored == 1 ? 'setting' : 'settings'} restored',
      ];

  bool get anyMissing =>
      favoritesRestored < favoritesTotal ||
      playlistSongsRestored < playlistSongsTotal ||
      historyRestored < historyTotal ||
      positionsRestored < positionsTotal;
}

/// Makes backups from, and merges them into, the library database and [SettingsStore].
class LibraryBackupService {
  final AppDatabase _db;
  final SettingsStore _settings;
  final Random _random;

  LibraryBackupService(this._db, this._settings, [Random? random]) : _random = random ?? Random();

  Future<BackupData> export({DateTime? now}) async {
    final rows = await _db.select(_db.mediaItemsTable).get();
    final playlists = await (_db.select(_db.playlistsTable)..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).get();
    final playlistItems = await (_db.select(_db.playlistItemsTable)
          ..orderBy([(p) => OrderingTerm.asc(p.playlistId), (p) => OrderingTerm.asc(p.position)]))
        .get();
    final progress = await _db.select(_db.videoProgressTable).get();

    final byId = {for (final r in rows) r.id: r};
    final needed = <String>{
      for (final r in rows)
        if (r.isFavorite || r.playCount > 0 || r.lastPlayed != null) r.id,
      for (final p in playlistItems)
        if (byId.containsKey(p.mediaId)) p.mediaId,
      for (final v in progress)
        if (byId.containsKey(v.mediaId)) v.mediaId,
    };
    final items = [
      for (final id in needed)
        BackupItem(
          id: id,
          mediaType: byId[id]!.mediaType,
          title: byId[id]!.title,
          sizeBytes: max(0, byId[id]!.sizeBytes),
          durationMs: max(0, byId[id]!.durationMs),
          favorite: byId[id]!.isFavorite,
          favoritedAt: byId[id]!.favoritedAt,
          playCount: max(0, byId[id]!.playCount),
          lastPlayed: byId[id]!.lastPlayed,
        ),
    ];
    final settings = <String, Object>{};
    LibraryBackup.settingKeys.forEach((key, type) {
      if (type == bool) {
        // getBool needs a default: probe both to tell "saved" from "never set".
        final a = _settings.getBool(key, defaultValue: true);
        final b = _settings.getBool(key, defaultValue: false);
        if (a == b) settings[key] = a;
      } else {
        final list = _settings.getStringList(key);
        if (list.isNotEmpty) settings[key] = list;
      }
    });
    return BackupData(
      createdAt: now ?? DateTime.now(),
      items: items,
      playlists: [
        for (final p in playlists)
          BackupPlaylist(
            name: p.name,
            createdAt: p.createdAt,
            itemIds: [
              for (final i in playlistItems)
                if (i.playlistId == p.id && byId.containsKey(i.mediaId)) i.mediaId,
            ],
          ),
      ],
      videoPositions: [
        for (final v in progress)
          if (byId.containsKey(v.mediaId))
            BackupVideoPosition(
              itemId: v.mediaId,
              positionMs: max(0, v.positionMs),
              durationMs: max(0, v.durationMs),
              updatedAt: v.updatedAt,
            ),
      ],
      settings: settings,
    );
  }

  static String _identity(String type, String title, int size) => '$type|${title.trim().toLowerCase()}|$size';

  /// Backup item id -> this library's row id, for the items that can be found.
  Map<String, String> _match(List<BackupItem> items, List<MediaItemEntry> rows) {
    final byId = {for (final r in rows) r.id: r};
    final byKey = <String, List<MediaItemEntry>>{};
    for (final r in rows) {
      if (r.sizeBytes <= 0) continue; // size unknown: not safe to match
      byKey.putIfAbsent(_identity(r.mediaType, r.title, r.sizeBytes), () => []).add(r);
    }
    final backupKeyCount = <String, int>{};
    for (final i in items) {
      if (i.sizeBytes <= 0) continue;
      final k = _identity(i.mediaType, i.title, i.sizeBytes);
      backupKeyCount[k] = (backupKeyCount[k] ?? 0) + 1;
    }
    final out = <String, String>{};
    for (final i in items) {
      final same = byId[i.id];
      if (same != null &&
          same.mediaType == i.mediaType &&
          same.title.trim().toLowerCase() == i.title.trim().toLowerCase()) {
        out[i.id] = same.id;
        continue;
      }
      if (i.sizeBytes <= 0) continue;
      final k = _identity(i.mediaType, i.title, i.sizeBytes);
      final candidates = byKey[k];
      // Only an unambiguous pair, like the rescan.
      if (candidates == null || candidates.length != 1 || backupKeyCount[k] != 1) continue;
      final row = candidates.single;
      if ((row.durationMs - i.durationMs).abs() > 2000) continue;
      out[i.id] = row.id;
    }
    return out;
  }

  /// Merges [data] into the library in one transaction: favourites are added
  /// (never removed), play counts and last-played keep the larger / later
  /// value, playlists with the same name get the missing songs appended,
  /// others are created, video positions replace older ones. Settings are
  /// written after the transaction.
  Future<RestoreReport> restore(BackupData data) async {
    late RestoreReport report;
    await _db.transaction(() async {
      final rows = await _db.select(_db.mediaItemsTable).get();
      final rowById = {for (final r in rows) r.id: r};
      final match = _match(data.items, rows);

      var favRestored = 0, histTotal = 0, histRestored = 0;
      for (final item in data.items) {
        final hasHistory = item.playCount > 0 || item.lastPlayed != null;
        if (hasHistory) histTotal++;
        final localId = match[item.id];
        if (localId == null) continue;
        final row = rowById[localId]!;
        var changes = const MediaItemsTableCompanion();
        var changed = false;
        if (item.favorite) {
          favRestored++;
          if (!row.isFavorite) {
            changed = true;
            changes = changes.copyWith(
              isFavorite: const Value(true),
              favoritedAt: Value(row.favoritedAt ?? item.favoritedAt ?? DateTime.now()),
            );
          }
        }
        if (hasHistory) {
          histRestored++;
          if (item.playCount > row.playCount) {
            changed = true;
            changes = changes.copyWith(playCount: Value(item.playCount));
          }
          final last = item.lastPlayed;
          if (last != null && (row.lastPlayed == null || last.isAfter(row.lastPlayed!))) {
            changed = true;
            changes = changes.copyWith(lastPlayed: Value(last.toLocal()));
          }
        }
        if (changed) {
          await (_db.update(_db.mediaItemsTable)..where((r) => r.id.equals(localId))).write(changes);
        }
      }

      var songsTotal = 0, songsRestored = 0;
      final existing = await _db.select(_db.playlistsTable).get();
      final byName = {for (final p in existing) p.name.trim().toLowerCase(): p.id};
      final now = DateTime.now();
      for (final pl in data.playlists) {
        songsTotal += pl.itemIds.length;
        final name = pl.name.trim().isEmpty ? 'Untitled Playlist' : pl.name.trim();
        var playlistId = byName[name.toLowerCase()];
        final List<String> present;
        if (playlistId == null) {
          playlistId = _newPlaylistId(now);
          await _db.into(_db.playlistsTable).insert(PlaylistsTableCompanion.insert(
                id: playlistId,
                name: name,
                createdAt: pl.createdAt?.toLocal() ?? now,
                updatedAt: now,
              ));
          byName[name.toLowerCase()] = playlistId;
          present = [];
        } else {
          final pid = playlistId;
          present = [
            for (final r in await (_db.select(_db.playlistItemsTable)..where((r) => r.playlistId.equals(pid))).get())
              r.mediaId,
          ];
        }
        final pid = playlistId;
        final maxRow = await (_db.selectOnly(_db.playlistItemsTable)
              ..addColumns([_db.playlistItemsTable.position.max()])
              ..where(_db.playlistItemsTable.playlistId.equals(pid)))
            .map((r) => r.read(_db.playlistItemsTable.position.max()))
            .getSingleOrNull();
        var position = (maxRow ?? -1) + 1;
        // A song already in the playlist counts as found; repeats in the backup
        // are matched one for one against what is there.
        final remaining = List<String>.of(present);
        var added = false;
        for (final ref in pl.itemIds) {
          final localId = match[ref];
          if (localId == null) continue;
          songsRestored++;
          if (remaining.remove(localId)) continue;
          await _db.into(_db.playlistItemsTable).insert(PlaylistItemsTableCompanion.insert(
                playlistId: pid,
                mediaId: localId,
                position: position++,
                addedAt: now,
              ));
          added = true;
        }
        if (added) {
          await (_db.update(_db.playlistsTable)..where((p) => p.id.equals(pid)))
              .write(PlaylistsTableCompanion(updatedAt: Value(now)));
        }
      }

      var posRestored = 0;
      for (final v in data.videoPositions) {
        final localId = match[v.itemId];
        if (localId == null) continue;
        posRestored++;
        final current =
            await (_db.select(_db.videoProgressTable)..where((r) => r.mediaId.equals(localId))).getSingleOrNull();
        if (current != null && !v.updatedAt.isAfter(current.updatedAt)) continue;
        await _db.into(_db.videoProgressTable).insertOnConflictUpdate(VideoProgressTableCompanion.insert(
              mediaId: localId,
              positionMs: v.positionMs,
              durationMs: v.durationMs,
              updatedAt: v.updatedAt.toLocal(),
            ));
      }

      report = RestoreReport(
        favoritesTotal: data.favoriteCount,
        favoritesRestored: favRestored,
        playlistsTotal: data.playlists.length,
        playlistSongsTotal: songsTotal,
        playlistSongsRestored: songsRestored,
        historyTotal: histTotal,
        historyRestored: histRestored,
        positionsTotal: data.videoPositions.length,
        positionsRestored: posRestored,
        settingsRestored: 0,
      );
    });

    var settingsRestored = 0;
    for (final e in data.settings.entries) {
      final value = e.value;
      if (value is bool) {
        await _settings.setBool(e.key, value);
      } else if (value is List<String>) {
        await _settings.setStringList(e.key, value);
      } else {
        continue;
      }
      settingsRestored++;
    }
    return RestoreReport(
      favoritesTotal: report.favoritesTotal,
      favoritesRestored: report.favoritesRestored,
      playlistsTotal: report.playlistsTotal,
      playlistSongsTotal: report.playlistSongsTotal,
      playlistSongsRestored: report.playlistSongsRestored,
      historyTotal: report.historyTotal,
      historyRestored: report.historyRestored,
      positionsTotal: report.positionsTotal,
      positionsRestored: report.positionsRestored,
      settingsRestored: settingsRestored,
    );
  }

  String _newPlaylistId(DateTime now) {
    final suffix = List<String>.generate(6, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'pl_${now.millisecondsSinceEpoch}_$suffix';
  }
}
