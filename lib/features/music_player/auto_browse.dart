// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:audio_service/audio_service.dart';

import '../../domain/models/media_item.dart' as domain;
import '../../domain/repositories/library_repository.dart';

/// What Android Auto (and any other MediaBrowser client: a car head unit,
/// a watch) can browse: Songs, Albums, Playlists and Favourites.
///
/// Folder ids: [songsId], [albumsId] (then `album:<key>`), [playlistsId]
/// (then `playlist:<id>`), [favouritesId]. A playable song in a list has the
/// id `<folder id>|<song id>`, so playing it plays that whole list from
/// there ([split]).
class AutoBrowseTree {
  AutoBrowseTree(this._library);

  final LibraryRepository _library;

  static const String songsId = 'songs';
  static const String albumsId = 'albums';
  static const String playlistsId = 'playlists';
  static const String favouritesId = 'favourites';

  /// Cars scroll badly through thousands of rows: lists stop here.
  static const int maxItems = 500;

  /// The root's extras for audio_service (lists, not grids).
  static const Map<String, dynamic> rootExtras = {
    AndroidContentStyle.supportedKey: true,
    AndroidContentStyle.browsableHintKey: AndroidContentStyle.listItemHintValue,
    AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
  };

  static MediaItem _folder(String id, String title) => MediaItem(id: id, title: title, playable: false);

  /// The root's four folders.
  static List<MediaItem> get rootFolders => [
        _folder(songsId, 'Songs'),
        _folder(albumsId, 'Albums'),
        _folder(playlistsId, 'Playlists'),
        _folder(favouritesId, 'Favourites'),
      ];

  /// (folder id, song id) of a playable browse id, or null for anything else.
  static (String, String)? split(String mediaId) {
    final bar = mediaId.indexOf('|');
    if (bar <= 0 || bar == mediaId.length - 1) return null;
    return (mediaId.substring(0, bar), mediaId.substring(bar + 1));
  }

  /// The songs of folder [parentId] (in the order shown), or null when it is
  /// not a song list.
  Future<List<domain.MediaItem>?> songsOf(String parentId) async {
    List<domain.MediaItem>? songs;
    if (parentId == songsId) {
      songs = await _library.watchSongs().first;
    } else if (parentId == favouritesId) {
      songs = await _library.watchFavorites().first;
    } else if (parentId.startsWith('album:')) {
      songs = await _library.watchAlbumSongs(parentId.substring(6)).first;
    } else if (parentId.startsWith('playlist:')) {
      songs = await _library.watchPlaylistSongs(parentId.substring(9)).first;
    }
    if (songs == null) return null;
    // Only what the car can play: songs that are there, never Online items or videos.
    return songs
        .where((s) =>
            s.mediaType == domain.MediaType.audio &&
            !s.isOnline &&
            s.availability == domain.MediaAvailability.available)
        .take(maxItems)
        .toList();
  }

  /// The children of [parentId]; [toSessionItem] turns a song into the
  /// session's item (with its cover).
  Future<List<MediaItem>> children(
    String parentId,
    MediaItem Function(domain.MediaItem song, String browseId) toSessionItem,
  ) async {
    if (parentId == AudioService.browsableRootId) return rootFolders;
    if (parentId == albumsId) {
      final albums = await _library.watchAlbums().first;
      return [
        for (final a in albums.take(maxItems))
          MediaItem(
            id: 'album:${a.key}',
            title: a.album,
            artist: a.artist,
            playable: false,
          ),
      ];
    }
    if (parentId == playlistsId) {
      final playlists = await _library.watchPlaylists().first;
      return [
        for (final p in playlists.take(maxItems)) MediaItem(id: 'playlist:${p.id}', title: p.name, playable: false),
      ];
    }
    final songs = await songsOf(parentId);
    if (songs == null) return const [];
    return [for (final s in songs) toSessionItem(s, '$parentId|${s.id}')];
  }
}
