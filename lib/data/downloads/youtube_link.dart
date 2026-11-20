/// What kind of YouTube page a link opens.
enum YoutubeLinkKind {
  /// `youtube.com/watch?v=<id>` (also `m.` and `music.` hosts).
  watch,

  /// `youtu.be/<id>`: the short form the Online tab copies.
  shortLink,

  /// `youtube.com/shorts/<id>`.
  short,

  /// `youtube.com/live/<id>`: a live stream, or the recording of one that ended.
  live,

  /// `youtube.com/embed/<id>` or the old `youtube.com/v/<id>`.
  embed,
}

/// One YouTube video, parsed from a page link.
///
/// Pure parsing (no network): used to decide which download path a pasted or
/// handed-over link takes, and to turn every accepted shape into the same
/// canonical `https://youtu.be/<id>` link.
class YoutubeLink {
  const YoutubeLink._(this.videoId, this.kind, {this.isMusic = false});

  /// The 11-character video id.
  final String videoId;
  final YoutubeLinkKind kind;

  /// The link was on `music.youtube.com`.
  final bool isMusic;

  /// `https://youtu.be/<id>`, without tracking parameters (`si`, `pp`, `feature`, ...).
  String get canonicalUrl => 'https://youtu.be/$videoId';

  /// `https://www.youtube.com/watch?v=<id>`.
  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';

  /// YouTube's own still for the video. Built from the id, so it can only
  /// ever point at YouTube's image host.
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// True for exactly 11 URL-safe characters.
  static bool isValidId(String id) => _idPattern.hasMatch(id);

  /// Hosts whose page links are parsed. A fixed list (not "anything ending in
  /// youtube.com"), so lookalikes such as `youtube.com.example.net` never match.
  static const Set<String> _pageHosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
  };

  /// First path segments that open a playlist or a channel, never one video.
  static const Set<String> _collectionSegments = {'playlist', 'channel', 'c', 'user', 'feed'};

  /// [host] lower-cased, without the trailing dot of a fully qualified name.
  static String _normalHost(String host) {
    final h = host.toLowerCase();
    return h.endsWith('.') ? h.substring(0, h.length - 1) : h;
  }

  /// True when [host] is one of YouTube's page hosts.
  static bool isYoutubeHost(String host) => _pageHosts.contains(_normalHost(host));

  /// True for YouTube's media servers (`googlevideo.com` and its subdomains),
  /// the only hosts a YouTube stream may be downloaded from.
  static bool isYoutubeMediaHost(String host) {
    final h = _normalHost(host);
    return h == 'googlevideo.com' || h.endsWith('.googlevideo.com');
  }

  /// [url] as a [Uri] when it is an https address on YouTube's media servers
  /// (no user name, standard port), otherwise null. Every stream address a
  /// lookup returns goes through this before it is downloaded, so a bad
  /// lookup result can never send the downloader (and the phone's IP address)
  /// to some other server.
  static Uri? trustedStreamUri(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return null;
    if (uri.hasPort && uri.port != 443) return null;
    return isYoutubeMediaHost(uri.host) ? uri : null;
  }

  /// The video [text] links to, or null (not a link, not YouTube, or not one video).
  static YoutubeLink? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri == null ? null : parse(uri);
  }

  /// The video [uri] links to, or null when it is not a link to one YouTube video.
  static YoutubeLink? parse(Uri uri) => check(uri).link;

  /// Like [parse], but also says whether the link was a YouTube playlist or
  /// channel page (so the message can say why it cannot be downloaded).
  static YoutubeLinkCheck check(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' || uri.userInfo.isNotEmpty) {
      return const YoutubeLinkCheck._(null, isYoutube: false);
    }
    if (uri.hasPort && uri.port != 443) return const YoutubeLinkCheck._(null, isYoutube: false);
    final host = _normalHost(uri.host);
    if (!isYoutubeHost(host)) return const YoutubeLinkCheck._(null, isYoutube: false);

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final isMusic = host == 'music.youtube.com';

    YoutubeLinkCheck video(String id, YoutubeLinkKind kind) => isValidId(id)
        ? YoutubeLinkCheck._(YoutubeLink._(id, kind, isMusic: isMusic), isYoutube: true)
        : const YoutubeLinkCheck._(null, isYoutube: true);

    if (host == 'youtu.be') {
      if (segments.isEmpty) return const YoutubeLinkCheck._(null, isYoutube: true);
      return video(segments.first, YoutubeLinkKind.shortLink);
    }

    if (segments.isEmpty) return const YoutubeLinkCheck._(null, isYoutube: true);
    final first = segments.first.toLowerCase();
    switch (first) {
      case 'watch':
        final id = uri.queryParameters['v'];
        if (id != null && id.isNotEmpty) return video(id, YoutubeLinkKind.watch);
        // "watch?list=..." without a video is a playlist.
        return YoutubeLinkCheck._(null, isYoutube: true, isCollection: uri.queryParameters.containsKey('list'));
      case 'shorts':
      case 'live':
      case 'embed':
      case 'v':
        if (segments.length < 2) return const YoutubeLinkCheck._(null, isYoutube: true);
        final kind = switch (first) {
          'shorts' => YoutubeLinkKind.short,
          'live' => YoutubeLinkKind.live,
          _ => YoutubeLinkKind.embed,
        };
        return video(segments[1], kind);
    }
    final isCollection = _collectionSegments.contains(first) || first.startsWith('@') || first == 'browse';
    return YoutubeLinkCheck._(null, isYoutube: true, isCollection: isCollection);
  }

  @override
  bool operator ==(Object other) =>
      other is YoutubeLink && other.videoId == videoId && other.kind == kind && other.isMusic == isMusic;

  @override
  int get hashCode => Object.hash(videoId, kind, isMusic);

  @override
  String toString() => 'YoutubeLink($videoId, ${kind.name}${isMusic ? ', music' : ''})';
}

/// Result of [YoutubeLink.check].
class YoutubeLinkCheck {
  const YoutubeLinkCheck._(this.link, {required this.isYoutube, this.isCollection = false});

  /// The video, when the link points at exactly one.
  final YoutubeLink? link;

  /// The link is on one of YouTube's page hosts.
  final bool isYoutube;

  /// The link opens a playlist or a channel instead of one video.
  final bool isCollection;
}
