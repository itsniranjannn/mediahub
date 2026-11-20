import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/domain/models/download_progress.dart';
import 'package:mediahub/personal/format_options.dart';
import 'fake_extractor_backend.dart';
import 'fake_failing_database.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late FakeExtractorBackend backend;
  late ExtractorDownloadRunner runner;
  late List<DownloadProgressUpdate> updates;

  FormatChoice choice(String id) {
    final meta = FakeExtractorBackend.sampleMetadata();
    return FormatOptions.build(meta).firstWhere((c) => c.id == id);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('extractor_runner_');
    backend = FakeExtractorBackend();
    updates = [];
    runner = ExtractorDownloadRunner(
      db: db,
      backend: backend,
      downloadDir: dir,
      publish: updates.add,
    );
  });

  tearDown(() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<DownloadEntry> rowOf(String id) {
    return (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
  }

  test('enqueue stores everything the list needs: kind, quality, size, thumbnail url', () async {
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v1080'),
    );
    final row = await rowOf(id);
    expect(row.state, 'queued');
    expect(row.engine, 'extractor');
    expect(row.kind, 'video');
    expect(row.qualityLabel, '1080p');
    expect(row.totalBytes, 18000000);
    expect(row.host, 'www.youtube.com');
    expect(row.displayName, 'Sample Test Video');
    expect(row.uploader, 'Test Author');
    expect(row.durationSec, 120);
  });

  test('video download completes: file moved to library folder, media row has type, duration and source', () async {
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v1080'),
    );
    await runner.run(id);

    final row = await rowOf(id);
    expect(row.state, 'completed');
    expect(row.kind, 'video');
    expect(row.mimeType, 'video/mp4');
    expect(row.finalPath, isNotNull);
    expect(File(row.finalPath!).existsSync(), isTrue);
    expect(File(row.finalPath!).parent.path, dir.path);
    expect(row.receivedBytes, 2048);
    expect(row.totalBytes, 2048);

    final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(row.mediaId!))).getSingle();
    expect(media.mediaType, 'video');
    expect(media.source, 'download');
    expect(media.durationMs, 120000);
    expect(media.artist, 'Test Author');
    expect(media.format, 'mp4');

    // intermediate files are gone, and progress with sizes was published
    expect(runner.workDir.listSync().whereType<File>(), isEmpty);
    expect(updates, isNotEmpty);
    final mid = updates.firstWhere((u) => u.progress != null && u.progress! < 1.0);
    expect(mid.totalBytes, 18000000);
    // 50% of the 15 MB video stream
    expect(mid.receivedBytes, 7500000);
    expect(mid.speedBytesPerSec, closeTo(1024 * 1024, 1));
    expect(backend.downloadCalls.single['formatSelector'], contains('height<=1080'));
  });

  test('audio choice (MP3) is stored as audio with the right quality label', () async {
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://music.youtube.com/watch?v=abc',
      choice: choice('audio_mp3_320'),
    );
    await runner.run(id);

    final row = await rowOf(id);
    expect(row.state, 'completed');
    expect(row.kind, 'audio');
    expect(row.qualityLabel, 'MP3 320 kbps');
    expect(row.mimeType, 'audio/mpeg');
    expect(backend.downloadCalls.single['audioFormat'], 'mp3');
    expect(backend.downloadCalls.single['audioQuality'], '320K');
    final media = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(row.mediaId!))).getSingle();
    expect(media.mediaType, 'audio');
  });

  test('extractor errors become a failed row with a mapped code', () async {
    backend.simulateError = true;
    backend.errorCode = 'PRIVATE_CONTENT';
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    await runner.run(id);
    final row = await rowOf(id);
    expect(row.state, 'failed');
    expect(row.errorCode, 'x_private_content');
  });

  test('the real reason from the downloader is kept so the card can show it', () async {
    backend.simulateError = true;
    backend.errorCode = 'EXTRACTION_FAILED';
    backend.errorDetail = 'HTTP Error 403: Forbidden';
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://youtu.be/abc',
      choice: choice('v1080'),
    );
    await runner.run(id);
    final row = await rowOf(id);
    expect(row.state, 'failed');
    expect(row.errorCode, 'x_extraction_failed');
    expect(row.errorDetail, 'HTTP Error 403: Forbidden');
  });

  test('a merge step after the last stream still ends in a completed task', () async {
    backend.emitMergeLine = true;
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://youtu.be/abc',
      choice: choice('v1080'),
    );
    await runner.run(id);
    expect((await rowOf(id)).state, 'completed');
  });

  test('pause keeps the task resumable and resume finishes it', () async {
    backend.blockDownload = Completer<void>();
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    final running = runner.run(id);
    await pumpEventQueue();
    expect((await rowOf(id)).state, 'downloading');

    await runner.pause(id);
    await running;
    expect((await rowOf(id)).state, 'paused');
    expect(backend.cancelled, contains(id));

    backend.blockDownload = null;
    await runner.run(id);
    expect((await rowOf(id)).state, 'completed');
  });

  test('cancel removes partial files and marks the task cancelled', () async {
    backend.blockDownload = Completer<void>();
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    runner.workDir.createSync(recursive: true);
    File('${runner.workDir.path}/$id.f137.mp4.part').writeAsBytesSync([1, 2, 3]);

    final running = runner.run(id);
    await pumpEventQueue();
    await runner.cancel(id);
    await running;

    expect((await rowOf(id)).state, 'cancelled');
    expect(runner.workDir.listSync().whereType<File>(), isEmpty);
  });

  test('tasks interrupted by an app kill are queued again at startup', () async {
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
        .write(const DownloadsTableCompanion(state: Value('downloading')));

    final recovered = await runner.reconcileOnStartup();
    expect(recovered, [id]);
    expect((await rowOf(id)).state, 'queued');
  });

  group('free space', () {
    ExtractorDownloadRunner runnerWithFree(int freeBytes) => ExtractorDownloadRunner(
          db: db,
          backend: backend,
          downloadDir: dir,
          publish: updates.add,
          freeSpaceProvider: () async => freeBytes,
        );

    test('needs room for the streams and the merged output plus a margin', () {
      const mb = 1024 * 1024;
      expect(ExtractorDownloadRunner.requiredFreeBytes(100 * mb), 400 * mb);
      // Unknown size counts as the 2 GB limit.
      expect(ExtractorDownloadRunner.requiredFreeBytes(null), 2 * DownloadEngine.maxDownloadSizeBytes + 200 * mb);
      expect(ExtractorDownloadRunner.requiredFreeBytes(0), 2 * DownloadEngine.maxDownloadSizeBytes + 200 * mb);
      // Parts already downloaded are not needed again, but the margin stays.
      expect(ExtractorDownloadRunner.requiredFreeBytes(100 * mb, existingWorkBytes: 50 * mb), 350 * mb);
      expect(ExtractorDownloadRunner.requiredFreeBytes(100 * mb, existingWorkBytes: 1000 * mb), 200 * mb);
    });

    test('a resume counts the parts already in the work folder', () async {
      final id = await runner.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://www.youtube.com/watch?v=abc',
        choice: choice('v1080'),
      );
      // 4 MB of an earlier attempt (size only; the content does not matter).
      const existing = 4 * 1024 * 1024;
      final part = File('${runner.workDir.path}/$id.f137.mp4.part')..createSync(recursive: true);
      final raf = part.openSync(mode: FileMode.write);
      raf.truncateSync(existing);
      raf.closeSync();

      final total = (await rowOf(id)).totalBytes;
      final fresh = ExtractorDownloadRunner.requiredFreeBytes(total);
      expect(ExtractorDownloadRunner.requiredFreeBytes(total, existingWorkBytes: existing), fresh - existing);

      // Free space between the two thresholds: enough to resume, not to start over.
      await runnerWithFree(fresh - 1).run(id);
      final row = await rowOf(id);
      expect(row.state, 'completed');
      expect(row.errorCode, isNull);
      expect(backend.downloadCalls, hasLength(1));
    });

    test('not enough space fails before yt-dlp starts, with the direct-link error code', () async {
      final id = await runner.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://www.youtube.com/watch?v=abc',
        choice: choice('v1080'),
      );
      final needed = ExtractorDownloadRunner.requiredFreeBytes((await rowOf(id)).totalBytes);
      await runnerWithFree(needed - 1).run(id);

      final row = await rowOf(id);
      expect(row.state, 'failed');
      expect(row.errorCode, 'insufficient_disk_space');
      expect(backend.downloadCalls, isEmpty);

      // Exactly enough space: the retry goes ahead.
      await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
          .write(const DownloadsTableCompanion(state: Value('queued')));
      await runnerWithFree(needed).run(id);
      expect((await rowOf(id)).state, 'completed');
    });

    test('an unknown size is checked against the 2 GB limit', () async {
      final id = await runner.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://www.youtube.com/watch?v=abc',
        choice: choice('v1080'),
      );
      await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
          .write(const DownloadsTableCompanion(totalBytes: Value(null)));
      await runnerWithFree(3 * 1024 * 1024 * 1024).run(id);
      expect((await rowOf(id)).errorCode, 'insufficient_disk_space');
      expect(backend.downloadCalls, isEmpty);
    });
  });

  test('an error while finalizing ends the task failed, not stuck in finalizing', () async {
    final failingDb = FailingFinalizeDatabase(NativeDatabase.memory());
    addTearDown(failingDb.close);
    final r = ExtractorDownloadRunner(db: failingDb, backend: backend, downloadDir: dir, publish: updates.add);
    final id = await r.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    failingDb.failMediaInsert = true;

    await r.run(id); // completes normally: nothing escapes to the coordinator

    final row = await (failingDb.select(failingDb.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(row.state, 'failed');
    expect(row.errorCode, 'download_error');
    expect(row.errorDetail, 'Unexpected error (StateError)');
    expect(r.isRunning(id), isFalse);

    // The moved file went back to yt-dlp's work folder (which a retry treats
    // as already downloaded): no media file without a row in the library
    // folder, and no library row pointing at a missing file.
    expect(dir.listSync().whereType<File>(), isEmpty);
    expect(r.workDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last), ['$id.mp4']);
    expect(await failingDb.select(failingDb.mediaItemsTable).get(), isEmpty);

    // A retry finishes under the original name, not "... (1)".
    failingDb.failMediaInsert = false;
    await r.run(id);
    final retried = await (failingDb.select(failingDb.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(retried.state, 'completed');
    expect(retried.fileName, 'Sample Test Video.mp4');
    expect(dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last), ['Sample Test Video.mp4']);
    expect(r.workDir.listSync().whereType<File>(), isEmpty);
  });

  group('a pause / cancel while the download folder is still resolving', () {
    test('pause keeps the task paused and yt-dlp never starts', () async {
      final folder = Completer<Directory>();
      final r = ExtractorDownloadRunner(db: db, backend: backend, downloadDir: folder.future, publish: updates.add);
      final id = await r.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://www.youtube.com/watch?v=abc',
        choice: choice('v720'),
      );
      final running = r.run(id);
      await pumpEventQueue();
      expect((await rowOf(id)).state, 'preparing');

      await r.pause(id);
      folder.complete(dir);
      await running;

      // Not overwritten with 'downloading' (stuck with no worker).
      expect((await rowOf(id)).state, 'paused');
      expect(backend.downloadCalls, isEmpty);
      expect(r.isRunning(id), isFalse);
    });

    test('cancel ends cancelled and yt-dlp never starts', () async {
      final folder = Completer<Directory>();
      final r = ExtractorDownloadRunner(db: db, backend: backend, downloadDir: folder.future, publish: updates.add);
      final id = await r.enqueue(
        meta: FakeExtractorBackend.sampleMetadata(),
        pageUrl: 'https://www.youtube.com/watch?v=abc',
        choice: choice('v720'),
      );
      final running = r.run(id);
      await pumpEventQueue();

      final cancelling = r.cancel(id); // its work-file cleanup waits for the folder too
      await pumpEventQueue();
      folder.complete(dir);
      await cancelling;
      await running;

      expect((await rowOf(id)).state, 'cancelled');
      expect(backend.downloadCalls, isEmpty);
    });
  });

  test('a yt-dlp work-file extension is replaced by the sniffed media extension', () async {
    // An MP4 header ("ftyp" at offset 4) inside a ".part" file.
    backend.outputExtension = 'mp4.part';
    backend.outputBytes = [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D, ...List.filled(500, 0)];
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    await runner.run(id);

    final row = await rowOf(id);
    expect(row.state, 'completed');
    expect(row.finalPath, endsWith('.mp4'));
    expect(row.fileName, 'Sample Test Video.mp4');
  });

  test('a yt-dlp work file that is not media is not finalized', () async {
    backend.outputExtension = 'ytdl';
    final id = await runner.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    await runner.run(id);
    final row = await rowOf(id);
    expect(row.state, 'failed');
    expect(row.errorCode, 'x_no_output');
    expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.ytdl')), isEmpty);
  });

  group('yt-dlp work files', () {
    File work(String name) => File('${runner.workDir.path}/$name')..createSync(recursive: true);

    Future<void> insertRow(String id, String state) {
      final now = DateTime.now();
      return db.into(db.downloadsTable).insert(DownloadsTableCompanion.insert(
            id: id,
            url: 'https://www.youtube.com/watch?v=$id',
            host: 'www.youtube.com',
            displayName: id,
            fileName: '$id.mp4',
            state: state,
            engine: const Value('extractor'),
            createdAt: now,
            updatedAt: now,
          ));
    }

    test('deleteWorkFiles removes only that task\'s files', () async {
      final mine = [work('x1.f137.mp4.part'), work('x1.f140.m4a'), work('x1.ytdl'), work('x1.temp.mp4')];
      final other = work('x12.f137.mp4.part'); // same prefix digits, different task

      await runner.deleteWorkFiles('x1');

      for (final f in mine) {
        expect(f.existsSync(), isFalse, reason: f.path);
      }
      expect(other.existsSync(), isTrue);
    });

    test('startup removes files no unfinished task owns and keeps resumable ones', () async {
      await insertRow('x10', 'failed'); // retry resumes from its files
      await insertRow('x11', 'paused');
      await insertRow('x12', 'queued');
      await insertRow('x13', 'completed');
      await insertRow('x14', 'cancelled');
      final kept = [work('x10.f137.mp4.part'), work('x11.ytdl'), work('x12.f140.m4a.part')];
      final removed = [work('x13.f137.mp4'), work('x14.temp.mp4'), work('x99.f137.mp4.part')]; // x99: row deleted

      await runner.reconcileOnStartup();

      for (final f in kept) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
      for (final f in removed) {
        expect(f.existsSync(), isFalse, reason: f.path);
      }
    });
  });

  test('while the download folder is still resolving, enqueue does not wait and run writes only to it', () async {
    final folder = Completer<Directory>();
    final r = ExtractorDownloadRunner(db: db, backend: backend, downloadDir: folder.future, publish: updates.add);
    expect(() => r.workDir, throwsStateError);

    final id = await r.enqueue(
      meta: FakeExtractorBackend.sampleMetadata(),
      pageUrl: 'https://www.youtube.com/watch?v=abc',
      choice: choice('v720'),
    );
    expect((await rowOf(id)).state, 'queued');

    final running = r.run(id);
    await pumpEventQueue();
    expect(backend.downloadCalls, isEmpty, reason: 'yt-dlp must not start before the folder is known');

    folder.complete(dir);
    await running;

    final row = await rowOf(id);
    expect(row.state, 'completed');
    expect(File(row.finalPath!).parent.path, dir.path);
    expect(r.workDir.path, '${dir.path}${Platform.pathSeparator}ytdlp');
  });
}
