/// Pure-Dart helpers for the Online (YouTube) tab: which hosts may load inside
/// the WebView, which page kind is open, the video id, and the clean link that
/// "Copy link" and "Download" hand on. No Flutter imports, so they are cheap to
/// unit test.
library;

/// The page the Online tab opens first.
const String youTubeHomeUrl = 'https://m.youtube.com/';

/// Video ids are exactly 11 URL-safe characters (same rule as
/// `OnlineVideo.isValidId`). Anything else never becomes part of a link.
final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

bool isValidYouTubeVideoId(String id) => _videoIdPattern.hasMatch(id);

/// Hosts that serve YouTube pages and may load as the WebView's main page.
/// Subresources (i.ytimg.com, *.googlevideo.com, fonts ...) are not
/// navigations and are not filtered here.
const Set<String> _pageHosts = {
  'youtube.com',
  'm.youtube.com',
  'www.youtube.com',
  'music.youtube.com',
  // EU / UK cookie consent.
  'consent.youtube.com',
  // Short links redirect to a watch page.
  'youtu.be',
};

/// Google's sign-in pages that YouTube's "Sign in" walks through as whole
/// pages, so a sign-in can finish inside the Online tab:
/// - accounts.google.com: the sign-in itself (account, password, 2-Step
///   Verification, the account chooser, and signing out);
/// - accounts.youtube.com: the hop that hands the finished sign-in to
///   YouTube (/accounts/SetSID) and back on sign-out;
/// - gds.google.com: the "keep your account safe" prompts Google may show
///   right after (a recovery phone or email).
///
/// Exact hosts, https only. They are not YouTube pages: the media bridge never
/// runs or answers on them (see [isYouTubePage]). Anything else of Google's
/// (My Account, Help) opens in the phone's browser, like any other site.
const Set<String> _signInHosts = {
  'accounts.google.com',
  'accounts.youtube.com',
  'gds.google.com',
};

/// Hosts whose URLs can carry a video id ("Copy link", "Download").
const Set<String> _videoHosts = {
  'youtube.com',
  'm.youtube.com',
  'www.youtube.com',
  'music.youtube.com',
  'youtu.be',
};

String _host(Uri uri) {
  var h = uri.host.toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h;
}

/// True for the hosts that may be shown as the WebView's page.
bool isYouTubePageHost(String host) {
  var h = host.toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return _pageHosts.contains(h);
}

/// True when [uri] is an https (or http) YouTube page.
bool isYouTubePage(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return false;
  if (uri.userInfo.isNotEmpty) return false; // "https://youtube.com@evil.example/"
  if (uri.hasPort && uri.port != 443 && uri.port != 80) return false;
  return isYouTubePageHost(_host(uri));
}

/// True when [uri] is one of Google's sign-in pages that may load inside the
/// Online tab (https only, the default port, an exact host). Never a YouTube
/// page: the bridge stays off there.
bool isGoogleSignInPage(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') return false;
  if (uri.userInfo.isNotEmpty) return false;
  if (uri.hasPort && uri.port != 443) return false;
  return _signInHosts.contains(_host(uri));
}

/// YouTube's own sign-in (the Online menu's "Sign in to YouTube"): Google's
/// sign-in for the YouTube service, the same address YouTube's own "Sign in"
/// button opens. When it is done, Google hands the sign-in to YouTube and
/// returns to [returnTo] when that is a YouTube page on the mobile site (the
/// page the user was on), else to YouTube's home.
Uri youTubeSignInUri({Uri? returnTo}) {
  var next = youTubeHomeUrl;
  if (returnTo != null && returnTo.scheme.toLowerCase() == 'https' && isYouTubePage(returnTo)) {
    final host = _host(returnTo);
    if (host == 'm.youtube.com' || host == 'www.youtube.com' || host == 'youtube.com') {
      next = returnTo.toString();
    }
  }
  final handOver = Uri.https('www.youtube.com', '/signin', {
    'action_handle_signin': 'true',
    'app': 'm',
    'next': next,
  });
  return Uri.https('accounts.google.com', '/ServiceLogin', {
    'service': 'youtube',
    'uilel': '3',
    'passive': 'true',
    'continue': handOver.toString(),
  });
}

/// What kind of page is open; the watch strip shows on [watch], [shorts] and [live].
enum YouTubePageKind { watch, shorts, live, other }

/// The page kind of [uri] (only for YouTube hosts; anything else is [YouTubePageKind.other]).
YouTubePageKind youTubePageKind(Uri? uri) {
  if (uri == null || !isYouTubePage(uri)) return YouTubePageKind.other;
  final host = _host(uri);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (host == 'youtu.be') {
    return segments.isNotEmpty && isValidYouTubeVideoId(segments.first)
        ? YouTubePageKind.watch
        : YouTubePageKind.other;
  }
  if (segments.isEmpty) return YouTubePageKind.other;
  switch (segments.first) {
    case 'watch':
      final v = uri.queryParameters['v'];
      return v != null && isValidYouTubeVideoId(v) ? YouTubePageKind.watch : YouTubePageKind.other;
    case 'shorts':
      return segments.length > 1 && isValidYouTubeVideoId(segments[1])
          ? YouTubePageKind.shorts
          : YouTubePageKind.other;
    case 'live':
      return segments.length > 1 && isValidYouTubeVideoId(segments[1])
          ? YouTubePageKind.live
          : YouTubePageKind.other;
  }
  return YouTubePageKind.other;
}

/// True on pages with one video to act on (the watch strip is shown).
bool isYouTubeVideoPage(Uri? uri) => youTubePageKind(uri) != YouTubePageKind.other;

/// The 11-character video id in a YouTube link, or null.
///
/// Understands `watch?v=`, `youtu.be/<id>`, `/shorts/<id>`, `/live/<id>`,
/// `/embed/<id>` and `/v/<id>` on youtube.com, m., www. and music. hosts.
/// Any other host (including look-alikes such as `youtube.com.evil.example`)
/// gives null.
String? youTubeVideoId(Uri? uri) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  if (uri.userInfo.isNotEmpty) return null;
  final host = _host(uri);
  if (!_videoHosts.contains(host)) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  String? id;
  if (host == 'youtu.be') {
    id = segments.isNotEmpty ? segments.first : null;
  } else if (segments.isNotEmpty) {
    switch (segments.first) {
      case 'watch':
        id = uri.queryParameters['v'];
      case 'shorts':
      case 'live':
      case 'embed':
      case 'v':
        id = segments.length > 1 ? segments[1] : null;
    }
  }
  return id != null && isValidYouTubeVideoId(id) ? id : null;
}

/// Same as [youTubeVideoId] for a string; null when it does not parse.
String? youTubeVideoIdFromString(String? raw) {
  if (raw == null) return null;
  final uri = Uri.tryParse(raw.trim());
  return youTubeVideoId(uri);
}

/// The clean link to share or download: `https://youtu.be/<id>`, or
/// `https://youtube.com/shorts/<id>` for Shorts. Tracking parameters such as
/// `si`, `pp`, `feature` and the playlist context are dropped by building the
/// link from the id alone. Null when [uri] holds no video.
String? canonicalYouTubeLink(Uri? uri) {
  final id = youTubeVideoId(uri);
  if (id == null) return null;
  final isShort = uri!.pathSegments.where((s) => s.isNotEmpty).firstOrNull == 'shorts';
  return isShort ? 'https://youtube.com/shorts/$id' : 'https://youtu.be/$id';
}

/// Thumbnail for a video id when the page did not report one (mediaSession
/// artwork). Only built from a validated id.
String? youTubeThumbnailFor(String? videoId) =>
    videoId != null && isValidYouTubeVideoId(videoId) ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : null;

/// Hosts the page's artwork (thumbnail) may come from.
bool isYouTubeImageHost(String host) {
  final h = host.toLowerCase();
  return h == 'i.ytimg.com' ||
      h.endsWith('.ytimg.com') ||
      h == 'yt3.ggpht.com' ||
      h.endsWith('.ggpht.com') ||
      h.endsWith('.googleusercontent.com');
}

/// What the WebView does with a navigation.
enum OnlineNavigationKind {
  /// Load it inside the Online tab.
  allow,

  /// Not a YouTube page: hand it to the phone's browser (or the app that owns it).
  openExternally,

  /// Drop it (app schemes such as `intent://` or `vnd.youtube://`, `javascript:`, files).
  cancel,
}

class OnlineNavigationDecision {
  const OnlineNavigationDecision(this.kind, [this.uri]);

  final OnlineNavigationKind kind;

  /// The link to open externally, for [OnlineNavigationKind.openExternally].
  final Uri? uri;

  @override
  String toString() => 'OnlineNavigationDecision($kind${uri == null ? '' : ', $uri'})';
}

/// Navigation policy of the Online WebView.
///
/// - Main frame: YouTube page hosts and Google's sign-in pages (https only,
///   see [isGoogleSignInPage]) load inside; other http(s) links open in the
///   phone's browser; every other scheme is cancelled.
/// - Sub frames (iframes the page itself embeds): https and the inert
///   about:/data:/blob: documents are allowed, everything else is cancelled.
///   They never reach the media bridge (main frame only, plus a token).
OnlineNavigationDecision decideOnlineNavigation(Uri? uri, {required bool isMainFrame}) {
  if (uri == null) return const OnlineNavigationDecision(OnlineNavigationKind.cancel);
  final scheme = uri.scheme.toLowerCase();
  if (!isMainFrame) {
    if (scheme == 'https' || scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return const OnlineNavigationDecision(OnlineNavigationKind.allow);
    }
    return const OnlineNavigationDecision(OnlineNavigationKind.cancel);
  }
  if (scheme == 'about' && (uri.path == 'blank' || uri.toString() == 'about:blank')) {
    return const OnlineNavigationDecision(OnlineNavigationKind.allow);
  }
  if (scheme == 'https' || scheme == 'http') {
    if (isYouTubePage(uri)) {
      // No mixed content: a plain-http YouTube link is not loaded as is (the
      // site redirects to https anyway, and cleartext is off app-wide).
      if (scheme == 'http') {
        return OnlineNavigationDecision(OnlineNavigationKind.allow, uri.replace(scheme: 'https'));
      }
      return const OnlineNavigationDecision(OnlineNavigationKind.allow);
    }
    // Signing in to YouTube: Google's sign-in pages load in place, so the
    // sign-in finishes in the tab and its cookies stay with YouTube's.
    if (isGoogleSignInPage(uri)) return const OnlineNavigationDecision(OnlineNavigationKind.allow);
    if (uri.host.isEmpty) return const OnlineNavigationDecision(OnlineNavigationKind.cancel);
    return OnlineNavigationDecision(OnlineNavigationKind.openExternally, uri);
  }
  // intent://, vnd.youtube://, market://, javascript:, file:, content:, data:, blob: ...
  return const OnlineNavigationDecision(OnlineNavigationKind.cancel);
}

/// Whether a main-frame navigation that would leave YouTube was the user's
/// own tap, so it may open the browser (or another app).
///
/// Android reports [hasGesture] for every navigation. iOS never does
/// (flutter_inappwebview always sends null there), so a link activation or a
/// form submission ([linkOrFormActivated], from WebKit's navigation type)
/// stands in for the tap, and scripts, meta refreshes and 3xx redirects
/// (WebKit's "other") never count: a page or an ad frame cannot bounce the
/// phone to Safari or the App Store on its own.
bool isUserNavigation({required bool? hasGesture, required bool linkOrFormActivated}) =>
    hasGesture ?? linkOrFormActivated;

/// iOS: the page asked for a new window (a `target="_blank"` link, or
/// `window.open`). Android never asks: its WebView loads those links in place
/// (multiple windows are off), where [decideOnlineNavigation] handles them.
///
/// The new window would be a top-level page, so the main-frame rules apply:
/// a YouTube page is [OnlineNavigationKind.allow]ed (it loads in place), an
/// outside link opens in the phone's browser only when [userTapped] (see
/// [isUserNavigation]), and everything else is [OnlineNavigationKind.cancel]led.
OnlineNavigationDecision decideOnlineNewWindow(Uri? uri, {required bool userTapped}) {
  final decision = decideOnlineNavigation(uri, isMainFrame: true);
  if (decision.kind == OnlineNavigationKind.openExternally && !userTapped) {
    return const OnlineNavigationDecision(OnlineNavigationKind.cancel);
  }
  return decision;
}

/// The YouTube search results page for [query] (our own search sheet's fallback
/// when the page's search box cannot be focused).
Uri youTubeSearchUri(String query) =>
    Uri.https('m.youtube.com', '/results', {'search_query': query.trim()});

/// Short text for the address pill: the page title without " - YouTube", else the host.
String addressLabel({String? title, Uri? url}) {
  var t = (title ?? '').trim();
  if (t.endsWith(' - YouTube')) t = t.substring(0, t.length - ' - YouTube'.length).trim();
  if (t.isNotEmpty && t != 'YouTube' && !t.startsWith('http')) return t;
  final host = url == null ? '' : _host(url);
  return host.isEmpty ? 'YouTube' : host;
}
