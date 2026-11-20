import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/features/downloads/extractor_youtube_fallback.dart';
import 'package:mediahub/features/downloads/youtube_direct_resolver.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/personal/format_options.dart';

import 'fake_extractor_backend.dart';
import 'fake_online_source.dart';

const _id = 'RpkAZYU8AAA';

/// Records what would be queued; nothing is downloaded.
class _RecordingEngine extends Fake implements DownloadEngine {
  final List<Map<String, Object?>> enqueued = [];

  @override
  Future<void> enqueueDownload({
    required String id,
    required Uri url,
    required String displayName,
    required String suggestedFileName,
    String? kind,
    String? thumbnailUrl,
    String? qualityLabel,
    String? uploader,
    int? durationSec,
    int? totalBytes,
    String? linkSource,
  }) async {
    enqueued.add({
      'id': id,
      'url': url,
      'displayName': displayName,
      'suggestedFileName': suggestedFileName,
      'kind': kind,
      'thumbnailUrl': thumbnailUrl,
      'qualityLabel': qualityLabel,
      'uploader': uploader,
      'durationSec': durationSec,
      'totalBytes': totalBytes,
      'linkSource': linkSource,
    });
  }
}

YoutubeDirectChoice _video(int height) => YoutubeDirectChoice(
      id: 'yt_v$height',
      uri: Uri.parse('https://rr1---sn-test.googlevideo.com/videoplayback?itag=$height'),
      isAudio: false,
      label: '${height}p',
      container: 'mp4',
      fileExtension: 'mp4',
      qualityLabel: '${height}p',
      height: height,
    );

final _audio = YoutubeDirectChoice(
  id: 'yt_audio',
  uri: Uri.parse('https://rr1---sn-test.googlevideo.com/videoplayback?itag=140'),
  isAudio: true,
  label: 'Audio only (M4A, 128 kbps)',
  container: 'mp4',
  fileExtension: 'm4a',
  qualityLabel: 'Audio 128 kbps',
);

void main() {
  late AppDatabase db;
  late _RecordingEngine engine;
  late FakeOnlineSource source;
  late ExtractorYoutubeFallback fallback;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    engine = _RecordingEngine();
    source = FakeOnlineSource();
    fallback = ExtractorYoutubeFallback(
      engine: engine,
      resolver: () => YoutubeDirectResolver(
        source: source,
        fetchDetails: (id) async => YoutubeVideoDetails(id: id, title: 'From YouTube', author: 'Channel'),
      ),
      newId: () => '1700000000000001',
    );
  });

  tearDown(() => db.close());

  /// An extractor row as the runner has it.
  Future<DownloadEntry> row({
    String url = 'https://www.youtube.com/watch?v=$_id',
    String kind = 'video',
    String? selector = 'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b',
    String? audioFormat,
  }) async {
    final now = DateTime(2026, 11, 19);
    await db.into(db.downloadsTable).insert(DownloadsTableCompanion.insert(
          id: 'x1',
          url: url,
          host: Uri.parse(url).host,
          displayName: 'Mountain Song',
          fileName: 'Mountain Song.mp4',
          state: 'downloading',
          createdAt: now,
          updatedAt: now,
          kind: Value(kind),
          engine: const Value('extractor'),
          thumbnailUrl: const Value('https://i.ytimg.com/vi/$_id/hqdefault.jpg'),
          qualityLabel: const Value('1080p'),
          formatSelector: Value(selector),
          audioFormat: Value(audioFormat),
          uploader: const Value('Himal Sessions'),
          durationSec: const Value(210),
        ));
    return (db.select(db.downloadsTable)..where((t) => t.id.equals('x1'))).getSingle();
  }

  group('which file replaces the download', () {
    test('audio for an audio download', () {
      expect(ExtractorYoutubeFallback.pick([_video(360), _audio], audio: true), same(_audio));
      expect(ExtractorYoutubeFallback.pick([_video(360)], audio: true), isNull);
    });

    test('the highest video with sound that is not above the chosen height', () {
      final all = [_video(360), _video(720), _audio];
      expect(ExtractorYoutubeFallback.pick(all, audio: false, maxHeight: 1080)!.height, 720);
      expect(ExtractorYoutubeFallback.pick(all, audio: false, maxHeight: 480)!.height, 360);
      expect(ExtractorYoutubeFallback.pick(all, audio: false)!.height, 720);
      // Nothing that low: the lowest there is.
      expect(ExtractorYoutubeFallback.pick(all, audio: false, maxHeight: 240)!.height, 360);
      expect(ExtractorYoutubeFallback.pick([_audio], audio: false), isNull);
    });
  });

  test('a failed 1080p download is replaced by the 360p file, and the item says it is lower quality', () async {
    final queued = await fallback(await row(), stillWanted: () => true);

    expect(queued, isTrue);
    final q = engine.enqueued.single;
    expect((q['url']! as Uri).host, 'rr1---sn-test.googlevideo.com');
    expect(q['qualityLabel'], '360p · lower quality');
    expect(q['kind'], 'video', reason: 'a video stays in Videos');
    expect(q['displayName'], 'Mountain Song');
    expect(q['suggestedFileName'], 'Mountain Song.mp4');
    expect(q['thumbnailUrl'], 'https://i.ytimg.com/vi/$_id/hqdefault.jpg');
    expect(q['uploader'], 'Himal Sessions');
    expect(q['durationSec'], 210);
    expect(q['totalBytes'], 12 * 1024 * 1024);
    expect(q['id'], '1700000000000001');
    expect(q['linkSource'], isNull, reason: 'Android rows stay as they were');
    expect(source.streamCalls, [_id]);
  });

  test('an MP3 download is replaced by the M4A audio (Music), also marked lower quality', () async {
    final queued = await fallback(await row(kind: 'audio', selector: 'ba/b', audioFormat: 'mp3'), stillWanted: () => true);
    expect(queued, isTrue);
    final q = engine.enqueued.single;
    expect(q['kind'], 'audio');
    expect(q['suggestedFileName'], 'Mountain Song.m4a');
    expect(q['qualityLabel'], 'Audio 128 kbps · lower quality');
  });

  test('nothing is queued once the user paused or cancelled', () async {
    expect(await fallback(await row(), stillWanted: () => false), isFalse);
    expect(engine.enqueued, isEmpty);
  });

  test('nothing is queued when YouTube has nothing either', () async {
    final r = await row();
    source.onStreams = (_) async => throw const OnlineException('This video is private or age-restricted.');
    expect(await fallback(r, stillWanted: () => true), isFalse);

    source.onStreams = (_) async => const OnlineStreams(audio: [], video: []);
    expect(await fallback(r, stillWanted: () => true), isFalse);
    expect(engine.enqueued, isEmpty);
  });

  test('a link that is not a YouTube video is left alone', () async {
    final r = await row(url: 'https://vimeo.com/123');
    expect(await fallback(r, stillWanted: () => true), isFalse);
    expect(source.streamCalls, isEmpty);
  });

  test('a stream address off YouTube\'s media servers is never queued', () async {
    source.onStreams = (_) async => const OnlineStreams(audio: [], video: [
          OnlineStream(
            url: 'https://evil.example/video.mp4',
            kind: OnlineStreamKind.video,
            label: '360p',
            container: 'mp4',
            sizeBytes: 100,
            height: 360,
          ),
        ]);
    expect(await fallback(await row(), stillWanted: () => true), isFalse);
    expect(engine.enqueued, isEmpty);
  });

  test('wired into the runner (as the app does): yt-dlp fails, the 360p file is queued, the failed row goes', () async {
    final dir = await Directory.systemTemp.createTemp('extractor_fallback_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final backend = FakeExtractorBackend()
      ..simulateError = true
      ..errorCode = 'FORMAT_UNAVAILABLE';
    final runner = ExtractorDownloadRunner(
      db: db,
      backend: backend,
      downloadDir: dir,
      publish: (_) {},
      fallback: fallback.call,
    );
    final meta = FakeExtractorBackend.sampleMetadata();
    final id = await runner.enqueue(
      meta: meta,
      pageUrl: 'https://www.youtube.com/watch?v=$_id',
      choice: FormatOptions.build(meta).firstWhere((c) => c.id == 'v1080'),
    );
    await runner.run(id);

    expect(engine.enqueued.single['qualityLabel'], '360p · lower quality');
    expect(engine.enqueued.single['displayName'], 'Sample Test Video');
    expect(await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingleOrNull(), isNull);
  });

  test('a link problem (private) is never replaced', () async {
    final dir = await Directory.systemTemp.createTemp('extractor_fallback_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final backend = FakeExtractorBackend()
      ..simulateError = true
      ..errorCode = 'PRIVATE_CONTENT';
    final runner = ExtractorDownloadRunner(db: db, backend: backend, downloadDir: dir, publish: (_) {}, fallback: fallback.call);
    final meta = FakeExtractorBackend.sampleMetadata();
    final id = await runner.enqueue(
      meta: meta,
      pageUrl: 'https://www.youtube.com/watch?v=$_id',
      choice: FormatOptions.build(meta).firstWhere((c) => c.id == 'v720'),
    );
    await runner.run(id);
    expect(engine.enqueued, isEmpty);
    expect(source.streamCalls, isEmpty);
    final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(row.errorCode, 'x_private_content');
  });
}
