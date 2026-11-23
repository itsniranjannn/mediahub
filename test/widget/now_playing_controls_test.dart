import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/music_player/now_playing_sheet.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';

const _channel = MethodChannel('mediahub/media_store');

MediaItem _song(int n) => MediaItem(
      id: 'song_$n',
      uri: 'content://media/external/audio/media/$n',
      mediaType: MediaType.audio,
      title: 'Song $n',
      artist: 'Test Artist',
      durationMs: 300000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

domain.PlaybackState _at(List<MediaItem> queue, int index) => domain.PlaybackState(
      currentItemId: queue[index].id,
      queue: queue,
      originalQueue: queue,
      queueIndex: index,
      duration: const Duration(minutes: 5),
      updatedAt: DateTime(2026),
    );

/// Records the controls; [moveOnSkip] makes Next / Previous change the song
/// like the engine would.
class _Playback extends PlaybackNotifier {
  _Playback(this._initial, {this.moveOnSkip = false});

  final domain.PlaybackState _initial;
  final bool moveOnSkip;
  final List<String> calls = [];

  @override
  domain.PlaybackState build() => _initial;

  void _move(int by) {
    final i = (state.queueIndex + by).clamp(0, state.queue.length - 1);
    state = _at(state.queue, i);
  }

  @override
  Future<void> skipToNext() async {
    calls.add('next');
    if (moveOnSkip) _move(1);
  }

  @override
  Future<void> skipToPrevious() async {
    calls.add('previous');
    if (moveOnSkip) _move(-1);
  }

  @override
  Future<void> seek(Duration pos) async => calls.add('seek ${pos.inSeconds}');

  @override
  void setSleepTimer(Duration duration) => calls.add('sleep ${duration.inMinutes}');

  @override
  void setSleepTimerAtEndOfTrack() => calls.add('sleep end of song');

  @override
  void cancelSleepTimer() => calls.add('sleep off');
}

class _FixedSleep extends SleepTimerNotifier {
  _FixedSleep(this.value);
  final domain.SleepTimerStatus value;

  @override
  domain.SleepTimerStatus build() => value;
}

void main() {
  setUp(ArtworkService.instance.clearCache);
  tearDown(ArtworkService.instance.clearCache);

  Future<_Playback> pumpSheet(
    WidgetTester tester, {
    required domain.PlaybackState state,
    bool moveOnSkip = false,
    Stream<Duration>? positions,
    domain.SleepTimerStatus sleep = domain.SleepTimerStatus.off,
    Size size = const Size(360, 776),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
    final playback = _Playback(state, moveOnSkip: moveOnSkip);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackNotifierProvider.overrideWith(() => playback),
          throttledPositionStreamProvider
              .overrideWith((ref) => positions ?? Stream.value(const Duration(seconds: 15))),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
          sleepTimerProvider.overrideWith(() => _FixedSleep(sleep)),
        ],
        child: MaterialApp(theme: theme ?? AppTheme.darkTheme, home: const NowPlayingSheet()),
      ),
    );
    await tester.pumpAndSettle();
    return playback;
  }

  group('F8 seek bar', () {
    testWidgets('after a release the thumb stays where it was let go until the player catches up', (tester) async {
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final playback = await pumpSheet(tester, state: _at([_song(1)], 0), positions: positions.stream);
      positions.add(const Duration(seconds: 15));
      await tester.pump();
      await tester.pump();
      double value() => tester.widget<Slider>(find.byType(Slider)).value;
      expect(value(), 15000);

      // Drag to about three quarters and let go.
      final slider = tester.getRect(find.byType(Slider));
      await tester.dragFrom(Offset(slider.left + 4, slider.center.dy), Offset(slider.width * 0.75, 0));
      await tester.pump();
      final released = value();
      expect(released, greaterThan(200000));
      expect(playback.calls.single, 'seek ${released ~/ 1000}');

      // The stream still has the old time for a moment: the thumb holds.
      positions.add(const Duration(seconds: 16));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(value(), released, reason: 'it used to snap back to 0:16 here');

      // The player reports the new time: the thumb follows the stream again.
      final landed = Duration(milliseconds: released.toInt() + 300);
      positions.add(landed);
      await tester.pump();
      await tester.pump();
      expect(value(), landed.inMilliseconds.toDouble());
    });

    testWidgets('the hold ends after 600 ms even if the player never reports the new time', (tester) async {
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      await pumpSheet(tester, state: _at([_song(1)], 0), positions: positions.stream);
      positions.add(const Duration(seconds: 15));
      await tester.pump();
      final slider = tester.getRect(find.byType(Slider));
      await tester.dragFrom(Offset(slider.left + 4, slider.center.dy), Offset(slider.width * 0.5, 0));
      await tester.pump();
      double value() => tester.widget<Slider>(find.byType(Slider)).value;
      expect(value(), greaterThan(100000));
      await tester.pump(const Duration(milliseconds: 650));
      expect(value(), 15000);
    });
  });

  group('landscape', () {
    for (final (size, scale) in [(const Size(800, 360), 1.0), (const Size(740, 360), 1.0), (const Size(915, 412), 1.3)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} at ${scale}x: cover left, controls in view without scrolling',
          (tester) async {
        final queue = [_song(1), _song(2)];
        await pumpSheet(tester, state: _at(queue, 0), size: size, textScale: scale);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('now_playing_two_columns')), findsOneWidget);
        final cover = tester.getRect(find.byKey(const ValueKey('now_playing_cover_swipe')));
        for (final tip in ['Previous track', 'Play', 'Next track', 'View Queue']) {
          final r = tester.getRect(find.byTooltip(tip));
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$tip below the fold');
          expect(r.left, greaterThan(cover.right), reason: '$tip right of the cover');
        }
        expect(tester.getRect(find.byType(Slider)).bottom, lessThanOrEqualTo(size.height));
        expect(find.text('Song 1').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('F10 swipe the cover to skip', () {
    final queue = [_song(1), _song(2), _song(3)];
    final cover = find.byKey(const ValueKey('now_playing_cover_swipe'));

    testWidgets('left is Next, right is Previous; the cover ends in its place', (tester) async {
      final playback = await pumpSheet(tester, state: _at(queue, 1), moveOnSkip: true);
      final home = tester.getRect(find.byType(Hero));
      await tester.drag(cover, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(playback.calls, ['next']);
      expect(find.text('Song 3'), findsOneWidget);
      expect(tester.getRect(find.byType(Hero)), home);

      await tester.drag(cover, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(playback.calls, ['next', 'previous']);
      expect(find.text('Song 2'), findsOneWidget);
      expect(tester.getRect(find.byType(Hero)), home);
    });

    testWidgets('a short drag springs back; Next is not offered on the last song with repeat off', (tester) async {
      final playback = await pumpSheet(tester, state: _at(queue, 2));
      final home = tester.getRect(find.byType(Hero));
      await tester.drag(cover, const Offset(-40, 0));
      await tester.pumpAndSettle();
      await tester.drag(cover, const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(playback.calls, isEmpty);
      expect(tester.getRect(find.byType(Hero)), home);
    });

    testWidgets('a Previous that only restarts the song leaves the cover in place', (tester) async {
      final playback = await pumpSheet(tester, state: _at(queue, 1));
      final home = tester.getRect(find.byType(Hero));
      await tester.drag(cover, const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(playback.calls, ['previous']);
      expect(tester.getRect(find.byType(Hero)), home);
    });
  });

  group('F9 sleep timer on Now Playing', () {
    testWidgets('the moon opens the sheet; a preset sets the timer', (tester) async {
      final playback = await pumpSheet(tester, state: _at([_song(1)], 0));
      expect(find.byKey(const ValueKey('sleep_chip')), findsNothing);
      await tester.tap(find.byTooltip('Sleep timer'));
      await tester.pumpAndSettle();
      for (final label in ['5 minutes', '15 minutes', '30 minutes', '45 minutes', '1 hour', 'End of song']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // The sheet follows the app theme (outside the stage).
      expect(Theme.of(tester.element(find.text('15 minutes'))).brightness, Brightness.dark);
      await tester.tap(find.text('15 minutes'));
      await tester.pumpAndSettle();
      expect(playback.calls, ['sleep 15']);
      expect(find.text('15 minutes'), findsNothing, reason: 'the sheet closed');

      await tester.tap(find.byTooltip('Sleep timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End of song'));
      await tester.pumpAndSettle();
      expect(playback.calls, ['sleep 15', 'sleep end of song']);
    });

    testWidgets('while it runs: "SLEEP 12:30" under the artist, the countdown in figureLarge, Turn off',
        (tester) async {
      final status = domain.SleepTimerStatus(
        endsAt: DateTime(2026, 1, 1, 22, 30),
        remaining: const Duration(minutes: 12, seconds: 30),
      );
      final playback = await pumpSheet(tester, state: _at([_song(1)], 0), sleep: status);
      expect(find.text('SLEEP 12:30'), findsOneWidget);
      final chip = tester.getRect(find.byKey(const ValueKey('sleep_chip')));
      expect(chip.top, greaterThan(tester.getRect(find.text('Test Artist')).bottom));
      expect(chip.bottom, lessThan(tester.getRect(find.byType(Slider)).top));
      expect(find.byTooltip('Sleep timer on'), findsOneWidget);

      await tester.tap(find.byTooltip('Sleep timer on'));
      await tester.pumpAndSettle();
      final countdown = tester.widget<Text>(find.byKey(const ValueKey('sleep_countdown')));
      expect(countdown.data, '12:30');
      expect(countdown.style!.fontSize, 28, reason: 'figureLarge');
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(playback.calls, ['sleep off']);
    });

    testWidgets('"SLEEP · END OF SONG" for the end-of-song timer', (tester) async {
      await pumpSheet(tester, state: _at([_song(1)], 0), sleep: const domain.SleepTimerStatus(endOfTrack: true));
      expect(find.text('SLEEP · END OF SONG'), findsOneWidget);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('holds at 1.3x text on $width dp with the chip on', (tester) async {
        final status = domain.SleepTimerStatus(
          endsAt: DateTime(2026, 1, 1, 23),
          remaining: const Duration(hours: 1, minutes: 2, seconds: 3),
        );
        await pumpSheet(tester,
            state: _at([_song(1), _song(2)], 0), sleep: status, size: Size(width, 640), textScale: 1.3);
        expect(tester.takeException(), isNull);
        expect(find.text('SLEEP 1:02:03'), findsOneWidget);
        expect(find.byTooltip('Sleep timer on'), findsOneWidget);
      });
    }

    testWidgets('the sheet is on paper in the light theme, and holds at 1.3x text on 320 dp', (tester) async {
      final status = domain.SleepTimerStatus(
        endsAt: DateTime(2026, 1, 1, 23),
        remaining: const Duration(minutes: 44, seconds: 59),
      );
      await pumpSheet(tester,
          state: _at([_song(1)], 0),
          sleep: status,
          theme: AppTheme.lightTheme,
          size: const Size(320, 640),
          textScale: 1.3);
      await tester.tap(find.byTooltip('Sleep timer on'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(Theme.of(tester.element(find.text('Turn off'))).brightness, Brightness.light);
      expect(find.text('44:59'), findsOneWidget);
      expect(find.text('End of song'), findsOneWidget);
      // The stage behind it stays ink.
      expect(Theme.of(tester.element(find.byType(Slider))).brightness, Brightness.dark);
    });

    test('countdown text', () {
      expect(sleepCountdown(const Duration(minutes: 12, seconds: 30)), '12:30');
      expect(sleepCountdown(const Duration(seconds: 59, milliseconds: 1)), '1:00');
      expect(sleepCountdown(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(sleepCountdown(Duration.zero), '0:00');
    });
  });
}
