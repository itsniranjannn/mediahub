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
  };

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
