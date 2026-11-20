import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/features/downloads/web_link_download_flow.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';
import 'fake_extractor_backend.dart';

void main() {
  tearDown(PlatformInfo.resetForTests);

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
        'abr': 129.5,
      });
      expect(audioOnly.isVideo, isFalse);
      expect(audioOnly.isAudioOnly, isTrue);
      expect(audioOnly.abr, closeTo(129.5, 0.01));
    });

    test('Metadata model parses format arrays and extractor args', () {
      final meta = ExtractorMetadata.fromMap({
        'id': 'abc',
        'title': 'Test Title',
        'uploader': 'Artist',
        'duration': 180,
        'thumbnail': 'https://example.com/t.png',
        'extractorArgs': 'youtube:player_client=android_vr',
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
      expect(meta.extractorArgs, equals('youtube:player_client=android_vr'));
    });

    test('Without a format list the sheet still offers best video, original audio and MP3', () {
      const meta = ExtractorMetadata(
        id: '1',
        title: 'Title',
        uploader: 'Artist',
        durationSec: 100,
        thumbnailUrl: '',
        formats: [],
      );

      final presets = FormatSelectionSheet.getPresets(meta);
      expect(presets.length, equals(6)); // best, original, MP3 x4
      expect(presets.any((p) => p.isAudio), isTrue);
      expect(presets.any((p) => !p.isAudio), isTrue);
      // yt-dlp's own default: the best video with sound, whatever there is.
      expect(presets.first.selector, 'bv*+ba/b');
      expect(presets.last.selector, 'ba/b');
      expect(presets.last.audioFormat, equals('mp3-128'));
    });

    test('Quality list reflects the formats that were really found (not a fixed 720p cap)', () {
      final meta = FakeExtractorBackend.sampleMetadata();
      final choices = FormatOptions.build(meta);

      final video = choices.where((c) => !c.isAudio).toList();
      final labels = video.map((c) => c.label).toList();
      expect(labels.first, startsWith('Best available (1080p'));
      expect(labels, containsAll(['1080p', '720p', '360p']));

      final p1080 = video.firstWhere((c) => c.id == 'v1080');
      // Ends in the catch-all: never "Requested format is not available".
      expect(p1080.selector, equals('bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b'));
      // video-only 1080p (15 MB) + best audio (3 MB) are downloaded and merged
      expect(p1080.estimatedBytes, equals(18000000));
      expect(p1080.streamSizes, equals([15000000, 3000000]));

      // muxed 360p already contains audio: no extra audio stream
      final p360 = video.firstWhere((c) => c.id == 'v360');
      expect(p360.estimatedBytes, equals(8000000));
      expect(p360.streamSizes, equals([8000000]));

      final audio = choices.where((c) => c.isAudio).toList();
      expect(audio.map((c) => c.id), equals(['audio_best', 'audio_mp3_320', 'audio_mp3_256', 'audio_mp3_192', 'audio_mp3_128']));
      expect(audio.first.estimatedBytes, equals(3000000));
      expect(audio.last.audioFormat, equals('mp3-128'));
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

    test('Outside Android the real backend refuses to run (platform gate)', () async {
      // Deterministic on every host: no dependence on where the test runs.
      PlatformInfo.debugIsAndroid = false;
      final backend = AndroidExtractorBackend();
      expect(() => backend.init(), throwsA(isA<UnsupportedError>()));
      expect(() => backend.getInfo('https://youtube.com'), throwsA(isA<UnsupportedError>()));
      expect(
        () => backend.download(taskId: '1', url: 'https://youtube.com', outDir: '/tmp'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('WebLinkDownloadFlow.friendlyError', () {
    String forCode(String code) =>
        WebLinkDownloadFlow.friendlyError(ExtractorException(code, 'native message'));

    test('Playlist / channel links get their own message', () {
      expect(
        forCode('PLAYLIST_NOT_SUPPORTED'),
        "Playlists and channels can't be downloaded. Open a single video link instead.",
      );
    });

    test('Live streams get their own message', () {
      expect(forCode('LIVE_NOT_SUPPORTED'), "Live streams can't be downloaded.");
    });

    test('A quality lookup that timed out asks the user to try later', () {
      expect(
        WebLinkDownloadFlow.friendlyError(TimeoutException('getInfo', WebLinkDownloadFlow.infoTimeout)),
        'This link is taking too long. Try again later.',
      );
      expect(WebLinkDownloadFlow.infoTimeout, const Duration(seconds: 90));
    });

    test('A lookup stopped by the native watchdog (INFO_TIMEOUT) gets the same message', () {
      // The native side gives up after ~85 s, before the Dart 90 s timeout, so
      // on a real phone this is the code a stuck lookup usually ends with.
      expect(forCode('INFO_TIMEOUT'), 'This link is taking too long. Try again later.');
      expect(
        forCode('INFO_TIMEOUT'),
        WebLinkDownloadFlow.friendlyError(TimeoutException('getInfo', WebLinkDownloadFlow.infoTimeout)),
      );
    });

    test('Existing codes keep their messages', () {
      expect(forCode('HOST_NOT_ALLOWED'), 'This website is not supported by the web link downloader.');
      expect(forCode('LOGIN_REQUIRED'), 'This video needs a login. Only public videos are supported.');
      expect(forCode('PRIVATE_CONTENT'), 'This video is private and cannot be downloaded.');
      expect(forCode('DRM_PROTECTED'), 'This content is DRM protected and cannot be downloaded.');
      expect(forCode('NOT_FOUND'), 'The video was not found. Check the link.');
      expect(forCode('NETWORK_ERROR'), 'Network problem. Check your connection and try again.');
      // MediaHub updates yt-dlp by itself now: no "update the engine" advice.
      expect(forCode('EXTRACTION_FAILED'), 'Could not read this link. Please try again later.');
      expect(
        WebLinkDownloadFlow.friendlyError(UnsupportedError('x')),
        'The web link downloader is only available on Android.',
      );
      expect(WebLinkDownloadFlow.friendlyError(StateError('x')), 'Could not read this link. Please try again.');
    });
  });
}
