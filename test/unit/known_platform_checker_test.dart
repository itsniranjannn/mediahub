import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/known_platform_checker.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';

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

  group('Spotify songs are refused up front (SEC-14)', () {
    bool protectedLink(String url) => KnownPlatformChecker.isProtectedSpotifyLink(Uri.parse(url));

    test('tracks, albums and playlists, in any of their link shapes', () {
      for (final url in [
        'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
        'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc',
        'https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3',
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
        'https://open.spotify.com/intl-fr/album/1DFixLWuPkv3KT3TnV35m3',
        'https://open.spotify.com/embed/track/4cOdK2wGLETKBW3PvgPWqT',
        'https://OPEN.SPOTIFY.COM/Track/4cOdK2wGLETKBW3PvgPWqT',
        'https://open.spotify.com./track/4cOdK2wGLETKBW3PvgPWqT',
      ]) {
        expect(protectedLink(url), isTrue, reason: url);
        expect(KnownPlatformChecker.protectedContentMessage(Uri.parse(url)), KnownPlatformChecker.spotifyProtectedMessage);
      }
    });

    test('episodes, shows, other pages and look-alikes are not', () {
      for (final url in [
        'https://open.spotify.com/episode/512ojhOuo1ktJprKbVcKyQ',
        'https://open.spotify.com/show/2MAi0BvDc6GTFvKFPXnkCL',
        'https://open.spotify.com/',
        'https://open.spotify.com/artist/0OdUWJ0sBjDrqHygGUXeCF',
        'https://spotify.com.evil.example/track/4cOdK2wGLETKBW3PvgPWqT',
        'https://notspotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ]) {
        expect(protectedLink(url), isFalse, reason: url);
      }
    });

    test('the Downloads link check says so instead of a "Platform Link" card', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(inspectionProvider.notifier).inspect(Uri.parse('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT'));
      final s = container.read(inspectionProvider);
      expect(s.errorMessage, KnownPlatformChecker.spotifyProtectedMessage);
      expect(s.result, isNull);
      expect(s.isInspecting, isFalse);

      await container.read(inspectionProvider.notifier).inspect(Uri.parse('https://open.spotify.com/episode/512ojhOuo1ktJprKbVcKyQ'));
      expect(container.read(inspectionProvider).errorMessage, isNull);
      expect(container.read(inspectionProvider).knownPlatformName, 'Spotify');
    });
  });
}
