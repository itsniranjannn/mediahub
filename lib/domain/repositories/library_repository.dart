import '../models/media_item.dart';

abstract class LibraryRepository {
  /// Scans the device for local media files (audio & video) and saves them to the database.
  Future<void> scanDeviceMedia();

  /// Watches media items matching [mediaType], filtered by [searchQuery] and sorted by [sortBy].
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  });

  /// Fetches media items matching [mediaType], filtered by [searchQuery] and sorted by [sortBy].
  Future<List<MediaItem>> getMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  });

  /// Toggles favorite state for a media item.
  Future<void> toggleFavorite(String id);

  /// Records a play event (updates lastPlayed and increments playCount).
  Future<void> recordPlay(String id);
}
