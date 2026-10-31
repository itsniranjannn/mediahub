import '../models/media_item.dart';
import '../models/playlist_and_groups.dart';

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

  /// Watches favorites list.
  Stream<List<MediaItem>> watchFavorites({String? searchQuery});

  /// Toggles favorite state for a media item.
  Future<void> toggleFavorite(String id);

  /// Records a play event (updates lastPlayed and increments playCount).
  Future<void> recordPlay(String id);

  /// Updates availability state for a media item.
  Future<void> updateAvailability(String id, MediaAvailability availability);

  // Playlists
  Stream<List<Playlist>> watchPlaylists();
  Future<Playlist> createPlaylist(String name);
  Future<void> renamePlaylist(String id, String newName);
  Future<void> deletePlaylist(String id);
  Future<void> addSongToPlaylist(String playlistId, String mediaId);
  Future<void> removeSongFromPlaylist(String playlistId, String mediaId, int position);
  Future<void> reorderPlaylist(String playlistId, int oldPosition, int newPosition);
  Stream<List<MediaItem>> watchPlaylistSongs(String playlistId);

  // Albums & Artists
  Stream<List<AlbumGroup>> watchAlbums({String? searchQuery});
  Stream<List<MediaItem>> watchAlbumSongs(String album);
  Stream<List<ArtistGroup>> watchArtists({String? searchQuery});
  Stream<List<MediaItem>> watchArtistSongs(String artist);

  // Home sections
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20});
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20});
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType});
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10});
}
