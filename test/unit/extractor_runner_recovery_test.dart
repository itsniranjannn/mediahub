import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/features/downloads/extractor_youtube_fallback.dart';
import 'package:mediahub/personal/extractor_auto_updater.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';

import 'fake_extractor_backend.dart';

/// Records the fallback calls; answers [answer].
class _Fallback {
  bool answer = true;
  final List<DownloadEntry> rows = [];

  /// Waits on this before answering (to pause / cancel meanwhile).
  Completer<void>? gate;
  bool? stillWantedAtEnd;

  Future<bool> call(DownloadEntry row, {required bool Function() stillWanted}) async {
    rows.add(row);
    final g = gate;
    if (g != null) await g.future;
    stillWantedAtEnd = stillWanted();
    return answer && stillWanted();
  }
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late FakeExtractorBackend backend;
  late ExtractorAutoUpdater updater;
  late _Fallback fallback;
  late ExtractorDownloadRunner runner;

  FormatChoice choice(String id) => FormatOptions.build(FakeExtractorBackend.sampleMetadata()).firstWhere((c) => c.id == id);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('extractor_recovery_');
    backend = FakeExtractorBackend();
    updater = ExtractorAutoUpdater(
      backend: backend,
      store: SettingsStore.forTesting(),
      enabled: () => true,
    );
    fallback = _Fallback();
    runner = ExtractorDownloadRunner(
      db: db,
      backend: backend,
      downloadDir: dir,
      publish: (_) {},
      autoUpdater: updater,
      fallback: fallback.call,
    );
  });

  tearDown(() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<DownloadEntry?> rowOf(String id) => (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> enqueue(String choiceId, {String url = 'https://www.youtube.com/watch?v=RpkAZYU8AAA'}) =>
      runner.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: url, choice: choice(choiceId));

  group('the owner\'s 1080p failure ("Requested format is not available")', () {
    test('a download sends the degrading selector with the height cap as the format sort', () async {
      final id = await enqueue('v1080');
      await runner.run(id);
      final call = backend.downloadCalls.single;
      expect(call['formatSelector'], 'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b');
      expect(call['formatSort'], 'height:1080,vcodec:h264,ext:mp4:m4a');
      expect((await rowOf(id))!.state, 'completed');
    });

    test('a row queued by the old version gets the catch-all when retried', () async {
      final id = await enqueue('v1080');
      await (db.update(db.downloadsTable)..where((t) => t.id.equals(id))).write(
        const DownloadsTableCompanion(formatSelector: Value('bestvideo[height<=1080]+bestaudio/best[height<=1080]')),
      );
      await runner.run(id);
      expect(backend.downloadCalls.single['formatSelector'],
          'bestvideo[height<=1080]+bestaudio/best[height<=1080]/bv*+ba/b');
      expect(backend.downloadCalls.single['formatSort'], 'height:1080,vcodec:h264,ext:mp4:m4a');
    });

    test('sound only: no format sort, and MP3 stays a conversion', () async {
      final id = await enqueue('audio_mp3');
      await runner.run(id);
      expect(backend.downloadCalls.single['formatSelector'], 'ba/b');
      expect(backend.downloadCalls.single['formatSort'], isNull);
      expect(backend.downloadCalls.single['audioFormat'], 'mp3');
    });
  });

  group('yt-dlp updates itself and tries again', () {
    test('a site-changed error updates yt-dlp, then the second try saves the file', () async {
      backend.downloadErrors.add(const ExtractorException('FORMAT_UNAVAILABLE', 'Requested format is not available'));
      final id = await enqueue('v1080');
      await runner.run(id);

      expect(backend.updateCalls, 1);
      expect(backend.downloadCalls, hasLength(2));
      final row = (await rowOf(id))!;
      expect(row.state, 'completed');
      expect(row.errorCode, isNull);
      expect(fallback.rows, isEmpty);
    });

    test('only once per download: a second failure does not update again', () async {
      backend.downloadErrors
        ..add(const ExtractorException('EXTRACTION_FAILED', 'x'))
        ..add(const ExtractorException('EXTRACTION_FAILED', 'x'));
      fallback.answer = false;
      final id = await enqueue('v720', url: 'https://vimeo.com/123');
      await runner.run(id);
      expect(backend.updateCalls, 1);
      expect(backend.downloadCalls, hasLength(2));
      expect((await rowOf(id))!.errorCode, 'x_extraction_failed');
    });

    test('no retry when yt-dlp was already the newest', () async {
      final b = _UpToDate();
      final r = ExtractorDownloadRunner(
        db: db,
        backend: b,
        downloadDir: dir,
        publish: (_) {},
        autoUpdater: ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true),
      );
      b.downloadErrors.add(const ExtractorException('BOT_CHECK', 'Sign in to confirm you are not a bot'));
      final id = await r.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://youtu.be/RpkAZYU8AAA',
        choice: choice('v720'),
      );
      await r.run(id);
      expect(b.updateCalls, 1);
      expect(b.downloadCalls, hasLength(1));
      final row = (await rowOf(id))!;
      expect(row.state, 'failed');
      expect(row.errorCode, 'x_bot_check');
    });

    test('a problem with the video itself (private) neither updates nor falls back', () async {
      backend.simulateError = true;
      backend.errorCode = 'PRIVATE_CONTENT';
      final id = await enqueue('v720');
      await runner.run(id);
      expect(backend.updateCalls, 0);
      expect(fallback.rows, isEmpty);
      expect((await rowOf(id))!.errorCode, 'x_private_content');
    });

    test('a pause while yt-dlp updates keeps the download paused (no retry)', () async {
      final gate = Completer<void>();
      final b = _GatedUpdate(gate);
      final r = ExtractorDownloadRunner(
        db: db,
        backend: b,
        downloadDir: dir,
        publish: (_) {},
        autoUpdater: ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true),
      );
      b.downloadErrors.add(const ExtractorException('EXTRACTION_FAILED', 'x'));
      final id = await r.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://youtu.be/RpkAZYU8AAA',
        choice: choice('v720'),
      );
      final run = r.run(id);
      for (var i = 0; i < 200 && b.updateCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(b.updateCalls, 1);
      await r.pause(id);
      gate.complete();
      await run;
      expect(b.downloadCalls, hasLength(1));
      expect((await rowOf(id))!.state, 'paused');
    });
  });

  group('last resort: the YouTube file without yt-dlp', () {
    test('when yt-dlp still fails, the replacement is queued and this download leaves the list', () async {
      backend.downloadErrors
        ..add(const ExtractorException('FORMAT_UNAVAILABLE', 'x'))
        ..add(const ExtractorException('FORMAT_UNAVAILABLE', 'x'));
      final id = await enqueue('v1080');
      // A cover image and yt-dlp leftovers that must go with the row.
      final thumb = File('${dir.path}/$id.thumb')..writeAsBytesSync([1, 2, 3]);
      await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
          .write(DownloadsTableCompanion(thumbnailPath: Value(thumb.path)));
      final part = File('${dir.path}/ytdlp/$id.f137.mp4.part')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);

      await runner.run(id);

      expect(fallback.rows.single.id, id);
      expect(fallback.rows.single.url, 'https://www.youtube.com/watch?v=RpkAZYU8AAA');
      expect(await rowOf(id), isNull, reason: 'replaced by the new download');
      expect(thumb.existsSync(), isFalse);
      expect(part.existsSync(), isFalse);
    });

    test('yt-dlp cannot even start: a YouTube download is still saved another way', () async {
      final b = _InitFails();
      final f = _Fallback();
      final r = ExtractorDownloadRunner(db: db, backend: b, downloadDir: dir, publish: (_) {}, fallback: f.call);
      final id = await r.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://youtu.be/RpkAZYU8AAA',
        choice: choice('audio_mp3'),
      );
      await r.run(id);
      expect(f.rows, hasLength(1));
      expect(await rowOf(id), isNull);
    });

    test('when the fallback has nothing either, the download fails with the yt-dlp reason', () async {
      backend.simulateError = true;
      backend.errorCode = 'FORMAT_UNAVAILABLE';
      backend.errorDetail = '[youtube] RpkAZYU8AAA: Requested format is not available';
      fallback.answer = false;
      final id = await enqueue('v1080');
      await runner.run(id);
      final row = (await rowOf(id))!;
      expect(row.state, 'failed');
      expect(row.errorCode, 'x_format_unavailable');
      expect(row.errorDetail, contains('Requested format is not available'), reason: 'the small Reason line');
    });

    test('other sites have no such fallback', () async {
      backend.simulateError = true;
      backend.errorCode = 'EXTRACTION_FAILED';
      final id = await enqueue('v720', url: 'https://www.instagram.com/reel/abc/');
      await runner.run(id);
      expect(fallback.rows, isEmpty);
      expect((await rowOf(id))!.state, 'failed');
    });

    test('cancelled while the fallback looks the video up: nothing is queued, the row stays cancelled', () async {
      backend.simulateError = true;
      backend.errorCode = 'INIT_FAILED';
      fallback.gate = Completer<void>();
      final id = await enqueue('v720');
      final run = runner.run(id);
      for (var i = 0; i < 200 && fallback.rows.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(fallback.rows, hasLength(1));
      await runner.cancel(id);
      fallback.gate!.complete();
      await run;
      expect(fallback.stillWantedAtEnd, isFalse);
      expect((await rowOf(id))!.state, 'cancelled');
    });
  });

  // Review finding: two downloads failing together both skipped the update
  // ("another web link download is running") and were swapped for 360p.
  group('downloads that fail together share one update', () {
    // Found while testing this: two downloads queued within the clock's
    // resolution got the same id, and the second could not be saved.
    test('downloads queued in a burst never share an id', () async {
      final ids = await Future.wait([for (var i = 0; i < 40; i++) enqueue('v720')]);
      expect(ids.toSet(), hasLength(40));
    });

    test('both fail at once: yt-dlp updates once and both are saved at the chosen quality', () async {
      final b = _Ordered();
      final r = ExtractorDownloadRunner(
        db: db,
        backend: b,
        downloadDir: dir,
        publish: (_) {},
        autoUpdater: ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true),
        fallback: fallback.call,
      );
      final a = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v1080'));
      final c = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v720'));
      final holdA = b.holds[a] = Completer<void>();
      final holdC = b.holds[c] = Completer<void>();
      b.failFirst.addAll([a, c]);
      final runs = Future.wait([r.run(a), r.run(c)]);
      await _until(() => b.log.where((e) => e.startsWith('download:')).length == 2);
      holdA.complete();
      holdC.complete();
      await runs;

      expect(b.updateCalls, 1, reason: 'one update serves both');
      expect(fallback.rows, isEmpty, reason: 'no lower-quality copy');
      expect((await rowOf(a))!.state, 'completed');
      expect((await rowOf(c))!.state, 'completed');
      expect(b.log.indexOf('update'), lessThan(b.log.lastIndexOf('download:$a')));
      expect(b.log.indexOf('update'), lessThan(b.log.lastIndexOf('download:$c')));
    });

    test('one fails while another downloads: it waits, updates once that is done, and new ones hold back', () async {
      final b = _Ordered();
      final r = ExtractorDownloadRunner(
        db: db,
        backend: b,
        downloadDir: dir,
        publish: (_) {},
        autoUpdater: ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true),
        fallback: fallback.call,
      );
      final busy = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v720'));
      final failing = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v1080'));
      final later = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v720'));
      final holdBusy = b.holds[busy] = Completer<void>();
      b.failFirst.add(failing);

      final runBusy = r.run(busy);
      await _until(() => b.log.contains('download:$busy'));
      final runFailing = r.run(failing);
      await _until(() => b.log.contains('download:$failing'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(b.updateCalls, 0, reason: 'never replaced under a running download');
      expect((await rowOf(failing))!.state, 'preparing');

      final runLater = r.run(later);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(b.log, isNot(contains('download:$later')), reason: 'a new one holds back for the update');

      holdBusy.complete();
      await Future.wait([runBusy, runFailing, runLater]);
      expect(b.updateCalls, 1);
      expect(fallback.rows, isEmpty);
      for (final id in [busy, failing, later]) {
        expect((await rowOf(id))!.state, 'completed', reason: id);
      }
      expect(b.log.indexOf('update'), lessThan(b.log.indexOf('download:$later')));
    });

    test('others still running after the wait limit: no update, the YouTube fallback as before', () async {
      final b = _Ordered();
      final r = ExtractorDownloadRunner(
        db: db,
        backend: b,
        downloadDir: dir,
        publish: (_) {},
        autoUpdater: ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true),
        fallback: fallback.call,
        updateWaitLimit: const Duration(milliseconds: 200),
      );
      final busy = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v720'));
      final failing = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v1080'));
      final holdBusy = b.holds[busy] = Completer<void>();
      b.failFirst.add(failing);
      final runBusy = r.run(busy);
      await _until(() => b.log.contains('download:$busy'));
      await r.run(failing);
      expect(b.updateCalls, 0);
      expect(fallback.rows.single.id, failing);
      holdBusy.complete();
      await runBusy;
    });

    test('a pause while it waits for the others keeps it paused', () async {
      final b = _Ordered();
      final r = ExtractorDownloadRunner(
        db: db,
        backend: b,
        downloadDir: dir,
        publish: (_) {},
        autoUpdater: ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true),
        fallback: fallback.call,
      );
      final busy = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v720'));
      final failing = await r.enqueue(meta: FakeExtractorBackend.sampleMetadata(), pageUrl: _yt, choice: choice('v1080'));
      final holdBusy = b.holds[busy] = Completer<void>();
      b.failFirst.add(failing);
      final runBusy = r.run(busy);
      await _until(() => b.log.contains('download:$busy'));
      final runFailing = r.run(failing);
      await _until(() => b.log.contains('download:$failing'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await r.pause(failing);
      await runFailing;
      expect((await rowOf(failing))!.state, 'paused');
      expect(b.updateCalls, 0);
      expect(fallback.rows, isEmpty);
      holdBusy.complete();
      await runBusy;
    });
  });

  // Review finding: the catch-all can save another quality than the one
  // chosen, and the chip still said the chosen one.
  group('the quality chip says what was saved', () {
    Future<String?> labelAfter(String choiceId, int? height) async {
      backend.outputHeight = height;
      final id = await enqueue(choiceId);
      await runner.run(id);
      return (await rowOf(id))!.qualityLabel;
    }

    test('lower than chosen: "360p · lower quality"', () async {
      expect(await labelAfter('v1080', 360), '360p · lower quality');
    });

    test('the chosen height, or a file that does not say: unchanged', () async {
      expect(await labelAfter('v1080', 1080), '1080p');
      expect(await labelAfter('v720', null), '720p');
    });

    test('higher than chosen (only bigger formats existed): the real height', () async {
      expect(await labelAfter('v720', 1440), '1440p');
    });

    test('sound only keeps its chip', () async {
      expect(await labelAfter('audio_mp3', 360), 'MP3');
    });

    test('the rule, and the same words as the YouTube fallback', () {
      expect(ExtractorDownloadRunner.qualityLabelAfter('720p 60fps', savedHeight: 720), '720p 60fps');
      expect(ExtractorDownloadRunner.qualityLabelAfter('720p 60fps', savedHeight: 480), '480p · lower quality');
      expect(ExtractorDownloadRunner.qualityLabelAfter('Best', savedHeight: 480), 'Best');
      expect(ExtractorDownloadRunner.qualityLabelAfter(null, savedHeight: 480), isNull);
      expect(ExtractorDownloadRunner.lowerQualityNote, ExtractorYoutubeFallback.lowerQualityNote);
    });
  });

  group('videos go to Videos, sound only to Music', () {
    test('a video choice whose file turns out to be sound only is saved as audio', () async {
      backend.outputHasVideo = false;
      final id = await enqueue('v720');
      await runner.run(id);
      final row = (await rowOf(id))!;
      expect(row.kind, 'audio');
      final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(row.mediaId!))).getSingle();
      expect(media.mediaType, 'audio');
      expect(row.mimeType, 'audio/mp4');
    });

    test('a WebM with a picture is a video', () async {
      backend.outputHasVideo = true;
      backend.outputExtension = 'webm';
      final id = await enqueue('v720');
      await runner.run(id);
      final row = (await rowOf(id))!;
      expect(row.kind, 'video');
      expect(row.mimeType, 'video/webm');
    });

    test('with no track report from the phone, the shared classifier reads the file', () async {
      backend.outputBytes = _mp4(['soun']);
      final id = await enqueue('v720');
      await runner.run(id);
      final row = (await rowOf(id))!;
      expect(row.kind, 'audio', reason: 'an MP4 with sound only belongs in Music');
      expect(row.mimeType, 'audio/mp4');

      // Sound asked for ("Original audio") on a site that only has a file
      // with pictures (TikTok, many X, Facebook and Instagram links): it
      // still goes to Music. (It went to Videos before this was fixed.)
      backend.outputBytes = _mp4(['vide', 'soun']);
      final id2 = await enqueue('audio_best');
      await runner.run(id2);
      final row2 = (await rowOf(id2))!;
      expect(row2.kind, 'audio', reason: 'the user asked for the sound');
      final media2 = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(row2.mediaId!))).getSingle();
      expect(media2.mediaType, 'audio');
    });

    test('sound asked for stays in Music even when the phone reports a picture track', () async {
      backend.outputHasVideo = true;
      final id = await enqueue('audio_mp3');
      await runner.run(id);
      final row = (await rowOf(id))!;
      expect(row.kind, 'audio');
      final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(row.mediaId!))).getSingle();
      expect(media.mediaType, 'audio');
    });

    test('the rules', () {
      // What is in the file decides (the same rule as direct-link downloads).
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'mp4', kind: 'video', hasVideo: false), isFalse);
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'webm', kind: 'video', hasVideo: true), isTrue);
      // Sound asked for is Music, whatever the file holds (this was isTrue
      // before the fix: the owner's "audio in Music").
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'mp4', kind: 'audio', hasVideo: true), isFalse);
      // The file could not tell: an audio choice is Music, otherwise the extension.
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'mp4', kind: 'audio'), isFalse);
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'mkv', kind: 'video'), isTrue);
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'm4a', kind: 'video'), isFalse);
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'mp3', kind: null), isFalse);
      expect(ExtractorDownloadRunner.isVideoResult(ext: 'mp4', kind: null), isTrue);
    });
  });
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _box(String type, List<int> payload) => [..._u32(8 + payload.length), ...ascii.encode(type), ...payload];
List<int> _hdlr(String handler) =>
    _box('hdlr', [0, 0, 0, 0, ..._u32(0), ...ascii.encode(handler), ...List.filled(12, 0), ...ascii.encode('h'), 0]);
List<int> _trak(int id, String handler) => _box('trak', [
      ..._box('tkhd', [0, 0, 0, 3, ..._u32(0), ..._u32(0), ..._u32(id), ...List.filled(68, 0)]),
      ..._box('mdia', [..._box('mdhd', List.filled(24, 0)), ..._hdlr(handler), ..._box('minf', List.filled(16, 0))]),
    ]);

/// A minimal MP4 with one track per [handlers] entry ('vide' picture, 'soun' sound).
List<int> _mp4(List<String> handlers) => [
      ..._box('ftyp', [...ascii.encode('isom'), ..._u32(0), ...ascii.encode('isom'), ...ascii.encode('mp41')]),
      ..._box('moov', [
        ..._box('mvhd', List.filled(100, 0)),
        for (final (i, h) in handlers.indexed) ..._trak(i + 1, h),
      ]),
      ..._box('mdat', List.filled(2048, 0x11)),
    ];

const _yt = 'https://www.youtube.com/watch?v=RpkAZYU8AAA';

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'timed out waiting');
}

/// Records the order of yt-dlp calls; a task in [holds] waits in its first
/// download until that completes, and a task in [failFirst] then fails once
/// with FORMAT_UNAVAILABLE (the owner's error).
class _Ordered extends FakeExtractorBackend {
  final List<String> log = [];
  final Map<String, Completer<void>> holds = {};
  final Set<String> failFirst = {};

  @override
  Future<String> update() async {
    log.add('update');
    return super.update();
  }

  @override
  Future<ExtractorDownloadResult> download({
    required String taskId,
    required String url,
    required String outDir,
    String? formatSelector,
    String? formatSort,
    String? extractorArgs,
    String? audioFormat,
    void Function(double progress, int eta)? onProgress,
    void Function(String line)? onLine,
  }) async {
    log.add('download:$taskId');
    final hold = holds.remove(taskId);
    if (hold != null) await hold.future;
    if (failFirst.remove(taskId)) {
      throw const ExtractorException('FORMAT_UNAVAILABLE', 'Requested format is not available');
    }
    return super.download(
      taskId: taskId,
      url: url,
      outDir: outDir,
      formatSelector: formatSelector,
      formatSort: formatSort,
      extractorArgs: extractorArgs,
      audioFormat: audioFormat,
      onProgress: onProgress,
      onLine: onLine,
    );
  }
}

class _UpToDate extends FakeExtractorBackend {
  @override
  Future<String> update() async {
    updateCalls++;
    return 'ALREADY_UP_TO_DATE';
  }
}

class _GatedUpdate extends FakeExtractorBackend {
  _GatedUpdate(this.gate);
  final Completer<void> gate;

  @override
  Future<String> update() async {
    updateCalls++;
    await gate.future;
    return 'DONE';
  }
}

class _InitFails extends FakeExtractorBackend {
  @override
  Future<bool> init() async => throw const ExtractorException('INIT_FAILED', 'no python');
}
