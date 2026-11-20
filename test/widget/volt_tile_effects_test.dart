// Home bento effects: the Shuffle block's shine sweep (every ~6 s, none with
// reduced motion), its glow on ink, and the 0.97 press scale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool reduceMotion = false, ThemeData? theme}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: VoltTile(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle all',
                semanticLabel: 'Shuffle all songs',
                height: 140,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    ));
  }

  final shine = find.byKey(const ValueKey('volt_tile_shine'));

  testWidgets('a shine sweeps across every 6 s, then rests', (tester) async {
    await pump(tester);
    expect(shine, findsNothing, reason: 'at rest');
    await tester.pump(VoltTile.shineEvery);
    await tester.pump(const Duration(milliseconds: 500));
    expect(shine, findsOneWidget, reason: 'mid-sweep');
    await tester.pump(VoltTile.shineSweep);
    expect(shine, findsNothing, reason: 'sweep over');
  });

  testWidgets('no shine with reduced motion', (tester) async {
    await pump(tester, reduceMotion: true);
    await tester.pump(VoltTile.shineEvery * 2);
    await tester.pump(const Duration(milliseconds: 500));
    expect(shine, findsNothing);
  });

  testWidgets('press scales to 0.97 and back', (tester) async {
    await pump(tester);
    double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale;
    expect(scale(), 1);
    final gesture = await tester.startGesture(tester.getCenter(find.byType(VoltTile)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scale(), 0.97);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scale(), 1);
  });

  testWidgets('a glow sits under the block on ink', (tester) async {
    List<BoxShadow> shadows() => (tester
            .widgetList<DecoratedBox>(find.descendant(of: find.byType(VoltTile), matching: find.byType(DecoratedBox)))
            .map((b) => b.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.boxShadow != null)
            .boxShadow)!;
    await pump(tester);
    expect(shadows(), isNotEmpty);
  });
}
