// The Downloads tab keeps its Saved group short: every saved file is also in
// Videos or Music, so only the newest few show, and one "Show all N saved"
// row opens the rest in place (and "Show less" folds them away again).
// Anything that needs the user (running, waiting, paused, failed) always
// shows.
import 'dart:async';

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
import 'package:mediahub/shared/widgets/ui_kit.dart';

final _base = DateTime(2026, 11, 20, 12);

DownloadEntry _row(
  String id,
  String title, {
  required DownloadTaskState state,
  String kind = 'audio',
  DateTime? added,
  DateTime? finished,
  int received = 0,
  int? total,
}) {
  return DownloadEntry(
    id: id,
    url: 'https://example.com/$id.${kind == 'audio' ? 'mp3' : 'mp4'}',
    host: 'example.com',
    displayName: title,
    fileName: '$id.${kind == 'audio' ? 'mp3' : 'mp4'}',
    state: state.name,
    receivedBytes: received,
    totalBytes: total,
    supportsRange: true,
    createdAt: added ?? finished ?? _base,
    updatedAt: finished ?? added ?? _base,
    kind: kind,
    engine: 'http',
  );
}

/// "Track 01" (finished last) to "Track [n]" (finished first).
String _title(int i) => 'Track ${i.toString().padLeft(2, '0')}';

/// [n] saved downloads; the lower the number, the newer.
List<DownloadEntry> _saved(int n, {String kind = 'audio', int from = 1, String prefix = 's'}) => [
      for (var i = from; i < from + n; i++)
        _row(
          '$prefix$i',
          _title(i),
          state: DownloadTaskState.completed,
          kind: kind,
          finished: _base.subtract(Duration(minutes: i)),
          received: 1000,
          total: 1000,
        ),
    ];

const _toggleKey = ValueKey<String>('t_saved_toggle');

/// Every download title on screen, top to bottom.
List<String> _shownTitles(WidgetTester tester) => tester
    .widgetList<Text>(find.textContaining(RegExp(r'^(Track|Failed|Cancelled|Running|Waiting|Paused) ')))
    .map((t) => t.data!)
    .toList();

/// The download list's row count (group labels, cards and the toggle),
/// whether or not each row is built yet.
int _listRowCount(WidgetTester tester) {
  final list = tester.widget<SliverList>(
    find.descendant(of: find.byKey(const ValueKey('downloads-list')), matching: find.byType(SliverList)),
  );
  return list.delegate.estimatedChildCount!;
}

void main() {
  /// A view tall enough that every row is laid out, unless [tall] is false.
  Future<StreamController<List<DownloadEntry>>> pump(
    WidgetTester tester,
    List<DownloadEntry> rows, {
    bool tall = true,
    AppPalette palette = AppPalette.dark,
  }) async {
    if (tall) {
      tester.view.physicalSize = const Size(800, 7000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final stream = StreamController<List<DownloadEntry>>.broadcast();
    addTearDown(stream.close);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      downloadsStreamProvider.overrideWith((ref) async* {
        yield rows;
        yield* stream.stream;
      }),
      storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.build(palette), home: const DownloadsScreen()),
    ));
    await tester.pumpAndSettle();
    return stream;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapToggle(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_toggleKey));
    await tester.pump(); // lay out at the new scroll offset before tapping
    await tester.tap(find.descendant(of: find.byKey(_toggleKey), matching: find.byType(Text)));
    await tester.pumpAndSettle();
  }

  testWidgets('Sindur v2: the link field is the glowing hero, active cards carry a bold bar', (tester) async {
    for (final palette in [AppPalette.dark, AppPalette.light]) {
      await pump(tester, [
        _row('r1', 'Running one', state: DownloadTaskState.downloading, received: 300, total: 1000),
        ..._saved(2),
      ], palette: palette);
      final hero = find.byWidgetPredicate((w) => w is HeroBand && w.glow);
      expect(hero, findsOneWidget);
      expect(find.descendant(of: hero, matching: find.byType(TextField)), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first);
      expect(bar.minHeight, 8);
      expect(bar.color, palette.sliderActive);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    }
  });

  group('how many saved downloads show', () {
    testWidgets('0 saved: no Saved group and no toggle', (tester) async {
      await pump(tester, const []);
      expect(find.text('No downloads yet'), findsOneWidget);
      expect(find.byKey(_toggleKey), findsNothing);
      await unmount(tester);
    });

    testWidgets('0 saved but a failed one: it shows, with no toggle', (tester) async {
      await pump(tester, [_row('f1', 'Failed 1', state: DownloadTaskState.failed)]);
      expect(_shownTitles(tester), ['Failed 1']);
      expect(find.textContaining('SAVED'), findsNothing);
      expect(find.byKey(_toggleKey), findsNothing);
      await unmount(tester);
    });

    testWidgets('3 saved: all three, no toggle', (tester) async {
      await pump(tester, _saved(3));
      expect(_shownTitles(tester), [_title(1), _title(2), _title(3)]);
      expect(find.byKey(_toggleKey), findsNothing);
      await unmount(tester);
    });

    testWidgets('5 saved: all five, no toggle', (tester) async {
      await pump(tester, _saved(5));
      expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) _title(i)]);
      expect(find.byKey(_toggleKey), findsNothing);
      expect(_listRowCount(tester), 1 + 5);
      await unmount(tester);
    });

    testWidgets('6 saved: the newest five and "Show all 6 saved"', (tester) async {
      await pump(tester, _saved(6));
      expect(kSavedPreviewCount, 5);
      expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) _title(i)]);
      expect(find.text(_title(6)), findsNothing);
      expect(find.text('Show all 6 saved'), findsOneWidget);
      // The group heading keeps the full count.
      expect(find.text('SAVED  6'), findsOneWidget);

      await tapToggle(tester);
      expect(_shownTitles(tester), [for (var i = 1; i <= 6; i++) _title(i)]);
      expect(find.text('Show less'), findsOneWidget);

      await tapToggle(tester);
      expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) _title(i)]);
      expect(find.text('Show all 6 saved'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('30 saved: five, then all thirty under the toggle, then five again', (tester) async {
      await pump(tester, _saved(30));
      expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) _title(i)]);
      expect(_listRowCount(tester), 1 + 5 + 1);
      expect(find.text('Show all 30 saved'), findsOneWidget);
      // The header and the chip still count every saved download.
      expect(find.textContaining('30 SAVED'), findsOneWidget);
      expect(find.text('All  30'), findsOneWidget);
      expect(find.text('Audio  30'), findsOneWidget);

      await tapToggle(tester);
      expect(_shownTitles(tester), [for (var i = 1; i <= 30; i++) _title(i)]);
      expect(_listRowCount(tester), 1 + 30 + 1);
      // The toggle stays where it was: the older ones open below it.
      final toggleTop = tester.getTopLeft(find.byKey(_toggleKey)).dy;
      expect(tester.getTopLeft(find.text(_title(5))).dy, lessThan(toggleTop));
      expect(tester.getTopLeft(find.text(_title(6))).dy, greaterThan(toggleTop));
      expect(find.text('Show less'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);

      await tapToggle(tester);
      expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) _title(i)]);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      await unmount(tester);
    });
  });

  testWidgets('running, waiting, paused, failed and cancelled downloads always show', (tester) async {
    await pump(tester, [
      ..._saved(30),
      _row('a1', 'Running 1', state: DownloadTaskState.downloading, received: 500, total: 1000),
      _row('a2', 'Running 2', state: DownloadTaskState.finalizing, received: 1000, total: 1000),
      _row('q1', 'Waiting 1', state: DownloadTaskState.queued),
      _row('p1', 'Paused 1', state: DownloadTaskState.paused, received: 200, total: 1000),
      for (var i = 1; i <= 7; i++) _row('f$i', 'Failed $i', state: DownloadTaskState.failed),
      _row('c1', 'Cancelled 1', state: DownloadTaskState.cancelled),
    ]);
    final shown = _shownTitles(tester);
    expect(shown, [
      'Running 1',
      'Running 2',
      'Waiting 1',
      'Paused 1',
      for (var i = 1; i <= 5; i++) _title(i),
      for (var i = 1; i <= 7; i++) 'Failed $i',
      'Cancelled 1',
    ]);
    // Failed ones come after the toggle and stay there.
    final toggleTop = tester.getTopLeft(find.byKey(_toggleKey)).dy;
    expect(tester.getTopLeft(find.text('Failed 1')).dy, greaterThan(toggleTop));
    expect(find.text('Show all 30 saved'), findsOneWidget);

    await tapToggle(tester);
    expect(_shownTitles(tester).length, 4 + 30 + 8);
    await unmount(tester);
  });

  testWidgets('the kind chips choose which five show; their counts stay whole', (tester) async {
    // Audio and video saved one after another: audio i finished at minute
    // 2i - 1, video i at minute 2i.
    final audio = [
      for (var i = 1; i <= 8; i++)
        _row('a$i', 'Track A$i', state: DownloadTaskState.completed, kind: 'audio',
            finished: _base.subtract(Duration(minutes: 2 * i - 1)), received: 10, total: 10),
    ];
    final video = [
      for (var i = 1; i <= 7; i++)
        _row('v$i', 'Track V$i', state: DownloadTaskState.completed, kind: 'video',
            finished: _base.subtract(Duration(minutes: 2 * i)), received: 10, total: 10),
    ];
    await pump(tester, [...video, ...audio]);

    expect(_shownTitles(tester), ['Track A1', 'Track V1', 'Track A2', 'Track V2', 'Track A3']);
    expect(find.text('Show all 15 saved'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('downloads_kind_video')));
    await tester.pumpAndSettle();
    expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) 'Track V$i']);
    expect(find.text('Show all 7 saved'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('downloads_kind_audio')));
    await tester.pumpAndSettle();
    expect(_shownTitles(tester), [for (var i = 1; i <= 5; i++) 'Track A$i']);
    expect(find.text('Show all 8 saved'), findsOneWidget);

    // The chips keep their full counts whichever one is chosen.
    expect(find.text('All  15'), findsOneWidget);
    expect(find.text('Video  7'), findsOneWidget);
    expect(find.text('Audio  8'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a kind with five or fewer saved has no toggle', (tester) async {
    await pump(tester, [..._saved(12), ..._saved(3, kind: 'video', from: 50, prefix: 'v')]);
    expect(find.text('Show all 15 saved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('downloads_kind_video')));
    await tester.pumpAndSettle();
    expect(_shownTitles(tester), [_title(50), _title(51), _title(52)]);
    expect(find.byKey(_toggleKey), findsNothing);
    await unmount(tester);
  });

  testWidgets('a download added long ago that finished just now is among the five', (tester) async {
    await pump(tester, [
      ..._saved(10),
      _row(
        'old',
        'Track late',
        state: DownloadTaskState.completed,
        added: _base.subtract(const Duration(days: 9)),
        finished: _base.add(const Duration(minutes: 1)),
        received: 10,
        total: 10,
      ),
    ]);
    expect(_shownTitles(tester), ['Track late', _title(1), _title(2), _title(3), _title(4)]);
    await unmount(tester);
  });

  testWidgets('open stays open while the list changes and across kind chips', (tester) async {
    final stream = await pump(tester, _saved(20));
    await tapToggle(tester);
    expect(_shownTitles(tester).length, 20);

    // A new download finishes: still open, the new one first.
    stream.add([
      _row('new', 'Track new', state: DownloadTaskState.completed, finished: _base, received: 1, total: 1),
      ..._saved(20),
    ]);
    await tester.pumpAndSettle();
    expect(_shownTitles(tester).first, 'Track new');
    expect(_shownTitles(tester).length, 21);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('downloads_kind_audio')));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(_shownTitles(tester).length, 21);
    await unmount(tester);
  });

  testWidgets('nothing is saved: a new screen starts short again', (tester) async {
    await pump(tester, _saved(20));
    expect(_shownTitles(tester).length, 5);
    expect(find.text('Show all 20 saved'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the toggle is a button that says what it does and whether the list is open', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, _saved(30));

    expect(
      find.semantics.byLabel('Show all 30 saved downloads'),
      isSemantics(
        label: 'Show all 30 saved downloads',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    await tapToggle(tester);
    expect(
      find.semantics.byLabel('Show less saved downloads'),
      isSemantics(
        label: 'Show less saved downloads',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    // Its target is at least 48 dp tall.
    expect(tester.getSize(find.byKey(_toggleKey)).height, greaterThanOrEqualTo(48));
    await unmount(tester);
    handle.dispose();
  });

  testWidgets('hundreds of saved downloads: rows are built only as they scroll in', (tester) async {
    await pump(tester, _saved(300), tall: false);
    // The page's own scroll view (the link field in the hero has one too).
    final list = find.ancestor(of: find.byKey(const ValueKey('downloads-list')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(_toggleKey), 300, scrollable: list);
    expect(find.text('Show all 300 saved'), findsOneWidget);
    await tapToggle(tester);
    expect(_listRowCount(tester), 1 + 300 + 1);
    expect(_shownTitles(tester).length, lessThan(30), reason: 'only the rows near the screen are built');

    await tester.scrollUntilVisible(find.text(_title(300)), 2000, scrollable: list);
    expect(find.text(_title(300)), findsOneWidget);
    expect(find.text(_title(1)), findsNothing, reason: 'the rows scrolled far away are let go');
    await unmount(tester);
  });

  test('newest saved first: by when each finished, then when added, then id', () {
    final a = _row('a', 'A', state: DownloadTaskState.completed, added: _base, finished: _base);
    final b = _row('b', 'B', state: DownloadTaskState.completed,
        added: _base.subtract(const Duration(days: 1)), finished: _base.add(const Duration(seconds: 1)));
    final c = _row('c', 'C', state: DownloadTaskState.completed,
        added: _base.add(const Duration(seconds: 5)), finished: _base);
    final d = _row('d', 'D', state: DownloadTaskState.completed, added: _base, finished: _base);
    expect(newestSavedFirst([a, b, c, d]).map((e) => e.id), ['b', 'c', 'd', 'a']);
    expect(newestSavedFirst([d, c, b, a]).map((e) => e.id), ['b', 'c', 'd', 'a']);
    expect(newestSavedFirst(const []), isEmpty);
  });
}
