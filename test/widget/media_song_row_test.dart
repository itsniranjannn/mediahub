import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_spacing.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/widgets/artwork_thumbnail.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/downloads/download_quality.dart';
import 'package:mediahub/features/library/media_song_row.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';

import '../helpers/app_fonts.dart';

const _longTitle = 'Resham Firiri (Folk Song, Live at the Valley Festival 2026)';
const _longArtist = 'The Kathmandu Valley Folk Ensemble and Friends';

MediaItem _song({
  String id = 'song_1',
  String title = 'Resham Firiri',
  String? artist = 'Bipana Thapa',
  int durationMs = 245000,
  String source = 'device',
  MediaAvailability availability = MediaAvailability.available,
}) =>
    MediaItem(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      mediaType: MediaType.audio,
      title: title,
      artist: artist,
      durationMs: durationMs,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      source: source,
      availability: availability,
    );

Future<void> _pumpRows(
  WidgetTester tester,
  List<MediaItem> items, {
  double width = 360,
  double textScale = 1.0,
  MediaItem? playing,
  bool showArtwork = true,
  bool numbered = false,
  ThemeData? theme,
  Set<String> favorites = const {},
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMediaItemProvider.overrideWith((ref) => playing),
        isFavoriteProvider.overrideWith((ref, id) => Stream.value(favorites.contains(id))),
        downloadQualityProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              for (final (i, item) in items.indexed)
                MediaSongRow(item: item, showArtwork: showArtwork, index: numbered ? i + 1 : null),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _inRow(MediaItem item, Finder matching) =>
    find.descendant(of: find.byWidgetPredicate((w) => w is MediaSongRow && w.item.id == item.id), matching: matching);

/// The paragraph shows all of its text: not ellipsized, not clipped.
void _expectFullyShown(WidgetTester tester, Finder text) {
  // A Text with a semanticsLabel wraps its RichText in Semantics.
  final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
    of: text,
    matching: find.byType(RichText),
    matchRoot: true,
  ));
  expect(paragraph.didExceedMaxLines, isFalse, reason: '"${paragraph.text.toPlainText()}" is cut');
  expect(paragraph.size.width, greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity) - 0.01),
      reason: '"${paragraph.text.toPlainText()}" is narrower than its text');
}

void main() {
  // The bundled fonts, so text widths match the phone.
  setUpAll(loadAppFonts);

  testWidgets('the length ends the meta line and the title gets the freed width', (tester) async {
    final song = _song(title: _longTitle);
    await _pumpRows(tester, [song]);

    final clock = find.text(' · 4:05');
    expect(clock, findsOneWidget, reason: 'formatClock: no leading zero, after the artist');
    expect(find.text('4:05'), findsNothing, reason: 'no standalone duration column any more');
    _expectFullyShown(tester, clock);

    final title = tester.getRect(find.text(_longTitle));
    final artist = tester.getRect(find.text('Bipana Thapa'));
    final clockRect = tester.getRect(clock);
    expect(clockRect.top, greaterThanOrEqualTo(title.bottom), reason: 'on the meta line, under the title');
    expect(clockRect.left, moreOrLessEquals(artist.right, epsilon: 0.5),
        reason: 'reads "Bipana Thapa · 4:05", not a dot floating at the far end');
    expect(clockRect.right, lessThanOrEqualTo(tester.getRect(find.byType(FavoriteFeedbackButton)).left));

    // 360 - 16 - 48 art - 12 - 4 - 48 heart - 48 more - 4 = 180 dp.
    expect(title.width, greaterThanOrEqualTo(178));
    expect(tester.renderObject<RenderParagraph>(find.text(_longTitle)).didExceedMaxLines, isTrue,
        reason: 'a long title still ellipsizes on one line');
  });

  testWidgets('rows stay 64 dp with the art on the 16 dp gutter, playing or not', (tester) async {
    final song = _song();
    final other = _song(id: 'song_2', title: 'Sunrise Over Phewa');
    await _pumpRows(tester, [song, other], playing: song);

    for (final item in [song, other]) {
      final row = tester.getRect(find.byWidgetPredicate((w) => w is MediaSongRow && w.item.id == item.id));
      expect(row.height, 64);
      expect(tester.getRect(_inRow(item, find.byType(ArtworkThumbnail))).left, AppSpacing.lg16);
      expect(tester.getSize(_inRow(item, find.byType(ArtworkThumbnail))), const Size.square(48));
      expect(tester.widget<ArtworkThumbnail>(_inRow(item, find.byType(ArtworkThumbnail))).borderRadius,
          AppSpacing.radiusArtSmall);
    }
  });

  /// The 3 dp now-playing bar on a row's leading edge.
  Finder playingBar(MediaItem item, Color color) => _inRow(
        item,
        find.byWidgetPredicate((w) =>
            w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color),
      );

  testWidgets('the playing row has a 3 dp primary bar on its edge and a primary title, never colour alone',
      (tester) async {
    final song = _song();
    final other = _song(id: 'song_2', title: 'Sunrise Over Phewa');
    await _pumpRows(tester, [song, other], playing: song);

    final bar = playingBar(song, AppPalette.dark.primary);
    expect(bar, findsOneWidget);
    final barRect = tester.getRect(bar);
    final row = tester.getRect(find.byWidgetPredicate((w) => w is MediaSongRow && w.item.id == song.id));
    expect(barRect.width, MediaSongRow.playingBarWidth);
    expect(barRect.left, row.left, reason: 'on the leading edge');
    expect(barRect.top - row.top, MediaSongRow.playingBarInset);
    expect(row.bottom - barRect.bottom, MediaSongRow.playingBarInset);
    expect(playingBar(other, AppPalette.dark.primary), findsNothing);

    expect(tester.widget<Text>(_inRow(song, find.text('Resham Firiri'))).style?.color, AppPalette.dark.primary);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget, reason: 'the equaliser over the art');
    // Screen readers hear "now playing" as the row's selected state; the
    // glyph's own label is no longer read on top of it.
    expect(find.semantics.byLabel(RegExp('^Song: Resham Firiri ')), isSemantics(isSelected: true));
    expect(find.semantics.byLabel(RegExp('^Song: Sunrise Over Phewa ')), isSemantics(isSelected: false),
        reason: 'only the playing row');
    expect(find.bySemanticsLabel(RegExp('Now playing')), findsNothing);
  });

  testWidgets('nothing overflows or cuts the length at 320 dp and 1.3x text', (tester) async {
    final items = [
      _song(id: 'plain', title: _longTitle, artist: _longArtist),
      _song(id: 'download', title: _longTitle, artist: _longArtist, source: 'download'),
      _song(id: 'missing', title: _longTitle, artist: _longArtist, availability: MediaAvailability.missing),
      _song(id: 'hour', title: _longTitle, artist: _longArtist, durationMs: 3723000),
      _song(id: 'hour_dl', title: _longTitle, artist: _longArtist, durationMs: 3723000, source: 'download'),
    ];
    for (final showArtwork in [true, false]) {
      await _pumpRows(tester, items, width: 320, textScale: 1.3, showArtwork: showArtwork);
      expect(tester.takeException(), isNull);

      for (final item in items) {
        final clock = item.durationMs > 3600000 ? ' · 1:02:03' : ' · 4:05';
        _expectFullyShown(tester, _inRow(item, find.text(clock)));
        if (item.availability == MediaAvailability.available) {
          // An ellipsized artist is only as wide as what it shows, so the
          // clock follows the "…" with no gap.
          final artist = tester.renderObject<RenderParagraph>(_inRow(item, find.text(_longArtist)));
          expect(artist.didExceedMaxLines, isTrue);
          expect(artist.textWidthBasis, TextWidthBasis.longestLine);
          expect(tester.getRect(_inRow(item, find.text(clock))).left,
              moreOrLessEquals(tester.getRect(_inRow(item, find.text(_longArtist))).right, epsilon: 0.5));
        }
        expect(tester.renderObject<RenderParagraph>(_inRow(item, find.text(_longTitle))).didExceedMaxLines, isTrue);
      }
      // Heart and "more" keep 48 dp targets.
      for (final size in [
        ...find.byType(FavoriteFeedbackButton).evaluate().map((e) => e.size!),
        ...find.byTooltip('More actions').evaluate().map((e) => e.size!),
      ]) {
        expect(size.width, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
        expect(size.height, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
      }
    }
  });

  testWidgets('a small row gives the heart button room to the artist and marks a favourite instead',
      (tester) async {
    final fav = _song(id: 'fav', artist: 'Himal Sessions');
    final plain = _song(id: 'plain', artist: 'Himal Sessions');

    // Roomy (360 dp, 1.0x): the 48 dp heart button on every row.
    await _pumpRows(tester, [fav, plain], favorites: {'fav'});
    await tester.pump();
    expect(find.byType(FavoriteFeedbackButton), findsNWidgets(2));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget, reason: 'the filled heart button');

    for (final (width, scale) in [(320.0, 1.0), (360.0, 1.3)]) {
      await _pumpRows(tester, [fav, plain], width: width, textScale: scale, favorites: {'fav'});
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(FavoriteFeedbackButton), findsNothing, reason: '$width dp at ${scale}x');
      // A 16 dp Flare heart before the favourite's meta line, read as part of the row.
      final mark = tester.widget<Icon>(_inRow(fav, find.byIcon(Icons.favorite_rounded)));
      expect(mark.color, AppPalette.dark.favorite);
      expect(mark.size, closeTo(16 * scale, 0.01));
      expect(_inRow(plain, find.byIcon(Icons.favorite_rounded)), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Song: Resham Firiri by Himal Sessions, 4:05, Favorite$')), findsOneWidget);
      // The artist shows in full where the heart used to take its room.
      _expectFullyShown(tester, _inRow(plain, find.text('Himal Sessions')));
      expect(find.byTooltip('More actions'), findsNWidgets(2), reason: 'the ⋮ stays');
    }
  });

  testWidgets('even at 2x text on 320 dp an hour-long download does not overflow', (tester) async {
    await _pumpRows(
      tester,
      [_song(title: _longTitle, artist: _longArtist, durationMs: 3723000, source: 'download')],
      width: 320,
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Downloaded" keeps its word on a wide row and its icon on a narrow one', (tester) async {
    final song = _song(source: 'download', durationMs: 180000);

    await _pumpRows(tester, [song], width: 480);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text(' · 3:00'), findsOneWidget);

    await _pumpRows(tester, [song], width: 320);
    expect(find.text('Downloaded'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Downloaded')), findsOneWidget, reason: 'the icon still says it');
    expect(find.text(' · 3:00'), findsOneWidget);
  });

  testWidgets('a missing file reads "Missing · artist" and an unknown length shows no clock', (tester) async {
    final missing = _song(availability: MediaAvailability.missing, durationMs: 0);
    await _pumpRows(tester, [missing]);

    final meta = tester.widget<Text>(find.byWidgetPredicate(
      (w) => w is Text && w.textSpan != null && w.textSpan!.toPlainText() == 'Missing · Bipana Thapa',
    ));
    expect(meta.maxLines, 1);
    expect(find.textContaining('--:--'), findsNothing);
    expect(find.textContaining(' · 0:00'), findsNothing);
  });

  // Semantics is on by default in testWidgets; the row merges its texts
  // into one node, so labels are matched by pattern.
  testWidgets('screen readers get the same row label and the clock without the dot', (tester) async {
    await _pumpRows(tester, [_song()]);

    expect(find.bySemanticsLabel(RegExp(r'Song: Resham Firiri by Bipana Thapa')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('4:05')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('·')), findsNothing);
  });

  testWidgets('the now-playing glyph sits on the full overlay veil, readable over a white cover', (tester) async {
    final song = _song();
    await _pumpRows(tester, [song], playing: song);

    final veil = tester.widget<DecoratedBox>(find.ancestor(
      of: find.byIcon(Icons.graphic_eq_rounded),
      matching: find.byType(DecoratedBox),
    ).first);
    expect((veil.decoration as BoxDecoration).color, AppPalette.dark.overlay);

    // Volt on the veil over pure white, the worst real cover: >= 3:1.
    final behind = Color.alphaBlend(AppPalette.dark.overlay, Colors.white);
    final glyph = tester.widget<Icon>(find.byIcon(Icons.graphic_eq_rounded));
    expect(glyph.color, AppPalette.dark.primary);
    expect(_contrast(glyph.color!, behind), greaterThanOrEqualTo(3.0));
    expect(glyph.semanticLabel, 'Now playing');
  });

  testWidgets('on paper the bar and title are Ultraviolet; the veil glyph stays Volt on ink', (tester) async {
    final song = _song();
    await _pumpRows(tester, [song], playing: song, theme: AppTheme.lightTheme);

    expect(playingBar(song, AppPalette.light.primary), findsOneWidget);
    expect(tester.widget<Text>(find.text('Resham Firiri')).style?.color, AppPalette.light.primary);
    final glyph = tester.widget<Icon>(find.byIcon(Icons.graphic_eq_rounded));
    expect(glyph.color, AppPalette.dark.primary, reason: 'the veil is ink in both themes');
    expect(tester.widget<Icon>(find.byIcon(Icons.more_vert_rounded)).color ?? AppPalette.light.textSecondary,
        AppPalette.light.textSecondary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album and playlist lists show "01" track numbers in DM Mono, the equaliser on the playing one',
      (tester) async {
    final song = _song();
    final other = _song(id: 'song_2', title: 'Sunrise Over Phewa');
    await _pumpRows(tester, [song, other], playing: other, numbered: true);

    expect(find.byType(ArtworkThumbnail), findsNothing);
    final number = tester.widget<Text>(find.text('01'));
    expect(number.style?.fontFamily, 'DMMono');
    expect(number.style?.color, AppPalette.dark.textMuted);
    expect(find.text('02'), findsNothing, reason: 'the playing row shows the equaliser instead');
    expect(_inRow(other, find.byIcon(Icons.graphic_eq_rounded)), findsOneWidget);
    expect(tester.getRect(find.text('01')).center.dx, closeTo(AppSpacing.lg16 + MediaSongRow.indexWidth / 2, 0.5));
    for (final item in [song, other]) {
      expect(tester.getSize(find.byWidgetPredicate((w) => w is MediaSongRow && w.item.id == item.id)).height, 64);
    }
  });

  testWidgets('the length is DM Mono at the meta line size', (tester) async {
    await _pumpRows(tester, [_song()]);
    final clock = tester.widget<Text>(find.text(' · 4:05'));
    final span = clock.textSpan! as TextSpan;
    final figures = span.children!.last as TextSpan;
    expect(figures.text, '4:05');
    expect(figures.style?.fontFamily, 'DMMono');
    expect(figures.style?.fontSize, 14);
    expect(figures.style?.color, AppPalette.dark.textMuted);
  });

  testWidgets('"Downloaded" is Ice at regular weight with a 16 dp glyph, not the primary of "now playing"', (tester) async {
    await _pumpRows(tester, [_song(source: 'download')], width: 480);

    final label = tester.widget<Text>(find.text('Downloaded'));
    expect(label.style?.color, AppPalette.dark.accent);
    expect(label.style?.fontWeight, isNot(FontWeight.w600));
    final marker = tester.widget<Icon>(find.byIcon(Icons.download_done_rounded));
    expect(marker.color, AppPalette.dark.accent);
    expect(marker.size, 16);
    expect(_contrast(AppPalette.dark.accent, AppPalette.dark.background), greaterThanOrEqualTo(4.5));
  });

  testWidgets('a missing download keeps its marker muted', (tester) async {
    await _pumpRows(
      tester,
      [_song(source: 'download', availability: MediaAvailability.missing)],
      width: 480,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.download_done_rounded)).color, AppPalette.dark.textMuted);
  });

  group('title lines', () {
    final song = _song(title: _longTitle);

    testWidgets('one line at default text on a 360 dp phone (rows stay 64 dp)', (tester) async {
      await _pumpRows(tester, [song]);
      expect(tester.widget<Text>(find.text(_longTitle)).maxLines, 1);
      expect(tester.getSize(find.byType(MediaSongRow)).height, 64);
    });

    for (final (name, width, scale) in [('1.3x text', 360.0, 1.3), ('a 320 dp phone', 320.0, 1.0)]) {
      testWidgets('two lines at $name, and the row grows instead of overflowing', (tester) async {
        await _pumpRows(tester, [song, _song(id: 'short', title: 'Resham')], width: width, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(tester.widget<Text>(find.text(_longTitle)).maxLines, 2);

        final title = tester.renderObject<RenderParagraph>(find.text(_longTitle));
        expect(title.size.height, greaterThan(tester.getSize(find.text('Resham')).height * 1.5),
            reason: 'the long title wraps onto a second line');
        final row = tester.getRect(_inRow(song, find.byType(Row)).first);
        expect(tester.getRect(find.text(_longTitle)).top, greaterThanOrEqualTo(row.top));
        expect(tester.getRect(_inRow(song, find.text(' · 4:05'))).bottom, lessThanOrEqualTo(row.bottom + 0.01));
      });
    }
  });
}

double _luminance(Color color) {
  double channel(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
