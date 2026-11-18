import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as d;
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';

/// Lets drift deliver stream events (real async) and rebuilds the widget tree.
Future<void> settleFavorite(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

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
      expect(find.bySemanticsLabel('Add to Liked songs'), findsOneWidget);

      // Tap favorite button
      await tester.tap(find.bySemanticsLabel('Add to Liked songs'));
      await tester.pump(); // Start animation & trigger toggle

      // Verify floating snackbar
      expect(find.text('Added to Liked songs'), findsOneWidget);
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

      // unmount so drift's stream clean-up timer fires before the test ends
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Heart follows the database even when the passed value is stale', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            libraryRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              // the queue snapshot says "not favorite" and never changes
              body: FavoriteFeedbackButton(itemId: 'test_song_1', isFavorite: false),
            ),
          ),
        ),
      );
      await settleFavorite(tester);
      expect(find.bySemanticsLabel('Add to Liked songs'), findsOneWidget);

      // The song becomes a favorite somewhere else (context menu, another screen ...)
      await tester.runAsync(() => repo.toggleFavorite('test_song_1'));
      await settleFavorite(tester);

      expect(find.bySemanticsLabel('Remove from Liked songs'), findsOneWidget);
      // The filled heart is favourite pink, not the (coral) error colour.
      final heart = tester.widget<Icon>(find.byIcon(Icons.favorite_rounded));
      expect(heart.color, AppPalette.dark.favorite);
      expect(heart.color, isNot(AppPalette.dark.error));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
