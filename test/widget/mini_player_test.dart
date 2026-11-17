import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart';
import 'package:mediahub/features/music_player/mini_player.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

/// A fixed external (YouTube) state, as the audio handler would report it.
class _FixedExternal extends ExternalMediaNotifier {
  _FixedExternal(this.value);
  final ExternalMediaSnapshot? value;

  @override
  ExternalMediaSnapshot? build() => value;
}

/// Local playback without the database behind it.
class _QuietPlayback extends PlaybackNotifier {
  @override
  PlaybackState build() => PlaybackState(updatedAt: DateTime(2026));
}

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

  group('while YouTube (the Online tab) owns the media session', () {
    const yt = ExternalMediaSnapshot(
      id: 'online:dQw4w9WgXcQ',
      title: 'Never Gonna Give You Up',
      artist: 'Rick Astley',
      playing: true,
      canSkipNext: true,
    );
    final localSong = MediaItem(
      id: 'song_1',
      uri: 'file:///song.mp3',
      mediaType: MediaType.audio,
      title: 'Local Song',
      artist: 'Local Artist',
      durationMs: 1000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

    Future<GoRouter> pump(WidgetTester tester, {required ExternalMediaSnapshot? external, bool hideExternal = false}) async {
      final router = GoRouter(
        initialLocation: '/music',
        routes: [
          GoRoute(
            path: '/music',
            builder: (context, state) => Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer(hideExternal: hideExternal))),
          ),
          GoRoute(path: '/online', builder: (context, state) => const Scaffold(body: Text('Online page'))),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalMediaProvider.overrideWith(() => _FixedExternal(external)),
            playbackNotifierProvider.overrideWith(_QuietPlayback.new),
            currentMediaItemProvider.overrideWith((ref) => localSong),
            isPlayingProvider.overrideWith((ref) => false),
            throttledPositionStreamProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      return router;
    }

    testWidgets('shows the video, a YOUTUBE tag, pause and next instead of the paused local track', (tester) async {
      await pump(tester, external: yt);
      expect(find.text('Never Gonna Give You Up'), findsOneWidget);
      expect(find.text('Rick Astley'), findsOneWidget);
      expect(find.text('YOUTUBE'), findsOneWidget);
      expect(find.text('Local Song'), findsNothing);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byTooltip('Next'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('next is only offered when the page has one; paused shows Play', (tester) async {
      await pump(
        tester,
        external: const ExternalMediaSnapshot(id: 'online:x', title: 'Short', playing: false, canSkipNext: false),
      );
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Next'), findsNothing);
    });

    testWidgets('tapping the card opens the Online tab', (tester) async {
      await pump(tester, external: yt);
      await tester.tap(find.byKey(const ValueKey('mini_player_external')));
      await tester.pumpAndSettle();
      expect(find.text('Online page'), findsOneWidget);
    });

    testWidgets('on the Online tab itself the card is hidden', (tester) async {
      await pump(tester, external: yt, hideExternal: true);
      expect(find.text('Never Gonna Give You Up'), findsNothing);
      expect(find.text('Local Song'), findsNothing);
    });

    testWidgets('back to local mode: the local track shows again', (tester) async {
      await pump(tester, external: null);
      expect(find.text('Local Song'), findsOneWidget);
      expect(find.text('YOUTUBE'), findsNothing);
    });
  });
}
