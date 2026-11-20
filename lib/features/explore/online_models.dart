/// A video found by the online search.
class OnlineVideo {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final bool isLive;

  const OnlineVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.duration,
    this.isLive = false,
  });

  /// Video ids are exactly 11 URL-safe characters. Anything else is rejected
  /// before it can become part of a URL.
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static bool isValidId(String id) => _idPattern.hasMatch(id);

  String get watchUrl => 'https://www.youtube.com/watch?v=$id';
}

enum OnlineStreamKind { audio, video }

/// One directly playable / downloadable stream of a video.
class OnlineStream {
  final String url;
  final OnlineStreamKind kind;

  /// "1080p", "720p", "128 kbps" ...
  final String label;

  /// mp4, webm, m4a ...
  final String container;
  final int sizeBytes;
  final int? bitrateKbps;
  final int? height;

  const OnlineStream({
    required this.url,
    required this.kind,
    required this.label,
    required this.container,
    required this.sizeBytes,
    this.bitrateKbps,
    this.height,
  });

  bool get isAudio => kind == OnlineStreamKind.audio;
}

/// The streams of one video: audio only, and video that already contains sound.
class OnlineStreams {
  final List<OnlineStream> audio;
  final List<OnlineStream> video;

  const OnlineStreams({required this.audio, required this.video});

  /// Highest bitrate audio; AAC in an mp4/m4a container wins ties (best device support).
  OnlineStream? get bestAudio {
    if (audio.isEmpty) return null;
    final sorted = [...audio]..sort((a, b) {
        final byRate = (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0);
        if (byRate != 0) return byRate;
        final am = (a.container == 'mp4' || a.container == 'm4a') ? 1 : 0;
        final bm = (b.container == 'mp4' || b.container == 'm4a') ? 1 : 0;
        return bm.compareTo(am);
      });
    return sorted.first;
  }

  /// Highest resolution video-with-sound stream.
  OnlineStream? get bestVideo {
    if (video.isEmpty) return null;
    final sorted = [...video]..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    return sorted.first;
  }
}

class OnlineException implements Exception {
  final String message;
  const OnlineException(this.message);

  @override
  String toString() => message;
}
