import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/backup/library_backup.dart';
import 'package:mediahub/data/database/app_database.dart';

Future<void> _addItem(
  AppDatabase db,
  String id, {
  String type = 'audio',
  required String title,
  int size = 1000,
  int durationMs = 180000,
  bool favorite = false,
  int playCount = 0,
}) {
  return db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
        id: id,
        uri: 'content://media/$id',
        mediaType: type,
        title: title,
        durationMs: durationMs,
        sizeBytes: size,
        dateAdded: DateTime(2026, 1, 1),
        isFavorite: Value(favorite),
        favoritedAt: Value(favorite ? DateTime(2026, 2, 1) : null),
        playCount: Value(playCount),
        lastPlayed: Value(playCount > 0 ? DateTime(2026, 3, 1) : null),
      ));
}

Future<void> _addPlaylist(AppDatabase db, String id, String name, List<String> items) async {
  await db.into(db.playlistsTable).insert(PlaylistsTableCompanion.insert(
        id: id,
        name: name,
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      ));
  for (var i = 0; i < items.length; i++) {
    await db.into(db.playlistItemsTable).insert(PlaylistItemsTableCompanion.insert(
          playlistId: id,
          mediaId: items[i],
          position: i,
          addedAt: DateTime(2026, 1, 2),
        ));
  }
}

Map<String, dynamic> _validJson() => {
      'app': LibraryBackup.appId,
      'schemaVersion': 1,
      'createdAt': '2026-11-23T10:00:00.000Z',
      'items': [
        {'id': 'audio_1', 'type': 'audio', 'title': 'A', 'size': 10, 'durationMs': 1000, 'favorite': true},
      ],
      'playlists': [
        {'name': 'P', 'items': ['audio_1']},
      ],
      'videoPositions': <Object>[],
      'settings': {'online_block_ads': false},
    };

List<int> _bytes(Object json) => utf8.encode(jsonEncode(json));

void main() {
  late AppDatabase source;
  late AppDatabase target;
  late SettingsStore sourceSettings;
  late SettingsStore targetSettings;

  setUp(() {
    source = AppDatabase(NativeDatabase.memory(), () async => null);
    target = AppDatabase(NativeDatabase.memory(), () async => null);
    sourceSettings = SettingsStore.forTesting();
    targetSettings = SettingsStore.forTesting();
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<BackupData> roundTrip() async {
    final data = await LibraryBackupService(source, sourceSettings).export(now: DateTime.utc(2026, 11, 23));
    return BackupData.decode(data.encode());
  }

  test('export then import on another phone: matched by type, title and size', () async {
    await _addItem(source, 'audio_1', title: 'Song One', size: 111, favorite: true, playCount: 4);
    await _addItem(source, 'audio_2', title: 'Song Two', size: 222, favorite: true);
    await _addItem(source, 'video_3', type: 'video', title: 'Clip', size: 333);
    await _addItem(source, 'audio_9', title: 'Not in backup', size: 999);
    await _addPlaylist(source, 'pl_1', 'Road trip', ['audio_2', 'audio_1']);
    await source.into(source.videoProgressTable).insert(VideoProgressTableCompanion.insert(
          mediaId: 'video_3',
          positionMs: 42000,
          durationMs: 90000,
          updatedAt: DateTime(2026, 4, 1),
        ));
    await sourceSettings.setStringList('user_name', ['Asha']);
    await sourceSettings.setBool('online_block_ads', false);
    await sourceSettings.setBool('ytdlp_checked_at', true); // not a backed-up key

    final data = await roundTrip();
    expect(data.items.map((i) => i.id), unorderedEquals(['audio_1', 'audio_2', 'video_3']));
    expect(data.settings, {'user_name': ['Asha'], 'online_block_ads': false});
    expect(jsonEncode(data.toJson()), isNot(contains('content://')), reason: 'no file paths');

    // Other phone: different ids; Song Two is missing; title case differs.
    await _addItem(target, 'audio_50', title: 'song one', size: 111, durationMs: 181000);
    await _addItem(target, 'video_60', type: 'video', title: 'Clip', size: 333);
    final report = await LibraryBackupService(target, targetSettings).restore(data);

    expect(report.favoritesTotal, 2);
    expect(report.favoritesRestored, 1);
    expect(report.lines.first, '1 of 2 favourites restored');
    expect(report.playlistSongsTotal, 2);
    expect(report.playlistSongsRestored, 1);
    expect(report.positionsRestored, 1);
    expect(report.settingsRestored, 2);
    expect(report.anyMissing, isTrue);

    final song = await (target.select(target.mediaItemsTable)..where((r) => r.id.equals('audio_50'))).getSingle();
    expect(song.isFavorite, isTrue);
    expect(song.playCount, 4);
    final pl = await target.select(target.playlistsTable).getSingle();
    expect(pl.name, 'Road trip');
    final items = await target.select(target.playlistItemsTable).get();
    expect(items.map((i) => i.mediaId), ['audio_50']);
    final pos = await target.select(target.videoProgressTable).getSingle();
    expect(pos.mediaId, 'video_60');
    expect(pos.positionMs, 42000);
    expect(targetSettings.getStringList('user_name'), ['Asha']);
    expect(targetSettings.getBool('online_block_ads', defaultValue: true), isFalse);
  });

  test('restore merges: same-name playlist gets only missing songs, counts keep the larger, twice is a no-op',
      () async {
    await _addItem(source, 'audio_1', title: 'A', size: 1, playCount: 2);
    await _addItem(source, 'audio_2', title: 'B', size: 2);
    await _addPlaylist(source, 'pl_1', 'Mix', ['audio_1', 'audio_2']);
    final data = await roundTrip();

    await _addItem(target, 'audio_1', title: 'A', size: 1, playCount: 7, favorite: true);
    await _addItem(target, 'audio_2', title: 'B', size: 2);
    await _addPlaylist(target, 'pl_x', 'mix', ['audio_1']);
    final service = LibraryBackupService(target, targetSettings);
    await service.restore(data);
    await service.restore(data);

    expect(await target.select(target.playlistsTable).get(), hasLength(1));
    final items = await (target.select(target.playlistItemsTable)..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
    expect(items.map((i) => i.mediaId), ['audio_1', 'audio_2']);
    final a = await (target.select(target.mediaItemsTable)..where((r) => r.id.equals('audio_1'))).getSingle();
    expect(a.playCount, 7, reason: 'never lowered');
    expect(a.isFavorite, isTrue, reason: 'favourites are never removed');
  });

  test('ambiguous identity is not guessed', () async {
    await _addItem(source, 'audio_1', title: 'Same', size: 5, favorite: true);
    final data = await roundTrip();
    await _addItem(target, 'audio_7', title: 'Same', size: 5);
    await _addItem(target, 'audio_8', title: 'same', size: 5);
    final report = await LibraryBackupService(target, targetSettings).restore(data);
    expect(report.favoritesRestored, 0);
  });

  test('bad files are refused with a plain message', () {
    void bad(Object json, String message) {
      expect(
        () => BackupData.decode(json is List<int> ? json : _bytes(json)),
        throwsA(isA<BackupFormatException>().having((e) => e.message, 'message', contains(message))),
      );
    }

    expect(BackupData.decode(_bytes(_validJson())).items, hasLength(1));
    bad(utf8.encode('not json'), 'not a MediaHub backup');
    bad(<Object>[], 'not a MediaHub backup');
    bad({..._validJson(), 'app': 'other.app'}, 'not a MediaHub backup');
    bad({..._validJson(), 'schemaVersion': 2}, 'newer MediaHub');
    bad({..._validJson(), 'schemaVersion': '1'}, 'damaged');
    bad({..._validJson(), 'createdAt': 'yesterday'}, 'damaged');
    bad({
      ..._validJson(),
      'items': [
        {'id': 'x', 'type': 'image', 'title': 'A', 'size': 1, 'durationMs': 1},
      ],
    }, 'damaged');
    bad({
      ..._validJson(),
      'items': [
        {'id': 'x', 'type': 'audio', 'title': 'A', 'size': -1, 'durationMs': 1},
      ],
    }, 'damaged');
    bad({
      ..._validJson(),
      'playlists': [
        {'name': 'P', 'items': ['nope']},
      ],
    }, 'damaged');
    bad({..._validJson(), 'settings': {'online_block_ads': 'no'}}, 'damaged');
    bad(List<int>.filled(LibraryBackup.maxBytes + 1, 32), 'too large');
  });

  test('unknown settings in a backup are ignored', () {
    final data = BackupData.decode(_bytes({
      ..._validJson(),
      'settings': {'online_block_ads': true, 'cookie': 'secret'},
    }));
    expect(data.settings, {'online_block_ads': true});
  });

  test('file name', () {
    expect(LibraryBackup.fileNameFor(DateTime(2026, 3, 7)), 'mediahub-backup-2026-03-07.json');
  });
}
