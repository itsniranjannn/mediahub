import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart';

MediaItem _createTestItem(String id, String title) {
  return MediaItem(
    id: id,
    uri: 'file:///path/to/$id.mp3',
    mediaType: MediaType.audio,
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 180000,
    sizeBytes: 1024,
    dateAdded: DateTime(2026, 1, 1),
  );
}

class QueueController {
  List<MediaItem> _queue = [];
  int _currentIndex = -1;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  bool _shuffle = false;
  List<int> _shuffledIndices = [];

  List<MediaItem> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get shuffleEnabled => _shuffle;

  void loadQueue(List<MediaItem> items, {int startIndex = 0}) {
    _queue = List.from(items);
    _currentIndex = startIndex;
    if (_shuffle) _generateShuffleIndices();
  }

  void addToQueue(MediaItem item) {
    _queue.add(item);
    if (_shuffle) _generateShuffleIndices();
  }

  void playNext(MediaItem item) {
    if (_queue.isEmpty) {
      loadQueue([item]);
      return;
    }
    int insertIndex = _currentIndex + 1;
    _queue.insert(insertIndex, item);
    if (_shuffle) _generateShuffleIndices();
  }

  void removeQueueItemAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (_shuffle) _generateShuffleIndices();

    if (removingCurrent) {
      if (_queue.isEmpty) {
        _currentIndex = -1;
      } else {
        if (_currentIndex >= _queue.length) {
          _currentIndex = _queue.length - 1;
        }
      }
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0 || newIndex >= _queue.length) {
      return;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
      _currentIndex--;
    } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
      _currentIndex++;
    }
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case PlaybackRepeatMode.off:
        _repeatMode = PlaybackRepeatMode.all;
        break;
      case PlaybackRepeatMode.all:
        _repeatMode = PlaybackRepeatMode.one;
        break;
      case PlaybackRepeatMode.one:
        _repeatMode = PlaybackRepeatMode.off;
        break;
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) {
      _generateShuffleIndices();
    }
  }

  void _generateShuffleIndices() {
    _shuffledIndices = List.generate(_queue.length, (i) => i);
    _shuffledIndices.shuffle();
    if (_currentIndex >= 0 && _shuffledIndices.contains(_currentIndex)) {
      _shuffledIndices.remove(_currentIndex);
      _shuffledIndices.insert(0, _currentIndex);
    }
  }
}

void main() {
  group('Queue operations unit tests', () {
    late QueueController controller;
    final item1 = _createTestItem('1', 'Song 1');
    final item2 = _createTestItem('2', 'Song 2');
    final item3 = _createTestItem('3', 'Song 3');

    setUp(() {
      controller = QueueController();
    });

    test('loadQueue sets items and startIndex', () {
      controller.loadQueue([item1, item2, item3], startIndex: 1);
      expect(controller.queue.length, 3);
      expect(controller.currentIndex, 1);
      expect(controller.queue[1].id, '2');
    });

    test('addToQueue appends item', () {
      controller.loadQueue([item1], startIndex: 0);
      controller.addToQueue(item2);
      expect(controller.queue.length, 2);
      expect(controller.queue.last.id, '2');
    });

    test('playNext inserts item immediately after current index', () {
      controller.loadQueue([item1, item3], startIndex: 0);
      controller.playNext(item2);
      expect(controller.queue.length, 3);
      expect(controller.queue[1].id, '2');
      expect(controller.queue[2].id, '3');
    });

    test('removeQueueItemAt removes item and updates index', () {
      controller.loadQueue([item1, item2, item3], startIndex: 2);
      controller.removeQueueItemAt(0);
      expect(controller.queue.length, 2);
      expect(controller.queue[0].id, '2');
      expect(controller.currentIndex, 1);
    });

    test('reorderQueue moves item 0 to 1, 1 to 0, and follows current item', () {
      // 1. Move item 0 to 1
      controller.loadQueue([item1, item2, item3], startIndex: 0);
      controller.reorderQueue(0, 1);
      expect(controller.queue[0].id, '2');
      expect(controller.queue[1].id, '1');
      expect(controller.queue[2].id, '3');
      expect(controller.currentIndex, 1);

      // 2. Move item 1 to 0
      controller.reorderQueue(1, 0);
      expect(controller.queue[0].id, '1');
      expect(controller.queue[1].id, '2');
      expect(controller.queue[2].id, '3');
      expect(controller.currentIndex, 0);

      // 3. Move current item from 0 to 2
      controller.reorderQueue(0, 2);
      expect(controller.queue[0].id, '2');
      expect(controller.queue[1].id, '3');
      expect(controller.queue[2].id, '1');
      expect(controller.currentIndex, 2);
    });

    test('repeat transitions: off -> all -> one -> off', () {
      expect(controller.repeatMode, PlaybackRepeatMode.off);
      controller.cycleRepeatMode();
      expect(controller.repeatMode, PlaybackRepeatMode.all);
      controller.cycleRepeatMode();
      expect(controller.repeatMode, PlaybackRepeatMode.one);
      controller.cycleRepeatMode();
      expect(controller.repeatMode, PlaybackRepeatMode.off);
    });

    test('shuffle toggling generates shuffle indices', () {
      controller.loadQueue([item1, item2, item3], startIndex: 0);
      expect(controller.shuffleEnabled, isFalse);
      controller.toggleShuffle();
      expect(controller.shuffleEnabled, isTrue);
      controller.toggleShuffle();
      expect(controller.shuffleEnabled, isFalse);
    });
  });
}
