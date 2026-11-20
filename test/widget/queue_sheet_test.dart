import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_spacing.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/widgets/artwork_thumbnail.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/music_player/queue_sheet.dart';

import '../helpers/app_fonts.dart';

class _FakePlayback extends PlaybackNotifier {
  _FakePlayback(this._initial);

  final domain.PlaybackState _initial;

  @override
  domain.PlaybackState build() => _initial;
}

const _longTitle = 'Resham Firiri (Folk Song, Live at the Valley Festival 2026)';

MediaItem _song(int n, {String? title}) => MediaItem(
      id: 'song_$n',
      uri: 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: title ?? 'Song $n',
      artist: 'Himal Sessions',
      durationMs: 240000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

void main() {
  // The bundled fonts, so text widths match the phone.
  setUpAll(loadAppFonts);

  final queue = [_song(1), _song(2, title: _longTitle), _song(3)];

  Future<void> pumpQueue(
    WidgetTester tester, {
    int current = 1,
    ThemeData? theme,
    double width = 360,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    final state = domain.PlaybackState(
      currentItemId: queue[current].id,
      queue: queue,
      originalQueue: queue,
      queueIndex: current,
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackNotifierProvider.overrideWith(() => _FakePlayback(state))],
        child: MaterialApp(theme: theme ?? AppTheme.darkTheme, home: const Scaffold(body: QueueSheet())),
      ),
    );
    await tester.pump();
  }

  // DESIGN.md 7.10: queue rows show their track number and a reorder grip
  // (the covers they had before are gone).
  testWidgets('track numbers sit in a 32 dp column on the 16 dp gutter, like the header', (tester) async {
    await pumpQueue(tester);
    expect(tester.takeException(), isNull);

    expect(find.byType(ArtworkThumbnail), findsNothing);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('02'), findsNothing, reason: 'the current row shows the equaliser in its place');
    for (final n in ['01', '03']) {
      // Centred in the 32 dp column that starts on the gutter.
      expect(tester.getRect(find.text(n)).center.dx, closeTo(AppSpacing.lg16 + 16, 0.5));
    }
    expect(tester.getRect(find.text('Current queue')).left, AppSpacing.lg16, reason: 'the same gutter as the header');
    final figures = tester.widget<Text>(find.text('01')).style!;
    expect(figures.fontFamily, 'DMMono', reason: 'the index role');
    expect(figures.color, AppPalette.dark.textMuted);
  });

  testWidgets('titles get the width left after the number, remove button and grip', (tester) async {
    await pumpQueue(tester);
    // 360 - 8 inset - 8 - 32 number - 12 - 48 remove - 48 grip - 8 inset.
    expect(tester.getSize(find.text(_longTitle)).width, greaterThanOrEqualTo(196 - 0.5));
  });

  testWidgets('the current track: a 3 dp primary bar, the equaliser for its number, a primary title', (tester) async {
    await pumpQueue(tester);

    final glyph = find.byIcon(Icons.graphic_eq_rounded);
    expect(glyph, findsOneWidget);
    expect(tester.widget<Icon>(glyph).semanticLabel, 'Now playing');
    expect(tester.widget<Icon>(glyph).color, AppPalette.dark.primary);

    final bar = find.byKey(const ValueKey('queue_now_bar'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).width, 3);
    expect(((tester.widget<DecoratedBox>(bar).decoration) as BoxDecoration).color, AppPalette.dark.primary);
    // 12 dp in from the row's top and bottom, on the leading edge of the row.
    final barRect = tester.getRect(bar);
    final rowRect = tester.getRect(find.ancestor(of: bar, matching: find.byType(InkWell)).first);
    expect(barRect.left, AppSpacing.sm8);
    expect(barRect.top, rowRect.top + 12);
    expect(barRect.bottom, rowRect.bottom - 12);

    expect(tester.widget<Text>(find.text(_longTitle)).style!.color, AppPalette.dark.primary);
    expect(tester.widget<Text>(find.text('Song 1')).style!.color, AppPalette.dark.textPrimary);

    // Keeps the remove button, the grip and the selected state.
    expect(find.byTooltip('Remove from queue'), findsNWidgets(queue.length));
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(queue.length));
    expect(tester.widget<Icon>(find.byIcon(Icons.drag_handle_rounded).first).color, AppPalette.dark.dragHandle);
    bool? selected(String title) => tester
        .widget<Semantics>(find
            .ancestor(
              of: find.text(title),
              matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected != null),
            )
            .first)
        .properties
        .selected;
    expect(selected(_longTitle), isTrue);
    expect(selected('Song 1'), isFalse);
  });

  testWidgets('in the light theme the queue is on paper, with Ultraviolet (not Volt) for the current track',
      (tester) async {
    await pumpQueue(tester, theme: AppTheme.lightTheme);
    const paper = AppPalette.light;
    expect(tester.widget<Text>(find.text(_longTitle)).style!.color, paper.primary);
    expect(tester.widget<Text>(find.text('Song 1')).style!.color, paper.textPrimary);
    expect(tester.widget<Icon>(find.byIcon(Icons.graphic_eq_rounded)).color, paper.primary);
    expect(tester.widget<Text>(find.text('Current queue')).style!.color, paper.textPrimary);
    expect(
      ((tester.widget<DecoratedBox>(find.byKey(const ValueKey('queue_now_bar'))).decoration) as BoxDecoration).color,
      paper.primary,
    );
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('holds at 1.3x text on $width dp', (tester) async {
      await pumpQueue(tester, width: width, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text('03'), findsOneWidget);
      // Rows grow with the text instead of clipping it.
      final row = tester.getRect(find.ancestor(of: find.text('Song 1'), matching: find.byType(InkWell)).first);
      expect(row.height, greaterThanOrEqualTo(64));
    });
  }
}
