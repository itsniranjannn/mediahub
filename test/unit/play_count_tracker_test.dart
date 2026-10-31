import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/utils/play_count_tracker.dart';

void main() {
  group('PlayCountTracker', () {
    late PlayCountTracker tracker;
    late List<String> recordedPlays;

    setUp(() {
      recordedPlays = [];
      tracker = PlayCountTracker(onCountPlay: (id) async {
        recordedPlays.add(id);
      });
    });

    test('counts a play when playing for 30 seconds on a long track (> 60s)', () async {
      // 4 minute track (240s): threshold is min(30s, 120s) = 30s
      tracker.onTrackChanged('track_1', const Duration(seconds: 240));

      // Initial position at 0
      tracker.onPositionUpdated(Duration.zero, isPlaying: true);

      // Simulate 1-second ticks
      for (int i = 1; i <= 10; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      expect(recordedPlays, isEmpty);

      for (int i = 11; i <= 29; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      expect(recordedPlays, isEmpty);

      // Tick 30: reaches 30s threshold
      tracker.onPositionUpdated(const Duration(seconds: 30), isPlaying: true);
      expect(recordedPlays, equals(['track_1']));

      // Continuing to play does NOT count again (once per play)
      for (int i = 31; i <= 50; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      expect(recordedPlays.length, equals(1));
    });

    test('counts a play after 50% on a short track (< 60s)', () async {
      // 40 second track: threshold is min(30s, 20s) = 20s
      tracker.onTrackChanged('short_track', const Duration(seconds: 40));

      tracker.onPositionUpdated(Duration.zero, isPlaying: true);
      for (int i = 1; i <= 15; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      expect(recordedPlays, isEmpty);

      for (int i = 16; i <= 20; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      expect(recordedPlays, equals(['short_track']));

      // Further updates on same track do not re-count
      for (int i = 21; i <= 35; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      expect(recordedPlays.length, equals(1));
    });

    test('skipping within 5 seconds does NOT count a play', () async {
      tracker.onTrackChanged('track_skip', const Duration(seconds: 200));

      tracker.onPositionUpdated(Duration.zero, isPlaying: true);
      for (int i = 1; i <= 4; i++) {
        tracker.onPositionUpdated(Duration(seconds: i), isPlaying: true);
      }
      tracker.onTrackChanged('track_next', const Duration(seconds: 200));

      expect(recordedPlays, isEmpty);
    });

    test('resetting track or seeking does not violate threshold', () async {
      tracker.onTrackChanged('track_seek', const Duration(seconds: 100));

      tracker.onPositionUpdated(const Duration(seconds: 0), isPlaying: true);
      // Large jump: seeking forward 45s should NOT count as played time
      tracker.onPositionUpdated(const Duration(seconds: 45), isPlaying: true);
      expect(recordedPlays, isEmpty);

      tracker.accumulatePlayback(const Duration(seconds: 2));
      expect(recordedPlays, isEmpty);
    });
  });
}
