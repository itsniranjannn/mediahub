import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

void main() {
  group('F8 throttled position: at most ~4 a second, never stale', () {
    test('the newest value of a window goes out when it closes, instead of being dropped', () {
      fakeAsync((async) {
        final positions = StreamController<Duration>();
        final out = <int>[];
        throttlePositions(positions.stream, isPlaying: () => true).listen((d) => out.add(d.inMilliseconds));

        positions.add(const Duration(milliseconds: 1000));
        async.flushMicrotasks();
        expect(out, [1000], reason: 'the first value at once');

        async.elapse(const Duration(milliseconds: 50));
        positions.add(const Duration(milliseconds: 1050));
        async.elapse(const Duration(milliseconds: 100));
        positions.add(const Duration(milliseconds: 1150));
        async.flushMicrotasks();
        expect(out, [1000], reason: 'held inside the 240 ms window');

        async.elapse(const Duration(milliseconds: 100)); // the window closes at 240 ms
        expect(out, [1000, 1150], reason: 'the latest value, not the one from before (it used to be dropped)');

        // Nothing new: nothing is sent.
        async.elapse(const Duration(seconds: 1));
        expect(out, [1000, 1150]);
        positions.close();
      });
    });

    test('a jump (a seek, a new song) goes out at once, even inside the window', () {
      fakeAsync((async) {
        final positions = StreamController<Duration>();
        final out = <int>[];
        throttlePositions(positions.stream, isPlaying: () => true).listen((d) => out.add(d.inMilliseconds));
        positions.add(const Duration(seconds: 10));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 30));
        positions.add(const Duration(seconds: 95));
        async.flushMicrotasks();
        expect(out, [10000, 95000]);
        async.elapse(const Duration(milliseconds: 30));
        positions.add(Duration.zero);
        async.flushMicrotasks();
        expect(out, [10000, 95000, 0]);
        positions.close();
      });
    });

    test('paused: the value goes out at once, and a pause flushes the held one', () {
      fakeAsync((async) {
        final positions = StreamController<Duration>();
        final playing = StreamController<bool>();
        var isPlaying = true;
        final out = <int>[];
        throttlePositions(positions.stream, isPlaying: () => isPlaying, playingChanges: playing.stream)
            .listen((d) => out.add(d.inMilliseconds));
        positions.add(const Duration(milliseconds: 5000));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 40));
        positions.add(const Duration(milliseconds: 5040));
        async.flushMicrotasks();
        expect(out, [5000]);
        isPlaying = false;
        playing.add(false);
        async.flushMicrotasks();
        expect(out, [5000, 5040], reason: 'the bar stops where the music stopped');
        positions.add(const Duration(milliseconds: 5041));
        async.flushMicrotasks();
        expect(out.last, 5041);
        positions.close();
        playing.close();
      });
    });
  });
}
