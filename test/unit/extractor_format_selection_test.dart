import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';

import 'fake_extractor_backend.dart';

/// The Android side's Kotlin file: its regexes are read from the source, so
/// these tests fail as soon as the two sides drift apart.
final _kotlin = File('android/app/src/main/kotlin/com/example/mediahub/personal/ExtractorChannel.kt');

/// The Kotlin `Regex("...")` assigned to [name], as a Dart [RegExp].
RegExp kotlinRegex(String name) {
  final source = _kotlin.readAsStringSync();
  final m = RegExp('private val $name = Regex\\("((?:[^"\\\\]|\\\\.)*)"\\)').firstMatch(source);
  expect(m, isNotNull, reason: '$name not found in ${_kotlin.path}');
  // Kotlin string escapes -> the regex text itself.
  final pattern = m!.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e.group(1)!);
  return RegExp(pattern);
}

ExtractorFormat _video(int height, {String vcodec = 'avc1.640028', bool audio = false, int size = 1000}) =>
    ExtractorFormat(
      formatId: 'v$height$vcodec',
      ext: vcodec.startsWith('vp') ? 'webm' : 'mp4',
      formatNote: '${height}p',
      hasVideo: true,
      hasAudio: audio,
      height: height,
      width: height * 16 ~/ 9,
      filesize: size,
      tbr: 1000,
      vcodec: vcodec,
    );

const _audio = ExtractorFormat(
  formatId: '140',
  ext: 'm4a',
  formatNote: 'medium',
  hasVideo: false,
  hasAudio: true,
  height: 0,
  width: 0,
  filesize: 300,
  abr: 128,
  acodec: 'mp4a.40.2',
);

/// A YouTube-like list: VP9 only above 1080p (as YouTube serves it).
final _wide = ExtractorMetadata(
  id: 'w',
  title: 'Wide',
  uploader: '',
  durationSec: 60,
  thumbnailUrl: '',
  formats: [
    _video(2160, vcodec: 'vp9'),
    _video(1440, vcodec: 'vp9'),
    _video(1080),
    _video(1080, vcodec: 'vp9'),
    _video(720),
    _video(480),
    _video(360, audio: true),
    _video(240),
    _video(144),
    _audio,
  ],
);

/// Selectors older versions of the app stored on their download rows.
const _legacySelectors = [
  'bestvideo[height<=1080]+bestaudio/best[height<=1080]',
  'bestvideo[height<=720]+bestaudio/best[height<=720]',
  'bestvideo+bestaudio/best',
  'bestaudio/best',
];

void main() {
  group('format selectors never fail outright (the 1080p "Requested format is not available")', () {
    test('a video quality is capped at its height and ends with the catch-all', () {
      expect(FormatOptions.videoSelector(1080), 'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b');
      expect(FormatOptions.videoSelector(360), 'bv*[height<=360]+ba/b[height<=360]/bv*+ba/b');
      expect(FormatOptions.videoSelector(null), 'bv*+ba/b');
      expect(FormatOptions.audioSelector, 'ba/b');
    });

    test('every choice in the quality sheet ends with yt-dlp\'s catch-all', () {
      for (final meta in [FakeExtractorBackend.sampleMetadata(), _wide]) {
        for (final c in FormatOptions.build(meta)) {
          final catchAll = c.isAudio ? 'ba/b' : 'bv*+ba/b';
          expect(c.selector == catchAll || c.selector.endsWith('/$catchAll'), isTrue,
              reason: '${c.id}: ${c.selector}');
        }
      }
      final v720 = FormatOptions.build(_wide).firstWhere((c) => c.id == 'v720');
      expect(FormatOptions.maxHeightOf(v720.selector), 720, reason: 'the chosen height stays the cap');
    });

    test('downloads queued by older versions get the catch-all on retry', () {
      expect(
        FormatOptions.withCatchAll(_legacySelectors[0], audio: false),
        'bestvideo[height<=1080]+bestaudio/best[height<=1080]/bv*+ba/b',
      );
      // Already a catch-all ("best" takes whatever there is): unchanged.
      expect(FormatOptions.withCatchAll('bestvideo+bestaudio/best', audio: false), 'bestvideo+bestaudio/best');
      expect(FormatOptions.withCatchAll('bestaudio/best', audio: true), 'bestaudio/best');
      // New selectors are left alone.
      expect(FormatOptions.withCatchAll(FormatOptions.videoSelector(720), audio: false),
          FormatOptions.videoSelector(720));
      expect(FormatOptions.withCatchAll('ba/b', audio: true), 'ba/b');
      expect(FormatOptions.withCatchAll('bestaudio[ext=m4a]', audio: true), 'bestaudio[ext=m4a]/ba/b');
      expect(FormatOptions.withCatchAll('', audio: false), '');
    });

    test('the format sort keeps the height cap and prefers H.264 + M4A (an MP4 that plays everywhere)', () {
      expect(FormatOptions.formatSortFor(FormatOptions.videoSelector(1080)), 'height:1080,vcodec:h264,ext:mp4:m4a');
      expect(FormatOptions.formatSortFor(_legacySelectors[1]), 'height:720,vcodec:h264,ext:mp4:m4a');
      expect(FormatOptions.formatSortFor('bv*+ba/b'), 'res,vcodec:h264,ext:mp4:m4a');
      // Sound only: the sound the sheet showed (no reordering), and MP3 is converted anyway.
      expect(FormatOptions.formatSortFor('ba/b'), isNull);
      expect(FormatOptions.formatSortFor('bestaudio/best'), isNull);
      expect(FormatOptions.formatSortFor('ba/b', audioFormat: 'mp3'), isNull);
      expect(FormatOptions.formatSortFor(FormatOptions.videoSelector(720), audioFormat: 'mp3'), isNull);
      expect(FormatOptions.formatSortFor(null), isNull);
      expect(FormatOptions.formatSortFor(''), isNull);
    });

    test('above 1080p YouTube has only VP9: the sheet says MKV there, MP4 below', () {
      final byId = {for (final c in FormatOptions.build(_wide)) c.id: c};
      expect(byId['v2160']!.subtitle, startsWith('MKV'));
      expect(byId['v1440']!.subtitle, startsWith('MKV'));
      expect(byId['v1080']!.subtitle, startsWith('MP4'));
      expect(byId['v360']!.subtitle, startsWith('MP4'));
      expect(byId['best']!.subtitle, startsWith('MKV'));
    });
  });

  group('the Android side accepts what Dart sends (Kotlin regexes, read from the source)', () {
    late RegExp selectorRegex;
    late RegExp sortRegex;

    setUpAll(() {
      selectorRegex = kotlinRegex('FORMAT_SELECTOR_REGEX');
      sortRegex = kotlinRegex('FORMAT_SORT_REGEX');
    });

    test('every selector the app can send passes FORMAT_SELECTOR_REGEX', () {
      final selectors = <String>{
        for (final meta in [FakeExtractorBackend.sampleMetadata(), _wide])
          for (final c in FormatOptions.build(meta)) c.selector,
        for (final s in _legacySelectors) FormatOptions.withCatchAll(s, audio: s.startsWith('bestaudio')),
        for (final h in [144, 240, 360, 480, 720, 1080, 1440, 2160, 4320]) FormatOptions.videoSelector(h),
        'bv*+ba/b',
        'ba/b',
      };
      for (final s in selectors) {
        expect(selectorRegex.hasMatch(s), isTrue, reason: s);
      }
    });

    test('every format sort the app can send passes FORMAT_SORT_REGEX (and stays short)', () {
      final sorts = <String>{
        for (final meta in [FakeExtractorBackend.sampleMetadata(), _wide])
          for (final c in FormatOptions.build(meta)) ?FormatOptions.formatSortFor(c.selector, audioFormat: c.audioFormat),
        for (final s in _legacySelectors) ?FormatOptions.formatSortFor(s),
      };
      expect(sorts, containsAll(['height:1080,vcodec:h264,ext:mp4:m4a', 'res,vcodec:h264,ext:mp4:m4a']));
      for (final s in sorts) {
        expect(sortRegex.hasMatch(s), isTrue, reason: s);
        expect(s.length, lessThanOrEqualTo(80));
      }
    });

    test('options smuggled in as a selector or sort are refused', () {
      for (final bad in ['-o /sdcard/x', '--exec rm', 'b; rm -rf /', 'b\nx', '']) {
        expect(selectorRegex.hasMatch(bad), isFalse, reason: bad);
      }
      for (final bad in ['-S', '--exec', 'res;rm', 'res,vcodec:h264 --exec x', 'res,', ',res', 'RES', '']) {
        expect(sortRegex.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });
}
