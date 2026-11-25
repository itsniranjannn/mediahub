// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Settings → Online → Block ads: the request rules the Online WebView gets
/// on top of the page script (`assets/web/youtube_bridge.js`, section g),
/// which does most of the work: it removes the ad fields from YouTube's
/// player data, mutes and skips an ad that plays anyway, hides ad boxes and
/// fails the page's own requests to the addresses below.
///
/// Where each platform blocks requests natively:
/// - **iOS:** a WebKit content rule list ([onlineAdContentBlockers]). WebKit
///   compiles it once per WebView and checks every request itself.
/// - **Android: nothing native.** flutter_inappwebview_android 1.1.3 has no
///   cheap way:
///   - its content blockers (ContentBlockerHandler `checkUrl`) make an extra
///     HTTP HEAD request for every resource the page loads, video segments
///     included, to learn its type: that would double YouTube's requests;
///   - `shouldInterceptRequest` would stop the network thread for a Dart
///     round trip on every request;
///   - `regexToCancelSubFramesLoading` is only read inside
///     `shouldOverrideUrlLoading` (InAppWebViewClient(Compat).java), which
///     Android's WebView never calls for an http(s) navigation in a frame,
///     so it never sees an ad frame; and for a frame the plugin answers
///     `shouldOverrideUrlLoading` itself, at once, so a Dart decision there
///     cannot cancel one either.
///
///   So on Android the bridge alone blocks: the page's own fetch, XHR and
///   sendBeacon calls to these addresses fail. A `<script>`, `<img>` or
///   `<iframe>` the page loads from them, and anything inside such a frame,
///   still loads.
///
/// Never matched: the video itself (`googlevideo.com/videoplayback`),
/// YouTube's player API (`/youtubei/v1/...`), its pictures (`i.ytimg.com`,
/// `yt3.ggpht.com`), its watch-time and playback stats, and Google's
/// sign-in or attestation hosts.
const List<String> onlineAdHosts = [
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'googletagservices.com',
  'imasdk.googleapis.com',
];

/// YouTube's own ad and ad-tracking paths (on any youtube.com host).
const List<String> onlineAdYouTubePaths = [
  '/pagead/',
  '/api/stats/ads',
  '/ptracking',
  '/get_midroll_',
];

String _escapeDots(String s) => s.replaceAll('.', r'\.');

/// WebKit `url-filter` patterns, one per host or path, in the form WebKit's
/// own documentation gives for "this domain and its subdomains". WebKit's
/// filter syntax has no `|`, no `{n}` and no `(?...)`: a rule list that does
/// not compile leaves the iOS page blank, so only that form is used.
List<String> onlineAdUrlFilters() => [
      for (final host in onlineAdHosts) '^[^:]+://+([^:/]+\\.)?${_escapeDots(host)}[:/]',
      for (final path in onlineAdYouTubePaths) '^[^:]+://+([^:/]+\\.)?youtube\\.com$path',
    ];

/// iOS: the content rule list (block, any resource type, any frame).
List<ContentBlocker> onlineAdContentBlockers() => [
      for (final filter in onlineAdUrlFilters())
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: filter),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
    ];

/// Whether the iOS rule list blocks [url] (for tests and diagnostics; WebKit
/// filters are case-insensitive by default).
bool onlineAdRuleBlocks(String url) =>
    onlineAdUrlFilters().any((f) => RegExp(f, caseSensitive: false).hasMatch(url));
