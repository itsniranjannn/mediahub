import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/known_platform_checker.dart';
import 'package:mediahub/core/security/url_policy.dart';
import 'package:mediahub/data/downloads/youtube_link.dart';

const _id = 'dQw4w9WgXcQ';

YoutubeLink? _parse(String url) => YoutubeLink.tryParse(url);

void main() {
  group('YoutubeLink.parse accepts every single-video link shape', () {
    final cases = <String, YoutubeLinkKind>{
      'https://www.youtube.com/watch?v=$_id': YoutubeLinkKind.watch,
      'https://youtube.com/watch?v=$_id&t=42s': YoutubeLinkKind.watch,
      'https://m.youtube.com/watch?v=$_id&pp=ygUEdGVzdA%3D%3D': YoutubeLinkKind.watch,
      'https://www.youtube.com/watch?v=$_id&list=PL1234567890&index=3': YoutubeLinkKind.watch,
      'https://music.youtube.com/watch?v=$_id&feature=share': YoutubeLinkKind.watch,
      'https://youtu.be/$_id': YoutubeLinkKind.shortLink,
      'https://youtu.be/$_id?si=AbCdEfGhIjKlMnOp': YoutubeLinkKind.shortLink,
      'https://www.youtube.com/shorts/$_id': YoutubeLinkKind.short,
      'https://youtube.com/shorts/$_id?feature=share': YoutubeLinkKind.short,
      'https://www.youtube.com/live/$_id?si=x': YoutubeLinkKind.live,
      'https://www.youtube.com/embed/$_id': YoutubeLinkKind.embed,
      'https://www.youtube.com/v/$_id': YoutubeLinkKind.embed,
      'HTTPS://WWW.YOUTUBE.COM/watch?v=$_id': YoutubeLinkKind.watch,
      'https://www.youtube.com./watch?v=$_id': YoutubeLinkKind.watch, // fully qualified host
      'https://youtu.be:443/$_id': YoutubeLinkKind.shortLink,
    };
    cases.forEach((url, kind) {
      test(url, () {
        final link = _parse(url);
        expect(link, isNotNull);
        expect(link!.videoId, _id);
        expect(link.kind, kind);
        expect(link.canonicalUrl, 'https://youtu.be/$_id');
      });
    });

    test('music.youtube.com is marked as music', () {
      expect(_parse('https://music.youtube.com/watch?v=$_id')!.isMusic, isTrue);
      expect(_parse('https://www.youtube.com/watch?v=$_id')!.isMusic, isFalse);
    });
  });

  group('links copied from the Online tab parse everywhere in Downloads', () {
    for (final copied in ['https://youtu.be/$_id', 'https://youtube.com/shorts/$_id']) {
      test(copied, () {
        final uri = Uri.parse(copied);
        expect(UrlPolicy.validate(copied).isValid, isTrue, reason: 'the link field accepts it');
        expect(KnownPlatformChecker.matchPlatformName(uri), 'YouTube', reason: 'the link card knows the site');
        expect(YoutubeLink.parse(uri)?.videoId, _id, reason: 'the YouTube download path finds the video');
      });
    }
  });

  group('YoutubeLink.parse refuses everything else', () {
    for (final url in [
      'http://www.youtube.com/watch?v=$_id', // not https
      'https://user@www.youtube.com/watch?v=$_id', // user name
      'https://www.youtube.com:8443/watch?v=$_id', // odd port
      'https://youtube.com.evil.example/watch?v=$_id', // lookalike
      'https://notyoutube.com/watch?v=$_id',
      'https://youtu.be.evil.example/$_id',
      'https://www.youtube-nocookie.com/embed/$_id',
      'https://www.youtube.com/watch?v=short',
      'https://www.youtube.com/watch?v=$_id%22%3E', // id with extra characters
      'https://youtu.be/',
      'https://www.youtube.com/',
      'https://www.youtube.com/shorts/',
      'https://example.com/watch?v=$_id',
      'not a link',
    ]) {
      test(url, () => expect(_parse(url), isNull));
    }
  });

  group('playlists and channels are told apart from other non-video pages', () {
    for (final url in [
      'https://www.youtube.com/playlist?list=PL1234567890',
      'https://www.youtube.com/watch?list=PL1234567890',
      'https://www.youtube.com/@SomeChannel',
      'https://www.youtube.com/channel/UC1234567890',
      'https://www.youtube.com/c/SomeName',
      'https://music.youtube.com/browse/MPREb_123',
    ]) {
      test(url, () {
        final check = YoutubeLink.check(Uri.parse(url));
        expect(check.link, isNull);
        expect(check.isYoutube, isTrue);
        expect(check.isCollection, isTrue);
      });
    }

    test('a search page is YouTube but neither a video nor a collection', () {
      final check = YoutubeLink.check(Uri.parse('https://www.youtube.com/results?search_query=x'));
      expect(check.isYoutube, isTrue);
      expect(check.isCollection, isFalse);
      expect(check.link, isNull);
    });

    test('another site is not YouTube at all', () {
      final check = YoutubeLink.check(Uri.parse('https://example.com/playlist?list=1'));
      expect(check.isYoutube, isFalse);
      expect(check.isCollection, isFalse);
    });
  });

  group('stream host allowlist: https on googlevideo.com only', () {
    test('accepts YouTube media servers', () {
      for (final url in [
        'https://rr5---sn-4g5e6nsz.googlevideo.com/videoplayback?expire=1&itag=18',
        'https://googlevideo.com/videoplayback',
        'https://RR1---SN-ABC.GOOGLEVIDEO.COM/videoplayback',
        'https://rr1---sn-abc.googlevideo.com:443/videoplayback',
      ]) {
        expect(YoutubeLink.trustedStreamUri(url), isNotNull, reason: url);
      }
    });

    test('refuses every other address', () {
      for (final url in [
        'http://rr5---sn-4g5e6nsz.googlevideo.com/videoplayback', // not https
        'https://googlevideo.com.evil.example/videoplayback', // lookalike
        'https://evilgooglevideo.com/videoplayback',
        'https://user:pw@rr1.googlevideo.com/videoplayback', // credentials
        'https://rr1.googlevideo.com:8443/videoplayback', // odd port
        'https://www.youtube.com/watch?v=$_id', // a page, not a media server
        'https://example.com/file.mp4',
        'file:///etc/passwd',
        '',
      ]) {
        expect(YoutubeLink.trustedStreamUri(url), isNull, reason: url);
      }
    });

    test('the media host check is exact or by subdomain', () {
      expect(YoutubeLink.isYoutubeMediaHost('rr1---sn-abc.googlevideo.com'), isTrue);
      expect(YoutubeLink.isYoutubeMediaHost('googlevideo.com.'), isTrue);
      expect(YoutubeLink.isYoutubeMediaHost('googlevideo.co'), isFalse);
      expect(YoutubeLink.isYoutubeMediaHost('xgooglevideo.com'), isFalse);
    });
  });

  test('the cover is always built from the id on YouTube\'s image host', () {
    expect(_parse('https://youtu.be/$_id')!.thumbnailUrl, 'https://i.ytimg.com/vi/$_id/mqdefault.jpg');
    expect(_parse('https://youtu.be/$_id')!.watchUrl, 'https://www.youtube.com/watch?v=$_id');
  });
}
