import 'dart:io';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/data/repositories/direct_url_resolver.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/repositories/platform_resolver.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/library/media_song_row.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/media_item_tile.dart';
import 'fake_extractor_backend.dart';

class _FakeDirectUrlResolver extends DirectUrlResolver {
  final SourceInfo Function(Uri uri) handler;
  _FakeDirectUrlResolver(this.handler);

  @override
  Future<SourceInfo> inspect(Uri uri) async => handler(uri);
}

/// Lets real async work (drift, dart:io) finish and rebuilds the tree several
/// times; `pumpAndSettle` alone cannot do that inside FakeAsync.
Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  group('PART 4: Downloads Screen and Library Tests', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('dl_screen_test');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets('1. URL validation messages in plain language', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
            storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
          ],
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).first;

      // HTTP scheme -> error
      await tester.enterText(textField, 'http://example.com/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Only secure HTTPS links are allowed.'), findsOneWidget);

      // Userinfo credentials -> error
      await tester.enterText(textField, 'https://user:pass@example.com/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Links containing credentials or usernames are not allowed.'), findsOneWidget);

      // Blocked private IP literal -> error
      await tester.enterText(textField, 'https://192.168.1.1/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Private or internal network addresses are blocked.'), findsOneWidget);

      // Valid link -> no error
      await tester.enterText(textField, 'https://example.com/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Only secure HTTPS links are allowed.'), findsNothing);
      expect(find.text('Private or internal network addresses are blocked.'), findsNothing);
    });

    testWidgets('2. Inspect states: downloadable, web page, unsupported type, unknown size', (tester) async {
      final fakeResolver = _FakeDirectUrlResolver((uri) {
        if (uri.path.contains('webpage')) {
          return SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {},
            contentType: 'text/html; charset=utf-8',
            restrictions: const ['unsupported_media_type'],
          );
        } else if (uri.path.contains('unknown_size')) {
          return SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {SourceCapability.download},
            contentType: 'audio/mpeg',
            contentLength: null,
            suggestedFilename: 'unknown.mp3',
            supportsRange: false,
          );
        } else {
          return SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {SourceCapability.download},
            contentType: 'audio/mpeg',
            contentLength: 5 * 1024 * 1024,
            suggestedFilename: 'song.mp3',
            supportsRange: true,
          );
        }
      });

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
          storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
        ],
      );
      container.read(inspectionProvider.notifier).setResolverForTesting(fakeResolver);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A. Downloadable link inspect
      final textField = find.byType(TextField).first;
      await tester.enterText(textField, 'https://example.com/song.mp3');
      await tester.pumpAndSettle();

      final inspectBtn = find.text('Inspect');
      await tester.tap(inspectBtn);
      await tester.pumpAndSettle();

      expect(find.text('Inspection Result'), findsOneWidget);
      expect(find.text('Host: example.com'), findsOneWidget);
      expect(find.text('Content Type: audio/mpeg'), findsOneWidget);
      expect(find.text('Size: 5.00 MB'), findsOneWidget);
      expect(find.text('Pause and resume supported'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      // B. Web page link inspect
      await tester.enterText(textField, 'https://example.com/webpage.html');
      await tester.pumpAndSettle();
      await tester.tap(inspectBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('This is a web page, not a media file. MediaHub can only download direct media files that you have the right to save.'),
        findsOneWidget,
      );
      expect(find.text('Open link'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      // C. Unknown size inspect
      await tester.enterText(textField, 'https://example.com/unknown_size.mp3');
      await tester.pumpAndSettle();
      await tester.tap(inspectBtn);
      await tester.pumpAndSettle();

      expect(find.text('Size: Unknown size'), findsOneWidget);
      expect(find.text('Pause and resume not supported'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('3. First-use agreement dialog shown once and remembers agreement', (tester) async {
      final fakeResolver = _FakeDirectUrlResolver((uri) => SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {SourceCapability.download},
            contentType: 'audio/mpeg',
            contentLength: 1024,
            suggestedFilename: 'track.mp3',
          ));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
          storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
        ],
      );
      container.read(inspectionProvider.notifier).setResolverForTesting(fakeResolver);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).first;
      await tester.enterText(textField, 'https://example.com/track.mp3');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inspect'));
      await tester.pumpAndSettle();

      // Click Download -> First-use notice dialog appears
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.text('Download Notice'), findsOneWidget);
      expect(find.text('Only download files you have the right to save. MediaHub does not support unauthorized or copyright-protected content.'), findsOneWidget);

      // Tap Agree
      await tester.tap(find.text('Agree'));
      await tester.pumpAndSettle();

      expect(find.text('Download added to queue'), findsOneWidget);

      // Next download -> Dialog is NOT shown again
      await tester.enterText(find.byType(TextField).first, 'https://example.com/track.mp3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.text('Download Notice'), findsNothing);
    });

    testWidgets('4. Download row states and delete confirmation removes file and DB row', (tester) async {
      final now = DateTime.now();
      final dummyFile = File('${tempDir.path}/finished.mp3');

      // dart:io and drift complete on the real event loop: inside testWidgets
      // (FakeAsync) they only work through tester.runAsync, otherwise the test hangs.
      await tester.runAsync(() async {
        await dummyFile.writeAsString('audio-content');

        // Seed database with a completed download
        await db.into(db.downloadsTable).insert(
          DownloadsTableCompanion.insert(
            id: 'dl_completed_1',
            url: 'https://example.com/finished.mp3',
            host: 'example.com',
            displayName: 'Finished Song',
            fileName: 'finished.mp3',
            state: DownloadTaskState.completed.name,
            receivedBytes: const d.Value(1024),
            totalBytes: const d.Value(1024),
            finalPath: d.Value(dummyFile.path),
            mediaId: const d.Value('dl_dl_completed_1'),
            kind: const d.Value('audio'),
            createdAt: now,
            updatedAt: now,
          ),
        );

        await db.into(db.mediaItemsTable).insert(
          MediaItemsTableCompanion.insert(
            id: 'dl_dl_completed_1',
            uri: dummyFile.path,
            mediaType: 'audio',
            title: 'Finished Song',
            durationMs: 0,
            sizeBytes: 1024,
            dateAdded: now,
            source: const d.Value('download'),
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 1024, freeBytes: 1000000000))),
          ],
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      // let the drift stream deliver its first rows, then rebuild
      await settle(tester);

      expect(find.text('Finished Song'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      // audio/video is shown as a chip on every row
      expect(find.text('Audio'), findsOneWidget);

      // Tap Delete icon
      final deleteBtn = find.byTooltip('Delete');
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Delete confirmation dialog
      expect(find.text('Delete Download'), findsOneWidget);
      expect(find.text('Delete "finished.mp3"? Your other files are safe.'), findsOneWidget);

      // Confirm Delete
      await tester.tap(find.text('Delete'));
      await settle(tester);

      // Verifications: file deleted from disk, rows deleted from DB
      await tester.runAsync(() async {
        expect(dummyFile.existsSync(), isFalse);
        final dlRows = await db.select(db.downloadsTable).get();
        expect(dlRows, isEmpty);
        final mediaRows = await db.select(db.mediaItemsTable).get();
        expect(mediaRows, isEmpty);
      });

      // unmount so the drift streams are cancelled, then let drift's own
      // clean-up timer fire (an un-fired timer fails the test)
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('4b. Deleting a web-link download also removes its yt-dlp work files', (tester) async {
      final now = DateTime.now();
      final workDir = Directory('${tempDir.path}/ytdlp');
      final ownFiles = [
        File('${workDir.path}/x100.f137.mp4.part'),
        File('${workDir.path}/x100.ytdl'),
      ];
      final otherTaskFile = File('${workDir.path}/x200.f137.mp4.part');

      await tester.runAsync(() async {
        for (final f in [...ownFiles, otherTaskFile]) {
          await f.create(recursive: true);
          await f.writeAsBytes([1, 2, 3]);
        }
        await db.into(db.downloadsTable).insert(
              DownloadsTableCompanion.insert(
                id: 'x100',
                url: 'https://www.youtube.com/watch?v=abc',
                host: 'www.youtube.com',
                displayName: 'Failed Web Video',
                fileName: 'Failed Web Video.mp4',
                state: DownloadTaskState.failed.name,
                errorCode: const d.Value('x_network_error'),
                engine: const d.Value('extractor'),
                kind: const d.Value('video'),
                createdAt: now,
                updatedAt: now,
              ),
            );
      });

      final runner = ExtractorDownloadRunner(
        db: db,
        backend: FakeExtractorBackend(),
        downloadDir: tempDir,
        publish: (_) {},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
            extractorDownloadRunnerProvider.overrideWithValue(runner),
          ],
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Failed Web Video'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete Download'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await settle(tester);

      await tester.runAsync(() async {
        for (final f in ownFiles) {
          expect(f.existsSync(), isFalse, reason: f.path);
        }
        expect(otherTaskFile.existsSync(), isTrue, reason: 'other tasks keep their files');
        expect(await db.select(db.downloadsTable).get(), isEmpty);
      });

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('5. Library shows "Downloaded" badge on audio and video rows', (tester) async {
      final downloadedAudio = MediaItem(
        id: 'dl_audio_1',
        uri: '/storage/downloaded_audio.mp3',
        mediaType: MediaType.audio,
        title: 'Downloaded Track',
        durationMs: 180000,
        sizeBytes: 3000000,
        dateAdded: DateTime.now(),
        source: 'download',
      );

      final downloadedVideo = MediaItem(
        id: 'dl_video_1',
        uri: '/storage/downloaded_video.mp4',
        mediaType: MediaType.video,
        title: 'Downloaded Video',
        durationMs: 60000,
        sizeBytes: 12000000,
        dateAdded: DateTime.now(),
        source: 'download',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  MediaSongRow(item: downloadedAudio),
                  MediaItemTile(item: downloadedVideo),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Downloaded'), findsNWidgets(2));
      expect(find.text('Downloaded Track'), findsOneWidget);
      expect(find.text('Downloaded Video'), findsOneWidget);
    });
  });
}
