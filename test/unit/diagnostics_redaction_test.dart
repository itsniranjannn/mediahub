import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';

void main() {
  final diagnostics = DiagnosticsService.instance;

  setUp(() async {
    DiagnosticsService.enableDebounce = false;
    await diagnostics.clear();
  });

  /// Logs one event and returns its details as decoded from the log line.
  Map<String, dynamic> logAndDecode(Map<String, dynamic> details) {
    diagnostics.logEvent('probe', details);
    final line = diagnostics.logs.last;
    final match = RegExp(r'^\[\d\d:\d\d:\d\d\] probe (.*)$').firstMatch(line);
    expect(match, isNotNull, reason: 'log format is "[hh:mm:ss] event {json}": $line');
    return Map<String, dynamic>.from(jsonDecode(match!.group(1)!) as Map);
  }

  group('redact() finds links and paths anywhere in the text', () {
    test('http and https links', () {
      expect(
        DiagnosticsService.redact('Failed for https://rr3---sn.googlevideo.com/videoplayback?ip=1.2.3.4&sig=x now'),
        'Failed for <url> now',
      );
      expect(DiagnosticsService.redact('GET http://example.com/a b'), 'GET <url> b');
      expect(DiagnosticsService.redact('HTTPS://EXAMPLE.COM/x'), '<url>');
    });

    test('file and content links', () {
      expect(
        DiagnosticsService.redact('cannot open file:///storage/emulated/0/Music/a.mp3 (denied)'),
        'cannot open <file> (denied)',
      );
      expect(
        DiagnosticsService.redact('uri content://media/external/audio/media/42 gone'),
        'uri <file> gone',
      );
    });

    test('Android and iOS storage paths', () {
      for (final path in [
        '/data/user/0/com.example.mediahub/app_flutter/x.db',
        '/storage/emulated/0/Download/song.m4a',
        '/sdcard/Movies/clip.mp4',
        '/mnt/media_rw/1234-5678/a.mp3',
        '/private/var/mobile/Containers/Data/Application/ABC/Documents/a.mp3',
        '/var/mobile/Containers/Data/Application/ABC/Documents/a.mp3',
      ]) {
        expect(DiagnosticsService.redact('open($path) failed'), 'open(<path> failed',
            reason: path);
        expect(DiagnosticsService.redact('error at $path'), 'error at <path>', reason: path);
      }
    });

    test('Windows drive paths', () {
      expect(DiagnosticsService.redact(r'cannot read C:\Users\me\Music\a.mp3 now'),
          'cannot read <path> now');
      expect(DiagnosticsService.redact('cannot read d:/media/a.mp3'), 'cannot read <path>');
    });

    test('a quoted path or link is hidden up to the closing quote, spaces included', () {
      expect(
        DiagnosticsService.redact(
            "FileSystemException: Cannot open file, path = '/storage/emulated/0/My Music/a b.mp3' (OS Error: 2)"),
        "FileSystemException: Cannot open file, path = '<path>' (OS Error: 2)",
      );
      expect(
        DiagnosticsService.redact('Invalid argument(s): "https://example.com/a b c"'),
        'Invalid argument(s): "<url>"',
      );
    });

    test('apostrophes inside a single-quoted path do not end it early', () {
      expect(
        DiagnosticsService.redact("FileSystemException: Cannot open file, path = "
            "'/storage/emulated/0/Music/Don't Stop Me Now.mp3' (OS Error: 2)"),
        "FileSystemException: Cannot open file, path = '<path>' (OS Error: 2)",
      );
      expect(
        DiagnosticsService.redact(
            "Cannot open file, path = '/storage/emulated/0/Rock 'n' Roll/a.mp3' (OS Error: 13)"),
        "Cannot open file, path = '<path>' (OS Error: 13)",
      );
      expect(
        DiagnosticsService.redact("open '/storage/emulated/0/it's mine.mp3'"),
        "open '<path>'",
      );
    });

    test('an unquoted path with spaces is hidden up to its media file name', () {
      expect(
        DiagnosticsService.redact(
            'could not open /storage/emulated/0/Music/Private Song.mp3 (ENOENT)'),
        'could not open <path> (ENOENT)',
      );
      expect(
        DiagnosticsService.redact(r'read C:\Users\me\My Music\a b.FLAC failed'),
        'read <path> failed',
      );
    });

    test('a link ending in a media name still hides its query', () {
      expect(
        DiagnosticsService.redact('Failed for https://cdn.example/v.mp4?ip=203.0.113.9 now'),
        'Failed for <url> now',
      );
    });

    test('redacting an already-written JSON line keeps it valid JSON', () {
      final line = '[10:00:00] probe ${jsonEncode({
        'a': 'open "/storage/emulated/0/x y.mp3" failed',
        'b': "path = '/data/user/0/app/files/Don't.mp3'",
        'c': 'see https://example.com/a.mp3',
        'd': 'plain',
      })}';
      final redacted = DiagnosticsService.redact(line);
      final json = redacted.substring(redacted.indexOf('{'));
      expect(jsonDecode(json), {
        'a': 'open "<path>" failed',
        'b': "path = '<path>'",
        'c': 'see <url>',
        'd': 'plain',
      });
    });

    test('several secrets in one text are all replaced', () {
      expect(
        DiagnosticsService.redact('copy /storage/emulated/0/a.mp3 to https://x.example/up failed'),
        'copy <path> to <url> failed',
      );
    });

    test('text without links or paths is unchanged', () {
      for (final text in [
        'in_app',
        'SocketException: Connection refused (errno = 111)',
        'TimeoutException after 0:00:30.000000',
        'host=googlevideo.com status=403',
        'ratio 16:9 and 4:3',
        'metadata/missing',
      ]) {
        expect(DiagnosticsService.redact(text), text);
      }
    });

    test('an already redacted text stays the same', () {
      const text = 'Failed for <url> at <path> via <file>';
      expect(DiagnosticsService.redact(text), text);
    });
  });

  group('logEvent()', () {
    test('keeps the "[hh:mm:ss] event {json}" format and plain values', () {
      final details = logAndDecode({
        'caller': 'in_app',
        'count': 3,
        'ok': true,
        'none': null,
      });
      expect(details, {'caller': 'in_app', 'count': 3, 'ok': true, 'none': null});
    });

    test('an event without details is just the time and the name', () {
      diagnostics.logEvent('service_start');
      expect(diagnostics.logs.last, matches(RegExp(r'^\[\d\d:\d\d:\d\d\] service_start$')));
    });

    test('links and paths inside longer values are redacted', () {
      final details = logAndDecode({
        'error': 'HttpException: 403 for https://rr1---sn.googlevideo.com/videoplayback?ip=203.0.113.9',
        'reason': 'PathNotFoundException: Cannot open file, path = '
            "'/data/user/0/com.example.mediahub/files/My Song.mp3'",
        'win': r'copy failed: C:\Users\me\Downloads\x.part',
      });
      expect(details['error'], 'HttpException: 403 for <url>');
      expect(details['reason'],
          "PathNotFoundException: Cannot open file, path = '<path>'");
      expect(details['win'], 'copy failed: <path>');
      expect(diagnostics.logs.last, isNot(contains('googlevideo')));
      expect(diagnostics.logs.last, isNot(contains('203.0.113.9')));
      expect(diagnostics.logs.last, isNot(contains('My Song')));
    });

    test('a value that is a whole link or path (even with spaces) becomes one placeholder', () {
      final details = logAndDecode({
        'url': 'https://example.com/a?b=c',
        'file': 'file:///storage/emulated/0/My Music/a.mp3',
        'path': '/storage/emulated/0/My Music/a song.mp3',
        'uri': Uri.parse('https://example.com/x'),
      });
      expect(details, {'url': '<url>', 'file': '<file>', 'path': '<path>', 'uri': '<url>'});
    });

    test('bare media file names are still hidden', () {
      final details = logAndDecode({'name': 'Holiday video.mp4', 'song': 'track 01.MP3'});
      expect(details, {'name': '<sanitized>', 'song': '<sanitized>'});
    });

    test('lists and maps are redacted item by item', () {
      final details = logAndDecode({
        'urls': ['https://a.example/1', 'plain'],
        'nested': {'where': 'at /sdcard/x.bin', 'n': 1},
      });
      expect(details['urls'], ['<url>', 'plain']);
      expect(details['nested'], {'where': 'at <path>', 'n': 1});
    });
  });

  // Kept last: it points the shared service at a temp file.
  group('loading the log file at startup', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mediahub_diagnostics_test_');
      file = File('${dir.path}/diagnostics.log');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('old unredacted lines are scrubbed in memory and on disk right away', () async {
      await file.writeAsString([
        '[10:00:00] service_start',
        '[10:00:01] player_error {"error":"403 for '
            'https://rr1---sn.googlevideo.com/videoplayback?ip=203.0.113.9"}',
        '[10:00:02] scan_error {"reason":"path = '
            "'/storage/emulated/0/Music/Don't Stop.mp3'\"}",
      ].join('\n'));

      await diagnostics.initWithFile(file);

      const expected = [
        '[10:00:00] service_start',
        '[10:00:01] player_error {"error":"403 for <url>"}',
        '[10:00:02] scan_error {"reason":"path = \'<path>\'"}',
      ];
      expect(diagnostics.logs, expected);
      // No new event was logged, yet the file no longer holds the old text.
      expect(await file.readAsString(), expected.join('\n'));
    });

    test('a log without anything to redact is not rewritten', () async {
      const content = '[10:00:00] service_start\n[10:00:01] play {"caller":"in_app"}\n';
      await file.writeAsString(content);

      await diagnostics.initWithFile(file);

      expect(diagnostics.logs,
          ['[10:00:00] service_start', '[10:00:01] play {"caller":"in_app"}']);
      expect(await file.readAsString(), content,
          reason: 'a rewrite would have dropped the trailing newline');
    });
  });
}
