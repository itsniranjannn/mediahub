import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/safe_filename.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/personal/format_options.dart';
import 'package:path/path.dart' as p;

import 'fake_extractor_backend.dart';
import 'test_safe_http_client_seam.dart';

/// A long Nepali song title (well over 100 characters; 3 UTF-8 bytes each).
const String _nepali =
    'सयौं थुँगा फूलका हामी एउटै माला नेपाली सार्वभौम भई फैलिएका मेची-महाकाली '
    'प्रकृतिका कोटी-कोटी सम्पदाको आँचल वीरहरूका रगतले स्वतन्त्र र अटल '
    'ज्ञानभूमि शान्तिभूमि तराई पहाड हिमाल अखण्ड यो प्यारो हाम्रो मातृभूमि नेपाल';

int _bytes(String s) => utf8.encode(s).length;

/// [cut] is the start of [original], ending between two whole characters.
void _expectWholeCharacterPrefix(String cut, String original) {
  final c = cut.characters.toList();
  expect(c, original.characters.take(c.length).toList(), reason: 'cut inside a character');
}

final List<int> _mp3Bytes = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A, ...List.filled(512, 0xAA)];

Future<HttpServer> _serveBytes(List<int> payload) async {
  final serverContext = SecurityContext()
    ..useCertificateChain('test/certs/localhost.crt')
    ..usePrivateKey('test/certs/localhost.key');
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
  server.listen((HttpRequest req) {
    req.response.statusCode = 200;
    req.response.headers.set(HttpHeaders.contentLengthHeader, payload.length.toString());
    req.response.add(payload);
    req.response.close();
  });
  return server;
}

SafeHttpClient _localClient() {
  final clientContext = SecurityContext()..setTrustedCertificates('test/certs/localhost.crt');
  return SafeHttpClient(
    customSecurityContext: clientContext,
    seam: const TestSafeHttpClientSeam(),
    dnsResolver: (host) async => [InternetAddress.loopbackIPv4],
  );
}

void main() {
  test('the title is long enough to have broken the old 120-character rule', () {
    expect(_nepali.length, greaterThan(100));
    expect(_bytes(_nepali.substring(0, 120)), greaterThan(255));
  });

  group('SafeFilename byte budget (SEC-2)', () {
    test('a 100+ character Devanagari title fits the 255-byte name limit', () {
      final name = SafeFilename.sanitize('$_nepali.mp3');
      expect(_bytes(name), lessThanOrEqualTo(SafeFilename.maxFilenameBytes));
      expect(name.endsWith('.mp3'), isTrue);
      final base = p.basenameWithoutExtension(name);
      expect(_bytes(base), lessThanOrEqualTo(SafeFilename.maxBaseNameBytes));
      expect(base.length, greaterThan(50), reason: 'still most of the title, not a fallback');
      _expectWholeCharacterPrefix(base, _nepali);
    });

    test('never cut inside a conjunct, an accented letter or an emoji', () {
      // क्ष (ka + virama + ssa) and कि (ka + vowel sign) are one character
      // each; an emoji is a surrogate pair.
      for (final unit in ['क्षि', 'é', '😀', '👍🏽']) {
        final raw = unit * 150;
        final base = SafeFilename.sanitize(raw);
        expect(_bytes(base), lessThanOrEqualTo(SafeFilename.maxBaseNameBytes), reason: unit);
        _expectWholeCharacterPrefix(base, raw);
        expect(base.contains('�'), isFalse);
        expect(utf8.decode(utf8.encode(base)), base, reason: 'no lone surrogate');
      }
    });

    test('a cut that ends in a space or dot is tidied', () {
      // 66 letters (198 bytes) then " . x": the cut lands right after them.
      final raw = '${'अ' * 66} . ${'x' * 40}.mp3';
      final name = SafeFilename.sanitize(raw);
      final base = p.basenameWithoutExtension(name);
      expect(base.endsWith(' '), isFalse);
      expect(base.endsWith('.'), isFalse);
      expect(name.endsWith('.mp3'), isTrue);
    });

    test('ASCII names keep the old 120-character limit', () {
      final name = SafeFilename.sanitize('${'a' * 150}.mp3');
      expect(name.length, lessThanOrEqualTo(120));
      expect(name.endsWith('.mp3'), isTrue);
    });

    test('a finished media name (.part dropped) fits too', () {
      final name = SafeFilename.finalMediaName('$_nepali.part', mediaExtension: 'mp3');
      expect(name.endsWith('.mp3'), isTrue);
      expect(_bytes(name), lessThanOrEqualTo(SafeFilename.maxFilenameBytes));
    });

    test('the " (n)" duplicate name keeps within the limit, even for an over-long base', () {
      final base = p.basenameWithoutExtension(SafeFilename.sanitize('$_nepali.webm'));
      for (final n in [1, 9, 10, 999, 123456]) {
        final name = SafeFilename.numbered(base, n, '.webm');
        expect(_bytes(name), lessThanOrEqualTo(SafeFilename.maxFilenameBytes), reason: '$n');
        expect(name.endsWith(' ($n).webm'), isTrue);
      }
      final huge = SafeFilename.numbered(_nepali * 2, 3, '.mp3');
      expect(_bytes(huge), lessThanOrEqualTo(SafeFilename.maxFilenameBytes));
      expect(huge.endsWith(' (3).mp3'), isTrue);
      _expectWholeCharacterPrefix(huge.substring(0, huge.length - ' (3).mp3'.length), _nepali * 2);
      expect(SafeFilename.numbered('song', 2, '.mp3'), 'song (2).mp3');
      expect(SafeFilename.numbered('', 2, '.mp3'), 'download (2).mp3');
    });
  });

  group('downloads save a long Devanagari title, also as a duplicate', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dir = await Directory.systemTemp.createTemp('safe_name_bytes_');
    });

    tearDown(() async {
      await db.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('direct link: the " (1)" name stays within 255 bytes', () async {
      final server = await _serveBytes(_mp3Bytes);
      try {
        final engine = DownloadEngine(db: db, httpClient: _localClient(), downloadDir: dir);
        final suggested = '$_nepali.mp3';
        // The same song was saved before.
        final first = SafeFilename.finalMediaName(suggested, mediaExtension: 'mp3');
        File(p.join(dir.path, first)).writeAsStringSync('earlier');

        await engine.enqueueDownload(
          id: 'dl_np',
          url: Uri.parse('https://localhost:${server.port}/song.mp3'),
          displayName: _nepali,
          suggestedFileName: suggested,
        );
        await engine.runTask('dl_np');

        final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals('dl_np'))).getSingle();
        expect(row.state, DownloadTaskState.completed.name);
        final name = p.basename(row.finalPath!);
        expect(name.endsWith(' (1).mp3'), isTrue, reason: name);
        expect(_bytes(name), lessThanOrEqualTo(255));
        expect(File(row.finalPath!).existsSync(), isTrue);
        engine.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('web link (yt-dlp): the " (1)" name stays within 255 bytes', () async {
      final runner = ExtractorDownloadRunner(
        db: db,
        backend: FakeExtractorBackend(),
        downloadDir: dir,
        publish: (_) {},
      );
      final meta = FakeExtractorBackend.sampleMetadata();
      final choice = FormatOptions.build(meta).firstWhere((c) => c.id == 'v1080');
      final id = await runner.enqueue(meta: meta, pageUrl: 'https://www.youtube.com/watch?v=abc', choice: choice);
      await (db.update(db.downloadsTable)..where((t) => t.id.equals(id)))
          .write(const DownloadsTableCompanion(displayName: Value(_nepali)));
      final base = p.basenameWithoutExtension(SafeFilename.sanitize('$_nepali.mp4'));
      File(p.join(dir.path, '$base.mp4')).writeAsStringSync('earlier');

      await runner.run(id);

      final row = await (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
      expect(row.state, 'completed');
      final name = p.basename(row.finalPath!);
      expect(name.endsWith(' (1).mp4'), isTrue, reason: name);
      expect(_bytes(name), lessThanOrEqualTo(255));
      expect(_bytes(base), lessThanOrEqualTo(SafeFilename.maxBaseNameBytes));
    });
  });
}
