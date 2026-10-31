import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/music_player/mini_player.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

void main() {
  testWidgets('Mini-player is hidden when queue is empty, and appears when item is set',
      (tester) async {
    final song = MediaItem(
      id: 'song_1',
      uri: 'file:///song.mp3',
      mediaType: MediaType.audio,
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      durationMs: 354000,
      sizeBytes: 8000000,
      dateAdded: DateTime.now(),
    );

    final container = ProviderContainer(
      overrides: [
        currentMediaItemProvider.overrideWith((ref) => null),
        isPlayingProvider.overrideWith((ref) => false),
        throttledPositionStreamProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: MiniPlayer(),
          ),
        ),
      ),
    );

    // Mini-player should be hidden (SizedBox.shrink)
    expect(find.text('Bohemian Rhapsody'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Now update container with a playing item
    final containerPlaying = ProviderContainer(
      overrides: [
        currentMediaItemProvider.overrideWith((ref) => song),
        isPlayingProvider.overrideWith((ref) => true),
        throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 15))),
      ],
    );
    addTearDown(containerPlaying.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: containerPlaying,
        child: const MaterialApp(
          home: Scaffold(
            body: MiniPlayer(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Mini-player shows title, artist, play/pause icon, progress line
    expect(find.text('Bohemian Rhapsody'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('Tapping the mini-player twice opens only one Now Playing sheet',
      (tester) async {
    int openCount = 0;
    DateTime lastTap = DateTime.fromMillisecondsSinceEpoch(0);
    bool isOpen = false;

    void openSheet() {
      final now = DateTime.now();
      if (now.difference(lastTap).inMilliseconds < 400) return;
      lastTap = now;
      if (isOpen) return;
      isOpen = true;
      openCount++;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: openSheet,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      ),
    );

    // Tap rapidly twice
    await tester.tap(find.text('Tap Me'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Tap Me'), warnIfMissed: false);
    await tester.pump();

    // Debounce & single-open guard ensures sheet opened exactly once
    expect(openCount, equals(1));
  });
}
