// What a screen reader (TalkBack / VoiceOver) gets from the song rows, the
// mini player, Now Playing and the queue: every row and card is one node that
// is read once, and the heart / more / transport buttons stay nodes of their
// own. Emulator QA found rows and the mini player read twice, the progress
// percentage in front of the mini player's label and one sheet-sized Now
// Playing node that merged the title with "Add to favorites".
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/core/utils/formatters.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/library/media_song_row.dart';
import 'package:mediahub/features/music_player/mini_player.dart';
import 'package:mediahub/features/music_player/now_playing_sheet.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/music_player/queue_sheet.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';

class _FakePlayback extends PlaybackNotifier {
  _FakePlayback(this._initial);

  final domain.PlaybackState _initial;
  final List<int> skippedTo = [];

  @override
  domain.PlaybackState build() => _initial;

  @override
  Future<void> skipToQueueItem(int index) async => skippedTo.add(index);

  // The queue sheet names the row's song too (F6).
  final List<String> skippedToIds = [];

  @override
  Future<void> skipToQueueEntry(int index, String expectedId) async {
    skippedTo.add(index);
    skippedToIds.add(expectedId);
  }
}

/// Records swipe-to-remove from the queue.
class _RemovingPlayback extends _FakePlayback {
  _RemovingPlayback(super.initial);

  final List<int> removed = [];

  @override
  Future<void> removeQueueItemAt(int index) async => removed.add(index);

  final List<String> removedIds = [];

  @override
  Future<void> removeQueueEntry(int index, String expectedId) async {
    removed.add(index);
    removedIds.add(expectedId);
  }
}

const _channel = MethodChannel('mediahub/media_store');

/// The file-style name from the emulator QA run.
const _fileTitle = 'Audit_Long_Tone_5min';

MediaItem _song(
  int n, {
  String? title,
  String? artist = 'Test Artist',
  int durationMs = 300000,
  String source = 'device',
  MediaAvailability availability = MediaAvailability.available,
}) =>
    MediaItem(
      id: 'song_$n',
      uri: 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: title ?? 'Song $n',
      artist: artist,
      durationMs: durationMs,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      source: source,
      availability: availability,
    );

domain.PlaybackState _playing(List<MediaItem> queue, {int index = 0}) => domain.PlaybackState(
      currentItemId: queue[index].id,
      queue: queue,
      originalQueue: queue,
      queueIndex: index,
      duration: Duration(milliseconds: queue[index].durationMs),
      updatedAt: DateTime(2026),
    );

/// Nodes whose label contains [text].
SemanticsFinder _labelled(String text) => find.semantics.byPredicate((node) => node.label.contains(text));

SemanticsData _data(SemanticsFinder finder) => finder.evaluate().single.getSemanticsData();

/// Device art: none, so the covers fall back to their placeholders.
void _mockNoArtwork(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
}

void main() {
  setUp(ArtworkService.instance.clearCache);
  tearDown(ArtworkService.instance.clearCache);

  group('song row', () {
    Future<void> pumpRows(
      WidgetTester tester,
      List<Widget> rows, {
      MediaItem? playing,
      double width = 360,
    }) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentMediaItemProvider.overrideWith((ref) => playing),
            isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: ListView(children: rows)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('each row is one node, read once, with the tap and the playing row selected', (tester) async {
      final handle = tester.ensureSemantics();
      final playing = _song(1, title: _fileTitle, artist: null);
      final other = _song(2);
      await pumpRows(tester, [MediaSongRow(item: playing), MediaSongRow(item: other)], playing: playing);

      final row = find.semantics.byLabel('Song: $_fileTitle by Unknown artist, 5:00');
      expect(row, findsOne);
      expect(
        row,
        isSemantics(isButton: true, isSelected: true, hasSelectedState: true, hasTapAction: true),
      );
      expect(_labelled(_fileTitle), findsOne, reason: 'no second node repeats the title');
      expect(_labelled('Now playing'), findsNothing, reason: 'the selected state says it, once');

      expect(
        find.semantics.byLabel('Song: Song 2 by Test Artist, 5:00'),
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );
      expect(_labelled('Song 2'), findsOne);
      handle.dispose();
    });

    testWidgets('the heart and "more" stay buttons of their own, outside the row label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRows(tester, [MediaSongRow(item: _song(1, title: _fileTitle))]);

      final heart = find.semantics.byLabel('Add to Favourites');
      expect(heart, findsOne);
      expect(heart, isSemantics(isButton: true, hasTapAction: true));
      expect(_data(heart).tooltip, isEmpty, reason: 'VoiceOver would read the label and the tooltip');
      expect(find.semantics.byPredicate((n) => n.tooltip == 'Add to Favourites'), findsNothing);

      final more = find.semantics.byPredicate((n) => n.tooltip == 'More actions');
      expect(more, findsOne);
      expect(more, isSemantics(isButton: true, hasTapAction: true));

      expect(
        find.semantics.byPredicate((n) => n.label.contains(_fileTitle) && n.label.contains('Add to Favourites')),
        findsNothing,
      );
      // The tooltip still shows to sighted users on a long press.
      await tester.longPress(find.byType(FavoriteFeedbackButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Add to Favourites'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      handle.dispose();
    });

    testWidgets('the row node taps like the row itself', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpRows(tester, [MediaSongRow(item: _song(1), onTap: () => taps++)]);

      tester.semantics.tap(find.semantics.byLabel(RegExp('^Song: Song 1 by ')));
      await tester.pump();
      expect(taps, 1);

      await tester.tap(find.text('Song 1'));
      await tester.pump();
      expect(taps, 2, reason: 'the ink well still takes touches');
      handle.dispose();
    });

    testWidgets('a missing file says so first, and its tap still shows the snackbar', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpRows(tester, [
        MediaSongRow(item: _song(1, availability: MediaAvailability.missing), onTap: () => taps++),
      ]);

      final row = find.semantics.byLabel('Missing file. Song: Song 1 by Test Artist, 5:00');
      expect(row, findsOne);
      expect(_labelled('Missing'), findsOne, reason: 'the visible "Missing ·" is not read again');

      tester.semantics.tap(row);
      await tester.pump();
      expect(find.text('File is missing or unavailable on storage'), findsOneWidget);
      expect(taps, 0, reason: 'a missing file never plays');
      handle.dispose();
    });

    testWidgets('"Downloaded" and the length are in the label once, at any width', (tester) async {
      final handle = tester.ensureSemantics();
      final song = _song(1, source: 'download', durationMs: 245000);
      for (final width in [480.0, 320.0]) {
        await pumpRows(tester, [MediaSongRow(item: song)], width: width);
        expect(find.semantics.byLabel('Song: Song 1 by Test Artist, Downloaded, 4:05'), findsOne);
        expect(_labelled('Downloaded'), findsOne, reason: 'at $width dp');
        expect(_labelled('4:05'), findsOne, reason: 'at $width dp');
        expect(_labelled('·'), findsNothing);
      }
      handle.dispose();
    });

    testWidgets('a two-line title wraps after "_" but reads the real name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRows(tester, [MediaSongRow(item: _song(1, title: _fileTitle))], width: 320);

      expect(find.text(breakableTitle(_fileTitle)), findsOneWidget);
      expect(tester.widget<Text>(find.text(breakableTitle(_fileTitle))).maxLines, 2);
      expect(_labelled(_fileTitle), findsOne);
      expect(find.semantics.byPredicate((n) => n.label.contains('​')), findsNothing);
      handle.dispose();
    });

    testWidgets('a trailing button keeps its own node and action', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await pumpRows(tester, [
        MediaSongRow(
          item: _song(1),
          trailing: IconButton(
            tooltip: 'Remove from playlist',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => pressed++,
          ),
        ),
      ]);

      expect(find.semantics.byPredicate((n) => n.tooltip == 'More actions'), findsNothing);
      final trailing = find.semantics.byPredicate((n) => n.tooltip == 'Remove from playlist');
      expect(trailing, isSemantics(isButton: true, hasTapAction: true));
      tester.semantics.tap(trailing);
      await tester.pump();
      expect(pressed, 1);
      expect(find.semantics.byLabel(RegExp('^Song: Song 1 ')), findsOne);
      handle.dispose();
    });

    testWidgets('in a reorderable list the row node carries the move actions too', (tester) async {
      final handle = tester.ensureSemantics();
      final songs = [_song(1), _song(2), _song(3)];
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentMediaItemProvider.overrideWith((ref) => null),
            isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: songs.length,
                onReorderItem: (_, _) {},
                itemBuilder: (context, index) => Dismissible(
                  key: ValueKey(songs[index].id),
                  direction: DismissDirection.endToStart,
                  child: MediaSongRow(item: songs[index], onTap: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // One stop per row: its label, its tap and the list's "Move up / down",
      // not an unlabelled node holding the moves around a labelled one.
      final middle = find.semantics.byLabel(RegExp('^Song: Song 2 '));
      expect(middle, findsOne);
      expect(middle, isSemantics(hasTapAction: true));
      expect(_data(middle).customSemanticsActionIds, isNotEmpty);
      expect(
        find.semantics.byPredicate(
          (n) => n.label.isEmpty && (n.getSemanticsData().customSemanticsActionIds?.isNotEmpty ?? false),
        ),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('mini player', () {
    Future<_FakePlayback> pumpMini(WidgetTester tester, MediaItem song) async {
      _mockNoArtwork(tester);
      MiniPlayer.isNowPlayingOpen = false;
      addTearDown(() => MiniPlayer.isNowPlayingOpen = false);
      final playback = _FakePlayback(_playing([song, _song(2)]));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackNotifierProvider.overrideWith(() => playback),
            currentMediaItemProvider.overrideWith((ref) => song),
            isPlayingProvider.overrideWith((ref) => true),
            throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 63))),
            isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer())),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return playback;
    }

    testWidgets('one card node: title by artist, no progress number, title read once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMini(tester, _song(1, title: _fileTitle, artist: null));

      final card = find.semantics.byLabel('Mini player: $_fileTitle by Unknown artist');
      expect(card, findsOne);
      expect(card, isSemantics(hint: 'Opens Now Playing', isButton: true, hasTapAction: true));
      final data = _data(card);
      expect(data.value, isEmpty, reason: 'the progress line used to put "21" in front of the label');
      expect(data.role, isNot(SemanticsRole.progressBar));
      expect(data.label, isNot(contains(RegExp(r'\d{2}'))), reason: 'only the title\'s own "5"');
      expect(RegExp(_fileTitle).allMatches(data.label), hasLength(1));
      expect(_labelled(_fileTitle), findsOne);
      expect(find.semantics.byPredicate((n) => n.value.isNotEmpty), findsNothing);
      expect(
        find.semantics.byPredicate(
          (n) => n.getSemanticsData().hasAction(SemanticsAction.scrollLeft) ||
              n.getSemanticsData().hasAction(SemanticsAction.scrollUp),
        ),
        findsNothing,
        reason: 'the swipes are shortcuts for Previous / Next, not a scrollable',
      );
      handle.dispose();
    });

    testWidgets('Previous, Pause and Next stay separate buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMini(tester, _song(1));
      for (final tooltip in ['Previous', 'Pause', 'Next']) {
        final button = find.semantics.byPredicate((n) => n.tooltip == tooltip);
        expect(button, findsOne, reason: tooltip);
        expect(button, isSemantics(isButton: true, hasTapAction: true), reason: tooltip);
        expect(_data(button).label, isEmpty, reason: '$tooltip is not merged with the card');
      }
      handle.dispose();
    });

    testWidgets('tapping the card node opens Now Playing', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMini(tester, _song(1));

      tester.semantics.tap(find.semantics.byLabel(RegExp('^Mini player: ')));
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingSheet), findsOneWidget);
      expect(MiniPlayer.isNowPlayingOpen, isTrue);
      handle.dispose();
    });
  });

  group('Now Playing', () {
    Future<void> pumpSheet(WidgetTester tester, List<MediaItem> queue) async {
      _mockNoArtwork(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 776);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackNotifierProvider.overrideWith(() => _FakePlayback(_playing(queue))),
            throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 106))),
            isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
          ],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const NowPlayingSheet()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no sheet-sized node merges the title with the heart and the times', (tester) async {
      final handle = tester.ensureSemantics();
      final queue = [_song(1, title: _fileTitle, artist: null), _song(2), _song(3)];
      await pumpSheet(tester, queue);

      expect(
        find.semantics.byPredicate((n) => n.label.contains(_fileTitle) && n.label.contains('Add to Favourites')),
        findsNothing,
      );
      expect(
        find.semantics.byPredicate((n) {
          final data = n.getSemanticsData();
          return data.hasAction(SemanticsAction.scrollDown) || data.hasAction(SemanticsAction.scrollUp);
        }),
        findsNothing,
        reason: 'the swipe-down detector is not a scrollable for a screen reader',
      );

      // Header, then the track as one stop.
      expect(find.semantics.byLabel('Now Playing\n1 of 3'), isSemantics(isHeader: true));
      final track = _labelled(_fileTitle);
      expect(track, findsOne);
      expect(_data(track).label, '$_fileTitle\nUnknown artist');
      expect(_labelled('Unknown artist'), findsOne);
      handle.dispose();
    });

    testWidgets('buttons stay their own nodes and the slider reads the position once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSheet(tester, [_song(1, title: _fileTitle), _song(2), _song(3)]);

      final heart = find.semantics.byLabel('Add to Favourites');
      expect(heart, findsOne);
      expect(heart, isSemantics(isButton: true, hasTapAction: true));
      expect(_data(heart).tooltip, isEmpty);

      for (final tooltip in [
        'Collapse Now Playing',
        'Playback Speed',
        'View Queue',
        'More options',
        'Shuffle disabled',
        'Previous track',
        'Play',
        'Next track',
        'Repeat mode: off',
      ]) {
        final button = find.semantics.byPredicate((n) => n.tooltip == tooltip);
        expect(button, findsOne, reason: tooltip);
        expect(button, isSemantics(isButton: true, hasTapAction: true), reason: tooltip);
      }

      // The node the platform gets: the Slider's own node is merged into the
      // one that carries its name.
      final slider = find.semantics.byPredicate(
        (n) => !n.isMergedIntoParent && n.getSemanticsData().flagsCollection.isSlider,
      );
      expect(slider, findsOne);
      expect(_data(slider).label, 'Playback position', reason: 'the one control that had no name');
      expect(slider, isSemantics(hasIncreaseAction: true, hasDecreaseAction: true));
      expect(_labelled('Playback position'), findsOne);
      expect(_data(slider).value, '1:46 of 5:00');
      expect(_data(slider).increasedValue, '2:01 of 5:00');
      // The labels under the bar are not read on top of the slider.
      expect(_labelled('1:46'), findsNothing);
      expect(_labelled('5:00'), findsNothing);
      // They still show: elapsed, and the time left (DESIGN.md 7.8).
      expect(find.text('1:46'), findsOneWidget);
      expect(find.text('-3:14'), findsOneWidget);
      expect(_labelled('3:14'), findsNothing);
      handle.dispose();
    });

    testWidgets('a file-style title wraps after "_" and still reads its real name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSheet(tester, [_song(1, title: _fileTitle)]);

      final shown = find.text(breakableTitle(_fileTitle));
      expect(shown, findsOneWidget);
      expect(tester.widget<Text>(shown).semanticsLabel, _fileTitle);
      expect(tester.widget<Text>(shown).maxLines, 2);
      expect(find.semantics.byPredicate((n) => n.label.contains('​')), findsNothing);
      handle.dispose();
    });
  });

  group('queue', () {
    Future<_FakePlayback> pumpQueue(WidgetTester tester, List<MediaItem> queue, {int current = 0}) async {
      _mockNoArtwork(tester);
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final playback = _FakePlayback(_playing(queue, index: current));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackNotifierProvider.overrideWith(() => playback)],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: QueueSheet())),
        ),
      );
      await tester.pump();
      return playback;
    }

    testWidgets('each queue row is one node with the current track selected', (tester) async {
      final handle = tester.ensureSemantics();
      final queue = [_song(1, title: _fileTitle, artist: null), _song(2), _song(3)];
      await pumpQueue(tester, queue);

      final current = find.semantics.byLabel('Song: $_fileTitle by Unknown artist');
      expect(current, findsOne);
      expect(current, isSemantics(isButton: true, isSelected: true, hasTapAction: true));
      expect(_labelled(_fileTitle), findsOne);
      expect(_labelled('Now playing'), findsNothing, reason: 'the selected state says it, once');

      for (final n in [2, 3]) {
        final row = find.semantics.byLabel('Song: Song $n by Test Artist');
        expect(row, findsOne);
        expect(row, isSemantics(isButton: true, isSelected: false, hasTapAction: true));
        expect(_data(row).customSemanticsActionIds, isNotEmpty, reason: 'Move up / down stay on the row');
      }

      final removes = find.semantics.byPredicate((n) => n.tooltip == 'Remove from queue');
      expect(removes, findsExactly(queue.length));
      for (final node in removes.evaluate()) {
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.label, isEmpty);
      }
      handle.dispose();
    });

    testWidgets('tapping a row node jumps to that track', (tester) async {
      final handle = tester.ensureSemantics();
      final playback = await pumpQueue(tester, [_song(1), _song(2), _song(3)]);

      tester.semantics.tap(find.semantics.byLabel('Song: Song 3 by Test Artist'));
      await tester.pump();
      expect(playback.skippedTo, [2]);
      expect(playback.skippedToIds, ['song_3'], reason: 'the row names its song (F6)');
      handle.dispose();
    });

    testWidgets('the header is one heading stop, read before Close, with one track or many', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpQueue(tester, [_song(1)]);
      final one = find.semantics.byLabel('Current queue\n1 track');
      expect(one, findsOne);
      expect(one, isSemantics(isHeader: true));
      expect(find.semantics.byLabel('1 track'), findsNothing, reason: 'the subtitle is no longer read first, alone');

      // A fresh ProviderScope (the same one would keep the first queue).
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpQueue(tester, [_song(1), _song(2), _song(3)]);
      expect(find.semantics.byLabel('Current queue\n3 tracks · Drag to reorder'), isSemantics(isHeader: true));
      handle.dispose();
    });

    testWidgets('with a screen reader on, a row has no swipe (scroll) actions that would remove it', (tester) async {
      final handle = tester.ensureSemantics();
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        accessibleNavigation: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final queue = [_song(1), _song(2), _song(3)];
      await pumpQueue(tester, queue);

      expect(
        find.semantics.byPredicate((n) {
          final data = n.getSemanticsData();
          return data.hasAction(SemanticsAction.scrollLeft) || data.hasAction(SemanticsAction.scrollRight);
        }),
        findsNothing,
        reason: '"scroll forward" on a row used to remove that track',
      );
      final row = find.semantics.byLabel('Song: Song 2 by Test Artist');
      expect(row, isSemantics(isButton: true, hasTapAction: true));
      expect(_data(row).customSemanticsActionIds, hasLength(4), reason: 'Move to the start / up / down / to the end');
      // Removing stays possible, on purpose, through the row's own button.
      expect(find.semantics.byPredicate((n) => n.tooltip == 'Remove from queue'), findsExactly(queue.length));
      handle.dispose();
    });

    testWidgets('without a screen reader the swipe to remove still works', (tester) async {
      final playback = _RemovingPlayback(_playing([_song(1), _song(2), _song(3)]));
      _mockNoArtwork(tester);
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackNotifierProvider.overrideWith(() => playback)],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: QueueSheet())),
        ),
      );
      await tester.pump();

      await tester.drag(find.text('Song 2'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(playback.removed, [1]);
      expect(playback.removedIds, ['song_2']);
    });
  });
}
