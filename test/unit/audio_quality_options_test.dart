import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';

import 'fake_extractor_backend.dart';

void main() {
  group('AudioConversion (option -> yt-dlp args)', () {
    test('each MP3 bitrate maps to fixed -x / --audio-format / --audio-quality args', () {
      for (final kbps in [320, 256, 192, 128]) {
        final c = AudioConversion.parse(AudioConversion.mp3(kbps))!;
        expect(c.codec, 'mp3');
        expect(c.quality, '${kbps}K');
        expect(c.ytDlpArgs, ['-x', '--audio-format', 'mp3', '--audio-quality', '${kbps}K']);
      }
    });

    test('a plain codec (rows from older versions) keeps best VBR', () {
      expect(AudioConversion.parse('mp3')!.ytDlpArgs, ['-x', '--audio-format', 'mp3', '--audio-quality', '0']);
      expect(AudioConversion.parse('M4A')!.codec, 'm4a');
    });

    test('anything off the whitelist is dropped, never passed through', () {
      for (final bad in [
        null,
        '',
        'mp3-999',
        'mp3-320; rm -rf',
        'mp3--exec',
        'ogg',
        'm4a-320',
        'mp3-320K',
        '--exec x',
      ]) {
        expect(AudioConversion.parse(bad), isNull, reason: '$bad');
      }
      expect(AudioConversion.qualities, {'0', '320K', '256K', '192K', '128K'});
    });
  });

  group('FormatOptions audio choices', () {
    test('MP3 320/256/192/128 with sizes from duration x bitrate', () {
      final meta = FakeExtractorBackend.sampleMetadata();
      final audio = FormatOptions.build(meta).where((c) => c.isAudio).toList();
      final mp3 = audio.where((c) => c.id.startsWith('audio_mp3_')).toList();
      expect(mp3.map((c) => c.label), ['MP3 · 320 kbps', 'MP3 · 256 kbps', 'MP3 · 192 kbps', 'MP3 · 128 kbps']);
      for (final c in mp3) {
        final kbps = int.parse(c.id.split('_').last);
        expect(c.audioFormat, 'mp3-$kbps');
        expect(c.selector, 'ba/b');
        expect(c.estimatedBytes, meta.durationSec * kbps * 125);
        expect(FormatOptions.formatSortFor(c.selector, audioFormat: c.audioFormat), isNull);
      }
      expect(audio.first.label, startsWith('Original · M4A'));
      expect(audio.first.audioFormat, isNull, reason: 'original: no re-encode');
    });

    test('Original Opus is offered when the site has it next to M4A', () {
      const meta = ExtractorMetadata(
        id: 'x',
        title: 't',
        uploader: 'u',
        durationSec: 200,
        thumbnailUrl: '',
        formats: [
          ExtractorFormat(formatId: '140', ext: 'm4a', formatNote: '', hasVideo: false, hasAudio: true, height: 0, width: 0, filesize: 0, abr: 129, tbr: 129),
          ExtractorFormat(formatId: '251', ext: 'webm', formatNote: '', hasVideo: false, hasAudio: true, height: 0, width: 0, filesize: 0, abr: 120, tbr: 120),
        ],
      );
      final opus = FormatOptions.build(meta).firstWhere((c) => c.id == 'audio_opus');
      expect(opus.label, 'Original · Opus (~120 kbps)');
      expect(opus.selector, 'ba[ext=webm]/ba/b');
      expect(opus.audioFormat, isNull);
      expect(opus.estimatedBytes, 120 * 125 * 200);
    });
  });
}
