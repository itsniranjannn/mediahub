import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/content_disposition.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/direct_link_probe.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/repositories/direct_url_resolver.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/domain/repositories/platform_resolver.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:path/path.dart' as p;

import 'test_safe_http_client_seam.dart';

/// Direct https links to media work whatever the server says about them: no
/// extension, a query string, a generic type, a name only in
/// Content-Disposition or after a redirect, a server that compresses, or
/// ignores ranges. Every safety rule still holds.

final Uint8List _mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0, 0, 0, 0, 0, 0x0A, ...List.filled(8192, 0xAA)]);
final Uint8List _m4a = Uint8List.fromList([
  0, 0, 0, 24, ...ascii.encode('ftypM4A '), 0, 0, 0, 0, ...ascii.encode('M4A mp42'),
  ...List.filled(4096, 0),
]);

class _Reply {
  _Reply(this.body, {this.type, this.disposition, this.redirect, this.ignoreRange = false});
  final List<int> body;
  final String? type;
  final String? disposition;
  final String? redirect;
  final bool ignoreRange;
}

class _FakeResolver extends DirectUrlResolver {
  _FakeResolver(this.answer);
  final Future<SourceInfo> Function(Uri uri) answer;
  @override
  Future<SourceInfo> inspect(Uri uri) => answer(uri);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('ContentDisposition', () {
    test('plain, quoted and unquoted names', () {
      expect(ContentDisposition.fileName('attachment; filename="song.mp3"'), 'song.mp3');
      expect(ContentDisposition.fileName('attachment; filename=song.mp3'), 'song.mp3');
      expect(ContentDisposition.fileName('inline;filename=clip.mp4;size=12'), 'clip.mp4');
      expect(ContentDisposition.fileName('filename="bare.mp3"'), 'bare.mp3');
    });

    test("apostrophes, semicolons and escaped quotes inside the quotes are kept", () {
      expect(ContentDisposition.fileName('attachment; filename="Don\'t Stop Me Now.mp3"'), "Don't Stop Me Now.mp3");
      expect(ContentDisposition.fileName('attachment; filename="Live; Part 2.mp3"'), 'Live; Part 2.mp3');
      expect(ContentDisposition.fileName(r'attachment; filename="The \"Best\" Song.mp3"'), 'The "Best" Song.mp3');
    });

    test('the encoded name wins, in UTF-8 or Latin-1', () {
      expect(
        ContentDisposition.fileName("attachment; filename=\"fallback.mp3\"; filename*=UTF-8''%E0%A4%B0%E0%A5%87%E0%A4%B6%E0%A4%AE.mp3"),
        'रेशम.mp3',
      );
      expect(ContentDisposition.fileName("attachment; filename*=iso-8859-1'en'caf%E9.mp3"), 'café.mp3');
      expect(ContentDisposition.fileName("attachment; filename*=UTF-8''Don%27t%20Stop.mp3"), "Don't Stop.mp3");
    });

    test('percent signs never throw', () {
      expect(ContentDisposition.fileName('attachment; filename="100% Hits.mp3"'), '100% Hits.mp3');
      expect(ContentDisposition.fileName('attachment; filename="My%20Song.mp3"'), 'My Song.mp3');
      expect(ContentDisposition.fileName("attachment; filename*=UTF-8''bad%ZZ.mp3; filename=\"ok.mp3\""), 'ok.mp3');
    });

    test('nothing to read', () {
      expect(ContentDisposition.fileName(null), isNull);
      expect(ContentDisposition.fileName(''), isNull);
      expect(ContentDisposition.fileName('inline'), isNull);
      expect(ContentDisposition.fileName('attachment; filename=""'), isNull);
    });
  });

  group('against a real local server', () {
    late HttpServer server;
    late SafeHttpClient client;
    final replies = <String, _Reply>{};
    final acceptEncodings = <String?>[];

    Future<void> answer(HttpRequest req) async {
      acceptEncodings.add(req.headers.value(HttpHeaders.acceptEncodingHeader));
      final reply = replies[req.uri.path];
      final res = req.response;
      if (reply == null) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      if (reply.redirect != null) {
        res.statusCode = 302;
        res.headers.set(HttpHeaders.locationHeader, reply.redirect!);
        await res.close();
        return;
      }
      if (reply.type != null) res.headers.set(HttpHeaders.contentTypeHeader, reply.type!);
      if (reply.disposition != null) res.headers.set('content-disposition', reply.disposition!);
      var body = reply.body;
      // A download script with compression on: gzip whenever offered.
      final offered = req.headers.value(HttpHeaders.acceptEncodingHeader) ?? '';
      if (offered.contains('gzip')) {
        body = gzip.encode(body);
        res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final m = range == null ? null : RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (m != null && !reply.ignoreRange && !offered.contains('gzip')) {
        final start = int.parse(m.group(1)!);
        final end = m.group(2)!.isEmpty ? body.length - 1 : int.parse(m.group(2)!).clamp(0, body.length - 1);
        res.statusCode = 206;
        res.headers.set('content-range', 'bytes $start-$end/${body.length}');
        res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        res.headers.set(HttpHeaders.contentLengthHeader, '${end - start + 1}');
        res.add(body.sublist(start, end + 1));
      } else {
        res.statusCode = 200;
        res.headers.set(HttpHeaders.contentLengthHeader, '${body.length}');
        res.add(body);
      }
      await res.close();
    }

    setUp(() async {
      final serverContext = SecurityContext()
        ..useCertificateChain('test/certs/localhost.crt')
        ..usePrivateKey('test/certs/localhost.key');
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
      server.autoCompress = false;
      server.listen((req) async {
        try {
          await answer(req);
        } catch (_) {
          // The probe hangs up after the first bytes.
        }
      });
      client = SafeHttpClient(
        customSecurityContext: SecurityContext()..setTrustedCertificates('test/certs/localhost.crt'),
        seam: const TestSafeHttpClientSeam(),
        dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
      );
    });

    tearDown(() async {
      replies.clear();
      acceptEncodings.clear();
      await server.close(force: true);
    });

    Uri at(String pathAndQuery) => Uri.parse('https://localhost:${server.port}$pathAndQuery');

    SourceInfo unsupported(Uri uri, {String? type = 'application/octet-stream', String name = 'get'}) => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.metadata},
          restrictions: const ['unsupported_media_type'],
          contentType: type,
          suggestedFilename: name,
        );

    group('SafeHttpClient', () {
      test('asks for the file as it is, so a compressing server sends it untouched', () async {
        replies['/song.mp3'] = _Reply(_mp3, type: 'audio/mpeg');
        final res = await client.request(at('/song.mp3'), maxBodySize: 1 << 20);
        expect(acceptEncodings.single, 'identity');
        expect(res.bodyBytes, _mp3);
      });

      test('a caller that asks for an encoding keeps its own choice', () async {
        replies['/song.mp3'] = _Reply(_mp3, type: 'audio/mpeg');
        await client.request(at('/song.mp3'), headers: const {'Accept-Encoding': 'gzip'}, maxBodySize: 1 << 20);
        expect(acceptEncodings.single, 'gzip');
      });

      test('the download engine saves the real file from such a server', () async {
        replies['/download.php'] = _Reply(_mp3, type: 'application/octet-stream');
        final db = AppDatabase(NativeDatabase.memory());
        final dir = await Directory.systemTemp.createTemp('download_direct_links_test_');
        addTearDown(() async {
          await db.close();
          dir.deleteSync(recursive: true);
        });
        final engine = DownloadEngine(db: db, httpClient: client, downloadDir: dir, freeSpaceProvider: () async => 1 << 40);
        addTearDown(engine.dispose);
        await engine.enqueueDownload(
          id: '1700000000501',
          url: at('/download.php?id=7&token=abc'),
          displayName: 'Song',
          suggestedFileName: 'download.php',
        );
        await engine.runTask('1700000000501');
        final row = await (db.select(db.downloadsTable)).getSingle();
        expect(row.state, DownloadTaskState.completed.name, reason: row.errorCode);
        expect(await File(row.finalPath!).readAsBytes(), _mp3);
        expect(p.basename(row.finalPath!), 'download.mp3', reason: 'a script name is not a media name');
      });
    });

    group('DirectLinkProbe', () {
      test('a link with no extension and a generic type is media by its first bytes', () async {
        replies['/get'] = _Reply(_mp3, type: 'application/octet-stream');
        final uri = at('/get?id=123');
        final info = await DirectLinkProbe(client: client).refine(unsupported(uri), uri);
        expect(info!.isDownloadable, isTrue);
        expect(info.contentType, 'audio/mpeg');
        expect(info.suggestedFilename, 'get.mp3');
        expect(info.contentLength, _mp3.length);
        expect(info.supportsRange, isTrue);
        expect(info.uri, uri, reason: 'the download still uses the link as given');
      });

      test("S3's binary/octet-stream with the name only in Content-Disposition", () async {
        replies['/obj'] = _Reply(_m4a,
            type: 'binary/octet-stream', disposition: 'attachment; filename="Don\'t Stop.m4a"');
        final uri = at('/obj');
        final info = await DirectLinkProbe(client: client).refine(unsupported(uri, type: 'binary/octet-stream'), uri);
        expect(info!.isDownloadable, isTrue);
        expect(info.contentType, 'audio/mp4');
        expect(info.suggestedFilename, "Don't Stop.m4a");
      });

      test('a redirect: the name at the end of it is used', () async {
        replies['/r'] = _Reply(const [], redirect: '/files/Mountain%20Song.mp3');
        replies['/files/Mountain%20Song.mp3'] = _Reply(_mp3, type: 'audio/mpeg');
        final uri = at('/r');
        final media = SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.download},
          contentType: 'audio/mpeg',
          suggestedFilename: 'r',
        );
        expect(DirectLinkProbe.needsProbe(media), isTrue);
        final info = await DirectLinkProbe(client: client).refine(media, uri);
        expect(info!.suggestedFilename, 'Mountain Song.mp3');
        expect(info.contentType, 'audio/mpeg');
      });

      test('a server that ignores ranges: only the first bytes are read', () async {
        final big = Uint8List.fromList([..._mp3, ...List.filled(8 << 20, 0x55)]);
        replies['/big'] = _Reply(big, type: 'application/octet-stream', ignoreRange: true);
        final uri = at('/big');
        final watch = Stopwatch()..start();
        final info = await DirectLinkProbe(client: client).refine(unsupported(uri, name: 'big'), uri);
        expect(info!.isDownloadable, isTrue);
        expect(info.contentLength, big.length);
        expect(info.supportsRange, isFalse);
        expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      });

      test('a web page stays a web page', () async {
        replies['/page'] = _Reply(utf8.encode('<!doctype html><html><body>video</body></html>'), type: 'text/html');
        final uri = at('/page');
        final before = unsupported(uri, type: 'text/html', name: 'page');
        final info = await DirectLinkProbe(client: client).refine(before, uri);
        expect(info, same(before));
      });

      test('a check that failed outright is answered by the first bytes', () async {
        replies['/100%25%20Hits.mp3'] = _Reply(_mp3, type: 'audio/mpeg');
        final uri = at('/100%25%20Hits.mp3');
        final info = await DirectLinkProbe(client: client).refine(null, uri);
        expect(info!.isDownloadable, isTrue);
        expect(info.suggestedFilename, '100% Hits.mp3');
      });

      test('a private address is still refused (no probe gets through)', () async {
        replies['/get'] = _Reply(_mp3, type: 'application/octet-stream');
        final strict = SafeHttpClient(
          customSecurityContext: SecurityContext()..setTrustedCertificates('test/certs/localhost.crt'),
          dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
        );
        final uri = at('/get');
        final before = unsupported(uri);
        expect(await DirectLinkProbe(client: strict).refine(before, uri), same(before));
        expect(acceptEncodings, isEmpty, reason: 'nothing reached the server');
      });

      test('what needs a probe', () {
        final uri = Uri.parse('https://example.com/x');
        expect(DirectLinkProbe.needsProbe(unsupported(uri)), isTrue);
        expect(
          DirectLinkProbe.needsProbe(SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {},
            restrictions: const ['policy_violation'],
          )),
          isFalse,
        );
        expect(
          DirectLinkProbe.needsProbe(SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {},
            restrictions: const ['unreachable'],
          )),
          isFalse,
        );
        expect(
          DirectLinkProbe.needsProbe(SourceInfo(
            providerId: 'direct',
            uri: uri,
            capabilities: {SourceCapability.download},
            suggestedFilename: 'song.mp3',
          )),
          isFalse,
          reason: 'a media name needs nothing more',
        );
      });
    });

    group('the Downloads link check', () {
      ProviderContainer container0() {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
        addTearDown(container.dispose);
        return container;
      }

      test('an octet-stream link without an extension can be downloaded', () async {
        replies['/get'] = _Reply(_mp3, type: 'application/octet-stream');
        final container = container0();
        final notifier = container.read(inspectionProvider.notifier);
        notifier.setResolverForTesting(_FakeResolver((uri) async => unsupported(uri)), probe: DirectLinkProbe(client: client));
        await notifier.inspect(at('/get?id=1'));
        final result = container.read(inspectionProvider).result!;
        expect(result.isDownloadable, isTrue);
        expect(result.suggestedFilename, 'get.mp3');
      });

      test('a check that throws (an odd address) falls back to the first bytes', () async {
        replies['/x'] = _Reply(_mp3, type: 'audio/mpeg');
        final container = container0();
        final notifier = container.read(inspectionProvider.notifier);
        notifier.setResolverForTesting(_FakeResolver((uri) async => throw const FormatException('bad %')),
            probe: DirectLinkProbe(client: client));
        await notifier.inspect(at('/x'));
        expect(container.read(inspectionProvider).result!.isDownloadable, isTrue);
        expect(container.read(inspectionProvider).errorMessage, isNull);
      });

      test('nothing found either way: the old message', () async {
        final container = container0();
        final notifier = container.read(inspectionProvider.notifier);
        notifier.setResolverForTesting(_FakeResolver((uri) async => throw const FormatException('bad %')),
            probe: DirectLinkProbe(client: client));
        await notifier.inspect(at('/missing'));
        expect(container.read(inspectionProvider).errorMessage,
            'Unable to inspect link. Please ensure it is a valid direct link.');
      });
    });
  });
}
