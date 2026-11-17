import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_colors.dart';
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

  Future<void> pumpQueue(WidgetTester tester, {int current = 1}) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

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
        child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: QueueSheet())),
      ),
    );
    await tester.pump();
  }

  testWidgets('covers start on the 16 dp gutter, with no position column', (tester) async {
    await pumpQueue(tester);
    expect(tester.takeException(), isNull);

    final covers = tester.widgetList<ArtworkThumbnail>(find.byType(ArtworkThumbnail)).toList();
    expect(covers, hasLength(queue.length));
    for (final cover in find.byType(ArtworkThumbnail).evaluate()) {
      expect(tester.getRect(find.byWidget(cover.widget)).left, AppSpacing.lg16);
    }
    expect(tester.getRect(find.text('Current Queue')).left, AppSpacing.lg16, reason: 'the same gutter as the header');
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsNothing, reason: 'the header and Now Playing give the position');
    }
  });

  testWidgets('titles get the width the number column used to take', (tester) async {
    await pumpQueue(tester);
    // 360 - 8 inset - 8 - 44 cover - 12 - 48 remove - 48 drag - 8 inset.
    expect(tester.getSize(find.text(_longTitle)).width, greaterThanOrEqualTo(184 - 0.5));
  });

  testWidgets('the current track wears the equaliser veil on its cover, like the song lists', (tester) async {
    await pumpQueue(tester);

    final glyph = find.byIcon(Icons.graphic_eq_rounded);
    expect(glyph, findsOneWidget);
    expect(tester.widget<Icon>(glyph).semanticLabel, 'Now playing');
    expect(tester.widget<Icon>(glyph).color, AppColors.primary);

    final veil = tester.widget<DecoratedBox>(find.ancestor(of: glyph, matching: find.byType(DecoratedBox)).first);
    expect((veil.decoration as BoxDecoration).color, AppColors.overlay);
    // Laid over the current row's cover, at the same size.
    final currentCover = tester.getRect(find.byWidgetPredicate((w) => w is ArtworkThumbnail && w.uri == queue[1].uri));
    expect(tester.getRect(find.ancestor(of: glyph, matching: find.byType(DecoratedBox)).first), currentCover);

    // Keeps the remove button, drag handle and the selected state.
    expect(find.byTooltip('Remove from queue'), findsNWidgets(queue.length));
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(queue.length));
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
}
