import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/personal/extractor_auto_updater.dart';
import 'package:mediahub/personal/extractor_backend.dart';

import 'fake_extractor_backend.dart';

/// Update answers scripted per test.
class _Backend extends FakeExtractorBackend {
  String status = 'DONE';
  Object? error;
  Completer<void>? gate;

  @override
  Future<String> update() async {
    updateCalls++;
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return status;
  }
}

void main() {
  late _Backend backend;
  late SettingsStore store;
  late DateTime now;
  late bool android;

  ExtractorAutoUpdater updater({bool background = true}) => ExtractorAutoUpdater(
        backend: backend,
        store: store,
        clock: () => now,
        enabled: () => android,
        backgroundChecks: background,
      );

  setUp(() {
    backend = _Backend();
    store = SettingsStore.forTesting();
    now = DateTime(2026, 11, 19, 10);
    android = true;
  });

  group('after a failure', () {
    test('updates and says so: worth trying the link again', () async {
      final u = updater();
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.updated);
      expect(backend.updateCalls, 1);
      expect(u.lastUpdated, now);
      expect(u.lastChecked, now);
    });

    test('at most once every 12 hours', () async {
      final u = updater();
      await u.updateAfterFailure();
      now = now.add(const Duration(hours: 11, minutes: 59));
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 1);

      now = now.add(const Duration(minutes: 2));
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.updated);
      expect(backend.updateCalls, 2);
    });

    test('a failed try (offline) also waits 12 hours; nothing new means no retry', () async {
      final u = updater();
      backend.error = const ExtractorException('UPDATE_ERROR', 'java.net.UnknownHostException');
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.failed);
      expect(u.lastChecked, isNull);
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.skipped);

      now = now.add(const Duration(hours: 13));
      backend.error = null;
      backend.status = 'ALREADY_UP_TO_DATE';
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.upToDate);
      expect(u.lastChecked, now);
      expect(u.lastUpdated, isNull);
    });

    test('never while another web link download runs', () async {
      final u = updater();
      expect(await u.updateAfterFailure(otherDownloadsRunning: true), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 0);
      // Not counted as a try: the next failure may update.
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.updated);
    });

    test('the native side refusing (BUSY: yt-dlp is running) is not counted as a try', () async {
      final u = updater();
      backend.error = const ExtractorException('BUSY', 'Wait for the current downloads to finish first');
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.skipped);
      backend.error = null;
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.updated);
      expect(backend.updateCalls, 2);
    });

    test('two failures at once share one update', () async {
      final u = updater();
      backend.gate = Completer<void>();
      final a = u.updateAfterFailure();
      final b = u.updateAfterFailure();
      expect(u.isUpdating, isTrue);
      backend.gate!.complete();
      expect(await a, ExtractorUpdateOutcome.updated);
      expect(await b, ExtractorUpdateOutcome.updated);
      expect(backend.updateCalls, 1);
      await Future<void>.delayed(Duration.zero);
      expect(u.isUpdating, isFalse);
    });

    test('nothing happens outside Android', () async {
      android = false;
      expect(await updater().updateAfterFailure(), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 0);
    });

    test('a clock moved back does not block updates for ever', () async {
      final u = updater();
      await u.updateAfterFailure();
      now = now.subtract(const Duration(days: 30));
      expect(await u.updateAfterFailure(), ExtractorUpdateOutcome.updated);
    });
  });

  group('the quiet check at app start', () {
    test('at most once a week', () async {
      final u = updater();
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.updated);
      now = now.add(const Duration(days: 6));
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.skipped);
      now = now.add(const Duration(days: 1, minutes: 1));
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.updated);
      expect(backend.updateCalls, 2);
    });

    test('an update after a failure counts as this week\'s check', () async {
      final u = updater();
      await u.updateAfterFailure();
      now = now.add(const Duration(days: 2));
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 1);
    });

    test('not on metered data; unknown counts as fine', () async {
      final u = updater();
      backend.metered = true;
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 0);
      backend.metered = null;
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.updated);
    });

    // Review finding: a check that failed ran again at every start. (This
    // test said "tries again at the next start" before.)
    test('an offline start tries again the next day, not at every start', () async {
      final u = updater();
      backend.error = const ExtractorException('UPDATE_ERROR', 'offline');
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.failed);
      backend.error = null;
      now = now.add(const Duration(hours: 3));
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 1);
      now = now.add(const Duration(days: 1));
      expect(await u.backgroundCheck(), ExtractorUpdateOutcome.updated);
      expect(backend.updateCalls, 2);
    });

    test('off unless switched on (debug builds and tests never download yt-dlp by themselves)', () async {
      expect(await updater(background: false).backgroundCheck(), ExtractorUpdateOutcome.skipped);
      expect(backend.updateCalls, 0);
    });
  });

  test('Settings\' Update button is remembered too, and listeners hear about every update', () async {
    final u = updater();
    var heard = 0;
    u.addListener(() => heard++);
    expect(await u.updateNow(), 'DONE');
    expect(u.lastUpdated, now);
    expect(heard, 1);

    now = now.add(const Duration(hours: 1));
    backend.status = 'ALREADY_UP_TO_DATE';
    expect(await u.updateNow(), 'ALREADY_UP_TO_DATE');
    expect(u.lastChecked, now);
    expect(u.lastUpdated, now.subtract(const Duration(hours: 1)));
    expect(heard, 2);

    backend.error = const ExtractorException('BUSY', 'busy');
    expect(u.updateNow(), throwsA(isA<ExtractorException>()));
  });

  test('times survive a new updater (they live in the settings file)', () async {
    await updater().updateAfterFailure();
    final again = updater();
    expect(again.lastUpdated, now);
    expect(await again.updateAfterFailure(), ExtractorUpdateOutcome.skipped);
  });
}
