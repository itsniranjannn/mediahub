// Review fixes that live in the Android code (Kotlin cannot run in these
// tests): its source is read and the rules are checked, and the Dart side of
// the new "height" answer is run through a mocked method channel.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/personal/extractor_backend.dart';

String _kt(String name) => File('android/app/src/main/kotlin/com/example/mediahub/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PlatformInfo.resetForTests);

  group('ExtractorChannel.kt', () {
    late String src;
    setUp(() => src = _kt('personal/ExtractorChannel.kt'));

    // YouTube's "Video unavailable. This content isn't available, try again
    // later" is a rate limit: it must not be told as a removed video.
    test('a rate limit is its own code, checked before "Video unavailable"', () {
      final rate = src.indexOf('Pair("RATE_LIMITED"');
      final unavailable = src.indexOf('Pair("UNAVAILABLE"');
      expect(rate, greaterThan(0));
      expect(rate, lessThan(unavailable));
      final branch = src.substring(src.lastIndexOf('->', rate) - 300, rate);
      expect(branch, contains('has("try again later")'));
      expect(branch, contains('has("HTTP Error 429")'));
      final retrySet = RegExp(r'RETRY_WITH_OTHER_CLIENT = setOf\(([^)]*)\)').firstMatch(src)!.group(1)!;
      expect(retrySet, isNot(contains('RATE_LIMITED')), reason: 'more runs would only make it worse');
    });

    test('at most three YouTube clients at the chosen quality, then the catch-all once', () {
      expect(src, contains('private const val MAX_CLIENT_TRIES = 3'));
      expect(src, contains('variants.take(MAX_CLIENT_TRIES).map { Attempt(it, strict) }'));
    });

    test('the finished file\'s video height goes back with the result', () {
      expect(src, contains('"height" to tracks.height'));
      expect(src, contains('MediaFormat.KEY_HEIGHT'));
    });
  });

  group('OtherAudioChannel.kt', () {
    late String src;
    setUp(() => src = _kt('OtherAudioChannel.kt'));

    test('a quiet moment counts as a stop only after 10 seconds', () {
      expect(src, contains('QUIET_DELAY_MS = 10_000L'));
    });

    test('nothing is reported right at start: the first look comes after a settle time', () {
      final start = src.substring(src.indexOf('private fun start()'), src.indexOf('private fun stop()'));
      expect(start, isNot(contains('onPlayback(')), reason: "MediaHub's own player may still be listed then");
      expect(start, contains('postDelayed(settled, SETTLE_MS)'));
      expect(src, contains('if (!watching || settling) return'));
    });
  });

  group('the download answer', () {
    const channel = MethodChannel('mediahub/extractor');

    Future<ExtractorDownloadResult> download(Map<String, Object?> answer) async {
      PlatformInfo.debugIsAndroid = true;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'download' ? answer : null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return AndroidExtractorBackend().download(taskId: 'x1', url: 'https://www.youtube.com/watch?v=a', outDir: '/x');
    }

    test('carries the video height when the phone read one', () async {
      final r = await download({'filePath': '/x/x1.mp4', 'hasVideo': true, 'height': 360});
      expect(r.hasVideo, isTrue);
      expect(r.height, 360);
    });

    test('no height (sound only, an older app side, or a nonsense value): null', () async {
      expect((await download({'filePath': '/x/x1.m4a', 'hasVideo': false})).height, isNull);
      expect((await download({'filePath': '/x/x1.mp4', 'hasVideo': true, 'height': 0})).height, isNull);
      expect((await download({'filePath': '/x/x1.mp4', 'height': '720'})).height, isNull);
    });
  });
}
