import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/music_player/mini_player.dart';

/// Found on the emulator: Now Playing's header (chevron, "NOW PLAYING · 3 / 11",
/// menu) sat under the status bar clock. The sheet is shown with
/// useSafeArea: false so it can paint under the status bar, and Flutter then
/// also strips the top inset from the sheet's MediaQuery.
void main() {
  testWidgets('a sheet shown without the safe area gets the status bar inset back', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.padding = const FakeViewPadding(top: 156); // 52 dp
    tester.view.viewPadding = const FakeViewPadding(top: 156);
    addTearDown(tester.view.reset);

    double? raw;
    double? restored;
    double? restoredView;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                final nav = Navigator.of(context).context;
                showModalBottomSheet<void>(
                  context: nav,
                  isScrollControlled: true,
                  useSafeArea: false,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(builder: (c) {
                        raw = MediaQuery.paddingOf(c).top;
                        return const SizedBox(height: 10);
                      }),
                      RestoreTopInset(
                        source: nav,
                        child: Builder(builder: (c) {
                          restored = MediaQuery.paddingOf(c).top;
                          restoredView = MediaQuery.viewPaddingOf(c).top;
                          return const SafeArea(bottom: false, child: Text('header'));
                        }),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(raw, 0, reason: 'what Flutter does with useSafeArea: false');
    expect(restored, 52);
    expect(restoredView, 52);
  });

  testWidgets('it leaves a MediaQuery that already has the inset alone', (tester) async {
    late BuildContext outer;
    double? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 30)),
        child: Builder(builder: (context) {
          outer = context;
          return MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 40)),
            child: Builder(
              builder: (_) => RestoreTopInset(
                source: outer,
                child: Builder(builder: (c) {
                  seen = MediaQuery.paddingOf(c).top;
                  return const SizedBox();
                }),
              ),
            ),
          );
        }),
      ),
    );
    expect(seen, 40);
  });
}
