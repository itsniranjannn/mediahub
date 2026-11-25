// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// iPhone: settings.json, the database and diagnostics.log move once from the
// Files-visible Documents folder to Application Support; the downloads stay.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/app_private_dir.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/online/online_web_view.dart' show isOnlineBridgeOrigin;
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory docs;
  late Directory support;

  setUp(() {
    root = Directory.systemTemp.createTempSync('private_dir');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'Library', 'Application Support'));
    debugDocumentsDir = () async => docs;
    debugPrivateDataDir = () async => support;
  });

  tearDown(() {
    debugDocumentsDir = null;
    debugPrivateDataDir = null;
    PlatformInfo.resetForTests();
    root.deleteSync(recursive: true);
  });

  test('moves settings, database and log out of Documents; downloads stay', () async {
    for (final name in ['settings.json', 'diagnostics.log', 'media_hub_db.sqlite', 'media_hub_db.sqlite-wal']) {
      File(p.join(docs.path, name)).writeAsStringSync(name);
    }
    final song = File(p.join(docs.path, 'downloads', 'song.mp3'))
      ..createSync(recursive: true)
      ..writeAsStringSync('audio');

    expect(await migratePrivateFilesOutOfDocuments(), 4);

    for (final name in ['settings.json', 'diagnostics.log', 'media_hub_db.sqlite', 'media_hub_db.sqlite-wal']) {
      expect(File(p.join(docs.path, name)).existsSync(), isFalse, reason: name);
      expect(File(p.join(support.path, name)).readAsStringSync(), name);
    }
    expect(song.existsSync(), isTrue, reason: 'user-visible music stays in Documents');
    expect(await migratePrivateFilesOutOfDocuments(), 0, reason: 'one time: nothing left to move');
  });

  test('a file already in Application Support wins; the Documents copy goes', () async {
    support.createSync(recursive: true);
    File(p.join(support.path, 'settings.json')).writeAsStringSync('{"new":true}');
    File(p.join(docs.path, 'settings.json')).writeAsStringSync('{"app_lock_enabled":false}');
    expect(await migratePrivateFilesOutOfDocuments(), 0);
    expect(File(p.join(support.path, 'settings.json')).readAsStringSync(), '{"new":true}');
    expect(File(p.join(docs.path, 'settings.json')).existsSync(), isFalse);
  });

  test('the App lock switch is read from Application Support, not Documents', () async {
    support.createSync(recursive: true);
    File(p.join(support.path, 'settings.json')).writeAsStringSync('{"app_lock_enabled":true}');
    // An edited copy where the Files app can reach it is ignored.
    File(p.join(docs.path, 'settings.json')).writeAsStringSync('{"app_lock_enabled":false}');
    PlatformInfo.debugIsIOS = true;
    final store = SettingsStore.forTesting();
    await store.loadFromDirectory(await appPrivateDataDir());
    expect(store.getBool('app_lock_enabled'), isTrue);
  });

  test('moveFiles does nothing when both folders are the same', () async {
    File(p.join(docs.path, 'settings.json')).writeAsStringSync('x');
    expect(await moveFiles(from: docs, to: docs, names: privateFileNames), 0);
    expect(File(p.join(docs.path, 'settings.json')).existsSync(), isTrue);
  });

  test('the YouTube bridge only answers YouTube pages over HTTPS', () {
    expect(isOnlineBridgeOrigin(Uri.parse('https://m.youtube.com/watch?v=x')), isTrue);
    expect(isOnlineBridgeOrigin(Uri.parse('https://youtube.com/')), isTrue);
    expect(isOnlineBridgeOrigin(Uri.parse('http://m.youtube.com/')), isFalse);
    expect(isOnlineBridgeOrigin(Uri.parse('https://youtube.com.evil.example/')), isFalse);
    expect(isOnlineBridgeOrigin(Uri.parse('https://evilyoutube.com/')), isFalse);
    expect(isOnlineBridgeOrigin(Uri.parse('https://googleads.g.doubleclick.net/')), isFalse);
    expect(isOnlineBridgeOrigin(null), isFalse);
  });
}
