import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/personal/extractor_hosts.dart';

/// The hosts listed in `ALLOWED_HOSTS` of the Android side.
List<String> kotlinAllowedHosts() {
  final source =
      File('android/app/src/main/kotlin/com/example/mediahub/personal/ExtractorChannel.kt').readAsStringSync();
  final block = RegExp(r'ALLOWED_HOSTS = listOf\(([^)]*)\)').firstMatch(source);
  expect(block, isNotNull, reason: 'ALLOWED_HOSTS not found');
  return RegExp(r'"([^"]+)"').allMatches(block!.group(1)!).map((m) => m.group(1)!).toList();
}

void main() {
  test('the Dart list is the Android list (same sites, same order)', () {
    expect(ExtractorHosts.allowed, kotlinAllowedHosts());
  });

  group('the common family sites are covered', () {
    for (final link in [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com/shorts/dQw4w9WgXcQ',
      'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtu.be/dQw4w9WgXcQ',
      'https://www.instagram.com/reel/C1abcDEF/',
      'https://www.facebook.com/watch/?v=123',
      'https://m.facebook.com/story.php?id=1',
      'https://fb.watch/abc123/',
      'https://www.tiktok.com/@someone/video/123',
      'https://vm.tiktok.com/ZMabc/',
      'https://x.com/someone/status/123',
      'https://twitter.com/someone/status/123',
      'https://vimeo.com/123456',
      'https://player.vimeo.com/video/123456',
      'https://www.dailymotion.com/video/x8abc',
      'https://dai.ly/x8abc',
      'https://soundcloud.com/artist/song',
      'https://on.soundcloud.com/abc',
      'https://www.reddit.com/r/videos/comments/abc/title/',
      'https://v.redd.it/abc123',
      'https://redd.it/abc123',
    ]) {
      test(link, () => expect(ExtractorHosts.isAllowed(Uri.parse(link)), isTrue));
    }
  });

  group('look-alikes and other sites never reach yt-dlp', () {
    for (final link in [
      'https://notyoutube.com/watch?v=x',
      'https://youtube.com.evil.example/watch?v=x',
      'https://evil-youtube.com/watch?v=x',
      'https://reddit.com.example/r/x',
      'https://example.com/video.mp4',
      'http://www.youtube.com/watch?v=dQw4w9WgXcQ', // https only
      'file:///sdcard/x.mp4',
    ]) {
      test(link, () => expect(ExtractorHosts.isAllowed(Uri.parse(link)), isFalse));
    }
  });
}
