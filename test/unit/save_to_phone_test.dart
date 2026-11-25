// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// "Save downloads to: Phone storage" / "Save to phone": the download moves
// into MediaStore (Android), keeps its id (favourites, plays, playlists) and
// the library shows it once, also after the phone scan finds the MediaStore
// copy. The iPhone keeps the file (audio is in Files, video goes to Photos).
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform/phone_media.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/downloads/save_to_phone.dart';
import 'package:path/path.dart' as p;

class FakePhoneMedia implements PhoneMedia {
  FakePhoneMedia({this.canSave = true, this.answer});

  bool canSave;

  /// What saveToPhone returns; null: a MediaStore URI.
  String? answer;
  bool fails = false;
  final List<String> saved = [];
  final List<List<String>> deleted = [];
  bool deleteAnswer = true;

  @override
  Future<PhoneMediaCapabilities> capabilities() async => PhoneMediaCapabilities(
        canSaveToPhone: canSave,
        canDeletePhoneMedia: true,
        systemAsksBeforeDelete: true,
      );

  @override
  Future<bool> deleteFromPhone(List<String> uris) async {
    deleted.add(uris);
    return deleteAnswer;
  }

  @override
  Future<({String? lrc, String? path})> lyricsSidecar(String uri) async => (path: null, lrc: null);

  @override
  Future<String> saveToPhone({
    required String path,
    required bool isVideo,
    required String displayName,
    String? mimeType,
  }) async {
    if (fails) throw PlatformException(code: 'SAVE_FAILED');
    saved.add('$path|$isVideo|$displayName|$mimeType');
    return answer ?? 'content://media/external/${isVideo ? 'video' : 'audio'}/media/42';
  }
}

/// MediaStore as the phone scan sees it after the move: the moved song is there.
class _ScanStore implements MethodChannel {
  _ScanStore(this.audio);
  final List<Map<String, Object?>> audio;

  @override
  String get name => 'mediahub/media_store';

  @override
  Future<List<T>?> invokeListMethod<T>(String method, [dynamic arguments]) async {
    if (method == 'queryAudio') return audio.cast<T>();
    if (method == 'queryVideo') return <T>[];
    return null;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late File song;
  late FakePhoneMedia phone;
  late SaveToPhoneService service;

  setUp(() async {
    PlatformInfo.debugIsAndroid = true;
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('save_to_phone');
    song = File(p.join(dir.path, 'Resham Firiri.m4a'))..writeAsBytesSync(List.filled(64, 1));
    phone = FakePhoneMedia();
    service = SaveToPhoneService(db: db, phoneMedia: phone, downloadsDir: () async => dir);
    final now = DateTime(2026, 11, 1);
    await db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
          id: 'dl_1',
          uri: song.path,
          mediaType: MediaType.audio.name,
          title: 'Resham Firiri',
          durationMs: 200000,
          sizeBytes: 64,
          dateAdded: now,
          source: const Value('download'),
          isFavorite: const Value(true),
          playCount: const Value(4),
        ));
    await db.into(db.downloadsTable).insert(DownloadsTableCompanion.insert(
          id: '1',
          url: 'https://example.com/a.m4a',
          host: 'example.com',
          fileName: 'Resham Firiri.m4a',
          displayName: 'Resham Firiri',
          state: 'completed',
          createdAt: now,
          updatedAt: now,
          mediaId: const Value('dl_1'),
          finalPath: Value(song.path),
          mimeType: const Value('audio/mp4'),
        ));
  });

  tearDown(() async {
    PlatformInfo.resetForTests();
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<MediaItemEntry> row() => (db.select(db.mediaItemsTable)..where((t) => t.id.equals('dl_1'))).getSingle();

  test('Android: moves the file into MediaStore, same id, app copy gone', () async {
    final result = await service.save('dl_1');
    expect(result, SaveToPhoneResult.saved);
    expect(phone.saved.single, '${song.path}|false|Resham Firiri.m4a|audio/mp4');
    final r = await row();
    expect(r.uri, 'content://media/external/audio/media/42');
    expect(r.relativePath, 'Music/MediaHub/');
    expect(r.isFavorite, isTrue);
    expect(r.playCount, 4);
    final d = await db.select(db.downloadsTable).getSingle();
    expect(d.finalPath, 'content://media/external/audio/media/42');
    expect(song.existsSync(), isFalse);
    // Twice: already there, nothing copied again.
    expect(await service.save('dl_1'), SaveToPhoneResult.alreadyThere);
    expect(phone.saved, hasLength(1));
  });

  test('a failed copy changes nothing', () async {
    phone.fails = true;
    expect(await service.save('dl_1'), SaveToPhoneResult.failed);
    expect((await row()).uri, song.path);
    expect(song.existsSync(), isTrue);
  });

  test('old Android (no MediaStore save) refuses without touching the file', () async {
    phone.canSave = false;
    expect(await service.save('dl_1'), SaveToPhoneResult.failed);
    expect(phone.saved, isEmpty);
    expect(song.existsSync(), isTrue);
  });

  test('a file outside the downloads folder is never offered to the phone', () async {
    final outside = File(p.join(Directory.systemTemp.path, 'outside_${DateTime.now().microsecondsSinceEpoch}.mp3'))
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => outside.deleteSync());
    await (db.update(db.mediaItemsTable)..where((t) => t.id.equals('dl_1')))
        .write(MediaItemsTableCompanion(uri: Value(outside.path)));
    expect(await service.save('dl_1'), SaveToPhoneResult.notPossible);
    expect(phone.saved, isEmpty);
  });

  test('iPhone audio stays put (already in Files); video is saved to Photos and kept', () async {
    phone.answer = song.path;
    expect(await service.save('dl_1'), SaveToPhoneResult.alreadyThere);
    expect((await row()).uri, song.path);
    expect(song.existsSync(), isTrue);
    await (db.update(db.mediaItemsTable)..where((t) => t.id.equals('dl_1')))
        .write(MediaItemsTableCompanion(mediaType: Value(MediaType.video.name)));
    expect(await service.save('dl_1'), SaveToPhoneResult.saved);
    expect((await row()).uri, song.path);
  });

  test('the phone scan never shows the moved download twice', () async {
    await service.save('dl_1');
    final repo = LibraryRepositoryImpl(
      db,
      _ScanStore([
        {
          'id': '42',
          'uri': 'content://media/external/audio/media/42',
          'title': 'Resham Firiri',
          'durationMs': 200000,
          'sizeBytes': 64,
          'dateAdded': 1700000000,
        },
        {
          'id': '7',
          'uri': 'content://media/external/audio/media/7',
          'title': 'Another song',
          'durationMs': 100000,
          'sizeBytes': 10,
          'dateAdded': 1700000000,
        },
      ]),
    );
    await repo.scanDeviceMedia();
    final songs = await repo.watchSongs().first;
    expect(songs.map((s) => s.id), unorderedEquals(['dl_1', 'audio_7']));
    final favs = await repo.watchFavorites().first;
    expect(favs.single.id, 'dl_1');
    // A second scan keeps it so.
    await repo.scanDeviceMedia();
    expect((await repo.watchSongs().first).length, 2);
  });

  test('a scan row added before the move is dropped once the download claims it', () async {
    await db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
          id: 'audio_42',
          uri: 'content://media/external/audio/media/42',
          mediaType: MediaType.audio.name,
          title: 'Resham Firiri',
          durationMs: 200000,
          sizeBytes: 64,
          dateAdded: DateTime(2026),
        ));
    await service.save('dl_1');
    final repo = LibraryRepositoryImpl(db, _ScanStore(const []));
    await repo.scanDeviceMedia();
    final ids = (await db.select(db.mediaItemsTable).get()).map((r) => r.id);
    expect(ids, ['dl_1']);
  });

  group('setting', () {
    test('defaults to inside MediaHub; phone only when chosen', () async {
      expect(DownloadSaveLocation.parse(null), DownloadSaveLocation.app);
      expect(DownloadSaveLocation.parse('nonsense'), DownloadSaveLocation.app);
      expect(DownloadSaveLocation.parse('phone'), DownloadSaveLocation.phone);
    });

    test('a finished download moves only when the setting says phone', () async {
      await SettingsStore.instance.remove(DownloadSaveLocationNotifier.prefKey);
      await service.onDownloadFinished('dl_1');
      expect(phone.saved, isEmpty);
      await SettingsStore.instance.setString(DownloadSaveLocationNotifier.prefKey, 'phone');
      addTearDown(() => SettingsStore.instance.remove(DownloadSaveLocationNotifier.prefKey));
      await service.onDownloadFinished('dl_1');
      expect(phone.saved, hasLength(1));
      expect((await row()).uri, startsWith('content://'));
    });
  });

  test('canOffer: local downloads only', () {
    MediaItem item(String uri, String source) => MediaItem(
          id: 'x',
          uri: uri,
          mediaType: MediaType.audio,
          title: 't',
          durationMs: 0,
          sizeBytes: 0,
          dateAdded: DateTime(2026),
          source: source,
        );
    expect(SaveToPhoneService.canOffer(item('/a/b.mp3', 'download')), isTrue);
    expect(SaveToPhoneService.canOffer(item('content://media/external/audio/media/1', 'download')), isFalse);
    expect(SaveToPhoneService.canOffer(item('content://media/external/audio/media/1', 'device')), isFalse);
    expect(SaveToPhoneService.canOffer(item('https://youtu.be/x', 'online')), isFalse);
  });
}
