// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import '../models/media_item.dart';
import '../models/playlist_and_groups.dart';

abstract class LibraryRepository {
  /// Scans the device for local media files (audio & video) and saves them to the database.
  Future<void> scanDeviceMedia();

  /// Songs the last [scanDeviceMedia] added to the library (not counting a
  /// file that only came back under a new id); null before the first scan.
  int? get lastScanNewSongCount;

  /// A value that changes whenever the phone's media files change (MediaStore
  /// generation, Android 11+), or null when the phone cannot tell. Lets a
  /// rescan on resume be skipped when nothing changed.
  Future<String?> mediaStoreGeneration();

  /// Watches media items matching [mediaType], filtered by [searchQuery] and sorted by [sortBy].
  ///
  /// Only files that are there: missing files and Online items are left out.
  /// Every word of [searchQuery] has to match the title, artist or album
  /// (accents and case ignored).
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  });

  /// Songs in one of the song-only orders ([SongSortOption.album],
  /// [SongSortOption.mostPlayed]) or any other; same filtering as
  /// [watchMediaItems].
  Stream<List<MediaItem>> watchSongs({
    String? searchQuery,
    SongSortOption sortBy = SongSortOption.title,
    bool ascending = true,
  });

  /// Fetches media items matching [mediaType], filtered by [searchQuery] and sorted by [sortBy].
  Future<List<MediaItem>> getMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  });

  /// Liked songs ("Favorites" before), newest liked first: songs on the
  /// phone, downloads and liked Online items.
  Stream<List<MediaItem>> watchFavorites({String? searchQuery});

  /// Toggles favorite state for a media item.
  Future<void> toggleFavorite(String id);

  /// Records a play event (updates lastPlayed and increments playCount).
  Future<void> recordPlay(String id);

  /// Updates availability state for a media item.
  Future<void> updateAvailability(String id, MediaAvailability availability);

  /// Removes a song or video from the library and from everything that
  /// points at it, in one transaction: its playlist entries (each playlist it
  /// was in is renumbered), its video progress and its row. Files are not
  /// touched; the caller deletes those.
  Future<void> deleteMediaCompletely(String mediaId);

  /// Saves an Online (YouTube) item so it can be liked and put in playlists:
  /// a `source: 'online'` row keyed by its video, with the canonical watch
  /// link as uri and the https thumbnail as artwork. Keeps the row's likes
  /// and plays when it is already there. Returns the saved item.
  Future<MediaItem> saveOnlineItem(MediaItem item);

  // Playlists
  Stream<List<Playlist>> watchPlaylists();

  /// One playlist, live (its name after a rename); null once it is deleted.
  Stream<Playlist?> watchPlaylist(String id);
  Future<Playlist> createPlaylist(String name);
  Future<void> renamePlaylist(String id, String newName);
  Future<void> deletePlaylist(String id);

  /// Adds [mediaId] at the end. Returns false, and adds nothing, when it is
  /// already in the playlist (unless [allowDuplicate]).
  Future<bool> addSongToPlaylist(String playlistId, String mediaId, {bool allowDuplicate = false});

  /// Adds every one of [mediaIds] that is not in the playlist yet, in order,
  /// in one transaction. Returns how many were added.
  Future<int> addSongsToPlaylist(String playlistId, List<String> mediaIds);

  /// Puts [mediaId] back at [position] (Undo of a removal).
  Future<void> insertSongIntoPlaylist(String playlistId, String mediaId, int position);

  /// Removes the entry of [mediaId] at its stored [position] (see
  /// [PlaylistTrack.position]).
  Future<void> removeSongFromPlaylist(String playlistId, String mediaId, int position);

  /// Moves the entry at stored position [oldPosition] to [newPosition].
  Future<void> reorderPlaylist(String playlistId, int oldPosition, int newPosition);
  Stream<List<MediaItem>> watchPlaylistSongs(String playlistId);

  /// The playlist's songs with their stored positions.
  Stream<List<PlaylistTrack>> watchPlaylistTracks(String playlistId);

  /// Ids of the playlists that hold [mediaId].
  Stream<Set<String>> watchPlaylistIdsContaining(String mediaId);

  // Albums & Artists
  Stream<List<AlbumGroup>> watchAlbums({String? searchQuery});

  /// The songs of the album with [albumKey] ([AlbumGroup.lookupKey]), by
  /// disc, then track number, then title.
  Stream<List<MediaItem>> watchAlbumSongs(String albumKey);

  /// The album [item] belongs to, or null when it has none.
  Future<AlbumGroup?> findAlbumOf(MediaItem item);
  Stream<List<ArtistGroup>> watchArtists({String? searchQuery});
  Stream<List<MediaItem>> watchArtistSongs(String artist);

  // Home sections
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20});
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20});
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType});
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10});
}
