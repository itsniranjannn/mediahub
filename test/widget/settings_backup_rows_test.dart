// Settings → Backup & restore (save / restore through the system file picker)
// and Settings → Downloads → "Ask before big downloads on mobile data".
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform/backup_file_picker.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/backup/library_backup.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart' show databaseProvider;
import 'package:mediahub/features/downloads/mobile_data_guard.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/settings/backup_restore.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../unit/fake_extractor_backend.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

MusicAudioHandler _handler() {
  final p = _MockAudioPlayer();
  when(() => p.playbackEventStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playerStateStream).thenAnswer((_) => const Stream.empty());
  when(() => p.currentIndexStream).thenAnswer((_) => const Stream.empty());
  when(() => p.positionStream).thenAnswer((_) => const Stream.empty());
  when(() => p.durationStream).thenAnswer((_) => const Stream.empty());
  when(() => p.dispose()).thenAnswer((_) async {});
  return MusicAudioHandler(player: p);
}

class _FakePicker implements BackupFilePicker {
  @override
  bool get isSupported => PlatformInfo.isAndroid || PlatformInfo.isIOS;
  Uint8List? saved;
  String? savedName;
  Uint8List? toOpen;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    savedName = fileName;
    saved = bytes;
    return true;
  }

  @override
  Future<Uint8List?> open({required int maxBytes}) async => toOpen;
}

void main() {
  setUpAll(() => DiagnosticsService.enableDebounce = false);
  tearDown(PlatformInfo.resetForTests);

  Future<(ProviderContainer, _FakePicker, AppDatabase)> pump(WidgetTester tester) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final db = AppDatabase(NativeDatabase.memory(), () async => null);
    addTearDown(db.close);
    final picker = _FakePicker();
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      extractorBackendProvider.overrideWithValue(FakeExtractorBackend()),
      databaseProvider.overrideWithValue(db),
      backupFilePickerProvider.overrideWithValue(picker),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 11000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsSectionPage.combined([SettingsSection.backup, SettingsSection.downloads])),
    ));
    await tester.pumpAndSettle();
    return (container, picker, db);
  }

  testWidgets('Android: backup rows and the mobile-data switch (on by default)', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await SettingsStore.instance.remove(AskBeforeBigDownloadsNotifier.prefKey);
    final (container, _, _) = await pump(tester);

    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Save a backup'), findsOneWidget);
    expect(find.text('Restore from backup'), findsOneWidget);
    final row = find.widgetWithText(SwitchListTile, 'Ask before big downloads on mobile data');
    expect(row, findsOneWidget);
    expect(tester.widget<SwitchListTile>(row).value, isTrue);
    await tester.tap(row);
    await tester.pump();
    expect(container.read(askBeforeBigDownloadsProvider), isFalse);
    expect(SettingsStore.instance.getBool(AskBeforeBigDownloadsNotifier.prefKey, defaultValue: true), isFalse);
    await SettingsStore.instance.remove(AskBeforeBigDownloadsNotifier.prefKey);
  });

  testWidgets('iPhone: backup rows and the mobile-data switch too', (tester) async {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
    await pump(tester);
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Save a backup'), findsOneWidget);
    expect(find.text('Restore from backup'), findsOneWidget);
    expect(find.text('Android only for now'), findsNothing);
    expect(find.text('Not on this device'), findsNothing);
    expect(find.text('Ask before big downloads on mobile data'), findsOneWidget);
  });

  testWidgets('no system file picker: a plain message instead of the rows', (tester) async {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = false;
    await pump(tester);
    expect(find.text('Save a backup'), findsNothing);
    expect(find.text('Not on this device'), findsOneWidget);
  });

  testWidgets('Save a backup hands a versioned JSON file to the picker', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    final (_, picker, db) = await pump(tester);
    await tester.runAsync(() => db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
          id: 'audio_1',
          uri: 'content://x',
          mediaType: 'audio',
          title: 'Song',
          durationMs: 1000,
          sizeBytes: 10,
          dateAdded: DateTime(2026),
          isFavorite: const Value(true),
        )));
    await tester.tap(find.text('Save a backup'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(picker.savedName, startsWith('mediahub-backup-'));
    final json = jsonDecode(utf8.decode(picker.saved!)) as Map<String, dynamic>;
    expect(json['app'], LibraryBackup.appId);
    expect(json['schemaVersion'], 1);
    expect((json['items'] as List).single['title'], 'Song');
    expect(find.text('Backup saved'), findsOneWidget);
  });

  testWidgets('Restore asks first, then reports what was found', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    final (_, picker, db) = await pump(tester);
    await tester.runAsync(() => db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
          id: 'audio_1',
          uri: 'content://x',
          mediaType: 'audio',
          title: 'Song',
          durationMs: 1000,
          sizeBytes: 10,
          dateAdded: DateTime(2026),
        )));
    picker.toOpen = Uint8List.fromList(utf8.encode(jsonEncode({
      'app': LibraryBackup.appId,
      'schemaVersion': 1,
      'createdAt': '2026-11-23T10:00:00.000Z',
      'items': [
        {'id': 'audio_1', 'type': 'audio', 'title': 'Song', 'size': 10, 'durationMs': 1000, 'favorite': true},
        {'id': 'audio_2', 'type': 'audio', 'title': 'Gone', 'size': 11, 'durationMs': 1000, 'favorite': true},
      ],
    })));

    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('2 favourites'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Backup restored'), findsOneWidget);
    expect(find.textContaining('1 of 2 favourites restored'), findsOneWidget);
    final row = await tester.runAsync(() => db.select(db.mediaItemsTable).getSingle());
    expect(row!.isFavorite, isTrue);
  });

  testWidgets('Restore of a bad file says so and changes nothing', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    final (_, picker, _) = await pump(tester);
    picker.toOpen = Uint8List.fromList(utf8.encode('{"app":"x"}'));
    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    expect(find.text('Restore this backup?'), findsNothing);
    expect(find.text('This file is not a MediaHub backup.'), findsOneWidget);
  });

  // Emulator QA: the confirm dialog named favourites and playlists only,
  // while the result dialog also listed play counts, positions and settings.
  test('the confirm dialog lists everything a restore brings back', () {
    final t = DateTime(2026, 11, 23, 12);
    final summary = restoreSummary(BackupData(
      createdAt: t,
      items: [
        BackupItem(id: 'a', mediaType: 'audio', title: 'A', sizeBytes: 1, durationMs: 1, favorite: true, playCount: 3),
        BackupItem(id: 'b', mediaType: 'audio', title: 'B', sizeBytes: 1, durationMs: 1, favorite: true),
        BackupItem(id: 'c', mediaType: 'audio', title: 'C', sizeBytes: 1, durationMs: 1, lastPlayed: t),
      ],
      playlists: const [BackupPlaylist(name: 'Road trip', itemIds: ['a', 'b', 'c'])],
      videoPositions: [BackupVideoPosition(itemId: 'v', positionMs: 1000, durationMs: 9000, updatedAt: t)],
      settings: const {'a': true, 'b': false, 'c': <String>['x']},
    ));
    expect(summary, contains('2 favourites'));
    expect(summary, contains('1 playlist (3 songs)'));
    expect(summary, contains('2 play counts'));
    expect(summary, contains('1 video position'));
    expect(summary, contains('3 settings'));
    expect(summary, contains('Nothing on this phone is removed.'));

    final empty = restoreSummary(BackupData(createdAt: t, items: const [], playlists: const [], videoPositions: const [], settings: const {}));
    expect(empty, contains('Nothing to restore.'));
  });
}
