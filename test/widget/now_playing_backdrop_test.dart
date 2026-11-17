import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_colors.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/music_player/now_playing_sheet.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';

class _FakePlayback extends PlaybackNotifier {
  _FakePlayback(this._initial);

  final domain.PlaybackState _initial;

  @override
  domain.PlaybackState build() => _initial;

  void emit(domain.PlaybackState next) => state = next;
}

const _channel = MethodChannel('mediahub/media_store');
const _longTitle = 'Resham Firiri (Folk Song, Live at the Valley Festival)';

MediaItem _song(int n, {String? title, String? artworkPath}) => MediaItem(
      id: 'song_$n',
      uri: 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: title ?? 'Song $n',
      artist: 'Test Artist',
      durationMs: 354000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      artworkPath: artworkPath,
    );

domain.PlaybackState _playing(List<MediaItem> queue, {int index = 0}) => domain.PlaybackState(
      currentItemId: queue[index].id,
      queue: queue,
      originalQueue: queue,
      queueIndex: index,
      duration: const Duration(milliseconds: 354000),
      updatedAt: DateTime(2026),
    );

double _luminance(Color color) {
  double channel(double v) {
    final c = (v * 255.0).round().clamp(0, 255) / 255.0;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _over(Color fg, double alpha, Color bg) => Color.alphaBlend(fg.withValues(alpha: alpha), bg);

bool _isCanvas(Color c) => (c.toARGB32() & 0xFFFFFF) == (AppColors.background.toARGB32() & 0xFFFFFF);

final _scrimFinder = find.byWidgetPredicate((widget) {
  if (widget is! DecoratedBox) return false;
  final decoration = widget.decoration;
  if (decoration is! BoxDecoration) return false;
  final gradient = decoration.gradient;
  return gradient is LinearGradient && gradient.colors.every(_isCanvas);
});

final _glowFinder = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PaletteGlow');

/// Opacity of the veil at [t] (0 top, 1 bottom).
double _alphaAt(LinearGradient g, double t) {
  final stops = g.stops ?? [for (var i = 0; i < g.colors.length; i++) i / (g.colors.length - 1)];
  final x = t.clamp(0.0, 1.0);
  if (x <= stops.first) return g.colors.first.a;
  for (var i = 1; i < stops.length; i++) {
    if (x <= stops[i]) {
      final f = (x - stops[i - 1]) / (stops[i] - stops[i - 1]);
      return lerpDouble(g.colors[i - 1].a, g.colors[i].a, f)!;
    }
  }
  return g.colors.last.a;
}

/// Lightest point of the veil between [t0] and [t1].
double _minAlpha(LinearGradient g, double t0, double t1) {
  final stops = g.stops ?? const <double>[];
  var alpha = math.min(_alphaAt(g, t0), _alphaAt(g, t1));
  for (final s in stops) {
    if (s > t0 && s < t1) alpha = math.min(alpha, _alphaAt(g, s));
  }
  return alpha;
}

/// What can sit under the veil: a white cover (the worst real artwork) or
/// the strongest point of any palette glow.
List<(String, Color)> _backdrops() => [
      ('white cover', Colors.white),
      for (final g in AppColors.artworkGradients)
        (
          'glow ${g.colors.first}',
          _over(g.colors.first, ArtworkTint.backdropLightAlpha,
              _over(g.colors.last, ArtworkTint.backdropDeepAlpha, AppColors.background)),
        ),
    ];

class _Screen {
  final String name;
  final Size size;
  final double bottomInset;
  final double textScale;

  const _Screen(this.name, this.size, {this.bottomInset = 0, this.textScale = 1});
}

void main() {
  setUp(ArtworkService.instance.clearCache);
  tearDown(ArtworkService.instance.clearCache);

  Future<ProviderContainer> pumpSheet(
    WidgetTester tester,
    domain.PlaybackState state, {
    Size size = const Size(360, 776),
    double bottomInset = 48,
    double textScale = 1,
    Set<String> embeddedArt = const {},
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // Device art: a few bytes for the given uris at the list size only,
    // nothing for anything else.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      final args = call.arguments as Map;
      return embeddedArt.contains(args['uri']) && args['width'] == 256 ? <int>[1, 2, 3] : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

    final container = ProviderContainer(
      overrides: [
        playbackNotifierProvider.overrideWith(() => _FakePlayback(state)),
        throttledPositionStreamProvider
            .overrideWith((ref) => Stream.value(const Duration(seconds: 15))),
        isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.darkTheme, home: const NowPlayingSheet()),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return container;
  }

  Color lightGlow(WidgetTester tester) {
    final glows = tester
        .widgetList<AnimatedContainer>(
          find.descendant(of: _glowFinder, matching: find.byType(AnimatedContainer)),
        )
        .toList();
    expect(glows, hasLength(2));
    final gradient = (glows.last.decoration! as BoxDecoration).gradient! as RadialGradient;
    return gradient.colors.first.withValues(alpha: 1);
  }

  final neutralViolet = AppColors.artworkGradients.first.colors.first;

  group('Now Playing backdrop contrast where the text sits', () {
    const screens = [
      _Screen('360x800 phone, button navigation', Size(360, 776), bottomInset: 48),
      _Screen('360x640 phone', Size(360, 616), bottomInset: 48),
      _Screen('shortest body before it scrolls', Size(360, 560), bottomInset: 48),
      _Screen('412x915 phone, gesture navigation', Size(412, 891), bottomInset: 24),
      _Screen('tablet', Size(800, 1256), bottomInset: 24),
      _Screen('360x800 phone, text at 130 %', Size(360, 776), bottomInset: 48, textScale: 1.3),
      _Screen('landscape phone (scrolls)', Size(800, 336)),
      _Screen('short window at 130 % text (scrolls)', Size(360, 600), bottomInset: 48, textScale: 1.3),
    ];

    for (final screen in screens) {
      testWidgets(screen.name, (tester) async {
        final queue = [_song(1, title: _longTitle), for (var i = 2; i <= 8; i++) _song(i)];
        await pumpSheet(
          tester,
          _playing(queue),
          size: screen.size,
          bottomInset: screen.bottomInset,
          textScale: screen.textScale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('1 of 8'), findsOneWidget);

        final scrim = (tester.widget<DecoratedBox>(_scrimFinder).decoration as BoxDecoration).gradient!
            as LinearGradient;
        final backdrop = tester.getRect(_scrimFinder);
        final scrolls = find.byType(SingleChildScrollView).evaluate().isNotEmpty;

        final skip = {
          ...find.descendant(of: find.byType(Hero), matching: find.byType(RichText)).evaluate(),
          ...find.descendant(of: find.byTooltip('Play'), matching: find.byType(RichText)).evaluate(),
        };
        final checked = <String>{};
        final failures = <String>[];

        void check(String label, Rect rect, Color color, double required) {
          // While the body scrolls, anything can pass over any band.
          final t0 = scrolls ? 0.0 : (rect.top - backdrop.top) / backdrop.height;
          final t1 = scrolls ? 1.0 : (rect.bottom - backdrop.top) / backdrop.height;
          final alpha = _minAlpha(scrim, t0, t1);
          for (final (name, under) in _backdrops()) {
            final behind = _over(AppColors.background, alpha, under);
            final ratio = _contrast(Color.alphaBlend(color, behind), behind);
            if (ratio < required) {
              failures.add('$label on $name under a ${alpha.toStringAsFixed(2)} veil: '
                  '${ratio.toStringAsFixed(2)} < $required');
            }
          }
          checked.add(label);
        }

        for (final element in find
            .descendant(of: find.byType(NowPlayingSheet), matching: find.byType(RichText))
            .evaluate()) {
          if (skip.contains(element)) continue;
          final paragraph = element.renderObject! as RenderParagraph;
          final style = paragraph.text.style!;
          final rect = MatrixUtils.transformRect(
            paragraph.getTransformTo(null),
            Offset.zero & paragraph.size,
          );
          final isIcon = style.fontFamily == 'MaterialIcons';
          final size = style.fontSize ?? 14;
          final bold = (style.fontWeight ?? FontWeight.w400).value >= 700;
          final large = size >= 24 || (size >= 18.66 && bold);
          final text = paragraph.text.toPlainText();
          final label = isIcon ? 'icon U+${text.runes.first.toRadixString(16)}' : text;
          check(label, rect, style.color!, isIcon || large ? 3.0 : 4.5);
        }
        // The played part of the seek bar is the one part that shows state.
        check('seek bar', tester.getRect(find.byType(Slider)), AppColors.primary, 3.0);

        expect(
          checked,
          containsAll(<String>['Now Playing', '1 of 8', 'Test Artist', '0:15', '5:54', 'seek bar']),
        );
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }

    testWidgets('the regular layout keeps the header band at 82 % and opens only around the cover',
        (tester) async {
      await pumpSheet(tester, _playing([_song(1)]));
      final scrim = (tester.widget<DecoratedBox>(_scrimFinder).decoration as BoxDecoration).gradient!
          as LinearGradient;
      expect(scrim.colors.map((c) => c.a), [
        closeTo(0.82, 0.005),
        closeTo(0.82, 0.005),
        closeTo(0.6, 0.005),
        closeTo(0.9, 0.005),
        1.0,
      ]);
      expect(scrim.stops, [0.0, 0.16, 0.26, 0.72, 1.0]);
    });
  });

  group('Now Playing glow', () {
    testWidgets('a song without art glows in its own cover palette', (tester) async {
      final song = _song(3);
      await pumpSheet(tester, _playing([song]));
      expect(lightGlow(tester), ArtworkTint.light(song.uri).withValues(alpha: 1));
    });

    testWidgets('a song with a saved thumbnail glows neutral violet from the first frame',
        (tester) async {
      final song = _song(4, artworkPath: '/data/user/0/app/thumbs/4.jpg');
      expect(ArtworkTint.light(song.uri), isNot(neutralViolet), reason: 'pick a seed off violet');
      await pumpSheet(tester, _playing([song]), settle: false);
      expect(lightGlow(tester), neutralViolet);
    });

    testWidgets('a song whose embedded art is loaded glows neutral violet', (tester) async {
      // the first song whose own palette is not violet
      var n = 5;
      while (ArtworkPlaceholder.paletteIndexFor(_song(n).uri) == 0) {
        n++;
      }
      final song = _song(n);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async => <int>[1, 2, 3],
      );
      await ArtworkService.instance.getArtwork(song.uri, size: 256);
      await pumpSheet(tester, _playing([song]), embeddedArt: {song.uri});
      expect(lightGlow(tester), neutralViolet);
    });

    testWidgets('on a track change the glow keeps its colours until the cover lookup answers',
        (tester) async {
      final a = _song(6);
      final b = _song(7);
      expect(ArtworkTint.light(a.uri), isNot(ArtworkTint.light(b.uri)),
          reason: 'pick two songs on different palettes');
      final container = await pumpSheet(tester, _playing([a, b]));
      expect(lightGlow(tester), ArtworkTint.light(a.uri));

      (container.read(playbackNotifierProvider.notifier) as _FakePlayback)
          .emit(_playing([a, b], index: 1));
      await tester.pump();
      expect(find.text('Song 7'), findsOneWidget);
      expect(lightGlow(tester), ArtworkTint.light(a.uri), reason: 'no hue before the lookup');

      await tester.pumpAndSettle();
      expect(lightGlow(tester), ArtworkTint.light(b.uri));
    });
  });

  group('Now Playing backdrop swatch', () {
    test('mean luma of raw pixels', () {
      ByteData pixels(List<int> rgba) => ByteData.sublistView(Uint8List.fromList(rgba));
      expect(meanLumaOfRgba(pixels([255, 255, 255, 255])), closeTo(1.0, 1e-9));
      expect(meanLumaOfRgba(pixels([0, 0, 0, 255, 255, 255, 255, 255])), closeTo(0.5, 1e-9));
      expect(meanLumaOfRgba(pixels([0, 255, 0, 255])), closeTo(0.7152, 1e-9));
      expect(meanLumaOfRgba(pixels([])), 0);
    });

    /// A 128 px square PNG of one colour, written to a temp file.
    Future<String> coverFile(WidgetTester tester, Color color) async {
      return (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 128, 128), Paint()..color = color);
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        picture.dispose();
        image.dispose();
        final dir = Directory.systemTemp.createTempSync('np_swatch');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/cover.png')..writeAsBytesSync(png!.buffer.asUint8List());
        return file.path;
      }))!;
    }

    /// Mean luma of the swatch drawn behind the veil, once it has loaded.
    Future<double> swatchLuma(WidgetTester tester) async {
      final backdrop = find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ArtworkBackdrop'),
        matching: find.byType(RawImage),
      );
      for (var i = 0; i < 20 && backdrop.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final swatch = tester.widget<RawImage>(backdrop).image!;
      return (await tester.runAsync(() async {
        final pixels = await swatch.toByteData(format: ui.ImageByteFormat.rawRgba);
        return meanLumaOfRgba(pixels!);
      }))!;
    }

    testWidgets('a white cover is darkened to a deep tone instead of a flat grey', (tester) async {
      final path = await coverFile(tester, const Color(0xFFFBFAF6));
      await pumpSheet(tester, _playing([_song(1, artworkPath: path)]), settle: false);
      expect(await swatchLuma(tester), closeTo(0.40, 0.02));
    });

    testWidgets('a colourful cover keeps its own brightness', (tester) async {
      // Mean luma about 0.33, under the cap.
      const red = Color(0xFFC0392B);
      final path = await coverFile(tester, red);
      await pumpSheet(tester, _playing([_song(1, artworkPath: path)]), settle: false);
      final expected = (0.2126 * 0xC0 + 0.7152 * 0x39 + 0.0722 * 0x2B) / 255;
      expect(await swatchLuma(tester), closeTo(expected, 0.02));
    });
  });

  group('Now Playing layout', () {
    testWidgets('the cover lines up with the 16 dp text and seek bar edges', (tester) async {
      await pumpSheet(tester, _playing([_song(1)]));
      final cover = tester.getRect(find.byType(Hero));
      expect(cover.width, 328);
      expect(cover.height, 328);
      expect(cover.left, 16);
      expect(tester.getRect(find.text('Song 1')).left, 16);
      final slider = tester.getRect(find.byType(Slider));
      expect(slider.left, 16);
      expect(slider.right, cover.right);
    });

    testWidgets('long titles get two lines, the artist reads as body text', (tester) async {
      await pumpSheet(tester, _playing([_song(1, title: _longTitle)]));
      final title = tester.widget<Text>(find.text(_longTitle));
      expect(title.maxLines, 2);
      expect(tester.getSize(find.text(_longTitle)).height, 56, reason: 'two 28 dp lines');
      final artist = tester.widget<Text>(find.text('Test Artist'));
      expect(artist.style!.fontSize, 15);
      expect(artist.style!.color, AppColors.textSecondary);
    });

    testWidgets('seek labels use the short clock', (tester) async {
      await pumpSheet(tester, _playing([_song(1)]));
      expect(find.text('0:15'), findsOneWidget);
      expect(find.text('5:54'), findsOneWidget);
      expect(find.text('00:15'), findsNothing);
    });

    testWidgets('seek labels sit with the bar they describe, not with the play controls', (tester) async {
      await pumpSheet(tester, _playing([_song(1)]));
      final slider = tester.getRect(find.byType(Slider));
      final trackCentre = slider.center.dy;
      final label = tester.getRect(find.text('0:15'));
      final controls = tester.getRect(find.byTooltip('Previous track'));

      final gapToTrack = label.top - trackCentre;
      final gapToControls = controls.top - label.bottom;
      expect(gapToTrack, greaterThan(0), reason: 'under the track');
      expect(gapToTrack, lessThan(gapToControls), reason: 'closer to the bar than to the controls');
      expect(tester.getRect(find.text('5:54')).top, label.top);

      // Moved by paint only: the slider keeps its 48 dp touch target, and a
      // tap on a label still reaches the slider.
      expect(slider.height, 48);
      final hit = tester.hitTestOnBinding(label.center);
      expect(hit.path.any((entry) => entry.target.runtimeType.toString() == '_RenderSlider'), isTrue);
    });

    for (final title in ['Song 1', _longTitle]) {
      testWidgets('the favourite snackbar clears the heart ($title)', (tester) async {
        const size = Size(360, 776);
        const bottomInset = 48.0;
        await pumpSheet(tester, _playing([_song(1, title: title)]), size: size, bottomInset: bottomInset);
        final button = tester.widget<FavoriteFeedbackButton>(find.byType(FavoriteFeedbackButton));
        final heart = tester.getRect(find.byType(FavoriteFeedbackButton));
        // A floating snackbar sits [snackBottomMargin] above the safe bottom.
        final snackBottom = size.height - bottomInset - button.snackBottomMargin;
        expect(snackBottom, lessThanOrEqualTo(heart.top));
      });
    }
  });
}
