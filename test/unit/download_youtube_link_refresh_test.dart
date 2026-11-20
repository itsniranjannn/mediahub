import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/downloads/youtube_stream_source.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/downloads/youtube_direct_resolver.dart';
import 'package:mediahub/features/downloads/youtube_link_refresher.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

import 'fake_online_source.dart';
import 'test_safe_http_client_seam.dart';

/// iPhone YouTube downloads (no yt-dlp) save YouTube's link to the file,
/// which stops working after about six hours. The row keeps the video and the
/// chosen quality, and the engine looks the link up again: before it starts
/// with a link that is too old, and once when the server refuses the link.

const _videoId = 'dQw4w9WgXcQ';

/// Scripted stand-in for the YouTube lookup.
class _FakeRefresher implements StreamLinkRefresher {
  bool stale = false;
  Future<RefreshedStreamLink?> Function(DownloadEntry task)? next;
  final List<String> calls = [];

  @override
  bool canRefresh(DownloadEntry task) => task.formatSelector == 'refreshable';

  @override
  bool isStale(DownloadEntry task, DateTime now) => stale;

  @override
  Future<RefreshedStreamLink?> refresh(DownloadEntry task) async {
    calls.add(Uri.parse(task.url).path);
    final handler = next;
    return handler == null ? null : handler(task);
  }
}

Uint8List _m4a(int length, {int seed = 7}) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31 + seed) & 0xFF;
  }
  const header = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20]; // ....ftypM4A
  bytes.setRange(0, header.length, header);
  return bytes;
}

void main() {
  HttpOverrides.global = null;

  tearDown(PlatformInfo.resetForTests);

  group('DownloadEngine with a link refresher', () {
    late AppDatabase db;
    late Directory tempDir;
    late HttpServer server;
    late SafeHttpClient client;
    late List<String> requests;
    final body = _m4a(120 * 1024);
    final otherBody = _m4a(90 * 1024, seed: 3);

    Future<void> serve(HttpRequest req, Uint8List data) async {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      if (match == null) {
        req.response.statusCode = 200;
        req.response.headers.set(HttpHeaders.contentLengthHeader, data.length.toString());
        req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        req.response.add(data);
        await req.response.close();
        return;
      }
      final start = int.parse(match.group(1)!);
      final end = match.group(2)!.isEmpty ? data.length - 1 : int.parse(match.group(2)!);
      req.response.statusCode = 206;
      req.response.headers.set('content-range', 'bytes $start-$end/${data.length}');
      req.response.headers.set(HttpHeaders.contentLengthHeader, (end - start + 1).toString());
      req.response.add(data.sublist(start, end + 1));
      await req.response.close();
    }

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('download_link_refresh_test_');
      requests = [];
      final certFile = File('test/certs/localhost.crt');
      final keyFile = File('test/certs/localhost.key');
      final serverContext = SecurityContext()
        ..useCertificateChain(certFile.path)
        ..usePrivateKey(keyFile.path);
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        requests.add('${req.uri.path}${range == null ? '' : ' $range'}');
        switch (req.uri.path) {
          case '/new':
            await serve(req, body);
          case '/other':
            await serve(req, otherBody);
          default: // '/old': YouTube's answer for an expired link
            req.response.statusCode = 403;
            await req.response.close();
        }
      });
      client = SafeHttpClient(
        customSecurityContext: SecurityContext()..setTrustedCertificates(certFile.path),
        seam: const TestSafeHttpClientSeam(),
        dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
      );
    });

    tearDown(() async {
      await server.close(force: true);
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Uri link(String path) => Uri.parse('https://localhost:${server.port}$path');

    Future<DownloadEntry> row(String id) => (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();

    /// A paused download that already has [have] bytes of [body] and an
    /// expiring link source.
    Future<void> queuePaused(DownloadEngine engine, String id, {int have = 0}) async {
      await engine.enqueueDownload(
        id: id,
        url: link('/old'),
        displayName: 'Song',
        suggestedFileName: 'Song.m4a',
        kind: 'audio',
        totalBytes: body.length,
        linkSource: 'refreshable',
      );
      if (have > 0) {
        File('${tempDir.path}/$id.part').writeAsBytesSync(body.sublist(0, have));
        await (db.update(db.downloadsTable)..where((t) => t.id.equals(id))).write(
          DownloadsTableCompanion(receivedBytes: Value(have), supportsRange: const Value(true)),
        );
      }
    }

    test('a refused link is looked up again and the download carries on where it stopped', () async {
      final refresher = _FakeRefresher()
        ..next = (_) async => RefreshedStreamLink(uri: link('/new'), linkSource: 'refreshable', sizeBytes: body.length);
      final engine = DownloadEngine(
        db: db,
        httpClient: client,
        downloadDir: tempDir,
        freeSpaceProvider: () async => null,
        streamLinkRefresher: refresher,
      );
      const id = '1700000000901';
      await queuePaused(engine, id, have: 40 * 1024);

      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.completed.name, reason: 'error ${done.errorCode}');
      expect(requests, ['/old bytes=40960-', '/new bytes=40960-'], reason: 'the partial file is kept');
      expect(refresher.calls, ['/old']);
      expect(File(done.finalPath!).readAsBytesSync(), body);
      expect(Uri.parse(done.url).path, '/new');
      expect(done.host, 'localhost');
      engine.dispose();
    });

    test('a link known to be too old is looked up before it is used', () async {
      final refresher = _FakeRefresher()
        ..stale = true
        ..next = (_) async => RefreshedStreamLink(uri: link('/new'), linkSource: 'refreshable', sizeBytes: body.length);
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, streamLinkRefresher: refresher);
      const id = '1700000000902';
      await queuePaused(engine, id, have: 50 * 1024);

      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.completed.name, reason: 'error ${done.errorCode}');
      expect(requests, ['/new bytes=51200-'], reason: 'the old link is never asked');
      expect(refresher.calls, ['/old']);
      expect(File(done.finalPath!).readAsBytesSync(), body);
      engine.dispose();
    });

    test('a different file at the new address starts over from the beginning', () async {
      final refresher = _FakeRefresher()
        ..next = (_) async => RefreshedStreamLink(
              uri: link('/other'),
              linkSource: 'refreshable',
              sizeBytes: otherBody.length,
              sameFile: false,
            );
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, streamLinkRefresher: refresher);
      const id = '1700000000903';
      await queuePaused(engine, id, have: 40 * 1024);

      await engine.runTask(id);

      final done = await row(id);
      expect(done.state, DownloadTaskState.completed.name, reason: 'error ${done.errorCode}');
      expect(requests, ['/old bytes=40960-', '/other']);
      expect(File(done.finalPath!).readAsBytesSync(), otherBody, reason: 'no bytes of the old file are mixed in');
      expect(done.totalBytes, otherBody.length);
      engine.dispose();
    });

    test('Android (no refresher): a refused link fails exactly as before', () async {
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir);
      const id = '1700000000904';
      await queuePaused(engine, id, have: 40 * 1024);

      await engine.runTask(id);

      final failed = await row(id);
      expect(failed.state, DownloadTaskState.failed.name);
      expect(failed.errorCode, 'http_403');
      expect(requests, ['/old bytes=40960-']);
      expect(File('${tempDir.path}/$id.part').lengthSync(), 40 * 1024, reason: 'kept for a later try');
      engine.dispose();
    });

    test('when no new link is found the download fails as before, its partial file kept', () async {
      final refresher = _FakeRefresher()..next = (_) async => null;
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, streamLinkRefresher: refresher);
      const id = '1700000000905';
      await queuePaused(engine, id, have: 40 * 1024);

      await engine.runTask(id);

      final failed = await row(id);
      expect(failed.errorCode, 'http_403');
      expect(Uri.parse(failed.url).path, '/old');
      expect(refresher.calls, ['/old']);
      expect(File('${tempDir.path}/$id.part').lengthSync(), 40 * 1024);
      engine.dispose();
    });

    test('only one new lookup per run: a new link that is refused too ends the run', () async {
      final refresher = _FakeRefresher()
        ..next = (_) async => RefreshedStreamLink(uri: link('/old'), linkSource: 'refreshable', sizeBytes: body.length);
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, streamLinkRefresher: refresher);
      const id = '1700000000906';
      await queuePaused(engine, id);

      await engine.runTask(id);

      expect((await row(id)).errorCode, 'http_403');
      expect(refresher.calls, hasLength(1));
      expect(requests, ['/old', '/old']);
      engine.dispose();
    });

    test('a pause while the link is being looked up wins', () async {
      final answer = Completer<RefreshedStreamLink?>();
      final refresher = _FakeRefresher()
        ..stale = true
        ..next = (_) => answer.future;
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, streamLinkRefresher: refresher);
      const id = '1700000000907';
      await queuePaused(engine, id, have: 40 * 1024);

      final running = engine.runTask(id);
      for (var i = 0; i < 50 && refresher.calls.isEmpty; i++) {
        await pumpEventQueue();
      }
      await engine.pause(id);
      answer.complete(RefreshedStreamLink(uri: link('/new'), linkSource: 'refreshable', sizeBytes: body.length));
      await running;

      final paused = await row(id);
      expect(paused.state, DownloadTaskState.paused.name);
      expect(requests, isEmpty);
      expect(Uri.parse(paused.url).path, '/new', reason: 'the new link is kept for the resume');
      engine.dispose();
    });

    test('rows without a link source are never looked up', () async {
      final refresher = _FakeRefresher()
        ..stale = true
        ..next = (_) async => RefreshedStreamLink(uri: link('/new'));
      final engine = DownloadEngine(db: db, httpClient: client, downloadDir: tempDir, streamLinkRefresher: refresher);
      const id = '1700000000908';
      await engine.enqueueDownload(id: id, url: link('/old'), displayName: 'Song', suggestedFileName: 'Song.m4a');

      await engine.runTask(id);

      expect((await row(id)).errorCode, 'http_403');
      expect(refresher.calls, isEmpty);
      engine.dispose();
    });
  });

  group('YoutubeStreamSource', () {
    test('round trip', () {
      final source = YoutubeStreamSource(
        videoId: _videoId,
        choiceId: 'yt_v360',
        itag: 18,
        resolvedAt: DateTime.fromMillisecondsSinceEpoch(1763450000 * 1000),
      );
      final back = YoutubeStreamSource.tryDecode(source.encode())!;
      expect(back.videoId, _videoId);
      expect(back.choiceId, 'yt_v360');
      expect(back.itag, 18);
      expect(back.resolvedAt, source.resolvedAt);
    });

    test('anything else is not a source', () {
      for (final stored in [
        null,
        '',
        'bestvideo+bestaudio', // a yt-dlp format selector
        'youtube-direct:',
        'youtube-direct:{"v":"bad id","c":"yt_audio","t":1}',
        'youtube-direct:{"v":"$_videoId","t":1}',
        'youtube-direct:not json',
      ]) {
        expect(YoutubeStreamSource.tryDecode(stored), isNull, reason: stored);
      }
    });

    test('a link is old when past its stated end (less a margin) or older than five hours', () {
      final now = DateTime(2026, 11, 18, 12);
      final resolved = now.subtract(const Duration(hours: 1));
      Uri ending(Duration fromNow) => Uri.parse(
          'https://rr1---sn-test.googlevideo.com/videoplayback?itag=18&expire=${now.add(fromNow).millisecondsSinceEpoch ~/ 1000}');
      expect(YoutubeStreamSource.linkExpired(ending(const Duration(hours: 2)), resolved, now), isFalse);
      expect(YoutubeStreamSource.linkExpired(ending(const Duration(minutes: 5)), resolved, now), isTrue);
      expect(YoutubeStreamSource.linkExpired(ending(const Duration(hours: -1)), resolved, now), isTrue);
      final noEnd = Uri.parse('https://rr1---sn-test.googlevideo.com/videoplayback?itag=18');
      expect(YoutubeStreamSource.linkExpired(noEnd, resolved, now), isFalse);
      expect(YoutubeStreamSource.linkExpired(noEnd, now.subtract(const Duration(hours: 6)), now), isTrue);
    });
  });

  group('YoutubeLinkRefresher', () {
    late FakeOnlineSource source;
    final clock = DateTime(2026, 11, 18, 20);
    final saved = DateTime(2026, 11, 18, 8);

    YoutubeLinkRefresher refresher({bool mp4Only = true}) => YoutubeLinkRefresher(
          resolver: () => YoutubeDirectResolver(
            source: source,
            fetchDetails: (id) async => throw UnimplementedError(),
            mp4Only: mp4Only,
          ),
          clock: () => clock,
        );

    DownloadEntry task({String? formatSelector, String engine = 'http', String? url}) => DownloadEntry(
          id: '1',
          url: url ?? 'https://rr9---sn-old.googlevideo.com/videoplayback?itag=140&expire=1',
          host: 'rr9---sn-old.googlevideo.com',
          displayName: 'Song',
          fileName: 'Song.m4a',
          state: 'failed',
          receivedBytes: 0,
          supportsRange: true,
          createdAt: saved,
          updatedAt: saved,
          engine: engine,
          formatSelector: formatSelector,
        );

    String sourceFor(String choice, {int? itag}) =>
        YoutubeStreamSource(videoId: _videoId, choiceId: choice, itag: itag, resolvedAt: saved).encode();

    setUp(() => source = FakeOnlineSource());

    test('only rows made by the iPhone YouTube path can be looked up', () {
      final r = refresher();
      expect(r.canRefresh(task(formatSelector: sourceFor('yt_audio', itag: 140))), isTrue);
      expect(r.canRefresh(task()), isFalse);
      expect(r.canRefresh(task(formatSelector: 'bestaudio')), isFalse);
      expect(r.canRefresh(task(formatSelector: sourceFor('yt_audio'), engine: 'extractor')), isFalse);
    });

    test('stale: past the end the link states, or saved too long ago', () {
      final r = refresher();
      expect(r.isStale(task(formatSelector: sourceFor('yt_audio', itag: 140)), clock), isTrue);
      final fresh = task(
        formatSelector: YoutubeStreamSource(videoId: _videoId, choiceId: 'yt_audio', resolvedAt: clock).encode(),
        url: 'https://rr9---sn-old.googlevideo.com/videoplayback?itag=140'
            '&expire=${clock.add(const Duration(hours: 5)).millisecondsSinceEpoch ~/ 1000}',
      );
      expect(r.isStale(fresh, clock), isFalse);
      expect(r.isStale(task(), clock), isFalse, reason: 'no source: never');
    });

    test('the same file again when YouTube still offers it (the partial file carries on)', () async {
      final fresh = await refresher().refresh(task(formatSelector: sourceFor('yt_audio', itag: 140)));
      expect(source.streamCalls, [_videoId]);
      expect(fresh, isNotNull);
      expect(fresh!.uri.toString(), 'https://rr1---sn-test.googlevideo.com/videoplayback?itag=140');
      expect(fresh.sameFile, isTrue);
      expect(fresh.sizeBytes, 3 * 1024 * 1024);
      final next = YoutubeStreamSource.tryDecode(fresh.linkSource)!;
      expect(next.itag, 140);
      expect(next.resolvedAt, clock);
    });

    test('the itag is read from the saved link when the source has none', () async {
      final fresh = await refresher().refresh(task(formatSelector: sourceFor('yt_audio')));
      expect(fresh!.sameFile, isTrue);
      expect(YoutubeStreamSource.itagOf(fresh.uri), 140);
    });

    test('that file is gone: the same choice in today\'s file, starting over', () async {
      source.onStreams = (_) async => const OnlineStreams(
            video: [],
            audio: [
              OnlineStream(
                url: 'https://rr2---sn-test.googlevideo.com/videoplayback?itag=139',
                kind: OnlineStreamKind.audio,
                label: '48 kbps',
                container: 'mp4',
                sizeBytes: 1024 * 1024,
                bitrateKbps: 48,
              ),
            ],
          );
      final fresh = await refresher().refresh(task(formatSelector: sourceFor('yt_audio', itag: 140)));
      expect(fresh!.uri.host, 'rr2---sn-test.googlevideo.com');
      expect(fresh.sameFile, isFalse);
      expect(fresh.sizeBytes, 1024 * 1024);
      expect(YoutubeStreamSource.tryDecode(fresh.linkSource)!.itag, 139);
    });

    test('nothing usable: no new link', () async {
      // The quality is not offered any more.
      expect(await refresher().refresh(task(formatSelector: sourceFor('yt_v720', itag: 22))), isNull);

      // The lookup fails.
      source.onStreams = (_) async => throw TimeoutException('slow');
      expect(await refresher().refresh(task(formatSelector: sourceFor('yt_audio', itag: 140))), isNull);

      // A matching file on some other server is never used.
      source.onStreams = (_) async => const OnlineStreams(
            video: [],
            audio: [
              OnlineStream(
                url: 'https://evil.example.com/videoplayback?itag=140',
                kind: OnlineStreamKind.audio,
                label: '128 kbps',
                container: 'mp4',
                sizeBytes: 100,
              ),
            ],
          );
      expect(await refresher().refresh(task(formatSelector: sourceFor('yt_audio', itag: 140))), isNull);

      // iPhone: WebM never replaces an M4A.
      source.onStreams = (_) async => const OnlineStreams(
            video: [],
            audio: [
              OnlineStream(
                url: 'https://rr2---sn-test.googlevideo.com/videoplayback?itag=251',
                kind: OnlineStreamKind.audio,
                label: '160 kbps',
                container: 'webm',
                sizeBytes: 100,
              ),
            ],
          );
      expect(await refresher().refresh(task(formatSelector: sourceFor('yt_audio', itag: 140))), isNull);

      // No source on the row.
      expect(await refresher().refresh(task()), isNull);
    });
  });

  group('wiring', () {
    ProviderContainer container(AppDatabase db, Directory dir) {
      final c = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        downloadDirectoryProvider.overrideWith((ref) async => dir),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('iPhone looks expired links up again; Android keeps its engine as it was', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dir = await Directory.systemTemp.createTemp('download_link_refresh_wiring_');
      addTearDown(() => dir.deleteSync(recursive: true));

      PlatformInfo.debugIsAndroid = false;
      PlatformInfo.debugIsIOS = true;
      expect(container(db, dir).read(downloadEngineProvider).refreshesExpiredLinks, isTrue);

      PlatformInfo.debugIsAndroid = true;
      PlatformInfo.debugIsIOS = false;
      expect(container(db, dir).read(downloadEngineProvider).refreshesExpiredLinks, isFalse);
    });
  });
}
