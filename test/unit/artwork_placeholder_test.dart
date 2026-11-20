import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/core/widgets/artwork_thumbnail.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';

double _luminance(Color color) {
  double channel(double v) {
    final c = (v * 255.0).round().clamp(0, 255) / 255.0;
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// [fg] at [alpha] painted over the opaque [bg].
Color _over(Color fg, double alpha, Color bg) => Color.alphaBlend(fg.withValues(alpha: alpha), bg);

const _palettes = {'dark': AppPalette.dark, 'light': AppPalette.light};

void main() {
  group('ArtworkPlaceholder hash and palette', () {
    test('hashOf is 32-bit FNV-1a (published test vectors)', () {
      expect(ArtworkPlaceholder.hashOf(''), 0x811C9DC5);
      expect(ArtworkPlaceholder.hashOf('a'), 0xE40C292C);
      expect(ArtworkPlaceholder.hashOf('foobar'), 0xBF9CF968);
    });

    test('the same seed always picks the same gradient', () {
      const seed = 'content://media/external/audio/media/1234';
      final first = ArtworkPlaceholder.paletteIndexFor(seed);
      for (var i = 0; i < 5; i++) {
        expect(ArtworkPlaceholder.paletteIndexFor(seed), first);
      }
      expect(
        ArtworkPlaceholder.gradientFor(seed),
        same(AppPalette.dark.artworkGradients[first]),
      );
      expect(
        ArtworkPlaceholder.gradientFor(seed, AppPalette.light),
        same(AppPalette.light.artworkGradients[first]),
      );
    });

    test('an item keeps its hue in both themes: same index and top stop, paper lifts the deep stop', () {
      for (var i = 0; i < 50; i++) {
        final seed = 'content://media/external/audio/media/$i';
        final dark = ArtworkPlaceholder.gradientFor(seed, AppPalette.dark);
        final light = ArtworkPlaceholder.gradientFor(seed, AppPalette.light);
        expect(light.colors.first, dark.colors.first);
        expect(_luminance(light.colors.last), greaterThan(_luminance(dark.colors.last)),
            reason: 'the paper deep stop is one step lighter');
        expect(ArtworkTint.light(seed, AppPalette.light), ArtworkTint.light(seed));
        expect(ArtworkTint.deep(seed, AppPalette.light), light.colors.last);
      }
    });

    test('indices stay in range and every palette gets used', () {
      final used = <int>{};
      for (var i = 0; i < 400; i++) {
        final index = ArtworkPlaceholder.paletteIndexFor('content://media/external/audio/media/$i');
        expect(index, inInclusiveRange(0, ArtworkPlaceholder.paletteCount - 1));
        used.add(index);
      }
      expect(used.length, ArtworkPlaceholder.paletteCount);
    });

    for (final MapEntry(key: name, value: palette) in _palettes.entries) {
      test('there are 8 two-stop diagonal gradients ($name)', () {
        expect(palette.artworkGradients, hasLength(8));
        expect(ArtworkPlaceholder.paletteCount, 8);
        for (final gradient in palette.artworkGradients) {
          expect(gradient.colors, hasLength(2));
          expect(gradient.begin, Alignment.topLeft);
          expect(gradient.end, Alignment.bottomRight);
          expect(
            _luminance(gradient.colors.first),
            greaterThan(_luminance(gradient.colors.last)),
            reason: 'the top-left stop is the light one',
          );
        }
      });

      test('white glyphs at 85 % read on both stops and in the middle ($name)', () {
        final glyphAlpha = ArtworkPlaceholder.glyphOpacity;
        for (final gradient in palette.artworkGradients) {
          final light = gradient.colors.first;
          final deep = gradient.colors.last;
          final middle = Color.lerp(light, deep, 0.5)!;
          for (final stop in [light, deep]) {
            expect(_contrast(_over(Colors.white, glyphAlpha, stop), stop), greaterThanOrEqualTo(3.0),
                reason: 'glyph on $stop');
          }
          expect(_contrast(_over(Colors.white, glyphAlpha, middle), middle), greaterThanOrEqualTo(4.5),
              reason: 'glyph on the middle of $gradient');
        }
      });

      test('the eighth palette is rose, and no cover passes for the success green ($name)', () {
        expect(palette.artworkGradients.last.colors.first, const Color(0xFFB0407A));
        final successHue = HSVColor.fromColor(palette.success).hue;
        for (final gradient in palette.artworkGradients) {
          final hue = HSVColor.fromColor(gradient.colors.first).hue;
          final distance = (hue - successHue).abs();
          expect(min(distance, 360 - distance), greaterThan(15),
              reason: '${gradient.colors.first} looks like the success green');
        }
      });
    }

    testWidgets('the placeholder paints the gradient of the theme it sits in', (tester) async {
      const seed = 'content://media/external/audio/media/42';
      Future<LinearGradient> painted(ThemeData? theme) async {
        const cover = SizedBox.square(dimension: 64, child: ArtworkPlaceholder(seed: seed));
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: theme == null ? cover : Theme(data: theme, child: cover)),
          ),
        );
        final paint = tester.widget<CustomPaint>(
          find.descendant(of: find.byType(ArtworkPlaceholder), matching: find.byType(CustomPaint)).first,
        );
        return (paint.painter as dynamic).gradient as LinearGradient;
      }

      expect(await painted(null), ArtworkPlaceholder.gradientFor(seed), reason: 'no theme: the ink palette');
      expect(await painted(AppTheme.darkTheme), ArtworkPlaceholder.gradientFor(seed, AppPalette.dark));
      expect(await painted(AppTheme.lightTheme), ArtworkPlaceholder.gradientFor(seed, AppPalette.light));
    });
  });

  group('ArtworkTint contrast', () {
    // The Now Playing veil (now_playing_sheet.dart) is the canvas at 82 % over
    // the header band and opens up to 60 % only in the band around the cover.
    // test/widget/now_playing_backdrop_test.dart measures where each text
    // really sits on several screens; this checks the tint constants alone.
    const headerScrim = 0.82;
    const mostOpenScrim = 0.6;

    // Now Playing always renders with the ink palette, in both themes.
    const stage = AppPalette.dark;

    List<Color> glowPeaks() => [
          for (final gradient in stage.artworkGradients) ...[
            _over(gradient.colors.first, ArtworkTint.backdropLightAlpha, stage.background),
            _over(gradient.colors.last, ArtworkTint.backdropDeepAlpha, stage.background),
            _over(gradient.colors.first, ArtworkTint.backdropLightAlpha,
                _over(gradient.colors.last, ArtworkTint.backdropDeepAlpha, stage.background)),
          ],
        ];

    test('the glow peak keeps text >= 4.5:1 even where the veil opens most', () {
      for (final scrim in [headerScrim, mostOpenScrim]) {
        for (final glow in glowPeaks()) {
          final behindText = _over(stage.background, scrim, glow);
          for (final text in [stage.textPrimary, stage.textSecondary]) {
            expect(_contrast(text, behindText), greaterThanOrEqualTo(4.5),
                reason: '$text on $behindText (veil $scrim)');
          }
          expect(_contrast(stage.primary, behindText), greaterThanOrEqualTo(3.0),
              reason: 'Volt controls on $behindText (veil $scrim)');
        }
      }
    });

    test('a white cover under the header veil keeps the header text readable', () {
      final behindHeader = _over(stage.background, headerScrim, Colors.white);
      expect(_contrast(stage.textPrimary, behindHeader), greaterThanOrEqualTo(4.5));
      expect(_contrast(stage.textSecondary, behindHeader), greaterThanOrEqualTo(4.5));
      expect(_contrast(stage.primary, behindHeader), greaterThanOrEqualTo(3.0));
    });

    for (final MapEntry(key: name, value: palette) in _palettes.entries) {
      test('tinted hero surfaces keep label, title and metadata text >= 4.5:1 ($name)', () {
        for (var i = 0; i < ArtworkPlaceholder.paletteCount; i++) {
          // Find a seed for every palette.
          var n = 0;
          while (ArtworkPlaceholder.paletteIndexFor('seed$n') != i) {
            n++;
          }
          final gradient = ArtworkTint.surfaceGradient('seed$n', palette);
          expect(gradient.colors.last, palette.background);
          for (final stop in gradient.colors) {
            for (final text in [palette.primary, palette.textPrimary, palette.textSecondary]) {
              expect(_contrast(text, stop), greaterThanOrEqualTo(4.5), reason: '$text on $stop');
            }
          }
        }
      });
    }

    test('the surface recipe: ink melts the deep stop, paper washes the top stop', () {
      const seed = 'seed1';
      final dark = ArtworkTint.surfaceGradient(seed);
      final deep = ArtworkTint.deep(seed);
      expect(dark.colors[0], Color.lerp(deep, AppPalette.dark.background, 0.30));
      expect(dark.colors[1], Color.lerp(deep, AppPalette.dark.background, 0.68));
      expect(ArtworkTint.surfaceGradient(seed, AppPalette.dark), dark);

      final light = ArtworkTint.surfaceGradient(seed, AppPalette.light);
      final top = ArtworkTint.light(seed, AppPalette.light);
      expect(light.colors[0], Color.lerp(top, AppPalette.light.background, 0.85));
      expect(light.colors[1], Color.lerp(top, AppPalette.light.background, 0.93));
      expect(light.colors[2], AppPalette.light.background);
    });
  });

  group('ArtworkPlaceholder layout', () {
    Future<Size> glyphSlot(WidgetTester tester, Size box) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: box,
              child: const ArtworkPlaceholder(seed: 'x', icon: Icons.music_note_rounded),
            ),
          ),
        ),
      );
      final icon = find.byIcon(Icons.music_note_rounded);
      expect(icon, findsOneWidget);
      return tester.getSize(find.ancestor(of: icon, matching: find.byType(FittedBox)));
    }

    testWidgets('fills its box and sizes the glyph from the shortest side', (tester) async {
      expect(await glyphSlot(tester, const Size(100, 100)), const Size(40, 40));
      // Wide stills get about 30 % so the glyph does not dominate the frame.
      final wide = await glyphSlot(tester, const Size(320, 180));
      expect(wide.width, closeTo(54, 0.01));
      expect(wide.height, closeTo(54, 0.01));
      expect(await glyphSlot(tester, const Size(24, 24)), const Size(14, 14));
      expect(await glyphSlot(tester, const Size(400, 400)), const Size(96, 96));
      expect(tester.getSize(find.byType(ArtworkPlaceholder)), const Size(400, 400));
    });

    testWidgets('rings are drawn only on covers of 96 dp and up', (tester) async {
      Future<RenderObject> cover(Size size) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox.fromSize(
                size: size,
                child: const ArtworkPlaceholder(seed: 'x'),
              ),
            ),
          ),
        );
        return tester.renderObject(find.byType(CustomPaint).first);
      }

      expect(ArtworkPlaceholder.ringMinSide, 96);
      for (final side in [44.0, 52.0, 60.0, 80.0, 95.5]) {
        expect(await cover(Size.square(side)), paintsExactlyCountTimes(#drawCircle, 0),
            reason: '$side dp cover');
      }
      // A 16:9 still is judged by its short side.
      expect(await cover(const Size(160, 90)), paintsExactlyCountTimes(#drawCircle, 0));
      for (final side in [96.0, 168.0, 328.0]) {
        expect(await cover(Size.square(side)), paintsExactlyCountTimes(#drawCircle, 2),
            reason: '$side dp cover');
      }
    });

    testWidgets('ArtworkThumbnail without art shows the placeholder at its own shape',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ArtworkThumbnail(
              uri: 'content://media/external/video/media/7',
              width: 160,
              height: 90,
              placeholderIcon: Icons.movie_outlined,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(ArtworkThumbnail)), const Size(160, 90));
      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      final placeholder = tester.widget<ArtworkPlaceholder>(find.byType(ArtworkPlaceholder));
      expect(placeholder.seed, 'content://media/external/video/media/7');
    });
  });

  group('ArtworkThumbnail fade-in', () {
    const channel = MethodChannel('mediahub/media_store');
    // A valid 1x1 PNG, returned as the device's art for every uri.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );

    setUp(ArtworkService.instance.clearCache);
    tearDown(ArtworkService.instance.clearCache);

    Future<void> pumpThumbnail(WidgetTester tester, String uri, {bool reduceMotion = false}) async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => png.toList());
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: ArtworkThumbnail(uri: uri, size: 56)),
          ),
        ),
      );
      // The lookup answers; the bytes are then decoded off the fake clock.
      await tester.pump();
      expect(find.byType(ArtworkPlaceholder), findsOneWidget, reason: 'shown while decoding');
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
        final raw = find.byType(RawImage);
        if (raw.evaluate().isNotEmpty && tester.widget<RawImage>(raw).image != null) return;
      }
      fail('the cover never decoded');
    }

    testWidgets('the placeholder stops painting once the cover has faded in', (tester) async {
      await pumpThumbnail(tester, 'content://media/external/audio/media/fade');
      // Mid-fade the placeholder still shows through.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ArtworkPlaceholder), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkPlaceholder), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('with reduced motion the placeholder goes as soon as the cover is there',
        (tester) async {
      await pumpThumbnail(tester, 'content://media/external/audio/media/still', reduceMotion: true);
      expect(find.byType(ArtworkPlaceholder), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
    });
  });
}
