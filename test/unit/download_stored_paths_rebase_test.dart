import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/storage/download_folder.dart';
import 'package:mediahub/data/storage/stored_path_rebase.dart';
import 'package:path/path.dart' as p;

/// iOS moves the app's whole data folder to a container with a new id on
/// every update or reinstall over the old app, while the database keeps the
/// absolute paths saved under the old id. At open the database points those
/// paths at the current folder, and only those.
const _old = '1B2C3D4E-0000-4000-8000-00000000A0A0';
const _new = '9F8E7D6C-1111-4111-8111-11111111B1B1';

void main() {
  tearDown(PlatformInfo.resetForTests);

  group('StoredPathRebaser (iPhone paths, no files on disk)', () {
    const container = '/var/mobile/Containers/Data/Application';
    const newDir = '$container/$_new/Documents/downloads';
    const oldDir = '$container/$_old/Documents/downloads';
    final present = <String>{'$newDir/a.m4a', '$newDir/a.thumb', '$newDir/clips/b.mp4'};

    StoredPathRebaser rebaser([String dir = newDir]) =>
        StoredPathRebaser(currentDownloadsDir: dir, context: p.posix, fileExists: present.contains);

    test('a path into the old container moves to the new one', () {
      expect(rebaser().rebase('$oldDir/a.m4a'), '$newDir/a.m4a');
      expect(rebaser().rebase('$oldDir/a.thumb'), '$newDir/a.thumb');
      expect(rebaser().rebase('$oldDir/clips/b.mp4'), '$newDir/clips/b.mp4');
    });

    test('the /private/var spelling of the same folder moves too', () {
      expect(rebaser().rebase('/private$oldDir/a.m4a'), '$newDir/a.m4a');
      final spelledPrivate = StoredPathRebaser(
        currentDownloadsDir: '/private$newDir',
        context: p.posix,
        fileExists: {'/private$newDir/a.m4a'}.contains,
      );
      expect(spelledPrivate.rebase('$oldDir/a.m4a'), '/private$newDir/a.m4a');
    });

    test('a file that is not in the new folder stays as it was', () {
      expect(rebaser().rebase('$oldDir/gone.mp3'), isNull);
    });

    test('a path already in the current folder is left alone (running twice changes nothing)', () {
      expect(rebaser().rebase('$newDir/a.m4a'), isNull);
    });

    test('nothing outside the downloads folder is ever rewritten', () {
      final r = rebaser();
      for (final path in [
        '$container/$_old/Documents/settings.json', // outside downloads/
        '$container/$_old/Documents/a.m4a',
        '$container/$_old/Library/downloads/a.m4a', // another folder of the app
        '/var/mobile/Media/DCIM/100APPLE/a.m4a', // the phone's own files
        '/var/mobile/Containers/Data/Other/$_old/Documents/downloads/a.m4a',
        '$container/not-a-container-id/Documents/downloads/a.m4a',
        '$oldDir/../a.m4a',
        '$oldDir/./a.m4a',
        'content://media/external/audio/media/42',
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
        'file://$oldDir/a.m4a',
        'downloads/a.m4a', // not absolute
        oldDir, // the folder itself
        '',
      ]) {
        expect(r.rebase(path), isNull, reason: path);
      }
      expect(r.rebase(null), isNull);
    });

    test('a simulator container (inside a device folder) works the same way', () {
      const sim = '/Users/me/Library/Developer/CoreSimulator/Devices/0A0A0A0A-2222-4222-8222-222222222222/data'
          '/Containers/Data/Application';
      final files = {'$sim/$_new/Documents/downloads/a.m4a'};
      final r = StoredPathRebaser(
        currentDownloadsDir: '$sim/$_new/Documents/downloads',
        context: p.posix,
        fileExists: files.contains,
      );
      expect(r.rebase('$sim/$_old/Documents/downloads/a.m4a'), '$sim/$_new/Documents/downloads/a.m4a');
      // Another simulated device is another phone: not touched.
      expect(
        r.rebase('/Users/me/Library/Developer/CoreSimulator/Devices/0B0B0B0B-3333-4333-8333-333333333333/data'
            '/Containers/Data/Application/$_old/Documents/downloads/a.m4a'),
        isNull,
      );
    });

    test('Android: the folder has no container id, so nothing is ever rewritten', () {
      final r = StoredPathRebaser(
        currentDownloadsDir: '/data/user/0/com.example.mediahub/app_flutter/downloads',
        context: p.posix,
        fileExists: (_) => true,
      );
      expect(r.canRebase, isFalse);
      expect(r.marker, isNull);
      expect(r.rebase('/data/user/0/com.example.mediahub/app_flutter/downloads/a.m4a'), isNull);
      expect(r.rebase('$oldDir/a.m4a'), isNull);
    });

    test('the query marker is the part after the container id', () {
      expect(rebaser().marker, '/Documents/downloads/');
    });
  });

  group('when the database opens (temp folders as an old and a new container)', () {
    late Directory root;
    late String oldDir;
    late String newDir;

    String containerDir(String id) =>
        p.join(root.path, 'var', 'mobile', 'Containers', 'Data', 'Application', id, 'Documents', 'downloads');

    setUp(() async {
      root = await Directory.systemTemp.createTemp('stored_paths_rebase_test_');
      oldDir = containerDir(_old);
      newDir = containerDir(_new);
      // iOS moved the files: they are in the new container only.
      Directory(p.join(newDir, 'clips')).createSync(recursive: true);
      for (final name in ['a.m4a', 'a.thumb', 'clips/v.mp4', '3.thumb']) {
        File(p.join(newDir, name)).writeAsBytesSync([1, 2, 3]);
      }
    });

    tearDown(() {
      AppDatabase.downloadsFolderTimeout = const Duration(seconds: 5);
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    MediaItemsTableCompanion media(String id, String uri, {String? art, String source = 'download'}) =>
        MediaItemsTableCompanion.insert(
          id: id,
          uri: uri,
          mediaType: 'audio',
          title: id,
          durationMs: 1000,
          sizeBytes: 3,
          dateAdded: DateTime(2026, 11, 1),
          source: Value(source),
          artworkPath: Value(art),
        );

    DownloadsTableCompanion download(String id, {String? file, String? thumb, String state = 'completed'}) =>
        DownloadsTableCompanion.insert(
          id: id,
          url: 'https://example.com/$id.mp3',
          host: 'example.com',
          displayName: id,
          fileName: '$id.mp3',
          state: state,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
          finalPath: Value(file),
          thumbnailPath: Value(thumb),
        );

    /// A database file holding paths saved under [dir] (written with no
    /// folder known, so nothing is rewritten while seeding).
    Future<File> seed(String dir) async {
      final file = File(p.join(root.path, 'media_hub_db.sqlite'));
      final db = AppDatabase(NativeDatabase(file), () async => null);
      await db.batch((b) {
        b.insertAll(db.mediaItemsTable, [
          media('dl_1', p.join(dir, 'a.m4a'), art: p.join(dir, 'a.thumb')),
          media('dl_2', p.join(dir, 'clips', 'v.mp4')),
          media('dl_gone', p.join(dir, 'gone.mp3'), art: p.join(dir, 'gone.thumb')),
          media('dev_1', 'content://media/external/audio/media/42', source: 'device'),
          media('yt_dQw4w9WgXcQ', 'https://youtu.be/dQw4w9WgXcQ',
              art: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg', source: 'online'),
        ]);
        b.insertAll(db.downloadsTable, [
          download('1', file: p.join(dir, 'a.m4a'), thumb: p.join(dir, 'a.thumb')),
          download('2', file: p.join(dir, 'clips', 'v.mp4')),
          download('3', thumb: p.join(dir, '3.thumb'), state: 'paused'),
          download('4', file: p.join(dir, 'gone.mp3')),
        ]);
        b.insertAll(db.playbackStatesTable, [
          // Today's format: ids only (they follow the library rows).
          PlaybackStatesTableCompanion.insert(
            id: const Value(1),
            queueJson: jsonEncode({
              'queue': ['dl_1', 'dl_2'],
              'original': ['dl_1', 'dl_2'],
            }),
            updatedAt: DateTime(2026, 11, 1),
          ),
          // The old format kept whole items, paths included.
          PlaybackStatesTableCompanion.insert(
            id: const Value(2),
            queueJson: jsonEncode([
              {'id': 'dl_1', 'uri': p.join(dir, 'a.m4a'), 'artworkPath': p.join(dir, 'a.thumb')},
              {'id': 'dev_1', 'uri': 'content://media/external/audio/media/42', 'artworkPath': null},
            ]),
            updatedAt: DateTime(2026, 10, 1),
          ),
        ]);
      });
      await db.close();
      return file;
    }

    Future<Map<String, Object?>> snapshot(AppDatabase db) async => {
          for (final r in await db.select(db.mediaItemsTable).get()) 'media ${r.id}': [r.uri, r.artworkPath],
          for (final r in await db.select(db.downloadsTable).get()) 'download ${r.id}': [r.finalPath, r.thumbnailPath],
          for (final r in await db.select(db.playbackStatesTable).get()) 'queue ${r.id}': r.queueJson,
        };

    test('every saved path into the old container points at the new one by the first read', () async {
      final file = await seed(oldDir);
      final db = AppDatabase(NativeDatabase(file), () async => newDir);
      addTearDown(db.close);

      final rows = await snapshot(db);
      expect(rows['media dl_1'], [p.join(newDir, 'a.m4a'), p.join(newDir, 'a.thumb')]);
      expect(rows['media dl_2'], [p.join(newDir, 'clips', 'v.mp4'), null]);
      expect(rows['download 1'], [p.join(newDir, 'a.m4a'), p.join(newDir, 'a.thumb')]);
      expect(rows['download 2'], [p.join(newDir, 'clips', 'v.mp4'), null]);
      expect(rows['download 3'], [null, p.join(newDir, '3.thumb')], reason: 'an unfinished download keeps its cover');

      // A file that did not come along stays as it was (shown as missing).
      expect(rows['media dl_gone'], [p.join(oldDir, 'gone.mp3'), p.join(oldDir, 'gone.thumb')]);
      expect(rows['download 4'], [p.join(oldDir, 'gone.mp3'), null]);

      // Phone songs and online items are never touched.
      expect(rows['media dev_1'], ['content://media/external/audio/media/42', null]);
      expect(rows['media yt_dQw4w9WgXcQ'],
          ['https://youtu.be/dQw4w9WgXcQ', 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg']);

      // The saved queue: ids stay ids; the old whole-item format is moved.
      expect(jsonDecode(rows['queue 1']! as String), {
        'queue': ['dl_1', 'dl_2'],
        'original': ['dl_1', 'dl_2'],
      });
      final legacy = jsonDecode(rows['queue 2']! as String) as List;
      expect(legacy[0], {'id': 'dl_1', 'uri': p.join(newDir, 'a.m4a'), 'artworkPath': p.join(newDir, 'a.thumb')});
      expect(legacy[1], {'id': 'dev_1', 'uri': 'content://media/external/audio/media/42', 'artworkPath': null});
    });

    test('opening again changes nothing (idempotent)', () async {
      final file = await seed(oldDir);
      final first = AppDatabase(NativeDatabase(file), () async => newDir);
      final afterFirst = await snapshot(first);
      await first.close();

      final second = AppDatabase(NativeDatabase(file), () async => newDir);
      addTearDown(second.close);
      expect(await snapshot(second), afterFirst);
      expect(await second.rebaseStoredPaths(StoredPathRebaser(currentDownloadsDir: newDir)), 0);
      expect(await snapshot(second), afterFirst);
    });

    test('a second move (another update) follows the files again', () async {
      final file = await seed(oldDir);
      final first = AppDatabase(NativeDatabase(file), () async => newDir);
      await snapshot(first);
      await first.close();

      // The next update moves everything once more.
      const third = 'ABCDEF01-2345-4678-89AB-CDEF01234567';
      final thirdDir = containerDir(third);
      Directory(p.dirname(thirdDir)).createSync(recursive: true);
      Directory(newDir).renameSync(thirdDir);

      final db = AppDatabase(NativeDatabase(file), () async => thirdDir);
      addTearDown(db.close);
      final rows = await snapshot(db);
      expect(rows['media dl_1'], [p.join(thirdDir, 'a.m4a'), p.join(thirdDir, 'a.thumb')]);
      expect(rows['download 2'], [p.join(thirdDir, 'clips', 'v.mp4'), null]);
    });

    test('Android: paths do not move, and nothing is rewritten', () async {
      final androidDir = p.join(root.path, 'data', 'user', '0', 'com.example.mediahub', 'app_flutter', 'downloads');
      Directory(p.join(androidDir, 'clips')).createSync(recursive: true);
      for (final name in ['a.m4a', 'a.thumb', 'clips/v.mp4', '3.thumb']) {
        File(p.join(androidDir, name)).writeAsBytesSync([1, 2, 3]);
      }
      final file = await seed(androidDir);
      final seeded = AppDatabase(NativeDatabase(file), () async => null);
      final before = await snapshot(seeded);
      await seeded.close();

      final db = AppDatabase(NativeDatabase(file), () async => androidDir);
      addTearDown(db.close);
      expect(await snapshot(db), before);
      expect(await db.rebaseStoredPaths(StoredPathRebaser(currentDownloadsDir: androidDir)), 0);
    });

    test('Android: the database never even asks where downloads are', () async {
      PlatformInfo.debugIsAndroid = true;
      PlatformInfo.debugIsIOS = false;
      expect(await downloadsFolderToHealPaths(), isNull);
    });

    test('a folder lookup that fails or never answers does not keep the database from opening', () async {
      final file = await seed(oldDir);
      AppDatabase.downloadsFolderTimeout = const Duration(milliseconds: 100);

      final failing = AppDatabase(NativeDatabase(file), () async => throw StateError('no folder'));
      expect((await failing.select(failing.mediaItemsTable).get()).length, 5);
      await failing.close();

      final hanging = AppDatabase(NativeDatabase(file), () => Completer<String?>().future);
      addTearDown(hanging.close);
      final rows = await snapshot(hanging);
      expect(rows['media dl_1'], [p.join(oldDir, 'a.m4a'), p.join(oldDir, 'a.thumb')], reason: 'left for the next start');
    });
  });
}
