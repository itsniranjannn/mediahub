import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/known_platform_checker.dart';

void main() {
  group('TASK 5.2c Item 3: Known Platforms Host Matching', () {
    test('Exact host matches return correct platform name', () {
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://youtube.com/watch?v=123')), 'YouTube');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://youtu.be/bIQkviE_JJo')), 'YouTube');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://music.youtube.com/watch?v=123')), 'YouTube Music');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://instagram.com/p/123')), 'Instagram');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://facebook.com/watch')), 'Facebook');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://fb.watch/123')), 'Facebook');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://tiktok.com/@user')), 'TikTok');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://x.com/status/123')), 'X');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://twitter.com/status/123')), 'Twitter');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://spotify.com/track/123')), 'Spotify');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://soundcloud.com/artist/track')), 'SoundCloud');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://vimeo.com/123456')), 'Vimeo');
    });

    test('Subdomain host matches return correct platform name', () {
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://m.youtube.com/watch?v=123')), 'YouTube');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://open.spotify.com/track/123')), 'Spotify');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://mobile.twitter.com/status/123')), 'Twitter');
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://sub.vimeo.com/123')), 'Vimeo');
    });

    test('Lookalike hosts and unrelated domains MUST NOT match', () {
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://notyoutube.com.evil.example/watch')), isNull);
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://youtube.com.fake.com')), isNull);
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://spotify.com.attacker.org')), isNull);
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://fakevimeo.com')), isNull);
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://notx.com')), isNull);
      expect(KnownPlatformChecker.matchPlatformName(Uri.parse('https://example.com/audio.mp3')), isNull);
    });
  });
}
