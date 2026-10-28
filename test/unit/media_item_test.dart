import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/domain/models/media_item.dart';

void main() {
  group('MediaItem Search and Sort Tests', () {
    final now = DateTime.now();
    final items = [
      MediaItem(
        id: '1',
        uri: 'path/1.mp3',
        mediaType: MediaType.audio,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        durationMs: 354000,
        sizeBytes: 10000000,
        dateAdded: now.subtract(const Duration(days: 10)),
      ),
      MediaItem(
        id: '2',
        uri: 'path/2.mp3',
        mediaType: MediaType.audio,
        title: 'Hotel California',
        artist: 'Eagles',
        album: 'Hotel California',
        durationMs: 390000,
        sizeBytes: 12000000,
        dateAdded: now.subtract(const Duration(days: 5)),
      ),
      MediaItem(
        id: '3',
        uri: 'path/3.mp3',
        mediaType: MediaType.audio,
        title: 'Stairway to Heaven',
        artist: 'Led Zeppelin',
        album: 'Led Zeppelin IV',
        durationMs: 482000,
        sizeBytes: 15000000,
        dateAdded: now.subtract(const Duration(days: 1)),
      ),
    ];

    test('Search filtering matches title or artist case-insensitively', () {
      const query = 'queen';
      final filtered = items.where((item) {
        final term = query.toLowerCase();
        return item.title.toLowerCase().contains(term) ||
            (item.artist?.toLowerCase().contains(term) ?? false);
      }).toList();

      expect(filtered.length, equals(1));
      expect(filtered.first.artist, equals('Queen'));
    });

    test('Sorting by title ascending', () {
      final sorted = List<MediaItem>.from(items)
        ..sort((a, b) => a.title.compareTo(b.title));

      expect(sorted[0].title, equals('Bohemian Rhapsody'));
      expect(sorted[1].title, equals('Hotel California'));
      expect(sorted[2].title, equals('Stairway to Heaven'));
    });

    test('Sorting by duration descending', () {
      final sorted = List<MediaItem>.from(items)
        ..sort((a, b) => b.durationMs.compareTo(a.durationMs));

      expect(sorted[0].title, equals('Stairway to Heaven'));
      expect(sorted[1].title, equals('Hotel California'));
      expect(sorted[2].title, equals('Bohemian Rhapsody'));
    });
  });
}
