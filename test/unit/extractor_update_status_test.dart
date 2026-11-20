import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/personal/extractor_auto_updater.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';

import 'fake_extractor_backend.dart';

/// Update / reset answers scripted per test.
class _Backend extends FakeExtractorBackend {
  String updateStatus = 'DONE';
  Object? updateError;
  Object? resetError;

  @override
  Future<String> update() async {
    final e = updateError;
    if (e != null) throw e;
    currentVersion = '2026.11.15';
    return updateStatus;
  }

  @override
  Future<void> resetToBundled() async {
    final e = resetError;
    if (e != null) throw e;
    await super.resetToBundled();
  }
}

void main() {
  late _Backend backend;
  late ProviderContainer container;

  late ExtractorAutoUpdater updater;

  setUp(() {
    backend = _Backend();
    // Its own settings file: update times never leak into other tests.
    updater = ExtractorAutoUpdater(backend: backend, store: SettingsStore.forTesting(), enabled: () => true);
    container = ProviderContainer(overrides: [
      extractorBackendProvider.overrideWithValue(backend),
      extractorAutoUpdaterProvider.overrideWithValue(updater),
    ]);
  });

  tearDown(() => container.dispose());

  PersonalToolsNotifier tools() => container.read(personalToolsProvider.notifier);
  PersonalToolsState state() => container.read(personalToolsProvider);

  group('yt-dlp update status, in plain words (SEC-10)', () {
    test('a new version: "Updated to <version>"', () async {
      await tools().updateYtDlp();
      expect(state().updateStatus, 'Updated to 2026.11.15');
      expect(state().updateFailed, isFalse);
      expect(state().ytDlpVersion, '2026.11.15');
      expect(state().isUpdating, isFalse);
    });

    test('nothing new: "Already up to date"', () async {
      backend.updateStatus = 'ALREADY_UP_TO_DATE';
      await tools().updateYtDlp();
      expect(state().updateStatus, 'Already up to date');
      expect(state().updateFailed, isFalse);
    });

    test('a failure says what to do, not an exception dump', () async {
      backend.updateError = const ExtractorException('UPDATE_ERROR', 'java.net.UnknownHostException: github.com');
      await tools().updateYtDlp();
      expect(state().updateStatus, 'Could not update. Check your connection.');
      expect(state().updateFailed, isTrue);
      expect(state().updateStatus, isNot(contains('Exception')));
    });

    test('busy with a download: wait for it (the native side refuses)', () async {
      backend.updateError = const ExtractorException('BUSY', 'Wait for the current downloads to finish first');
      await tools().updateYtDlp();
      expect(state().updateStatus, PersonalToolsNotifier.busyMessage);
      expect(state().updateFailed, isTrue);

      backend.resetError = const ExtractorException('BUSY', 'Wait for the current downloads to finish first');
      await tools().resetYtDlp();
      expect(state().updateStatus, PersonalToolsNotifier.busyMessage);
      expect(backend.resetCalls, 0);
    });

    test('reset: restored, or a plain failure', () async {
      await tools().resetYtDlp();
      expect(state().updateStatus, 'Restored the built-in yt-dlp');
      expect(state().updateFailed, isFalse);
      expect(state().ytDlpVersion, '2025.10.22');

      backend.resetError = StateError('disk');
      await tools().resetYtDlp();
      expect(state().updateStatus, PersonalToolsNotifier.restoreFailedMessage);
      expect(state().updateFailed, isTrue);
    });

    test('a second press while one runs does nothing', () async {
      final gate = Completer<void>();
      final slow = _SlowBackend(gate);
      final c = ProviderContainer(overrides: [extractorBackendProvider.overrideWithValue(slow)]);
      addTearDown(c.dispose);
      final first = c.read(personalToolsProvider.notifier).updateYtDlp();
      await c.read(personalToolsProvider.notifier).updateYtDlp();
      await c.read(personalToolsProvider.notifier).resetYtDlp();
      gate.complete();
      await first;
      expect(slow.updates, 1);
      expect(slow.resetCalls, 0);
    });
  });

  group('Settings shows when yt-dlp was last updated (it updates itself now)', () {
    final now = DateTime(2026, 11, 19, 18);

    test('the version line', () {
      String line({DateTime? updated, DateTime? checked, String v = '2026.11.10'}) =>
          PersonalToolsState.formatVersionLine(v, lastUpdated: updated, lastChecked: checked, now: now);
      expect(line(v: ''), 'Loading...');
      expect(line(), '2026.11.10');
      expect(line(updated: now), '2026.11.10 · Updated today');
      expect(line(updated: now.subtract(const Duration(days: 1))), '2026.11.10 · Updated yesterday');
      expect(line(updated: DateTime(2026, 11, 16, 23)), '2026.11.10 · Updated 3 days ago');
      expect(line(updated: DateTime(2026, 10, 2)), '2026.11.10 · Updated on 2 Oct 2026');
      // Checked after the last update: the version is the newest.
      expect(line(updated: DateTime(2026, 10, 2), checked: now), '2026.11.10 · Checked today');
      expect(line(checked: now), '2026.11.10 · Checked today');
      // The same update and check: "Updated".
      expect(line(updated: now, checked: now), '2026.11.10 · Updated today');
    });

    test('Update in Settings is remembered', () async {
      expect(state().lastUpdated, isNull);
      await tools().updateYtDlp();
      expect(state().lastUpdated, isNotNull);
      expect(state().lastChecked, isNotNull);
      expect(state().versionLine(), '2026.11.15 · Updated today');
    });

    test('an update MediaHub did by itself shows up without a restart', () async {
      expect(state().lastUpdated, isNull);
      expect(await updater.updateAfterFailure(), ExtractorUpdateOutcome.updated);
      expect(state().lastUpdated, isNotNull);
      expect(state().updateStatus, isNull, reason: 'no status line for a quiet update');
    });
  });

  group('web link downloads running (Update / Reset stay off meanwhile)', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dir = await Directory.systemTemp.createTemp('extractor_running_');
    });

    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('the runner reports each start and end', () async {
      final reports = <int>[];
      final gate = Completer<void>();
      final fake = FakeExtractorBackend()..blockDownload = gate;
      final runner = ExtractorDownloadRunner(
        db: db,
        backend: fake,
        downloadDir: dir,
        publish: (_) {},
        onRunningChanged: reports.add,
      );
      final meta = FakeExtractorBackend.sampleMetadata();
      final choice = FormatOptions.build(meta).firstWhere((c) => c.id == 'v1080');
      final id = await runner.enqueue(meta: meta, pageUrl: 'https://www.youtube.com/watch?v=abc', choice: choice);
      final run = runner.run(id);
      expect(reports, [1], reason: 'reported as the run starts');
      // Wait until yt-dlp is "downloading" (the gate holds it there).
      for (var i = 0; i < 200 && fake.downloadCalls.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(fake.downloadCalls, hasLength(1));
      expect(reports, [1]);
      expect(runner.runningCount, 1);
      gate.complete();
      await run;
      expect(reports, [1, 0]);
      expect(runner.runningCount, 0);
    });

    test('the provider holds the count Settings reads', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(extractorRunningDownloadsProvider), 0);
      c.read(extractorRunningDownloadsProvider.notifier).set(2);
      expect(c.read(extractorRunningDownloadsProvider), 2);
      c.read(extractorRunningDownloadsProvider.notifier).set(-1);
      expect(c.read(extractorRunningDownloadsProvider), 0);
    });
  });
}

class _SlowBackend extends FakeExtractorBackend {
  _SlowBackend(this.gate);
  final Completer<void> gate;
  int updates = 0;

  @override
  Future<String> update() async {
    updates++;
    await gate.future;
    return 'DONE';
  }
}
