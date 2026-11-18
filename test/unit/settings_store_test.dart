import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mediahub_settings_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File settingsFile() => File('${dir.path}/${SettingsStore.fileName}');
  File tmpFile() => File('${dir.path}/${SettingsStore.fileName}.tmp');
  File badFile() => File('${dir.path}/${SettingsStore.fileName}.bad');

  Future<Map<String, dynamic>> readJson() async =>
      Map<String, dynamic>.from(jsonDecode(await settingsFile().readAsString()) as Map);

  Future<SettingsStore> loadedStore() async {
    final store = SettingsStore.forTesting();
    await store.loadFromDirectory(dir);
    return store;
  }

  group('in-memory mode (never loaded, as in the other tests)', () {
    test('keeps values in memory and writes no file', () async {
      final store = SettingsStore.forTesting();
      expect(store.getBool('a'), isFalse);
      expect(store.getBool('a', defaultValue: true), isTrue);
      expect(store.getStringList('l'), isEmpty);

      await store.setBool('a', true);
      await store.setStringList('l', ['x', 'y']);

      expect(store.getBool('a'), isTrue);
      expect(store.getStringList('l'), ['x', 'y']);
    });

    test('strings: missing or wrongly typed read null, a set one reads back', () async {
      final store = SettingsStore.forTesting();
      expect(store.getString('library.audio.sort'), isNull);
      await store.setString('library.audio.sort', 'album');
      expect(store.getString('library.audio.sort'), 'album');
      await store.setBool('flag', true);
      expect(store.getString('flag'), isNull, reason: 'a bool is not a string');
    });

    test('a list passed to setStringList is copied', () async {
      final store = SettingsStore.forTesting();
      final list = ['one'];
      await store.setStringList('l', list);
      list.add('two');
      expect(store.getStringList('l'), ['one']);
    });
  });

  group('on disk', () {
    test('no file yet: defaults, then the first save creates settings.json', () async {
      final store = await loadedStore();
      expect(store.getBool('flag', defaultValue: true), isTrue);
      expect(settingsFile().existsSync(), isFalse, reason: 'loading alone writes nothing');

      await store.setBool('flag', false);
      await store.setStringList('history', ['jazz', 'lofi']);

      expect(await readJson(), {
        'flag': false,
        'history': ['jazz', 'lofi'],
      });
      expect(tmpFile().existsSync(), isFalse, reason: 'the temp file is renamed over settings.json');
    });

    test('values survive a restart (a new store loading the same folder)', () async {
      final first = await loadedStore();
      await first.setBool('flag', true);
      await first.setStringList('history', ['a', 'b']);
      await first.setString('library.audio.sort', 'mostPlayed');

      final second = await loadedStore();
      expect(second.getBool('flag'), isTrue);
      expect(second.getStringList('history'), ['a', 'b']);
      expect(second.getString('library.audio.sort'), 'mostPlayed');
    });

    test('wrongly typed values fall back to the defaults', () async {
      await settingsFile().writeAsString(jsonEncode({'flag': 'yes', 'history': 'not a list'}));
      final store = await loadedStore();
      expect(store.getBool('flag', defaultValue: true), isTrue);
      expect(store.getStringList('history'), isEmpty);
    });

    test('overlapping writes are serialized and the latest state wins', () async {
      final store = await loadedStore();
      // Fire-and-forget, like the notifiers do.
      final pending = <Future<void>>[
        for (var i = 0; i < 25; i++) store.setStringList('history', ['q$i']),
        store.setBool('flag', true),
        store.setBool('flag', false),
      ];
      await Future.wait(pending);

      expect(await readJson(), {
        'history': ['q24'],
        'flag': false,
      });
      expect(tmpFile().existsSync(), isFalse);
    });

    test('a change made while a write is in progress is stored by the next write', () async {
      final store = await loadedStore();
      final first = store.setBool('flag', true);
      // Let the first write start: it has taken its snapshot and is now
      // waiting on the disk, so 'history' below is not part of it.
      await Future<void>.delayed(Duration.zero);
      final second = store.setStringList('history', ['later']);

      await Future.wait([first, second]);
      expect(await readJson(), {
        'flag': true,
        'history': ['later'],
      });
      expect(tmpFile().existsSync(), isFalse);
    });

    test('a stale settings.json.tmp from a killed write does not affect loading', () async {
      await settingsFile().writeAsString(jsonEncode({'flag': true}));
      await tmpFile().writeAsString('{"flag": fa'); // cut off mid-write
      final store = await loadedStore();
      expect(store.getBool('flag'), isTrue);
      expect(badFile().existsSync(), isFalse);

      await store.setBool('other', true);
      expect(await readJson(), {'flag': true, 'other': true});
      expect(tmpFile().existsSync(), isFalse);
    });

    test('a corrupt settings.json is moved to settings.json.bad, then defaults are used', () async {
      const corrupt = '{"flag": true, "history": ["a"'; // truncated JSON
      await settingsFile().writeAsString(corrupt);

      final store = await loadedStore();
      expect(store.getBool('flag'), isFalse, reason: 'defaults');
      expect(store.getStringList('history'), isEmpty);
      expect(badFile().readAsStringSync(), corrupt, reason: 'kept for inspection');
      expect(settingsFile().existsSync(), isFalse);

      await store.setBool('flag', true);
      expect(await readJson(), {'flag': true});
      expect(badFile().readAsStringSync(), corrupt, reason: 'a save never overwrites the bad copy');
    });

    test('a corrupt settings.json that cannot be kept aside is never overwritten', () async {
      const corrupt = '{"flag": tr';
      await settingsFile().writeAsString(corrupt);
      // A folder where settings.json.bad would go: neither moving nor
      // copying the corrupt file there can work.
      await Directory('${badFile().path}/occupied').create(recursive: true);

      final store = await loadedStore();
      expect(store.getBool('flag'), isFalse, reason: 'defaults');

      await store.setBool('flag', true);
      expect(store.getBool('flag'), isTrue, reason: 'kept in memory for this session');
      expect(settingsFile().readAsStringSync(), corrupt);
      expect(tmpFile().existsSync(), isFalse);
    });

    test('an empty settings.json counts as corrupt', () async {
      await settingsFile().writeAsString('');
      final store = await loadedStore();
      expect(store.getStringList('history'), isEmpty);
      expect(badFile().existsSync(), isTrue);
      expect(settingsFile().existsSync(), isFalse);
    });

    test('JSON that is not an object counts as corrupt', () async {
      await settingsFile().writeAsString('["flag", true]');
      final store = await loadedStore();
      expect(store.getBool('flag'), isFalse);
      expect(badFile().readAsStringSync(), '["flag", true]');
    });

    test('invalid UTF-8 counts as corrupt', () async {
      await settingsFile().writeAsBytes([0x7B, 0xFF, 0xFE, 0x7D]);
      final store = await loadedStore();
      expect(store.getBool('flag'), isFalse);
      expect(badFile().readAsBytesSync(), [0x7B, 0xFF, 0xFE, 0x7D]);
    });
  });
}
