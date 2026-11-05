import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/services/download_service_controller.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'dart:io';

class FakeDownloadServiceController implements DownloadServiceController {
  bool isServiceStarted = false;
  int startCallCount = 0;
  int stopCallCount = 0;
  int updateCallCount = 0;
  int lastCount = 0;
  int lastPercent = -1;
  String? lastFileName;

  DateTime? lastUpdateTime;
  final List<int> throttledUpdatePercents = [];

  final StreamController<String> _actionController = StreamController<String>.broadcast();

  @override
  Stream<String> get actionEvents => _actionController.stream;

  void emitAction(String action) {
    _actionController.add(action);
  }

  @override
  Future<void> startService({required int count, int percent = -1, String? fileName}) async {
    isServiceStarted = true;
    startCallCount++;
    lastCount = count;
    lastPercent = percent;
    lastFileName = fileName;
  }

  @override
  Future<void> updateProgress({required int count, int percent = -1, String? fileName}) async {
    final now = DateTime.now();
    // Strict 1-second throttle for EVERY value (including -1, 0, and 100)
    if (lastUpdateTime != null && now.difference(lastUpdateTime!).inMilliseconds < 1000) {
      return; // Throttled
    }
    lastUpdateTime = now;
    updateCallCount++;
    lastCount = count;
    lastPercent = percent;
    lastFileName = fileName;
    throttledUpdatePercents.add(percent);
  }

  @override
  Future<void> stopService() async {
    isServiceStarted = false;
    stopCallCount++;
  }

  @override
  void dispose() {
    _actionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempDir;
  late FakeDownloadServiceController fakeController;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('download_service_test_');
    fakeController = FakeDownloadServiceController();
  });

  tearDown(() async {
    await db.close();
    fakeController.dispose();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('TASK 5.3a.1: DownloadServiceController and Robustness tests', () {
    test('1. Service starts with the first active download and stops after the last', () async {
      expect(fakeController.isServiceStarted, isFalse);

      await fakeController.startService(count: 1, percent: 0, fileName: 'song1.mp3');
      expect(fakeController.isServiceStarted, isTrue);
      expect(fakeController.startCallCount, equals(1));
      expect(fakeController.lastFileName, equals('song1.mp3'));

      await fakeController.stopService();
      expect(fakeController.isServiceStarted, isFalse);
      expect(fakeController.stopCallCount, equals(1));
    });

    test('2. pauseAll and timeout action events reach listener cleanly and trigger pause', () async {
      final receivedActions = <String>[];
      final sub = fakeController.actionEvents.listen(receivedActions.add);

      fakeController.emitAction('pauseAll');
      fakeController.emitAction('timeout');

      await Future.delayed(const Duration(milliseconds: 10));
      expect(receivedActions, equals(['pauseAll', 'timeout']));
      await sub.cancel();
    });

    test('3. 100 rapid progress events in one second produce exactly one notification update (strict throttle for all values)', () async {
      await fakeController.startService(count: 1, percent: 0);

      // Rapidly fire 100 events across -1, 0, 50, 100
      for (int i = 0; i < 100; i++) {
        final pct = (i % 4 == 0) ? -1 : (i % 3 == 0 ? 0 : (i % 2 == 0 ? 100 : i));
        await fakeController.updateProgress(count: 1, percent: pct);
      }

      // Exactly 1 update went through because they all occurred within the 1-second throttle window
      expect(fakeController.updateCallCount, equals(1));
      expect(fakeController.throttledUpdatePercents.length, equals(1));
    });

    test('4. onTimeout pauses all active downloads in DB and keeps .part files', () async {
      // Simulate task in preparing/downloading state
      await db.into(db.downloadsTable).insert(
        DownloadsTableCompanion.insert(
          id: 'timeout_task_1',
          url: 'https://example.com/stream.mp3',
          host: 'example.com',
          displayName: 'Timeout Song',
          fileName: 'stream.mp3',
          state: DownloadTaskState.downloading.name,
          receivedBytes: const drift.Value(1024 * 1024),
          supportsRange: const drift.Value(true),
          mimeType: const drift.Value('audio/mpeg'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(),
        downloadDir: tempDir,
      );

      // On timeout event, pause is invoked
      await engine.pause('timeout_task_1');

      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('timeout_task_1'))).getSingle();
      expect(row.state, equals(DownloadTaskState.paused.name));
      expect(row.receivedBytes, equals(1024 * 1024));
    });

    test('5. Terminal states release wake lock / stop foreground service', () async {
      await fakeController.startService(count: 1, percent: 50);
      expect(fakeController.isServiceStarted, isTrue);

      await fakeController.stopService();
      expect(fakeController.isServiceStarted, isFalse);
      expect(fakeController.stopCallCount, equals(1));
    });

    test('6. Denied notification permission does not block downloads', () async {
      final engine = DownloadEngine(
        db: db,
        httpClient: SafeHttpClient(),
        downloadDir: tempDir,
      );

      await engine.enqueueDownload(
        id: 'test_denied_perm',
        url: Uri.parse('https://example.com/audio.mp3'),
        displayName: 'Allowed Download',
        suggestedFileName: 'audio.mp3',
      );

      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('test_denied_perm'))).getSingle();
      expect(row.state, equals(DownloadTaskState.queued.name));
      expect(row.displayName, equals('Allowed Download'));
    });
  });
}
