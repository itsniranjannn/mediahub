import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' show PlaybackRepeatMode;
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';

import 'fake_audio_player.dart';

domain.MediaItem _song(int i) => domain.MediaItem(
      id: 's$i',
      uri: 'content://media/external/audio/media/$i',
      mediaType: domain.MediaType.audio,
      title: 'Song $i',
      artist: 'Artist',
      album: 'Album',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

List<domain.MediaItem> _songs(int n) => [for (var i = 0; i < n; i++) _song(i)];

/// No cover lookups in these tests.
NowPlayingArt _noArt() => NowPlayingArt(cacheDirectory: () async => null);

/// Lets the chain, the streams and the fake player's timers run out.
Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

List<String> _ids(Iterable<dynamic> items) => [for (final m in items) (m as dynamic).id as String];

/// What the user should see after the presses, worked out independently of
/// the engine (Spotify / YT Music rules, docs/DESIGN.md 7.17).
class _Model {
  _Model({required this.length, required this.index, required this.playing, required this.repeat});

  final int length;
  int index;
  bool playing;
  PlaybackRepeatMode repeat;

  void next() {
    if (index < length - 1) {
      index++;
    } else if (repeat == PlaybackRepeatMode.off) {
      return; // ignored: Next is disabled here, nothing changes
    } else {
      index = 0;
    }
    playing = true;
  }

  void previous(Duration position) {
    if (position > MusicAudioHandler.restartThreshold) {
      // restart
    } else if (index > 0) {
      index--;
    } else if (repeat != PlaybackRepeatMode.off && length > 1) {
      index = length - 1;
    }
    playing = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late FakeAudioPlayer player;
  late MusicAudioHandler handler;

  Future<void> start(int n, {int startIndex = 0, bool autoPlay = false, bool shuffle = false}) async {
    player = FakeAudioPlayer();
    handler = MusicAudioHandler(player: player, art: _noArt());
    await handler.loadQueue(_songs(n), startIndex: startIndex, autoPlay: autoPlay, shuffle: shuffle);
    await _settle();
  }

  tearDown(() async => handler.dispose());

  /// Everything that has to agree once the presses have landed.
  void expectConsistent({String reason = ''}) {
    final idx = handler.currentIndex;
    final order = _ids(handler.playOrderQueue);
    expect(handler.hasPendingSkip, isFalse, reason: '$reason: no press left over');
    expect(idx, inInclusiveRange(0, order.length - 1), reason: '$reason: index in range');
    expect(player.loadedIds, order, reason: '$reason: the player has the handler\'s order');
    expect(_ids(handler.queue.value), order, reason: '$reason: the session queue follows the play order');
    expect(handler.mediaItem.value?.id, order[idx], reason: '$reason: the notification shows the playing song');
    expect(handler.playbackState.value.queueIndex, idx, reason: '$reason: the session index');
    final domainState = handler.getCurrentDomainState();
    expect(domainState.queueIndex, idx, reason: '$reason: the app index');
    expect(domainState.currentItemId, order[idx], reason: '$reason: the app shows the playing song');
    expect(handler.playbackState.value.playing, player.playing, reason: '$reason: session play state');
    expect(player.droppedSeeks, 0, reason: '$reason: no seek was lost to a load');
    expect(order.toSet(), _ids(handler.originalQueue).toSet(), reason: '$reason: same songs');
  }

  group('200-press fuzz', () {
    for (final n in [1, 2, 3, 7]) {
      for (final shuffle in [false, true]) {
        for (final repeat in PlaybackRepeatMode.values) {
          // About 3 s alone; the longer limit is for a busy machine (the
          // full suite runs files side by side and each step waits on real
          // timers).
          test('queue of $n, shuffle ${shuffle ? 'on' : 'off'}, repeat ${repeat.name}',
              timeout: const Timeout(Duration(minutes: 3)), () async {
            final rnd = Random(n * 100 + (shuffle ? 10 : 0) + repeat.index);
            final startIndex = rnd.nextInt(n);
            final autoPlay = rnd.nextBool();
            await start(n, startIndex: startIndex, autoPlay: autoPlay, shuffle: shuffle);
            await handler.setRepeatMode(switch (repeat) {
              PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
              PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
              PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
            });
            final model = _Model(length: n, index: handler.currentIndex, playing: autoPlay, repeat: repeat);
            expectConsistent(reason: 'after load');

            for (var step = 0; step < 200; step++) {
              final op = rnd.nextInt(9);
              final reason = 'step $step op $op';
              final actionsBefore = player.seekCalls + player.loads;
              switch (op) {
                case 0:
                case 1:
                  model.next();
                  await handler.skipToNext();
                case 2:
                  final position = rnd.nextBool() ? const Duration(seconds: 12) : const Duration(seconds: 1);
                  player.fakePosition = position;
                  model.previous(position);
                  await handler.skipToPrevious();
                case 3:
                case 4:
                  // A burst of un-awaited presses, sometimes into a load.
                  if (rnd.nextInt(3) == 0) player.simulateLoading(const Duration(milliseconds: 3));
                  final position = rnd.nextBool() ? const Duration(seconds: 12) : Duration.zero;
                  player.fakePosition = position;
                  final presses = 2 + rnd.nextInt(7);
                  final futures = <Future<void>>[];
                  // The 3 s rule reads the position at the first press that
                  // does something; after it the run is heading for a start.
                  var moving = false;
                  for (var k = 0; k < presses; k++) {
                    if (rnd.nextInt(3) == 0) {
                      model.previous(moving ? Duration.zero : position);
                      moving = true;
                      futures.add(rnd.nextBool() ? handler.skipToPrevious() : handler.click(MediaButton.previous));
                    } else {
                      final before = model.index;
                      final wasPlaying = model.playing;
                      model.next();
                      if (model.index != before || model.playing != wasPlaying || model.repeat != PlaybackRepeatMode.off) {
                        moving = true;
                      }
                      futures.add(rnd.nextBool() ? handler.skipToNext() : handler.click(MediaButton.next));
                    }
                    // Shown at once, before anything landed.
                    final shown = handler.getCurrentDomainState();
                    expect(shown.queueIndex, model.index, reason: '$reason press $k: target shown at once');
                    expect(handler.mediaItem.value?.id, shown.currentItemId,
                        reason: '$reason press $k: the notification shows the target');
                  }
                  await Future.wait(futures);
                case 5:
                  model.playing = false;
                  await handler.pause();
                case 6:
                  model.playing = true;
                  await handler.play();
                case 7:
                  final k = rnd.nextInt(n);
                  model
                    ..index = k
                    ..playing = true;
                  final row = handler.getCurrentDomainState().queue[k];
                  await handler.skipToQueueItem(k, expectedId: row.id);
                case 8:
                  // Next and a tap racing: the tap wins, wherever the Next was going.
                  model.next();
                  final pressed = handler.skipToNext();
                  final k = rnd.nextInt(n);
                  final row = handler.getCurrentDomainState().queue[k];
                  model
                    ..index = k
                    ..playing = true;
                  await Future.wait([pressed, handler.skipToQueueItem(k, expectedId: row.id)]);
              }
              await _settle();
              expect(handler.currentIndex, model.index, reason: '$reason: lands where the presses pointed');
              expect(player.playing, model.playing, reason: '$reason: play state');
              expect(player.seekCalls + player.loads - actionsBefore, lessThanOrEqualTo(1),
                  reason: '$reason: one seek (or reload) per run of presses');
              expectConsistent(reason: reason);
            }
          });
        }
      }
    }
  });

  group('regressions the audit found', () {
    test('F3: two quick Next presses on the last, paused track do not start playback', () async {
      await start(3, startIndex: 2);
      final a = handler.skipToNext();
      final b = handler.skipToNext();
      final c = handler.click(MediaButton.next);
      final d = handler.click(MediaButton.next);
      await Future.wait([a, b, c, d]);
      await _settle();
      expect(player.playing, isFalse);
      expect(player.playCalls, 0);
      expect(handler.currentIndex, 2);
      expect(handler.wantPlaying, isFalse);
    });

    test('F3: Next presses that run past the end keep the move and do not wrap', () async {
      await start(4, startIndex: 1);
      final presses = [for (var i = 0; i < 6; i++) handler.skipToNext()];
      await Future.wait(presses);
      await _settle();
      expect(handler.currentIndex, 3, reason: 'two moves, then the end');
      expect(player.playing, isTrue, reason: 'the presses that moved start playback');
    });

    test('F4: a Next pressed while the queue is still loading is not lost', () async {
      player = FakeAudioPlayer(loadDelay: const Duration(milliseconds: 40));
      handler = MusicAudioHandler(player: player, art: _noArt());
      final load = handler.loadQueue(_songs(5), startIndex: 0, autoPlay: true);
      final next = handler.skipToNext();
      await Future.wait([load, next]);
      await _settle();
      expect(handler.currentIndex, 1);
      expect(player.droppedSeeks, 0);
      expect(player.playing, isTrue);
    });

    test('F4: presses while the player loads wait for it instead of being dropped', () async {
      await start(5, autoPlay: true);
      player.simulateLoading(const Duration(milliseconds: 60));
      await handler.skipToNext();
      expect(handler.currentIndex, 1);
      player.simulateLoading(const Duration(milliseconds: 60));
      await handler.skipToQueueItem(4);
      expect(handler.currentIndex, 4);
      player.simulateLoading(const Duration(milliseconds: 60));
      await handler.seek(const Duration(seconds: 30));
      expect(player.position, const Duration(seconds: 30));
      expect(player.droppedSeeks, 0);
    });

    test('F4/F15: a repeated "completed" state is handled once', () async {
      await start(3, startIndex: 2, autoPlay: true);
      final pauses = player.pauseCalls;
      final seeks = player.seekCalls;
      player.finishTrack(); // the last song ends: completed
      player.repeatState(); // ... and the player says so again
      await _settle();
      expect(player.pauseCalls - pauses, 1, reason: 'it used to run the end-of-queue branch twice');
      expect(player.seekCalls - seeks, 1);
      expect(handler.currentIndex, 0, reason: 'the queue ended: paused at its start');
      expect(player.playing, isFalse);
    });

    test('F5: ten rapid presses seek once, and every press shows its target at once', () async {
      await start(12, autoPlay: true);
      final shown = <String?>[];
      final sub = handler.mediaItem.listen((m) => shown.add(m?.id));
      await _settle();
      shown.clear();
      final seeks = player.seekCalls;
      final futures = <Future<void>>[];
      for (var i = 1; i <= 10; i++) {
        futures.add(handler.skipToNext());
        expect(handler.mediaItem.value?.id, 's$i', reason: 'the notification follows each press');
        expect(handler.getCurrentDomainState().currentItemId, 's$i', reason: 'and so does the app');
      }
      await Future.wait(futures);
      await _settle();
      expect(player.seekCalls - seeks, 1, reason: 'no flicking through every song on the way');
      expect(handler.currentIndex, 10);
      expect(shown, [for (var i = 1; i <= 10; i++) 's$i'], reason: 'each target once, no repeats');
      await sub.cancel();
    });

    test('F5: Previous restarts first (position at the first press), the next presses go back', () async {
      await start(6, startIndex: 4, autoPlay: true);
      player.fakePosition = const Duration(seconds: 40);
      final a = handler.skipToPrevious();
      expect(handler.getCurrentDomainState().queueIndex, 4, reason: 'restart');
      final b = handler.skipToPrevious();
      final c = handler.skipToPrevious();
      await Future.wait([a, b, c]);
      await _settle();
      expect(handler.currentIndex, 2);
    });

    test('F5: repeated identical index events do not re-send the notification item', () async {
      await start(3, autoPlay: true);
      var sent = 0;
      final sub = handler.mediaItem.skip(1).listen((_) => sent++);
      await handler.skipToNext();
      await _settle();
      expect(sent, 1);
      // State and event noise from the player (buffering, ready, position).
      player.simulateLoading(Duration.zero);
      await _settle();
      await handler.setSpeed(1.0);
      await _settle();
      expect(sent, 1);
      await sub.cancel();
    });

    test('F6: a queue tap during pending skips lands on the tapped song', () async {
      await start(10, autoPlay: true);
      final a = handler.skipToNext();
      final b = handler.skipToNext();
      final tap = handler.skipToQueueItem(5, expectedId: 's5');
      await Future.wait([a, b, tap]);
      await _settle();
      expect(handler.currentIndex, 5, reason: 'it used to land 2 songs later');
      expect(handler.mediaItem.value?.id, 's5');
    });

    test('F6: a row drawn before an edit still reaches its own song', () async {
      await start(6, autoPlay: true);
      // The sheet shows s4 at index 4; an earlier removal is still on its way.
      final remove = handler.removeQueueItemAt(1, expectedId: 's1');
      final tap = handler.skipToQueueItem(4, expectedId: 's4');
      await Future.wait([remove, tap]);
      await _settle();
      expect(handler.mediaItem.value?.id, 's4');
      // Remove by a stale index: the id finds the right song.
      final staleRemove = handler.removeQueueItemAt(4, expectedId: 's2');
      await staleRemove;
      expect(_ids(handler.playOrderQueue), ['s0', 's3', 's4', 's5']);
      // A song that left the queue: the tap does nothing.
      await handler.skipToQueueItem(1, expectedId: 's1');
      expect(handler.mediaItem.value?.id, 's4');
      // Reorder by id.
      await handler.reorderQueue(3, 0, expectedId: 's5');
      expect(_ids(handler.playOrderQueue), ['s5', 's0', 's3', 's4']);
      await _settle();
      expectConsistent(reason: 'after the edits');
    });

    test('F7: the session queue follows the reshuffle at the wrap', () async {
      await start(6, autoPlay: true);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.toggleShuffle();
      for (var i = 0; i < 30; i++) {
        await handler.skipToNext();
        await _settle();
        expect(_ids(handler.queue.value), _ids(handler.playOrderQueue), reason: 'skip $i');
        expect(player.loadedIds, _ids(handler.playOrderQueue), reason: 'skip $i');
      }
    });

    test('a pause right after a run of presses keeps the player paused', () async {
      await start(8, autoPlay: true);
      final a = handler.skipToNext();
      final b = handler.skipToNext();
      final p = handler.pause();
      await Future.wait([a, b, p]);
      await _settle();
      expect(handler.currentIndex, 2);
      expect(player.playing, isFalse);
    });
  });

  group('queue actions for the library (P2 interface)', () {
    test('playNextAll puts the songs right after the current one, in order', () async {
      await start(4, startIndex: 1, autoPlay: true);
      await handler.playNextAll([_song(10), _song(11)]);
      expect(_ids(handler.playOrderQueue), ['s0', 's1', 's10', 's11', 's2', 's3']);
      expect(handler.currentIndex, 1);
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, 's10');
      await _settle();
      expectConsistent(reason: 'play next');
    });

    test('addAllToQueue appends; with nothing queued both start playing', () async {
      await start(2);
      await handler.addAllToQueue([_song(10), _song(11)]);
      expect(_ids(handler.playOrderQueue), ['s0', 's1', 's10', 's11']);
      await _settle();
      expectConsistent(reason: 'add all');

      final fresh = FakeAudioPlayer();
      final empty = MusicAudioHandler(player: fresh, art: _noArt());
      addTearDown(empty.dispose);
      await empty.addAllToQueue([_song(1), _song(2)]);
      expect(_ids(empty.playOrderQueue), ['s1', 's2']);
      expect(fresh.playing, isTrue);
    });

    test('removeFromQueueById: every copy goes, the current song hands over to the next', () async {
      await start(4, startIndex: 1, autoPlay: true);
      await handler.addToQueue(_song(1));
      await handler.removeFromQueueById('s1');
      expect(_ids(handler.playOrderQueue), ['s0', 's2', 's3']);
      await _settle();
      expect(handler.mediaItem.value?.id, 's2');
      expect(player.playing, isTrue);
      await handler.removeFromQueueById('absent');
      expect(_ids(handler.playOrderQueue), ['s0', 's2', 's3']);
      expectConsistent(reason: 'remove by id');
    });
  });

  group('a stuck load never holds the chain (review)', () {
    test('a tapped song starts at once, not after a stale skip times out on a slow stream', () {
      fakeAsync((async) {
        final player = FakeAudioPlayer();
        final handler = MusicAudioHandler(player: player, art: _noArt());
        handler.loadQueue(_songs(5), autoPlay: true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 50));

        // A slow stream: the player sits in "loading".
        player.simulateLoading(const Duration(minutes: 5));
        async.flushMicrotasks();
        handler.skipToNext();
        async.elapse(const Duration(milliseconds: 100));

        // The user taps a song elsewhere.
        var loaded = false;
        handler.loadQueue([_song(9), _song(8)], autoPlay: true).then((_) => loaded = true);
        async.elapse(const Duration(seconds: 2));
        expect(loaded, isTrue, reason: 'the new queue must not wait behind ~30 s of stale retries');
        expect(_ids(handler.playOrderQueue), ['s9', 's8']);
        expect(player.loadedIds, ['s9', 's8']);
        expect(player.playing, isTrue);
        handler.dispose();
        async.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('a newer press takes over from a skip that waits on a load', () {
      fakeAsync((async) {
        final player = FakeAudioPlayer();
        final handler = MusicAudioHandler(player: player, art: _noArt());
        handler.loadQueue(_songs(6), autoPlay: true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 50));

        player.simulateLoading(const Duration(seconds: 3));
        async.flushMicrotasks();
        handler.skipToNext(); // waits on the load
        async.elapse(const Duration(milliseconds: 100));
        handler.skipToNext();
        handler.skipToNext();
        async.elapse(const Duration(seconds: 4));
        expect(handler.currentIndex, 3, reason: 'three presses, one jump');
        expect(player.currentIndex, 3);
        expect(handler.hasPendingSkip, isFalse);
        handler.dispose();
        async.flushTimers(flushPeriodicTimers: false);
      });
    });
  });
}
