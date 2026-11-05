import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as d;
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';

void main() {
  group('FavoriteFeedbackButton Widget Tests', () {
    late AppDatabase db;
    late LibraryRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepositoryImpl(db);

      await db.into(db.mediaItemsTable).insert(
        MediaItemsTableCompanion.insert(
          id: 'test_song_1',
          uri: '/storage/test.mp3',
          mediaType: 'audio',
          title: 'Test Song',
          durationMs: 1000,
          sizeBytes: 100,
          dateAdded: DateTime.now(),
          isFavorite: const d.Value(false),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('Tapping favorite triggers 160ms animation, floating snackbar with Undo, and updates semantic label', (tester) async {
      bool isFav = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            libraryRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return FavoriteFeedbackButton(
                    itemId: 'test_song_1',
                    isFavorite: isFav,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Semantic label initial: "Add to favorites"
      expect(find.bySemanticsLabel('Add to favorites'), findsOneWidget);

      // Tap favorite button
      await tester.tap(find.bySemanticsLabel('Add to favorites'));
      await tester.pump(); // Start animation & trigger toggle

      // Verify floating snackbar
      expect(find.text('Added to Favorites'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);
      final snackBar = tester.widget<SnackBar>(snackBarFinder);
      expect(snackBar.behavior, equals(SnackBarBehavior.floating));
      expect(snackBar.margin, equals(const EdgeInsets.only(left: 16, right: 16, bottom: 76)));

      // Advance through 160ms scale animation
      await tester.pump(const Duration(milliseconds: 160));

      // DB state is updated
      final updated = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('test_song_1'))).getSingle();
      expect(updated.isFavorite, isTrue);

      // Tap Undo
      await tester.tap(find.text('Undo'));
      await tester.pump();

      final reverted = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('test_song_1'))).getSingle();
      expect(reverted.isFavorite, isFalse);

      // Dismiss snackbar and advance pending diagnostics throttle timer
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).hideCurrentSnackBar();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('Favorite heart updates live when favorite state changes', (tester) async {
      final favValueNotifier = ValueNotifier<bool>(false);
      addTearDown(favValueNotifier.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            libraryRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: favValueNotifier,
                builder: (context, val, _) {
                  return FavoriteFeedbackButton(
                    itemId: 'test_song_1',
                    isFavorite: val,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Add to favorites'), findsOneWidget);

      // Change state live
      favValueNotifier.value = true;
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Remove from favorites'), findsOneWidget);
    });
  });
}
