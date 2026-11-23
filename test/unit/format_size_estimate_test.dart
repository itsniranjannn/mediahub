import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';

ExtractorFormat _v(String id, String vcodec, double tbr, {double fps = 30}) => ExtractorFormat(
      formatId: id,
      ext: vcodec.startsWith('avc') ? 'mp4' : 'webm',
      formatNote: '720p',
      hasVideo: true,
      hasAudio: false,
      height: 720,
      width: 1280,
      filesize: 0,
      tbr: tbr,
      fps: fps,
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
  filesize: 0,
  tbr: 128,
  abr: 128,
  acodec: 'mp4a.40.2',
);

int? _size720(List<ExtractorFormat> formats) {
  final meta = ExtractorMetadata(id: 'x', title: 'T', uploader: 'U', durationSec: 597, thumbnailUrl: '', formats: formats);
  return FormatOptions.build(meta).firstWhere((c) => c.id == 'v720').estimatedBytes;
}

void main() {
  test('720p is sized from the H.264 stream the download takes, whatever else is listed', () {
    final avc = _v('136', 'avc1.4d401f', 1200);
    final onlyAvc = _size720([avc, _audio]);
    // The same video with a heavier VP9 stream listed too: same estimate.
    final withVp9 = _size720([_v('247', 'vp9', 2600), avc, _audio]);
    expect(withVp9, onlyAvc);
    expect(onlyAvc, (1200 * 125 * 597).round() + (128 * 125 * 597).round());
  });
}
