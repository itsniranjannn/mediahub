// The Sindur component toppings (docs/DESIGN.md 7): the crimson glow under
// Volt buttons and slider thumbs on ink only, soft card shadows on paper only,
// the 0.97 press scale, and reduced motion making it instant.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/app/theme/motion_tokens.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

Future<void> _pump(WidgetTester tester, Widget child, {required ThemeData theme, bool reduceMotion = false}) async {
  // A fresh key per pump, so MaterialApp does not animate from the last theme.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

ShapeDecoration _voltDecoration(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(of: find.byType(VoltButton), matching: find.byType(DecoratedBox)))
    .map((b) => b.decoration)
    .whereType<ShapeDecoration>()
    .single;

AnimatedScale _scaleOf(WidgetTester tester, Type type) =>
    tester.widget<AnimatedScale>(find.descendant(of: find.byType(type), matching: find.byType(AnimatedScale)).first);

void main() {
  group('VoltButton', () {
    testWidgets('glows crimson on ink, never on paper, and not when disabled', (tester) async {
      await _pump(tester, VoltButton(label: 'Play all', onPressed: () {}), theme: AppTheme.darkTheme);
      final dark = _voltDecoration(tester).shadows!;
      expect(dark, isNotEmpty);
      expect(dark.single.color, AppPalette.dark.voltGlow);

      await _pump(tester, VoltButton(label: 'Play all', onPressed: () {}), theme: AppTheme.lightTheme);
      expect(_voltDecoration(tester).shadows, isEmpty);

      await _pump(tester, const VoltButton(label: 'Play all', onPressed: null), theme: AppTheme.darkTheme);
      expect(_voltDecoration(tester).shadows, isEmpty);
    });

    testWidgets('the sheen runs top to bottom', (tester) async {
      for (final p in [AppPalette.dark, AppPalette.light]) {
        expect(p.primaryGradient.begin, Alignment.topCenter);
        expect(p.primaryGradient.end, Alignment.bottomCenter);
      }
    });

    testWidgets('scales to 0.97 while pressed, over MotionTokens.micro', (tester) async {
      await _pump(tester, VoltButton(label: 'Play all', onPressed: () {}), theme: AppTheme.darkTheme);
      expect(_scaleOf(tester, VoltButton).scale, 1);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(VoltButton)));
      await tester.pumpAndSettle();
      final pressed = _scaleOf(tester, VoltButton);
      expect(pressed.scale, MotionTokens.pressedScale);
      expect(pressed.duration, MotionTokens.micro);
      // The glow tightens under the finger.
      expect(_voltDecoration(tester).shadows!.single.blurRadius, lessThan(18));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, VoltButton).scale, 1);
    });

    testWidgets('with reduced motion the press scale is instant', (tester) async {
      await _pump(tester, VoltButton(label: 'Play all', onPressed: () {}), theme: AppTheme.darkTheme, reduceMotion: true);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(VoltButton)));
      await tester.pump();
      final pressed = _scaleOf(tester, VoltButton);
      expect(pressed.scale, MotionTokens.pressedScale);
      expect(pressed.duration, Duration.zero);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('TonalIconButton', () {
    testWidgets('is a round secondaryContainer disc that scales when pressed', (tester) async {
      await _pump(
        tester,
        TonalIconButton(icon: Icons.shuffle_rounded, tooltip: 'Shuffle', onPressed: () {}),
        theme: AppTheme.darkTheme,
      );
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(TonalIconButton), matching: find.byType(Material)).first,
      );
      expect(material.color, AppPalette.dark.secondaryContainer);
      expect(material.shape, isA<CircleBorder>());
      expect(tester.getSize(find.byType(IconButton)).width, greaterThanOrEqualTo(48));

      // Short of the tooltip's long press, which would take the gesture.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(TonalIconButton)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scaleOf(tester, TonalIconButton).scale, MotionTokens.pressedScale);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('SurfaceCard', () {
    List<BoxShadow> shadowsUnder(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(SurfaceCard), matching: find.byType(DecoratedBox)))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .expand((d) => d.boxShadow ?? const <BoxShadow>[])
        .toList();

    testWidgets('casts a soft shadow on paper and none on ink', (tester) async {
      await _pump(tester, const SurfaceCard(child: Text('Hi')), theme: AppTheme.lightTheme);
      expect(shadowsUnder(tester), isNotEmpty);
      await _pump(tester, const SurfaceCard(child: Text('Hi')), theme: AppTheme.darkTheme);
      expect(shadowsUnder(tester), isEmpty);
    });
  });

  group('theme toppings', () {
    test('the slider thumb glows on ink only', () {
      final dark = AppTheme.darkTheme.sliderTheme.thumbShape! as VoltSliderThumbShape;
      final light = AppTheme.lightTheme.sliderTheme.thumbShape! as VoltSliderThumbShape;
      expect(dark.glowColor, AppPalette.dark.voltGlow);
      expect(dark.glowColor.a, greaterThan(0));
      expect(light.glowColor.a, 0);
    });

    test('cards: hairline on ink, soft shadow on paper; dialogs and sheets radius 28', () {
      final dark = AppTheme.darkTheme;
      final light = AppTheme.lightTheme;
      expect((dark.cardTheme.shape! as RoundedRectangleBorder).side.color, AppPalette.dark.divider);
      expect(dark.cardTheme.elevation, 0);
      expect((light.cardTheme.shape! as RoundedRectangleBorder).side, BorderSide.none);
      expect(light.cardTheme.elevation, greaterThan(0));
      for (final t in [dark, light]) {
        expect((t.cardTheme.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(20));
        expect((t.dialogTheme.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(28));
        expect(
          (t.bottomSheetTheme.shape! as RoundedRectangleBorder).borderRadius,
          const BorderRadius.vertical(top: Radius.circular(28)),
        );
        expect(t.bottomSheetTheme.showDragHandle, isTrue);
      }
    });

    test('outlined buttons turn brand when pressed; icon buttons are round', () {
      for (final t in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        final p = t.extension<AppPalette>()!;
        final side = t.outlinedButtonTheme.style!.side!;
        expect(side.resolve({WidgetState.pressed})!.color, p.primary);
        expect(side.resolve({})!.color, p.outline);
        expect(t.iconButtonTheme.style!.shape!.resolve({}), isA<CircleBorder>());
        expect(t.iconButtonTheme.style!.overlayColor!.resolve({WidgetState.pressed}), isNotNull);
        expect(t.elevatedButtonTheme.style!.backgroundColor!.resolve({WidgetState.disabled})!.a, lessThan(0.2));
      }
    });
  });
}
