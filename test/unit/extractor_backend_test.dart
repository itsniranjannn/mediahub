import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';

class FakeExtractorBackend implements ExtractorBackend {
  bool initialized = false;
  String currentVersion = '2026.11.01';
  bool simulateError = false;

  @override
  Future<bool> init() async {
    initialized = true;
    return true;
  }

  @override
  Future<String> getVersion() async {
    return currentVersion;
  }

  @override
  Future<String> update() async {
    currentVersion = '2026.11.02';
    return 'DONE';
  }

  @override
  Future<ExtractorMetadata> getInfo(String url) async {
    if (simulateError) {
      throw const ExtractorException('EXTRACTION_FAILED', 'Failed to extract info');
    }
    return ExtractorMetadata(
      id: 'test_vid_1',
      title: 'Sample Test Video',
      uploader: 'Test Author',
      durationSec: 120,
      thumbnailUrl: 'https://example.com/thumb.jpg',
      formats: const [
        ExtractorFormat(
          formatId: '137',
          ext: 'mp4',
          formatNote: '1080p',
          hasVideo: true,
          hasAudio: false,
          height: 1080,
          width: 1920,
          filesize: 15000000,
        ),
        ExtractorFormat(
          formatId: '140',
          ext: 'm4a',
          formatNote: 'medium',
          hasVideo: false,
          hasAudio: true,
          height: 0,
          width: 0,
          filesize: 3000000,
        ),
        ExtractorFormat(
          formatId: '18',
          ext: 'mp4',
          formatNote: '360p',
          hasVideo: true,
          hasAudio: true,
          height: 360,
          width: 640,
          filesize: 8000000,
        ),
      ],
    );
  }

  @override
  Future<String> download({
    required String taskId,
    required String url,
    required String outDir,
    String? formatSelector,
    void Function(double progress, int eta)? onProgress,
  }) async {
    if (simulateError) {
      throw const ExtractorException('LOGIN_REQUIRED', 'This video requires login');
    }
    onProgress?.call(50.0, 10);
    onProgress?.call(100.0, 0);
    return '$outDir/$taskId.mp4';
  }

  @override
  Future<bool> cancel(String taskId) async {
    return true;
  }
}

void main() {
  group('TASK 6.1 ExtractorBackend & Formatting Tests', () {
    test('Format parsing distinguishes video, audio-only, and combined', () {
      final videoOnly = ExtractorFormat.fromMap({
        'formatId': '137',
        'ext': 'mp4',
        'formatNote': '1080p',
        'hasVideo': true,
        'hasAudio': false,
        'height': 1080,
        'width': 1920,
        'filesize': 15000000,
      });
      expect(videoOnly.isVideo, isTrue);
      expect(videoOnly.isAudioOnly, isFalse);
      expect(videoOnly.height, equals(1080));

      final audioOnly = ExtractorFormat.fromMap({
        'formatId': '140',
        'ext': 'm4a',
        'formatNote': 'medium',
        'hasVideo': false,
        'hasAudio': true,
        'height': 0,
        'width': 0,
        'filesize': 3000000,
      });
      expect(audioOnly.isVideo, isFalse);
      expect(audioOnly.isAudioOnly, isTrue);
    });

    test('Metadata model parses format arrays correctly', () {
      final meta = ExtractorMetadata.fromMap({
        'id': 'abc',
        'title': 'Test Title',
        'uploader': 'Artist',
        'duration': 180,
        'thumbnail': 'https://example.com/t.png',
        'formats': [
          {
            'formatId': '18',
            'ext': 'mp4',
            'hasVideo': true,
            'hasAudio': true,
            'height': 360,
            'filesize': 5000,
          }
        ]
      });

      expect(meta.id, equals('abc'));
      expect(meta.title, equals('Test Title'));
      expect(meta.durationSec, equals(180));
      expect(meta.formats.length, equals(1));
      expect(meta.formats.first.formatId, equals('18'));
    });

    test('Presets provide video and audio selectors', () {
      final meta = ExtractorMetadata(
        id: '1',
        title: 'Title',
        uploader: 'Artist',
        durationSec: 100,
        thumbnailUrl: '',
        formats: const [],
      );

      final presets = FormatSelectionSheet.getPresets(meta);
      expect(presets.length, equals(3));
      expect(presets.any((p) => p.isAudio), isTrue);
      expect(presets.any((p) => !p.isAudio), isTrue);
      expect(presets.first.formatSelector, contains('bestvideo+bestaudio'));
      expect(presets.last.formatSelector, contains('bestaudio'));
    });

    test('Fake backend handles init, version, update, getInfo and download flow', () async {
      final backend = FakeExtractorBackend();
      expect(await backend.init(), isTrue);
      expect(await backend.getVersion(), equals('2026.11.01'));

      final updateRes = await backend.update();
      expect(updateRes, equals('DONE'));
      expect(await backend.getVersion(), equals('2026.11.02'));

      final info = await backend.getInfo('https://youtube.com/watch?v=123');
      expect(info.title, equals('Sample Test Video'));

      double reportedProgress = 0.0;
      final path = await backend.download(
        taskId: 'task_99',
        url: 'https://youtube.com/watch?v=123',
        outDir: '/tmp',
        onProgress: (p, eta) {
          reportedProgress = p;
        },
      );
      expect(path, equals('/tmp/task_99.mp4'));
      expect(reportedProgress, equals(100.0));
    });

    test('Fake backend maps error codes on failure', () async {
      final backend = FakeExtractorBackend()..simulateError = true;

      expect(
        () => backend.getInfo('https://youtube.com/watch?v=fail'),
        throwsA(isA<ExtractorException>().having((e) => e.code, 'code', 'EXTRACTION_FAILED')),
      );

      expect(
        () => backend.download(taskId: '1', url: 'https://youtube.com', outDir: '/tmp'),
        throwsA(isA<ExtractorException>().having((e) => e.code, 'code', 'LOGIN_REQUIRED')),
      );
    });

    test('On non-Android platforms, AndroidExtractorBackend enforces platform gate', () async {
      if (!Platform.isAndroid) {
        final backend = AndroidExtractorBackend();
        expect(() => backend.init(), throwsA(isA<UnsupportedError>()));
        expect(() => backend.getInfo('https://youtube.com'), throwsA(isA<UnsupportedError>()));
        expect(
          () => backend.download(taskId: '1', url: 'https://youtube.com', outDir: '/tmp'),
          throwsA(isA<UnsupportedError>()),
        );
      }
    });
  });
}

