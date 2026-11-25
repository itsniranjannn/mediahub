// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
class KnownPlatformChecker {
  KnownPlatformChecker._();

  static const Map<String, String> _knownHosts = {
    'youtube.com': 'YouTube',
    'youtu.be': 'YouTube',
    'music.youtube.com': 'YouTube Music',
    'instagram.com': 'Instagram',
    'facebook.com': 'Facebook',
    'fb.watch': 'Facebook',
    'tiktok.com': 'TikTok',
    'x.com': 'X',
    'twitter.com': 'Twitter',
    'spotify.com': 'Spotify',
    'soundcloud.com': 'SoundCloud',
    'vimeo.com': 'Vimeo',
    'dailymotion.com': 'Dailymotion',
    'dai.ly': 'Dailymotion',
    'reddit.com': 'Reddit',
    'redd.it': 'Reddit',
  };

  /// Said at once for a Spotify song, album or playlist link.
  static const String spotifyProtectedMessage =
      "Spotify songs are protected and can't be saved. Search for the song in the Online tab instead.";

  static const Set<String> _spotifyProtectedKinds = {'track', 'album', 'playlist'};

  /// True for a Spotify track, album or playlist link
  /// (`open.spotify.com/track/...`, also with an `intl-xx/` language prefix
  /// or as an `embed/` link). That music is DRM protected and can never be
  /// saved, so it is refused before any lookup. Podcast episodes and shows
  /// can be plain public audio and stay allowed; look-alike hosts never match.
  static bool isProtectedSpotifyLink(Uri uri) {
    var host = uri.host.toLowerCase().trim();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host != 'spotify.com' && !host.endsWith('.spotify.com')) return false;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
    var i = 0;
    if (i < segments.length && segments[i].startsWith('intl-')) i++;
    if (i < segments.length && segments[i] == 'embed') i++;
    return i < segments.length && _spotifyProtectedKinds.contains(segments[i]);
  }

  /// Why [uri] can never be saved, or null when it may be tried.
  static String? protectedContentMessage(Uri uri) => isProtectedSpotifyLink(uri) ? spotifyProtectedMessage : null;

  /// Checks if [uri] belongs to a known platform.
  /// Host matching is exact or by subdomain (e.g. `m.youtube.com` matches `youtube.com`).
  /// Lookalikes such as `notyoutube.com.evil.example` will NOT match.
  static String? matchPlatformName(Uri uri) {
    final host = uri.host.toLowerCase().trim();
    if (host.isEmpty) return null;

    // Check exact match first
    if (_knownHosts.containsKey(host)) {
      return _knownHosts[host];
    }

    // Check subdomain match (must end with .domain.tld)
    for (final entry in _knownHosts.entries) {
      if (host.endsWith('.${entry.key}')) {
        return entry.value;
      }
    }

    return null;
  }
}
