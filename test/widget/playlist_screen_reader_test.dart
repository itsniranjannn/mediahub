// Playlist rows under TalkBack / VoiceOver: the swipe that removes a song
// used to reach a screen reader as unlabelled scroll actions on the row, so
// one "scroll forward" deleted the song from the playlist. With a screen
// reader on, the swipe is off and the row has a real "Remove from playlist"
// button instead (a custom action would split the row into two nodes).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mocktail/mocktail.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

const _channel = MethodChannel('mediahub/media_store');

MediaItem _song(int n) => MediaItem(
      id: 'song_$n',
      uri: 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: 'Song $n',
      artist: 'Test Artist',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

final _songs = [_song(1), _song(2), _song(3)];
final _playlist = Playlist(
  id: 'pl_1',
  name: 'Road trip',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  songCount: 3,
);

void main() {
  late _MockLibraryRepository repo;

  setUp(() {
    ArtworkService.instance.clearCache();
    repo = _MockLibraryRepository();
    when(() => repo.watchPlaylistSongs(_playlist.id)).thenAnswer((_) => Stream.value(_songs));
    when(() => repo.watchPlaylistTracks(_playlist.id)).thenAnswer(
      (_) => Stream.value([for (var i = 0; i < _songs.length; i++) PlaylistTrack(position: i, item: _songs[i])]),
    );
    when(() => repo.watchPlaylist(_playlist.id)).thenAnswer((_) => Stream.value(_playlist));
    when(() => repo.removeSongFromPlaylist(any(), any(), any())).thenAnswer((_) async {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    ArtworkService.instance.clearCache();
  });

  Future<void> pumpPlaylist(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          currentMediaItemProvider.overrideWith((ref) => null),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: PlaylistDetailScreen(playlist: _playlist)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void screenReaderOn(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  bool hasSwipeActions(SemanticsNode node) {
    final data = node.getSemanticsData();
    return data.hasAction(SemanticsAction.scrollLeft) || data.hasAction(SemanticsAction.scrollRight);
  }

  /// The custom action labels on [row].
  List<String> customActions(SemanticsFinder row) {
    final ids = row.evaluate().single.getSemanticsData().customSemanticsActionIds ?? const <int>[];
    return [for (final id in ids) CustomSemanticsAction.getAction(id)!.label!];
  }

  SemanticsFinder removeButtons() => find.semantics.byPredicate((n) => n.tooltip == 'Remove from playlist');

  testWidgets('with a screen reader on: no scroll actions, and a "Remove from playlist" button', (tester) async {
    final handle = tester.ensureSemantics();
    screenReaderOn(tester);
    await pumpPlaylist(tester);

    expect(find.semantics.byPredicate(hasSwipeActions), findsNothing, reason: '"scroll forward" deleted the song');

    // Still one stop per row: its label, its tap and the list's moves.
    final row = find.semantics.byLabel(RegExp('^Song: Song 2 by Test Artist'));
    expect(row, findsOne);
    expect(row, isSemantics(isButton: true, hasTapAction: true));
    expect(customActions(row), containsAll(<String>['Move up', 'Move down']));
    expect(
      find.semantics.byPredicate(
        (n) => n.label.isEmpty && (n.getSemanticsData().customSemanticsActionIds?.isNotEmpty ?? false),
      ),
      findsNothing,
      reason: 'no unlabelled node holding the moves around the row',
    );

    // Removing is a button of its own on every row, as in the queue.
    final removes = removeButtons();
    expect(removes, findsExactly(_songs.length));
    for (final node in removes.evaluate()) {
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    await tester.tap(find.byTooltip('Remove from playlist').at(1));
    await tester.pump();
    verify(() => repo.removeSongFromPlaylist(_playlist.id, 'song_2', 1)).called(1);
    handle.dispose();
  });

  testWidgets('without a screen reader: no extra button, and the swipe still removes the song', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlaylist(tester);
    expect(find.byTooltip('Remove from playlist'), findsNothing);
    expect(removeButtons(), findsNothing);
    handle.dispose();

    await tester.drag(find.text('Song 3'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    verify(() => repo.removeSongFromPlaylist(_playlist.id, 'song_3', 2)).called(1);
  });
}
