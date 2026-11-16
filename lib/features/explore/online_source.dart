import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'online_models.dart';

/// Where online search results and streams come from.
abstract class OnlineSource {
  Future<List<OnlineVideo>> search(String query);
  Future<OnlineStreams> streams(String videoId);
  void dispose();
}

/// Pure-Dart implementation (same code on Android and iOS, no native binaries,
/// no account, no cookies).
class YoutubeExplodeSource implements OnlineSource {
  final YoutubeExplode _yt;

  YoutubeExplodeSource([YoutubeExplode? yt]) : _yt = yt ?? YoutubeExplode();

  static const Duration _timeout = Duration(seconds: 25);

  @override
  Future<List<OnlineVideo>> search(String query) async {
    try {
      final list = await _yt.search.search(query).timeout(_timeout);
      return list
          .where((v) => OnlineVideo.isValidId(v.id.value))
          .take(30)
          .map((v) => OnlineVideo(
                id: v.id.value,
                title: v.title,
                author: v.author,
                duration: v.duration,
                thumbnailUrl: v.thumbnails.mediumResUrl,
                isLive: v.isLive,
              ))
          .toList();
    } on TimeoutException {
      throw const OnlineException('Search timed out. Check your connection and try again.');
    } on SocketException {
      throw const OnlineException('No internet connection.');
    } on HandshakeException {
      throw const OnlineException('Could not make a secure connection to the search service.');
    } catch (_) {
      throw const OnlineException('Search failed. Please try again in a moment.');
    }
  }

  @override
  Future<OnlineStreams> streams(String videoId) async {
    if (!OnlineVideo.isValidId(videoId)) {
      throw const OnlineException('Invalid video.');
    }
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(VideoId(videoId)).timeout(_timeout);

      final audio = manifest.audioOnly
          .map((s) => OnlineStream(
                url: s.url.toString(),
                kind: OnlineStreamKind.audio,
                label: '${s.bitrate.kiloBitsPerSecond.round()} kbps',
                container: s.container.name,
                sizeBytes: s.size.totalBytes,
                bitrateKbps: s.bitrate.kiloBitsPerSecond.round(),
              ))
          .toList();

      final video = manifest.muxed
          .map((s) => OnlineStream(
                url: s.url.toString(),
                kind: OnlineStreamKind.video,
                label: '${s.videoResolution.height}p',
                container: s.container.name,
                sizeBytes: s.size.totalBytes,
                bitrateKbps: s.bitrate.kiloBitsPerSecond.round(),
                height: s.videoResolution.height,
              ))
          .toList();

      if (audio.isEmpty && video.isEmpty) {
        throw const OnlineException('This video has no playable streams.');
      }
      return OnlineStreams(audio: audio, video: video);
    } on OnlineException {
      rethrow;
    } on TimeoutException {
      throw const OnlineException('Timed out while loading the video. Please try again.');
    } on SocketException {
      throw const OnlineException('No internet connection.');
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('unplayable') || text.contains('age') || text.contains('private')) {
        throw const OnlineException('This video cannot be played here (private, age-restricted or unavailable).');
      }
      throw const OnlineException('Could not load this video. Please try another one.');
    }
  }

  @override
  void dispose() => _yt.close();
}

/// Offline sample data for previews and screenshots:
/// `flutter run --dart-define=MEDIAHUB_DEMO=true`.
class DemoOnlineSource implements OnlineSource {
  static const List<OnlineVideo> _samples = [
    OnlineVideo(
      id: 'dQw4w9WgXcQ',
      title: 'Midnight Drive - Synthwave Mix for Late Night Focus',
      author: 'Neon Atlas',
      duration: Duration(minutes: 58, seconds: 12),
      thumbnailUrl: '',
    ),
    OnlineVideo(
      id: 'aqz-KE-bpKQ',
      title: 'Nepali Folk Fusion | Live Session',
      author: 'Himal Sessions',
      duration: Duration(minutes: 4, seconds: 36),
      thumbnailUrl: '',
    ),
    OnlineVideo(
      id: 'jNQXAC9IVRw',
      title: 'How Mountain Bridges Are Built',
      author: 'Engineering Stories',
      duration: Duration(minutes: 12, seconds: 5),
      thumbnailUrl: '',
    ),
    OnlineVideo(
      id: '9bZkp7q19f0',
      title: 'Lo-fi Beats To Study And Relax To',
      author: 'Quiet Hours',
      duration: Duration.zero,
      thumbnailUrl: '',
      isLive: true,
    ),
  ];

  @override
  Future<List<OnlineVideo>> search(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return _samples;
  }

  @override
  Future<OnlineStreams> streams(String videoId) async {
    throw const OnlineException('Demo mode: playback is disabled.');
  }

  @override
  void dispose() {}
}

const bool kMediaHubDemo = bool.fromEnvironment('MEDIAHUB_DEMO');

final onlineSourceProvider = Provider<OnlineSource>((ref) {
  final OnlineSource source = kMediaHubDemo ? DemoOnlineSource() : YoutubeExplodeSource();
  ref.onDispose(source.dispose);
  return source;
});
