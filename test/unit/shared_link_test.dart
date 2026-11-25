// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/downloads/download_link_inbox.dart';
import 'package:mediahub/features/downloads/shared_link.dart';

class FakeSharedTextSource implements SharedTextSource {
  final controller = StreamController<String>.broadcast();
  @override
  Stream<String> get texts => controller.stream;
}

void main() {
  group('parseSharedText', () {
    test('takes the first https link out of a caption', () {
      final o = parseSharedText('Check this https://www.instagram.com/reel/xyz/ and https://example.com/b');
      expect(o.isAccepted, isTrue);
      expect(o.url, 'https://www.instagram.com/reel/xyz/');
    });

    test('a bare link, a YouTube share, a TikTok share and a Facebook share', () {
      expect(parseSharedText('https://youtu.be/dQw4w9WgXcQ?si=abc').url, 'https://youtu.be/dQw4w9WgXcQ?si=abc');
      expect(parseSharedText('  https://vm.tiktok.com/ZM123/  ').url, 'https://vm.tiktok.com/ZM123/');
      expect(parseSharedText('Watch on Facebook:\nhttps://fb.watch/abc/').url, 'https://fb.watch/abc/');
    });

    test('sentence punctuation after the link is not part of it', () {
      expect(parseSharedText('Look: https://example.com/video.mp4.').url, 'https://example.com/video.mp4');
      expect(parseSharedText('(see https://example.com/a)').url, 'https://example.com/a');
      expect(
        parseSharedText('https://en.wikipedia.org/wiki/Foo_(bar)').url,
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
    });

    test('skips an http link for a later https one', () {
      expect(parseSharedText('http://a.com/x then https://b.com/y').url, 'https://b.com/y');
    });

    test('text without a link is refused with a friendly note', () {
      final o = parseSharedText('just some words');
      expect(o.isAccepted, isFalse);
      expect(o.message, SharedLinkMessages.noLink);
      expect(parseSharedText('   ').message, SharedLinkMessages.noLink);
    });

    test('http only is refused', () {
      expect(parseSharedText('http://example.com/video.mp4').message, SharedLinkMessages.notSecure);
    });

    test('private, loopback and odd links are refused (UrlPolicy)', () {
      for (final bad in [
        'https://192.168.1.10/a.mp4',
        'https://127.0.0.1/a',
        'https://localhost/a',
        'https://10.0.0.2/a',
        'https://user:pw@example.com/a',
        'https://example.com:8443/a',
        'https://0x7f.1/a',
      ]) {
        expect(parseSharedText('look $bad').message, SharedLinkMessages.blocked, reason: bad);
      }
    });

    test('other schemes never count as links', () {
      expect(parseSharedText('intent://scan/#Intent;scheme=zxing;end').message, SharedLinkMessages.noLink);
      expect(parseSharedText('file:///sdcard/a.mp4').message, SharedLinkMessages.noLink);
      expect(parseSharedText('javascript:alert(1)').message, SharedLinkMessages.noLink);
    });
  });

  group('listenForSharedLinks', () {
    late FakeSharedTextSource source;
    late ProviderContainer container;
    late List<String> events;

    setUp(() {
      source = FakeSharedTextSource();
      events = [];
      container = ProviderContainer(overrides: [sharedTextSourceProvider.overrideWithValue(source)]);
      final wiring = Provider<int>((ref) {
        final sub = listenForSharedLinks(
          ref,
          openDownloads: () => events.add('open'),
          showMessage: (m) => events.add('msg:$m'),
        );
        ref.onDispose(sub.cancel);
        return 0;
      });
      container.read(wiring);
    });

    tearDown(() => container.dispose());

    test('a good link lands in the Downloads inbox with the lookup on', () async {
      source.controller.add('Check this https://www.instagram.com/reel/xyz/');
      await Future<void>.delayed(Duration.zero);
      expect(events, ['open']);
      final link = container.read(downloadLinkInboxProvider);
      expect(link?.url, 'https://www.instagram.com/reel/xyz/');
      expect(link?.inspect, isTrue);
    });

    test('a bad share leaves the inbox empty and only shows a note', () async {
      source.controller.add('hello there');
      source.controller.add('https://192.168.0.1/x');
      await Future<void>.delayed(Duration.zero);
      expect(events, ['msg:${SharedLinkMessages.noLink}', 'msg:${SharedLinkMessages.blocked}']);
      expect(container.read(downloadLinkInboxProvider), isNull);
    });
  });
}
