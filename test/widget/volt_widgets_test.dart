// The Volt widgets and the rest of the Bijuli kit in both themes: Volt fills
// on paper always draw the 1.5 dp ink edge (docs/DESIGN.md 0.6 and 10), the
// kit reads context.palette, and the Ink Dock stays ink in the light theme.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_spacing.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/utils/formatters.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

import '../helpers/app_fonts.dart';

const _ink = Color(0xFF121214);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double width = 360,
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

/// The fill decoration a VoltButton paints (its background builder).
ShapeDecoration _buttonFill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(of: find.byType(VoltButton), matching: find.byType(DecoratedBox))
        .first,
  );
  return box.decoration as ShapeDecoration;
}

BorderSide _shapeSide(ShapeBorder shape) => switch (shape) {
      StadiumBorder(:final side) => side,
      CircleBorder(:final side) => side,
      RoundedRectangleBorder(:final side) => side,
      _ => throw StateError('unexpected shape $shape'),
    };

/// The Material a VoltDisc's IconButton draws.
Material _discMaterial(WidgetTester tester) => tester.widget<Material>(
      find.descendant(of: find.byType(VoltDisc), matching: find.byType(Material)).first,
    );

ShapeDecoration _slabFill(WidgetTester tester) {
  final ink = tester.widget<Ink>(find.descendant(of: find.byType(VoltSlab), matching: find.byType(Ink)));
  return ink.decoration! as ShapeDecoration;
}

void main() {
  setUpAll(loadAppFonts);

  group('the ink edge on paper', () {
    testWidgets('VoltButton, VoltDisc and VoltSlab paint a 1.5 dp #121214 border in light', (tester) async {
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VoltButton(label: 'Play all', icon: Icons.play_arrow_rounded, onPressed: () {}),
            VoltDisc(icon: Icons.play_arrow_rounded, onPressed: () {}, semanticLabel: 'Play'),
            SizedBox(width: 328, child: VoltSlab(title: 'Resham Firiri', subtitle: 'Himal Sessions', onPlay: () {})),
          ],
        ),
      );

      final button = _shapeSide(_buttonFill(tester).shape);
      expect(button.color, _ink);
      expect(button.width, 1.5);

      final disc = _shapeSide(_discMaterial(tester).shape!);
      expect(disc.color, _ink);
      expect(disc.width, 1.5);

      final slab = _shapeSide(_slabFill(tester).shape);
      expect(slab.color, _ink);
      expect(slab.width, 1.5);
      expect(_slabFill(tester).gradient, AppPalette.light.primaryGradient);
    });

    testWidgets('on ink the same widgets draw no edge', (tester) async {
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VoltButton(label: 'Play all', onPressed: () {}),
            VoltDisc(icon: Icons.play_arrow_rounded, onPressed: () {}),
            SizedBox(width: 328, child: VoltSlab(title: 'Resham Firiri', onPlay: () {})),
          ],
        ),
        theme: AppTheme.darkTheme,
      );
      expect(_shapeSide(_buttonFill(tester).shape), BorderSide.none);
      expect(_shapeSide(_discMaterial(tester).shape!), BorderSide.none);
      expect(_shapeSide(_slabFill(tester).shape), BorderSide.none);
      expect(_buttonFill(tester).gradient, AppPalette.dark.primaryGradient);
    });

    testWidgets('a selected chip in light wears the ink side and the Volt fill', (tester) async {
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChip(label: const Text('Folk'), selected: true, onSelected: (_) {}),
            FilterChip(label: const Text('Pop'), selected: false, onSelected: (_) {}),
          ],
        ),
      );
      ShapeBorder shapeOf(String label) {
        final material = tester.widget<Material>(
          find.descendant(of: find.widgetWithText(FilterChip, label), matching: find.byType(Material)).first,
        );
        return material.shape!;
      }

      final selected = _shapeSide(shapeOf('Folk'));
      expect(selected.color, _ink);
      expect(selected.width, 1.5);
      expect(_shapeSide(shapeOf('Pop')).color, AppPalette.light.outline);
      // The check mark keeps state from depending on colour alone.
      expect(find.descendant(of: find.widgetWithText(FilterChip, 'Folk'), matching: find.byType(CustomPaint)),
          findsWidgets);
      final label = tester.widget<RichText>(
        find.descendant(of: find.widgetWithText(FilterChip, 'Folk'), matching: find.byType(RichText)).first,
      );
      expect(label.text.style!.color, AppPalette.light.onVoltFill);
    });
  });

  group('VoltButton', () {
    testWidgets('52 dp, or 40 dp compact inside a 48 dp target, with an ink label', (tester) async {
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VoltButton(key: const Key('big'), label: 'Download', icon: Icons.download_rounded, onPressed: () {}),
            VoltButton.compact(key: const Key('small'), label: 'Download', icon: Icons.download_rounded, onPressed: () {}),
          ],
        ),
      );
      final big = tester.getSize(find.descendant(of: find.byKey(const Key('big')), matching: find.byType(Material)).first);
      expect(big.height, VoltButton.height);
      final small = tester.getSize(find.descendant(of: find.byKey(const Key('small')), matching: find.byType(Material)).first);
      expect(small.height, VoltButton.compactHeight);
      expect(tester.getSize(find.byKey(const Key('small'))).height, greaterThanOrEqualTo(AppSpacing.minTouchTarget));

      final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('big')), matching: find.byType(Icon)));
      final iconTheme = IconTheme.of(tester.element(find.descendant(of: find.byKey(const Key('big')), matching: find.byType(Icon))));
      expect(icon.icon, Icons.download_rounded);
      expect(iconTheme.size, VoltButton.iconSize);
      expect(iconTheme.color, AppPalette.light.onVoltFill);
      final text = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.descendant(of: find.byKey(const Key('big')), matching: find.text('Download')),
          matching: find.byType(RichText),
        ),
      );
      expect(text.text.style!.color, AppPalette.light.onVoltFill);
      expect(text.text.style!.fontFamily, 'AtkinsonNext');
    });

    testWidgets('pressed: the pressed Volt and a 0.97 scale; released: the sheen again', (tester) async {
      var taps = 0;
      await _pump(tester, VoltButton(label: 'Play all', onPressed: () => taps++), theme: AppTheme.darkTheme);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(VoltButton)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_buttonFill(tester).color, AppPalette.dark.voltPressed);
      expect(_buttonFill(tester).gradient, isNull);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.97);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(_buttonFill(tester).gradient, AppPalette.dark.primaryGradient);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('disabled: surfacePressed with a muted label, an outline edge on paper', (tester) async {
      await _pump(tester, const VoltButton(label: 'Download', onPressed: null));
      final fill = _buttonFill(tester);
      expect(fill.color, AppPalette.light.surfacePressed);
      expect(fill.gradient, isNull);
      expect(_shapeSide(fill.shape).color, AppPalette.light.outline);
      final text = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(VoltButton), matching: find.byType(RichText)),
      );
      expect(text.text.style!.color, AppPalette.light.textMuted);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
    });

    testWidgets('expand fills the width; long labels ellipsize at 1.3x on a 320 dp phone', (tester) async {
      await _pump(
        tester,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: VoltButton(
            label: 'Download this video and keep it on the phone',
            icon: Icons.download_rounded,
            onPressed: _noop,
            expand: true,
          ),
        ),
        width: 320,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(VoltButton)).width, 288);
    });
  });

  group('VoltDisc', () {
    testWidgets('44 / 56 / 72 dp with 24 / 28 / 36 glyphs; the glow only under 72 on ink', (tester) async {
      for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        // A fresh tree, so the theme does not animate over from the last one.
        await tester.pumpWidget(const SizedBox());
        await _pump(
          tester,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final size in [VoltDisc.small, VoltDisc.medium, VoltDisc.large])
                VoltDisc(key: ValueKey(size), icon: Icons.play_arrow_rounded, size: size, onPressed: () {}),
            ],
          ),
          theme: theme,
        );
        for (final (size, glyph) in [(44.0, 24.0), (56.0, 28.0), (72.0, 36.0)]) {
          final material = find.descendant(of: find.byKey(ValueKey(size)), matching: find.byType(Material)).first;
          expect(tester.getSize(material), Size.square(size));
          expect(tester.getSize(find.byKey(ValueKey(size))).height, greaterThanOrEqualTo(48));
          final iconElement = tester.element(find.descendant(of: find.byKey(ValueKey(size)), matching: find.byType(Icon)));
          expect(IconTheme.of(iconElement).size, glyph);
          expect(_discMaterialOf(tester, size).color, theme.extension<AppPalette>()!.voltFill);
        }
        final glows = find.descendant(
          of: find.byKey(const ValueKey(72.0)),
          matching: find.byWidgetPredicate(
            (w) => w is DecoratedBox && (w.decoration as BoxDecoration?)?.boxShadow != null,
          ),
        );
        final isDark = theme.brightness == Brightness.dark;
        expect(glows, isDark ? findsOneWidget : findsNothing);
        if (isDark) {
          final shadow = (tester.widget<DecoratedBox>(glows).decoration as BoxDecoration).boxShadow!.single;
          expect(shadow.color, AppPalette.dark.voltGlow);
          expect(shadow.blurRadius, 24);
        }
        for (final size in [44.0, 56.0]) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey(size)),
              matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration),
            ),
            findsNothing,
          );
        }
      }
    });

    testWidgets('reads its label and taps', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(tester, VoltDisc(icon: Icons.pause_rounded, semanticLabel: 'Pause', onPressed: () => taps++));
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      await tester.tap(find.byType(VoltDisc));
      expect(taps, 1);
      handle.dispose();
    });
  });

  group('VoltSlab', () {
    testWidgets('kicker, file-style title, subtitle, play disc and progress in ink', (tester) async {
      final handle = tester.ensureSemantics();
      var played = 0;
      var opened = 0;
      var sheets = 0;
      await _pump(
        tester,
        SizedBox(
          width: 328,
          child: VoltSlab(
            title: 'Audit_Long_Tone_5min',
            subtitle: 'Family Recordings · 2:41 left',
            progress: 0.4,
            onPlay: () => played++,
            onTap: () => opened++,
            onLongPress: () => sheets++,
          ),
        ),
      );
      final palette = AppPalette.light;
      final kicker = tester.widget<Text>(find.text('CONTINUE LISTENING'));
      expect(kicker.style!.color, palette.onVoltMuted);
      expect(kicker.style!.fontFamily, 'DMMono');
      final title = tester.widget<Text>(find.text(breakableTitle('Audit_Long_Tone_5min')));
      expect(title.semanticsLabel, 'Audit_Long_Tone_5min');
      expect(title.style!.color, palette.onVoltFill);
      expect(title.style!.fontFamily, 'AnekWide');
      expect(title.maxLines, 1);
      expect(tester.widget<Text>(find.text('Family Recordings · 2:41 left')).style!.color, palette.onVoltMuted);

      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, 0.4);
      expect(bar.color, palette.onVoltFill);
      expect(bar.backgroundColor, palette.onVoltFill.withValues(alpha: 0.2));
      final slabRect = tester.getRect(find.byType(VoltSlab));
      final barRect = tester.getRect(find.byType(LinearProgressIndicator));
      expect(barRect.height, VoltSlab.progressHeight);
      // Measured inside the 1.5 dp ink edge.
      expect(slabRect.bottom - barRect.bottom, VoltSlab.progressInset + 1.5);

      final disc = tester.widget<IconButton>(find.byType(IconButton));
      expect(disc.style!.backgroundColor!.resolve({}), palette.onVoltFill);
      expect(disc.style!.foregroundColor!.resolve({}), palette.voltFill);
      expect(tester.getSize(find.byType(IconButton)), const Size.square(48));

      await tester.tap(find.byType(IconButton));
      await tester.tap(find.text('CONTINUE LISTENING'));
      await tester.longPress(find.text('CONTINUE LISTENING'));
      expect((played, opened, sheets), (1, 1, 1));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('two title lines at large text, no overflow on a 320 dp phone with Nepali', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 288,
          child: VoltSlab(title: 'रेशम फिरिरी — झिलिमिली साँझ', subtitle: 'क्षितिज पारि', onPlay: () {}),
        ),
        width: 320,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.textContaining('रेशम')).maxLines, 2);
    });
  });

  group('InkDock', () {
    testWidgets('stays ink in the light theme and asks for light system-bar icons', (tester) async {
      late AppPalette inside;
      await _pump(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: InkDock(
            miniPlayer: const SizedBox(height: InkDock.miniPlayerHeight),
            navigation: Builder(builder: (context) {
              inside = context.palette;
              return const SizedBox(height: InkDock.navigationHeight);
            }),
          ),
        ),
      );
      expect(inside, same(AppPalette.dark));
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(of: find.byType(InkDock), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)),
      );
      expect(region.value, AppTheme.barsOnInk);
      final fill = tester.widget<ColoredBox>(find.descendant(of: find.byType(InkDock), matching: find.byType(ColoredBox)));
      expect(fill.color, AppPalette.light.dock, reason: 'the dock colours are the same in both palettes');
      expect(tester.getSize(find.byType(InkDock)).height, 128);
      expect(find.descendant(of: find.byType(InkDock), matching: find.byType(BackdropFilter)), findsOneWidget);
    });

    testWidgets('content padding clears the dock and the system inset', (tester) async {
      late double withMini;
      late double withoutMini;
      await _pump(
        tester,
        Builder(builder: (context) {
          withMini = InkDock.contentBottomPadding(context);
          withoutMini = InkDock.contentBottomPadding(context, hasMiniPlayer: false);
          return const SizedBox();
        }),
      );
      expect(withMini, 64 + 64 + 16);
      expect(withoutMini, 64 + 16);
    });
  });

  group('kit pieces read the palette', () {
    testWidgets('VoltSlab: the time left follows the artist and is never the part cut', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 288,
          child: VoltSlab(
            title: 'झिलिमिली साँझ',
            subtitle: 'The Kathmandu Valley Folk Ensemble',
            meta: '2:19 left',
            progress: 0.4,
            onPlay: () {},
          ),
        ),
        width: 320,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      final artist = tester.renderObject<RenderParagraph>(find.text('The Kathmandu Valley Folk Ensemble'));
      expect(artist.didExceedMaxLines, isTrue, reason: 'the artist gives way');
      final meta = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == ' · 2:19 left'),
      );
      expect(meta.didExceedMaxLines, isFalse, reason: 'the figure is shown in full');
      TextSpan? figure;
      meta.text.visitChildren((span) {
        if (span is TextSpan && span.text == '2:19') figure = span;
        return figure == null;
      });
      expect(figure?.style?.fontFamily, 'DMMono');
      expect(find.bySemanticsLabel(RegExp(r'The Kathmandu Valley Folk Ensemble\n2:19 left')), findsOneWidget,
          reason: 'read without the dot');
    });

    testWidgets('SurfaceCard, PillTag, DurationBadge.live and SectionHeader in light', (tester) async {
      await _pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SurfaceCard(child: Text('card')),
            PillTag(text: 'VIDEO'),
            PillTag(key: Key('filled'), text: 'NEW', filled: true, color: Color(0xFF00658A), onColor: Color(0xFFFFFFFF)),
            DurationBadge.live(),
            SectionHeader(title: 'Recently played', kicker: 'From your library'),
          ],
        ),
      );
      const p = AppPalette.light;
      final card = tester.widget<Material>(
        find.descendant(of: find.byType(SurfaceCard), matching: find.byType(Material)).first,
      );
      expect(card.color, p.surface);
      expect(card.borderRadius, BorderRadius.circular(20));

      final tint = tester.widget<Container>(
        find.descendant(of: find.widgetWithText(PillTag, 'VIDEO'), matching: find.byType(Container)).first,
      );
      expect((tint.decoration! as BoxDecoration).color, p.primary.withValues(alpha: PillTag.tintAlpha));
      expect(tester.widget<Text>(find.text('VIDEO')).style!.color, p.primary);
      expect(tester.widget<Text>(find.text('VIDEO')).style!.fontFamily, 'DMMono');
      expect(tester.widget<Text>(find.text('NEW')).style!.color, const Color(0xFFFFFFFF));

      final live = tester.widget<Container>(
        find.descendant(of: find.byType(DurationBadge), matching: find.byType(Container)).first,
      );
      expect((live.decoration! as BoxDecoration).color, p.liveFill);
      expect(tester.widget<Text>(find.text('LIVE')).style!.color, p.onLive);
      expect(find.descendant(of: find.byType(DurationBadge), matching: find.byType(Row)), findsNothing,
          reason: 'no dot any more');

      final kicker = tester.widget<Text>(find.text('FROM YOUR LIBRARY'));
      expect(kicker.style!.color, p.primary);
      expect(kicker.semanticsLabel, 'From your library');
      final rule = tester.widget<Container>(
        find.descendant(of: find.byType(SectionHeader), matching: find.byType(Container)).first,
      );
      expect(rule.color, p.rule);
      expect(tester.getSize(find.descendant(of: find.byType(SectionHeader), matching: find.byType(Container)).first).height,
          SectionHeader.ruleThickness);
      expect(tester.widget<Text>(find.text('Recently played')).style!.fontFamily, 'Unbounded');
    });

    testWidgets('a kicker header with an action keeps the rule on the full gutter and the label on it', (tester) async {
      await _pump(
        tester,
        SectionHeader(title: 'Recently played', kicker: 'Now playing', actionLabel: 'See all', onAction: () {}),
      );
      final rule = find.descendant(of: find.byType(SectionHeader), matching: find.byType(Container)).first;
      expect(tester.getRect(rule).left, AppSpacing.lg16);
      expect(tester.getRect(rule).right, 360 - AppSpacing.lg16);
      expect(tester.getRect(find.text('See all')).right, moreOrLessEquals(360 - AppSpacing.lg16, epsilon: 0.5));
    });

    testWidgets('EmptyHint: primary icon on the primaryBase halo, body message in textSecondary', (tester) async {
      await _pump(
        tester,
        const EmptyHint(icon: Icons.music_note_rounded, title: 'No songs yet', message: 'Scan the phone', kicker: 'Library'),
      );
      const p = AppPalette.light;
      expect(tester.widget<Icon>(find.byIcon(Icons.music_note_rounded)).color, p.primary);
      expect(tester.widget<Text>(find.text('Scan the phone')).style!.color, p.textSecondary);
      expect(tester.widget<Text>(find.text('LIBRARY')).style!.color, p.primary);
    });

    testWidgets('GlassContainer uses the palette glass', (tester) async {
      await _pump(tester, const GlassContainer(child: SizedBox(width: 40, height: 40)));
      final box = tester.widget<Container>(find.descendant(of: find.byType(GlassContainer), matching: find.byType(Container)));
      expect((box.decoration! as BoxDecoration).color, AppPalette.light.glass);
    });
  });
}

void _noop() {}

Material _discMaterialOf(WidgetTester tester, double size) => tester.widget<Material>(
      find.descendant(of: find.byKey(ValueKey(size)), matching: find.byType(Material)).first,
    );
