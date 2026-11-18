import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart';
import 'package:mediahub/features/music_player/mini_player.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

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

  // DESIGN.md 7.7 and 7.17: the dock row and the playback basics.
  group('the Ink Dock row', () {
    final songs = [
      for (var i = 1; i <= 3; i++)
        MediaItem(
          id: 'song_$i',
          uri: 'file:///song_$i.mp3',
          mediaType: MediaType.audio,
          title: 'Song $i',
          artist: 'Artist $i',
          durationMs: 200000,
          sizeBytes: 1,
          dateAdded: DateTime(2026),
        ),
    ];

    PlaybackState at(int index, {PlaybackRepeatMode repeat = PlaybackRepeatMode.off}) => PlaybackState(
          currentItemId: songs[index].id,
          queue: songs,
          originalQueue: songs,
          queueIndex: index,
          repeatMode: repeat,
          updatedAt: DateTime(2026),
        );

    Future<_RecordingPlayback> pumpRow(
      WidgetTester tester,
      PlaybackState state, {
      ThemeData? theme,
      bool inDock = true,
      double width = 360,
      double textScale = 1,
    }) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (textScale != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final playback = _RecordingPlayback(state);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalMediaProvider.overrideWith(() => _FixedExternal(null)),
            playbackNotifierProvider.overrideWith(() => playback),
            throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 50))),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.darkTheme,
            home: Scaffold(
              bottomNavigationBar: inDock
                  ? const InkDock(miniPlayer: MiniPlayer(), navigation: SizedBox(height: InkDock.navigationHeight))
                  : const MiniPlayer(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return playback;
    }

    IconButton button(WidgetTester tester, String tooltip) => tester.widget<IconButton>(
          find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).first,
        );

    testWidgets('previous, a 44 dp Volt play disc and next; Next is disabled on the last track with repeat off',
        (tester) async {
      await pumpRow(tester, at(1));
      expect(find.byType(VoltDisc), findsOneWidget);
      expect(tester.widget<VoltDisc>(find.byType(VoltDisc)).size, VoltDisc.small);
      expect(button(tester, 'Previous').onPressed, isNotNull);
      expect(button(tester, 'Next').onPressed, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpRow(tester, at(2));
      expect(button(tester, 'Next').onPressed, isNull, reason: 'the last track, repeat off');
      expect(button(tester, 'Previous').onPressed, isNotNull, reason: 'Previous restarts or goes back');

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpRow(tester, at(2, repeat: PlaybackRepeatMode.all));
      expect(button(tester, 'Next').onPressed, isNotNull, reason: 'repeat on: Next wraps');
    });

    testWidgets('a disabled Next is disabled for a screen reader too', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRow(tester, at(2));
      final next = find.semantics.byPredicate((n) => n.tooltip == 'Next');
      expect(next, isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, hasTapAction: false));
      final card = find.semantics.byLabel('Mini player: Song 3 by Artist 3');
      expect(card, isSemantics(isButton: true, hasTapAction: true, hasLongPressAction: true));
      handle.dispose();
    });

    testWidgets('the buttons and swipes skip; a swipe towards a disabled Next springs back', (tester) async {
      final playback = await pumpRow(tester, at(1));
      await tester.tap(find.byTooltip('Next'));
      await tester.tap(find.byTooltip('Previous'));
      await tester.tap(find.byTooltip('Play'));
      expect(playback.calls, ['next', 'previous', 'play']);

      final row = find.byKey(const ValueKey('mini_player_gesture_detector'));
      await tester.fling(row, const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      await tester.fling(row, const Offset(200, 0), 1000);
      await tester.pumpAndSettle();
      expect(playback.calls, ['next', 'previous', 'play', 'next', 'previous']);

      await tester.pumpWidget(const SizedBox.shrink());
      final last = await pumpRow(tester, at(2));
      await tester.fling(row, const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      expect(last.calls, isEmpty);
    });

    testWidgets('ink in the light theme: dock colours and Volt on the dock', (tester) async {
      await pumpRow(tester, at(0), theme: AppTheme.lightTheme);
      const ink = AppPalette.dark;
      final title = tester.widget<Text>(find.text('Song 1'));
      expect(title.style!.color, ink.onDock);
      expect(title.style!.fontSize, 15);
      expect(tester.widget<Text>(find.text('Artist 1')).style!.color, ink.onDockMuted);
      expect(Theme.of(tester.element(find.text('Song 1'))).brightness, Brightness.dark);
      final progress = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progress.color, ink.primary);
      expect(progress.backgroundColor, ink.dockLine);
      expect(progress.minHeight, 2);
      // Along the dock's top edge.
      expect(tester.getRect(find.byType(LinearProgressIndicator)).top, tester.getRect(find.byType(InkDock)).top);
    });

    testWidgets('away from the dock it brings its own ink slab', (tester) async {
      await pumpRow(tester, at(0), theme: AppTheme.lightTheme, inDock: false);
      expect(Theme.of(tester.element(find.text('Song 1'))).brightness, Brightness.dark);
      expect(
        find.byWidgetPredicate((w) => w is Material && w.color == AppPalette.dark.dock),
        findsOneWidget,
      );
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('holds at 1.3x text on $width dp', (tester) async {
        await pumpRow(tester, at(1), width: width, textScale: 1.3);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Next'), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('mini_player_gesture_detector'))).height,
            greaterThanOrEqualTo(InkDock.miniPlayerHeight));
      });
    }
  });
}

/// Local playback that records the transport calls instead of playing.
class _RecordingPlayback extends PlaybackNotifier {
  _RecordingPlayback(this._initial);

  final PlaybackState _initial;
  final List<String> calls = [];

  @override
  PlaybackState build() => _initial;

  @override
  Future<void> skipToNext() async => calls.add('next');

  @override
  Future<void> skipToPrevious() async => calls.add('previous');

  @override
  Future<void> togglePlayPause() async => calls.add(state.isPlaying ? 'pause' : 'play');
}
