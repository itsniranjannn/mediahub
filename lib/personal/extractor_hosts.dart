/// The sites the web link downloader (yt-dlp) may read: the same list, and the
/// same strict matching, as `ALLOWED_HOSTS` in the Android side
/// (`ExtractorChannel.kt`; a test compares the two).
///
/// Links to other sites never reach yt-dlp. They still download when they
/// point straight at an audio or video file (the direct-link engine).
class ExtractorHosts {
  ExtractorHosts._();

  static const List<String> allowed = [
    'youtube.com',
    'youtu.be',
    'music.youtube.com',
    'instagram.com',
    'facebook.com',
    'fb.watch',
    'tiktok.com',
    'x.com',
    'twitter.com',
    'spotify.com',
    'soundcloud.com',
    'vimeo.com',
    'dailymotion.com',
    'dai.ly',
    'reddit.com',
    'redd.it',
  ];

  /// True for an https link whose host is on [allowed] or one of its
  /// subdomains (`m.youtube.com`, `vm.tiktok.com`, `v.redd.it`). Look-alikes
  /// such as `youtube.com.example` or `notyoutube.com` never match.
  static bool isAllowed(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return allowed.any((a) => host == a || host.endsWith('.$a'));
  }
}
