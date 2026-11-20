// Settings → Online → Block ads: the WebView's ad request rules
// (lib/features/online/online_ad_block.dart): iOS only, Android has none. The
// page script's own part (all of Android's blocking) is tested in
// test/js/youtube_bridge_test.js.
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/online/online_ad_block.dart';
import 'package:mediahub/features/online/online_web_view.dart';

/// Ad and ad-tracking addresses the rules must stop.
const _ads = [
  'https://googleads.g.doubleclick.net/pagead/id',
  'https://static.doubleclick.net/instream/ad_status.js',
  'https://securepubads.g.doubleclick.net/tag/js/gpt.js',
  'https://doubleclick.net/x',
  'https://www.googleadservices.com/pagead/conversion/1001/',
  'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js',
  'https://tpc.googlesyndication.com/simgad/123',
  'https://www.googletagservices.com/tag/js/gpt.js',
  'https://imasdk.googleapis.com/js/sdkloader/ima3.js',
  'https://m.youtube.com/pagead/viewthroughconversion/962985656/?backend=innertube',
  'https://www.youtube.com/pagead/paralleladview?ai=x',
  'https://www.youtube.com/api/stats/ads?ver=2&ns=1',
  'https://www.youtube.com/ptracking?ptk=youtube_none&pltype=content',
  'https://www.youtube.com/get_midroll_info?ei=x',
];

/// What the video and the page need: never blocked.
const _needed = [
  'https://rr1---sn-ab5l6nzr.googlevideo.com/videoplayback?expire=1&id=o-x&itag=251&source=youtube',
  // An ad's own video comes from the same host: still never blocked by address.
  'https://rr3---sn-ab5l6nzr.googlevideo.com/videoplayback?expire=1&ctier=L&oad=1&itag=18',
  'https://m.youtube.com/youtubei/v1/player?prettyPrint=false',
  'https://www.youtube.com/youtubei/v1/next?prettyPrint=false',
  'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
  'https://m.youtube.com/watch?v=dQw4w9WgXcQ&next=/pagead/x',
  'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
  'https://www.youtube.com/s/player/abc123/player_ias.vflset/en_US/base.js',
  'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
  'https://yt3.ggpht.com/ytc/abc=s88-c-k',
  'https://www.youtube.com/api/stats/watchtime?ns=yt&docid=dQw4w9WgXcQ',
  'https://www.youtube.com/api/stats/playback?ns=yt',
  'https://s.youtube.com/api/stats/qoe?event=streamingstats',
  'https://www.youtube.com/generate_204',
  'https://jnn-pa.googleapis.com/\$rpc/google.internal.waa.v1.Waa/GenerateIT',
  'https://www.google.com/js/th/abc.js',
  'https://accounts.google.com/v3/signin/identifier',
  'https://accounts.youtube.com/accounts/SetSID',
  'https://fonts.gstatic.com/s/roboto/v30/x.woff2',
  'https://doubleclick.net.example.org/pagead/id',
  'https://notdoubleclick.net/x',
];

void main() {
  group('iOS rule list (WebKit content blockers)', () {
    test('blocks every ad address', () {
      for (final url in _ads) {
        expect(onlineAdRuleBlocks(url), isTrue, reason: url);
      }
    });

    test('never the video, the player API, pictures, stats the page needs or sign-in', () {
      for (final url in _needed) {
        expect(onlineAdRuleBlocks(url), isFalse, reason: url);
      }
    });

    test("uses only WebKit's filter syntax, so the list compiles (a failed one leaves the page blank)", () {
      for (final filter in onlineAdUrlFilters()) {
        expect(filter, startsWith('^[^:]+://+([^:/]+\\.)?'), reason: filter);
        expect(filter, isNot(contains('|')), reason: '$filter: no alternatives in WebKit');
        expect(filter, isNot(contains('{')), reason: '$filter: no counted repeats');
        expect(filter, isNot(contains('(?')), reason: '$filter: no special groups');
        expect(RegExp(r'\\[dDwWsSbB]').hasMatch(filter), isFalse, reason: '$filter: no class escapes');
      }
    });

    test('each rule blocks; nothing narrows it to a resource type (that would cost a request on Android)', () {
      final rules = onlineAdContentBlockers();
      expect(rules, hasLength(onlineAdHosts.length + onlineAdYouTubePaths.length));
      for (final rule in rules) {
        final map = rule.toMap();
        expect(map['action'], {'type': 'block'});
        expect(map['trigger']!.containsKey('resource-type'), isFalse);
        expect(map['trigger']!['url-filter'], isA<String>());
      }
    });
  });

  group('WebView settings', () {
    test('iOS gets the rule list; Android no native ad rule at all (the page script blocks there)', () {
      final ios = onlineWebViewSettings(backgroundPlay: true, isIOS: true);
      expect(ios.contentBlockers!.map((b) => b.trigger.urlFilter), onlineAdUrlFilters());
      expect(ios.contentBlockers!.every((b) => b.action.type == ContentBlockerActionType.BLOCK), isTrue);
      expect(ios.regexToCancelSubFramesLoading, isNull);

      final android = onlineWebViewSettings(backgroundPlay: true, isIOS: false);
      expect(android.contentBlockers, isEmpty,
          reason: "the plugin's Android content blockers send a HEAD request for every resource");
      expect(android.regexToCancelSubFramesLoading, isNull,
          reason: 'the Android plugin reads it only in shouldOverrideUrlLoading, which the WebView never '
              'calls for an http(s) frame: it would block nothing (online_ad_block.dart)');
      expect(android.useShouldInterceptRequest, isNot(isTrue), reason: 'no Dart round trip per request');
    });

    test('Block ads off: nothing on either phone', () {
      for (final ios in [true, false]) {
        final s = onlineWebViewSettings(backgroundPlay: true, isIOS: ios, blockAds: false);
        expect(s.contentBlockers, isEmpty, reason: 'iOS: $ios');
        expect(s.regexToCancelSubFramesLoading, isNull, reason: 'iOS: $ios');
      }
    });
  });
}
