// The Downloads kind filter (All / Video / Audio) on the Bijuli chip theme:
// a selected chip is the Volt sticker, so everything on it must be ink.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

DownloadEntry _entry(String id, String kind) {
  final now = DateTime(2026, 11, 17, 12);
  return DownloadEntry(
    id: id,
    url: 'https://example.com/$id.${kind == 'audio' ? 'mp3' : 'mp4'}',
    host: 'example.com',
    displayName: 'Item $id',
    fileName: '$id.${kind == 'audio' ? 'mp3' : 'mp4'}',
    state: DownloadTaskState.failed.name,
    receivedBytes: 0,
    supportsRange: false,
    createdAt: now,
    updatedAt: now,
    kind: kind,
    engine: 'direct',
  );
}

void main() {
  for (final palette in [AppPalette.dark, AppPalette.light]) {
    final name = palette.isDark ? 'dark' : 'light';
    testWidgets('$name: the selected kind chip is ink on Volt, with only the check', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            downloadsStreamProvider.overrideWith((ref) => Stream.value([_entry('a', 'audio'), _entry('v', 'video')])),
            storageInfoProvider.overrideWith(
              (ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000)),
            ),
          ],
          child: MaterialApp(theme: AppTheme.build(palette), home: const DownloadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> check(String key, {required bool selected}) async {
        final chipFinder = find.byKey(ValueKey(key));
        expect(chipFinder, findsOneWidget);
        final chip = tester.widget<ChoiceChip>(chipFinder);
        expect(chip.selected, selected);
        expect(chip.labelStyle, isNull, reason: 'the chip theme colours the label');
        expect(chip.side, isNull, reason: 'the chip theme draws the edge');
        expect(chip.avatar == null, selected, reason: 'selected: only the ink check');
        final fill = Theme.of(tester.element(chipFinder)).chipTheme.color!.resolve({if (selected) WidgetState.selected})!;
        // The label ("Audio  1"), not the avatar glyph (also a RichText).
        final rich = tester.widget<RichText>(find.descendant(
          of: chipFinder,
          matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('  ')),
        ));
        final spans = <TextSpan>[];
        rich.text.visitChildren((span) {
          if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) spans.add(span);
          return true;
        });
        expect(spans, isNotEmpty);
        for (final span in spans) {
          final color = span.style?.color ?? rich.text.style!.color!;
          expect(_contrast(color, fill), greaterThanOrEqualTo(4.5), reason: '"${span.text}" on the chip');
        }
        if (selected) {
          for (final span in spans) {
            expect(span.style?.color ?? rich.text.style!.color, palette.onVoltFill, reason: '"${span.text}"');
          }
        }
      }

      await check('downloads_kind_all', selected: true);
      await check('downloads_kind_audio', selected: false);

      await tester.tap(find.byKey(const ValueKey('downloads_kind_audio')));
      await tester.pumpAndSettle();
      await check('downloads_kind_audio', selected: true);
      await check('downloads_kind_all', selected: false);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
