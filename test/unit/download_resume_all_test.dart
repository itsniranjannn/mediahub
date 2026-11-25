// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
// The download notification's "Pause all" leaves a "N downloads paused"
// notification, and its "Resume all" queues every paused download again.
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/services/download_service_controller.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_progress.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart' show appDatabaseProvider;

import 'download_service_controller_test.dart' show FakeDownloadServiceController;

/// Records pause / run calls; nothing touches the network or disk.
class _Engine extends Fake implements DownloadEngine {
  _Engine(this.db);
  final AppDatabase db;
  final List<String> paused = [];
  final List<String> ran = [];

  @override
  Stream<DownloadProgressUpdate> get progressStream => const Stream.empty();

  @override
  Future<void> pause(String id) async {
    paused.add(id);
    await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
        .write(DownloadsTableCompanion(state: drift.Value(DownloadTaskState.paused.name)));
  }

  @override
  Future<void> runTask(String id) async {
    ran.add(id);
    await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
        .write(DownloadsTableCompanion(state: drift.Value(DownloadTaskState.completed.name)));
  }
}

void main() {
  late AppDatabase db;
  late _Engine engine;
  late FakeDownloadServiceController service;
  late ProviderContainer container;

  Future<void> insert(String id, DownloadTaskState state) => db.into(db.downloadsTable).insert(
        DownloadsTableCompanion.insert(
          id: id,
          url: 'https://example.com/$id.mp3',
          host: 'example.com',
          displayName: id,
          fileName: '$id.mp3',
          state: state.name,
          receivedBytes: const drift.Value(4096),
          supportsRange: const drift.Value(true),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

  Future<String> stateOf(String id) async =>
      (await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle()).state;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    engine = _Engine(db);
    service = FakeDownloadServiceController();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      downloadEngineProvider.overrideWithValue(engine),
      downloadServiceControllerProvider.overrideWithValue(service),
    ]);
    container.read(downloadQueueCoordinatorProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('Pause all pauses every active download and leaves the paused notification', () async {
    await insert('a', DownloadTaskState.downloading);
    await insert('b', DownloadTaskState.queued);
    service.emitAction(DownloadServiceActions.pauseAll);
    await pumpEventQueue();
    expect(engine.paused, unorderedEquals(['a', 'b']));
    expect(await stateOf('a'), DownloadTaskState.paused.name);
    expect(service.pausedNoticeCount, 2);
  });

  test('Pause all with nothing running shows no paused notification', () async {
    service.emitAction(DownloadServiceActions.pauseAll);
    await pumpEventQueue();
    expect(service.pausedNoticeCount, -1);
  });

  test('Resume all queues every paused download again and runs them', () async {
    await insert('a', DownloadTaskState.paused);
    await insert('b', DownloadTaskState.paused);
    await insert('c', DownloadTaskState.completed);
    service.emitAction(DownloadServiceActions.resumeAll);
    await pumpEventQueue();
    expect(engine.ran, unorderedEquals(['a', 'b']));
    expect(await stateOf('c'), DownloadTaskState.completed.name);
    expect(service.hidePausedCount, 1);
  });
}
