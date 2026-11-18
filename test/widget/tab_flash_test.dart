import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_screen.dart';
import 'package:mediahub/shared/widgets/empty_state_widget.dart';
import 'package:mocktail/mocktail.dart';

class MockLibraryRepository extends Mock implements LibraryRepository {}
class MockMediaPermissionService extends Mock implements MediaPermissionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(MediaSortOption.title);
  });

  late MockLibraryRepository mockRepo;
  late MockMediaPermissionService mockPermService;

  setUp(() {
    mockRepo = MockLibraryRepository();
    mockPermService = MockMediaPermissionService();

    when(() => mockPermService.checkAudioPermission())
        .thenAnswer((_) async => MediaPermissionState.granted);
    when(() => mockPermService.checkVideoPermission())
        .thenAnswer((_) async => MediaPermissionState.granted);
    when(() => mockRepo.watchPlaylists())
        .thenAnswer((_) => Stream.value([]));
    when(() => mockRepo.watchAlbums(searchQuery: any(named: 'searchQuery')))
        .thenAnswer((_) => Stream.value([]));
    when(() => mockRepo.watchArtists(searchQuery: any(named: 'searchQuery')))
        .thenAnswer((_) => Stream.value([]));
    when(() => mockRepo.watchFavorites(searchQuery: any(named: 'searchQuery')))
        .thenAnswer((_) => Stream.value([]));
  });

  testWidgets('MusicScreen shows loader while loading, then EmptyState only after empty emission',
      (tester) async {
    final streamController = StreamController<List<MediaItem>>.broadcast();
    when(() => mockRepo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => streamController.stream);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(mockRepo),
          mediaPermissionServiceProvider.overrideWithValue(mockPermService),
        ],
        child: const MaterialApp(
          home: MusicScreen(),
        ),
      ),
    );

    // Initial microtask run for permission check
    await tester.pump();

    // At loading stage: CircularProgressIndicator should be visible, NOT EmptyStateWidget
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(EmptyStateWidget), findsNothing);
    expect(find.text('No songs yet'), findsNothing);

    // Now emit empty list from DB stream
    streamController.add([]);
    await tester.pump();

    // After emission: EmptyStateWidget with 'No songs yet' is shown
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(EmptyStateWidget), findsOneWidget);
    expect(find.text('No songs yet'), findsOneWidget);

    await streamController.close();
  });

  testWidgets('the empty Songs tab offers a Scan device button that scans', (tester) async {
    when(() => mockRepo.scanDeviceMedia()).thenAnswer((_) async {});
    when(() => mockRepo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => Stream.value(const []));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(mockRepo),
          mediaPermissionServiceProvider.overrideWithValue(mockPermService),
        ],
        child: const MaterialApp(home: MusicScreen()),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('No songs yet'), findsOneWidget);
    expect(find.text('Find the songs saved on this phone.'), findsOneWidget);
    expect(find.text('Search your music'), findsOneWidget, reason: 'a hint short enough to stay whole');

    // Forget the automatic scan on open, if any; only the tap counts.
    clearInteractions(mockRepo);
    await tester.tap(find.text('Scan device'));
    await tester.pump();
    verify(() => mockRepo.scanDeviceMedia()).called(1);
  });
}
