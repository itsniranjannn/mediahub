import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/downloads/fast_youtube_extractor_resolver.dart';

void main() {
  test('a failed details lookup keeps the manifest (no fall-through to yt-dlp)', () async {
    final r = await FastYoutubeExtractorResolver.manifestWithDetails<String, String>(
      Future.value('manifest'),
      Future.error(StateError('details failed')),
    );
    expect(r.$1, 'manifest');
    expect(r.$2, isNull);
  });

  test('lagging details are given up after the grace, never blocking the qualities', () async {
    final sw = Stopwatch()..start();
    final r = await FastYoutubeExtractorResolver.manifestWithDetails<String, String>(
      Future.value('manifest'),
      Completer<String>().future,
      grace: const Duration(milliseconds: 50),
    );
    expect(r.$1, 'manifest');
    expect(r.$2, isNull);
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('both requests run at once: the total is the slower one, not the sum', () async {
    final sw = Stopwatch()..start();
    final r = await FastYoutubeExtractorResolver.manifestWithDetails<String, String>(
      Future.delayed(const Duration(milliseconds: 200), () => 'manifest'),
      Future.delayed(const Duration(milliseconds: 200), () => 'details'),
    );
    expect(r, ('manifest', 'details'));
    expect(sw.elapsedMilliseconds, lessThan(380));
  });

  test('a manifest error is still thrown (the caller then tries yt-dlp)', () async {
    expect(
      FastYoutubeExtractorResolver.manifestWithDetails<String, String>(Future.error(StateError('x')), Future.value('d')),
      throwsStateError,
    );
  });
}
