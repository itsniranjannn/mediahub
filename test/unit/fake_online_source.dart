import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/explore/online_source.dart';

/// Scriptable stand-in for the Online tab's YouTube source (no network).
class FakeOnlineSource implements OnlineSource {
  /// Answers [streams]; by default one 360p MP4 and one M4A audio stream.
  Future<OnlineStreams> Function(String videoId)? onStreams;

  final List<String> streamCalls = [];

  static const OnlineStreams sampleStreams = OnlineStreams(
    video: [
      OnlineStream(
        url: 'https://rr1---sn-test.googlevideo.com/videoplayback?itag=18',
        kind: OnlineStreamKind.video,
        label: '360p',
        container: 'mp4',
        sizeBytes: 12 * 1024 * 1024,
        bitrateKbps: 500,
        height: 360,
      ),
    ],
    audio: [
      OnlineStream(
        url: 'https://rr1---sn-test.googlevideo.com/videoplayback?itag=140',
        kind: OnlineStreamKind.audio,
        label: '128 kbps',
        container: 'mp4',
        sizeBytes: 3 * 1024 * 1024,
        bitrateKbps: 128,
      ),
    ],
  );

  @override
  Future<List<OnlineVideo>> search(String query) async => const [];

  @override
  Future<OnlineStreams> streams(String videoId, {int variant = 0}) {
    streamCalls.add(videoId);
    final handler = onStreams;
    // Called without an await on purpose: a handler may throw synchronously.
    return handler != null ? handler(videoId) : Future.value(sampleStreams);
  }

  @override
  void dispose() {}
}
