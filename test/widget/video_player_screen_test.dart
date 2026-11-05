import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/domain/repositories/video_engine.dart';
import 'package:mediahub/domain/repositories/video_progress_repository.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/video_player_screen.dart';

class FakeVideoEngine implements VideoEngine {
  final bool shouldFail;
  final String? failureMessage;
  final StreamController<Duration> _posController = StreamController<Duration>.broadcast();
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  final StreamController<String?> _errController = StreamController<String?>.broadcast();

  FakeVideoEngine({this.shouldFail = false, this.failureMessage});

  @override
  bool get isInitialized => !shouldFail;

  @override
  bool get isPlaying => false;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => const Duration(minutes: 5);

  @override
  double get aspectRatio => 16 / 9;

  @override
  Size get videoSize => const Size(1920, 1080);

  @override
  Stream<Duration> get positionStream => _posController.stream;

  @override
  Stream<bool> get isPlayingStream => _playingController.stream;

  @override
  Stream<String?> get errorStream => _errController.stream;

  @override
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain}) => const SizedBox.expand();

  @override
  Future<void> initialize(String uri) {
    if (shouldFail) {
      final msg = failureMessage ?? 'File is corrupt or missing';
      _errController.add(msg);
      return Future.error(Exception(msg));
    }
    return Future.value();
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> dispose() async {
    await _posController.close();
    await _playingController.close();
    await _errController.close();
  }
}

class FakeVideoProgressRepository implements VideoProgressRepository {
  @override
  Future<void> deleteProgress(String mediaId) async {}

  @override
  Future<VideoProgress?> getProgress(String mediaId) async => null;

  @override
  Future<List<VideoProgress>> getAllProgress() async => [];

  @override
  Future<void> saveProgress(VideoProgress progress) async {}

  @override
  Stream<List<VideoProgress>> watchAllProgress() => Stream.value([]);
}

class FakeLibraryRepository implements LibraryRepository {
  final List<String> unavailableMarked = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> updateAvailability(String id, MediaAvailability availability) async {
    if (availability == MediaAvailability.missing) {
      unavailableMarked.add(id);
    }
  }

  @override
  Future<void> recordPlay(String id) async {}

  @override
  Future<void> scanDeviceMedia() async {}

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<List<MediaItem>> getMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) async => [];

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) => Stream.value([]);
}

void main() {
  testWidgets('VideoPlayerScreen displays error state with message, safety note, and Back button', (WidgetTester tester) async {
    final testItem = MediaItem(
      id: 'bad-vid',
      title: 'Corrupt Video',
      artist: 'Unknown',
      durationMs: 60000,
      uri: 'file:///non/existent/path.mp4',
      mediaType: MediaType.video,
      sizeBytes: 1024,
      dateAdded: DateTime.now(),
    );

    final fakeLibraryRepo = FakeLibraryRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoEngineProvider.overrideWith((ref) => FakeVideoEngine(shouldFail: true, failureMessage: 'Cannot open file')),
          videoProgressRepositoryProvider.overrideWithValue(FakeVideoProgressRepository()),
          libraryRepositoryProvider.overrideWithValue(fakeLibraryRepo),
        ],
        child: MaterialApp(
          home: VideoPlayerScreen(item: testItem),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify error UI is displayed
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.textContaining('Cannot open file'), findsOneWidget);
    expect(find.textContaining('safe on your device'), findsOneWidget);
    expect(find.text('Back to Videos'), findsOneWidget);

    // Verify it marked missing file as unavailable in the library
    expect(fakeLibraryRepo.unavailableMarked, contains('bad-vid'));

    // Tap Back button
    await tester.tap(find.text('Back to Videos'));
    await tester.pump();
  });
}
