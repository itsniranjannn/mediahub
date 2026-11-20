import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/personal/format_options.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';

import '../unit/fake_extractor_backend.dart';

void main() {
  Future<List<FormatChoice>> pump(WidgetTester tester, {double textScale = 1, double width = 360}) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final picked = <FormatChoice>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FormatSelectionSheet(metadata: FakeExtractorBackend.sampleMetadata(), onSelect: picked.add),
          ),
        ),
      ),
    ));
    await tester.pump();
    return picked;
  }

  testWidgets('Video and Audio sections: Video first, Audio lists the MP3 bitrates', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('format-sections')), findsOneWidget);
    final video = tester.getTopLeft(find.text('Video'));
    final audio = tester.getTopLeft(find.text('Audio'));
    expect(video.dx, lessThan(audio.dx), reason: 'Video first');

    // Video section shows video qualities, not audio ones.
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('MP3 · 320 kbps'), findsNothing);

    await tester.tap(find.text('Audio'));
    await tester.pump();
    expect(find.text('1080p'), findsNothing);
    final list = find.byType(Scrollable).last;
    for (final k in [320, 256, 192, 128]) {
      await tester.scrollUntilVisible(find.text('MP3 · $k kbps'), 80, scrollable: list);
      expect(find.text('MP3 · $k kbps'), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.textContaining('Original · M4A'), -80, scrollable: list);
    expect(find.textContaining('Original · M4A'), findsOneWidget);
    expect(find.text('AUDIO ONLY · SAVED TO MUSIC', skipOffstage: false), findsOneWidget);
  });

  testWidgets('choosing MP3 192 hands back the whitelisted conversion', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.text('Audio'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('MP3 · 192 kbps'), 80, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('MP3 · 192 kbps'));
    await tester.pump();
    expect(picked.single.audioFormat, 'mp3-192');
    expect(AudioConversion.parse(picked.single.audioFormat)!.ytDlpArgs.last, '192K');
    expect(picked.single.isAudio, isTrue);
  });

  testWidgets('no overflow at 360 dp and 1.3x text in either section', (tester) async {
    await pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Audio'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
