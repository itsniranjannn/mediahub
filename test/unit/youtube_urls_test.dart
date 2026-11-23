import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/online/youtube_urls.dart';

Uri u(String s) => Uri.parse(s);

void main() {
  group('youTubeVideoId', () {
    const id = 'dQw4w9WgXcQ';
    for (final url in [
      'https://www.youtube.com/watch?v=$id',
      'https://m.youtube.com/watch?v=$id&si=abc&pp=xyz',
      'https://youtube.com/watch?feature=share&v=$id',
      'https://music.youtube.com/watch?v=$id&list=RDAMVM',
      'https://youtu.be/$id',
      'https://youtu.be/$id?si=tracking123&t=42',
      'https://www.youtube.com/shorts/$id',
      'https://m.youtube.com/shorts/$id?feature=share',
      'https://www.youtube.com/live/$id?si=x',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/v/$id',
      'http://www.youtube.com/watch?v=$id',
      'https://WWW.YouTube.com/watch?v=$id',
    ]) {
      test('finds the id in $url', () => expect(youTubeVideoId(u(url)), id));
    }

    for (final url in [
      'https://www.youtube.com/',
      'https://www.youtube.com/feed/subscriptions',
      'https://www.youtube.com/watch?v=short',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ"><script>',
      'https://www.youtube.com/@channel',
      'https://youtube.com.evil.example/watch?v=$id',
      'https://evil.example/watch?v=$id',
      'https://notyoutube.com/watch?v=$id',
      'https://youtube.com@evil.example/watch?v=$id',
      'https://www.youtube.com.evil.example/shorts/$id',
      'ftp://www.youtube.com/watch?v=$id',
      'javascript:alert(1)',
      'intent://watch?v=$id#Intent;scheme=vnd.youtube;end',
      'vnd.youtube://$id',
    ]) {
      test('rejects $url', () => expect(youTubeVideoId(u(url)), isNull));
    }

    test('null and junk strings', () {
      expect(youTubeVideoId(null), isNull);
      expect(youTubeVideoIdFromString(null), isNull);
      expect(youTubeVideoIdFromString('   '), isNull);
      expect(youTubeVideoIdFromString(' https://youtu.be/$id '), id);
    });
  });

  group('canonicalYouTubeLink', () {
    test('watch pages become youtu.be without tracking parameters', () {
      expect(
        canonicalYouTubeLink(u('https://m.youtube.com/watch?v=dQw4w9WgXcQ&si=abc&pp=ygUE&feature=share&list=PL1')),
        'https://youtu.be/dQw4w9WgXcQ',
      );
      expect(canonicalYouTubeLink(u('https://youtu.be/dQw4w9WgXcQ?si=xyz')), 'https://youtu.be/dQw4w9WgXcQ');
      expect(canonicalYouTubeLink(u('https://www.youtube.com/live/dQw4w9WgXcQ?si=1')), 'https://youtu.be/dQw4w9WgXcQ');
    });

    test('Shorts keep their own link', () {
      expect(
        canonicalYouTubeLink(u('https://m.youtube.com/shorts/aqz-KE-bpKQ?feature=share&si=x')),
        'https://youtube.com/shorts/aqz-KE-bpKQ',
      );
    });

    test('no video, no link', () {
      expect(canonicalYouTubeLink(u('https://m.youtube.com/')), isNull);
      expect(canonicalYouTubeLink(u('https://example.com/watch?v=dQw4w9WgXcQ')), isNull);
      expect(canonicalYouTubeLink(null), isNull);
    });
  });

  group('youTubePageKind', () {
    test('watch, shorts and live show the watch strip', () {
      expect(youTubePageKind(u('https://m.youtube.com/watch?v=dQw4w9WgXcQ')), YouTubePageKind.watch);
      expect(youTubePageKind(u('https://m.youtube.com/shorts/dQw4w9WgXcQ')), YouTubePageKind.shorts);
      expect(youTubePageKind(u('https://m.youtube.com/live/dQw4w9WgXcQ')), YouTubePageKind.live);
      expect(isYouTubeVideoPage(u('https://youtu.be/dQw4w9WgXcQ')), isTrue);
    });

    test('everything else does not', () {
      expect(youTubePageKind(u('https://m.youtube.com/')), YouTubePageKind.other);
      expect(youTubePageKind(u('https://m.youtube.com/results?search_query=x')), YouTubePageKind.other);
      expect(youTubePageKind(u('https://m.youtube.com/watch')), YouTubePageKind.other);
      expect(youTubePageKind(u('https://m.youtube.com/shorts/')), YouTubePageKind.other);
      expect(youTubePageKind(u('https://example.com/watch?v=dQw4w9WgXcQ')), YouTubePageKind.other);
      expect(isYouTubeVideoPage(null), isFalse);
    });
  });

  group('decideOnlineNavigation', () {
    OnlineNavigationKind main(String url) => decideOnlineNavigation(u(url), isMainFrame: true).kind;
    OnlineNavigationKind sub(String url) => decideOnlineNavigation(u(url), isMainFrame: false).kind;

    test('YouTube page hosts load inside', () {
      for (final url in [
        'https://m.youtube.com/',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/feed/trending',
        'https://consent.youtube.com/m?continue=x',
        'https://accounts.youtube.com/accounts/SetSID',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://music.youtube.com/',
        'about:blank',
      ]) {
        expect(main(url), OnlineNavigationKind.allow, reason: url);
      }
    });

    test('plain-http YouTube is upgraded to https', () {
      final d = decideOnlineNavigation(u('http://m.youtube.com/watch?v=dQw4w9WgXcQ'), isMainFrame: true);
      expect(d.kind, OnlineNavigationKind.allow);
      expect(d.uri.toString(), 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('other web links open in the browser', () {
      for (final url in [
        'https://example.com/',
        // Google, but not its sign-in: My Account, Help, Search.
        'https://myaccount.google.com/',
        'https://support.google.com/accounts/answer/7675428',
        'https://www.google.com/search?q=x',
        'https://youtube.com.evil.example/',
        'https://www.youtube.com:8443/',
        'http://example.com/page',
      ]) {
        final d = decideOnlineNavigation(u(url), isMainFrame: true);
        expect(d.kind, OnlineNavigationKind.openExternally, reason: url);
        expect(d.uri, isNotNull);
      }
    });

    test('app schemes, scripts and files are cancelled', () {
      for (final url in [
        'intent://watch?v=dQw4w9WgXcQ#Intent;scheme=vnd.youtube;package=com.google.android.youtube;end',
        'vnd.youtube://dQw4w9WgXcQ',
        'market://details?id=com.google.android.youtube',
        'javascript:alert(1)',
        'file:///sdcard/secret.txt',
        'content://media/external/file/1',
        'data:text/html,<h1>x</h1>',
        'youtube://watch',
        'mailto:a@b.c',
      ]) {
        expect(main(url), OnlineNavigationKind.cancel, reason: url);
      }
      expect(decideOnlineNavigation(null, isMainFrame: true).kind, OnlineNavigationKind.cancel);
    });

    // The owner could not sign in: the sign-in page used to open the browser.
    test("Google's sign-in pages load inside, so a YouTube sign-in can finish in the tab", () {
      for (final url in [
        'https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin',
        'https://accounts.google.com/v3/signin/identifier?flowName=GlifWebSignIn',
        'https://accounts.google.com/v3/signin/challenge/pwd',
        'https://accounts.google.com/AccountChooser',
        'https://accounts.google.com/Logout?continue=https://m.youtube.com/',
        'https://accounts.youtube.com/accounts/SetSID?ssdc=1',
        'https://gds.google.com/web/recoveryoptions',
        'https://ACCOUNTS.Google.com./signin',
        'https://accounts.google.com:443/signin',
      ]) {
        final d = decideOnlineNavigation(u(url), isMainFrame: true);
        expect(d.kind, OnlineNavigationKind.allow, reason: url);
        expect(d.uri, isNull, reason: 'loaded as it is: $url');
      }
    });

    test('sign-in pages: exact hosts, https only', () {
      for (final url in [
        'http://accounts.google.com/ServiceLogin',
        'https://accounts.google.com:8443/',
        'https://accounts.google.com@evil.example/',
        'https://user@accounts.google.com/',
        'https://accounts.google.com.evil.example/',
        'https://evilaccounts.google.com/',
        'https://xaccounts.youtube.com/',
        'https://accounts.google.co.uk/',
        'https://google.com/accounts',
      ]) {
        final uri = u(url);
        expect(isGoogleSignInPage(uri), isFalse, reason: url);
        expect(decideOnlineNavigation(uri, isMainFrame: true).kind, isNot(OnlineNavigationKind.allow), reason: url);
      }
      // A plain-http sign-in link is never loaded in the tab: it goes the
      // way of any other site (the browser, only for a tap).
      expect(main('http://accounts.google.com/ServiceLogin'), OnlineNavigationKind.openExternally);
    });

    test('sign-in pages are never YouTube pages (the media bridge stays off there)', () {
      for (final url in [
        'https://accounts.google.com/ServiceLogin',
        'https://accounts.youtube.com/accounts/SetSID',
        'https://gds.google.com/web/recoveryoptions',
      ]) {
        expect(isYouTubePage(u(url)), isFalse, reason: url);
        expect(isGoogleSignInPage(u(url)), isTrue, reason: url);
        expect(youTubeVideoId(u(url)), isNull, reason: url);
      }
      // consent.youtube.com is still YouTube's own cookie page.
      expect(isYouTubePage(u('https://consent.youtube.com/m?continue=x')), isTrue);
    });

    test('a new window (iOS target="_blank") for the sign-in loads in place too', () {
      expect(
        decideOnlineNewWindow(u('https://accounts.google.com/ServiceLogin'), userTapped: false).kind,
        OnlineNavigationKind.allow,
      );
    });

    test('sub frames: https and inert documents only', () {
      expect(sub('https://www.youtube.com/embed/x'), OnlineNavigationKind.allow);
      expect(sub('https://googleads.g.doubleclick.net/pagead/x'), OnlineNavigationKind.allow);
      expect(sub('about:blank'), OnlineNavigationKind.allow);
      expect(sub('http://example.com/'), OnlineNavigationKind.cancel);
      expect(sub('intent://x#Intent;end'), OnlineNavigationKind.cancel);
      expect(sub('javascript:alert(1)'), OnlineNavigationKind.cancel);
      expect(sub('file:///etc/hosts'), OnlineNavigationKind.cancel);
    });
  });

  group('isUserNavigation (may a link leave for the browser?)', () {
    test('Android: the reported gesture decides', () {
      expect(isUserNavigation(hasGesture: true, linkOrFormActivated: false), isTrue);
      expect(isUserNavigation(hasGesture: false, linkOrFormActivated: true), isFalse);
      expect(isUserNavigation(hasGesture: false, linkOrFormActivated: false), isFalse);
    });

    test('iOS (no gesture reported): a link tap or form submit opens, a redirect does not', () {
      // flutter_inappwebview_ios always sends hasGesture: null.
      expect(isUserNavigation(hasGesture: null, linkOrFormActivated: true), isTrue);
      // A script, meta refresh or 3xx redirect is WebKit's "other".
      expect(isUserNavigation(hasGesture: null, linkOrFormActivated: false), isFalse);
    });
  });

  test('image hosts for artwork', () {
    expect(isYouTubeImageHost('i.ytimg.com'), isTrue);
    expect(isYouTubeImageHost('i9.ytimg.com'), isTrue);
    expect(isYouTubeImageHost('yt3.ggpht.com'), isTrue);
    expect(isYouTubeImageHost('lh3.googleusercontent.com'), isTrue);
    expect(isYouTubeImageHost('evil.example'), isFalse);
    expect(isYouTubeImageHost('ytimg.com.evil.example'), isFalse);
  });

  test('address label prefers the title without " - YouTube"', () {
    expect(addressLabel(title: 'Cats - YouTube', url: u('https://m.youtube.com/watch?v=dQw4w9WgXcQ')), 'Cats');
    expect(addressLabel(title: 'YouTube', url: u('https://m.youtube.com/')), 'm.youtube.com');
    expect(addressLabel(title: null, url: null), 'YouTube');
    expect(addressLabel(title: 'https://m.youtube.com/', url: u('https://m.youtube.com/')), 'm.youtube.com');
  });

  group("YouTube's sign-in address", () {
    Uri handOver(Uri signIn) => Uri.parse(signIn.queryParameters['continue']!);

    test("Google's sign-in for the YouTube service, handed back to YouTube's mobile site", () {
      final signIn = youTubeSignInUri();
      expect(signIn.scheme, 'https');
      expect(signIn.host, 'accounts.google.com');
      expect(signIn.path, '/ServiceLogin');
      expect(signIn.queryParameters['service'], 'youtube');
      expect(signIn.queryParameters['passive'], 'true');
      final back = handOver(signIn);
      expect(back.toString(), startsWith('https://www.youtube.com/signin?'));
      expect(back.queryParameters['action_handle_signin'], 'true');
      expect(back.queryParameters['app'], 'm');
      expect(back.queryParameters['next'], youTubeHomeUrl);
      // The whole hand-over travels as one encoded value.
      expect(signIn.toString(), contains('continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3F'));
      // Every step of it may load in the tab.
      expect(decideOnlineNavigation(signIn, isMainFrame: true).kind, OnlineNavigationKind.allow);
      expect(decideOnlineNavigation(back, isMainFrame: true).kind, OnlineNavigationKind.allow);
    });

    test('it returns to the YouTube page the user was on, never anywhere else', () {
      const watch = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42';
      expect(handOver(youTubeSignInUri(returnTo: u(watch))).queryParameters['next'], watch);
      for (final other in [
        'https://evil.example/',
        'https://accounts.google.com/ServiceLogin',
        'http://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://music.youtube.com/',
        'about:blank',
      ]) {
        expect(handOver(youTubeSignInUri(returnTo: u(other))).queryParameters['next'], youTubeHomeUrl, reason: other);
      }
    });
  });

  test('search uri encodes the query', () {
    expect(youTubeSearchUri(' lo-fi & chill ').toString(), 'https://m.youtube.com/results?search_query=lo-fi+%26+chill');
  });

  test('thumbnail only from a valid id', () {
    expect(youTubeThumbnailFor('dQw4w9WgXcQ'), 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(youTubeThumbnailFor('../../etc'), isNull);
    expect(youTubeThumbnailFor(null), isNull);
  });

  test('a YouTube link typed in the address bar opens; anything else is searched', () {
    expect(youTubePageFromTyped('https://youtu.be/dQw4w9WgXcQ').toString(), 'https://youtu.be/dQw4w9WgXcQ');
    expect(youTubePageFromTyped('  m.youtube.com/watch?v=dQw4w9WgXcQ ').toString(), 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(youTubePageFromTyped('http://www.youtube.com/shorts/dQw4w9WgXcQ').toString(), 'https://www.youtube.com/shorts/dQw4w9WgXcQ');
    expect(youTubePageFromTyped('https://music.youtube.com/'), isNotNull);
    expect(youTubePageFromTyped('lofi beats'), isNull);
    expect(youTubePageFromTyped('youtube'), isNull);
    expect(youTubePageFromTyped('https://example.com/watch?v=dQw4w9WgXcQ'), isNull);
    expect(youTubePageFromTyped('https://youtube.com.evil.example/'), isNull);
    expect(youTubePageFromTyped('https://youtube.com@evil.example/'), isNull);
    expect(youTubePageFromTyped('javascript:alert(1)'), isNull);
    expect(youTubePageFromTyped('https://youtube.com:8080/'), isNull);
  });
}
