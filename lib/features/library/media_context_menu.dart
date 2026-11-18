import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform/share_channel.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/widgets/favorite_feedback_button.dart' show isFavoriteProvider;
import '../downloads/download_link_inbox.dart';
import '../downloads/download_providers.dart';
import '../music_player/playback_notifier.dart';
import '../online/youtube_urls.dart';
import '../playlists/playlist_cover.dart';
import 'detail_screens.dart';
import 'playable.dart';

/// Everything the media sheet can do with an item (docs/DESIGN.md 7.10).
///
/// Which of them an item gets is decided by [MediaContextMenu.actionsFor]:
/// - songs: [playNext], [addToQueue], [addToPlaylist], [removeFromPlaylist]
///   (in a playlist), [favorite] (Liked songs), [goToAlbum], [goToArtist],
///   [share], [details], then [delete];
/// - videos: [play], [playAsAudio], [pictureInPicture], [share], [details],
///   [delete];
/// - Online (YouTube) items: [favorite], [addToPlaylist],
///   [removeFromPlaylist], [download], [copyLink], [share], [details].
///
/// "Share" needs the system share sheet (Android). "Delete" is offered only
/// for downloads, the files the app owns; removing a file another app put on
/// the phone needs Android's `MediaStore.createDeleteRequest` and an
/// Activity result, which the app does not have yet.
enum MediaAction {
  play,
  playAsAudio,
  pictureInPicture,
  playNext,
  addToQueue,
  addToPlaylist,
  removeFromPlaylist,
  favorite,
  goToAlbum,
  goToArtist,
  download,
  copyLink,
  share,
  details,
  delete,
}

/// Where in a playlist a song's menu was opened: "Remove from this
/// playlist" takes out that entry (its stored position).
@immutable
class PlaylistEntryRef {
  final String playlistId;
  final String playlistName;
  final int position;

  const PlaylistEntryRef({required this.playlistId, required this.playlistName, required this.position});
}

/// The platform pieces the media sheet uses, so tests can stand in for them.
class MediaMenuPlatform {
  const MediaMenuPlatform();

  /// Whether this phone can show picture-in-picture (Android 8+ with the
  /// feature on).
  Future<bool> isPipSupported() => DeviceControls.isPipSupported();

  /// Shrinks the app into the picture-in-picture window. False if it cannot.
  Future<bool> enterPip() => DeviceControls.enterPip();

  /// Opens the video player on [item].
  void openVideo(BuildContext context, MediaItem item) => context.push('/video_player', extra: item);

  /// Switches the bottom navigation to [location] (a tab such as '/downloads').
  void openTab(BuildContext context, String location) => GoRouter.maybeOf(context)?.go(location);

  Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

  /// Whether the system share sheet is there.
  bool get shareSupported => ShareChannel.available;

  /// Opens the share sheet for a media file; false when it could not.
  Future<bool> shareFile({required String uriOrPath, required String mimeType, String? title}) =>
      ShareChannel.shareFile(uriOrPath: uriOrPath, mimeType: mimeType, title: title);

  /// Opens the share sheet for a link; false when it could not.
  Future<bool> shareText(String text) => ShareChannel.shareText(text);
}

final mediaMenuPlatformProvider = Provider<MediaMenuPlatform>((ref) => const MediaMenuPlatform());

/// Deletes media files from the phone for the media sheet's "Delete from
/// phone".
abstract interface class MediaFileDeleter {
  /// Whether [item] can be deleted by the app.
  bool canDelete(MediaItem item);

  /// Removes [item]'s file and everything the app keeps about it. Throws when
  /// the file is there but cannot be removed (nothing else is touched then).
  Future<void> delete(MediaItem item);
}

final mediaFileDeleterProvider = Provider<MediaFileDeleter>((ref) => _DownloadedFileDeleter(ref));

/// Whether [path] is a file inside [dir] (never [dir] itself, never a path
/// that climbs out of it with `..`).
bool isPathInside(String dir, String path) => p.isWithin(p.normalize(dir), p.normalize(path));

/// Deletes downloads: their file lives in the app's own storage, so the app
/// may remove it. Then its saved cover and its rows in Downloads go, and
/// [LibraryRepository.deleteMediaCompletely] takes it out of every playlist
/// (each renumbered), its video progress and its library row.
///
/// Only files inside the downloads folder are ever deleted: a row pointing
/// anywhere else (a corrupt or crafted database) loses its rows, not a file.
class _DownloadedFileDeleter implements MediaFileDeleter {
  final Ref _ref;

  _DownloadedFileDeleter(this._ref);

  static bool _isLocalPath(String? path) => path != null && path.isNotEmpty && !path.contains('://');

  @override
  bool canDelete(MediaItem item) => item.source == 'download' && _isLocalPath(item.uri);

  @override
  Future<void> delete(MediaItem item) async {
    if (!canDelete(item)) throw StateError('${item.id} is not a download');
    final db = _ref.read(appDatabaseProvider);
    final repo = _ref.read(libraryRepositoryProvider);
    final dir = (await _ref.read(downloadDirectoryProvider.future)).path;

    final downloads = await (db.select(db.downloadsTable)..where((t) => t.mediaId.equals(item.id))).get();

    // The media file first: if it cannot go, the library keeps its row and
    // the song still plays.
    if (isPathInside(dir, item.uri)) {
      final media = File(item.uri);
      if (await media.exists()) await media.delete();
    }
    for (final path in {item.artworkPath, for (final d in downloads) ...[d.finalPath, d.thumbnailPath]}) {
      if (!_isLocalPath(path) || path == item.uri || !isPathInside(dir, path!)) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A leftover cover is harmless; the startup sweep may still get it.
      }
    }

    await repo.deleteMediaCompletely(item.id);
    await (db.delete(db.downloadsTable)..where((t) => t.mediaId.equals(item.id))).go();
  }
}

/// The media sheet ("media dropdown", docs/DESIGN.md 7.10): every ⋮ and long
/// press on an item opens it.
///
/// On a phone it is a modal bottom sheet in the app theme (also when opened
/// from the always-ink Now Playing): the item's art, title and meta line,
/// then one 56 dp row per action, with "Delete from phone" in the error
/// colour after a divider. On a screen 600 dp or wider, or in landscape, a
/// popup menu anchored to the ⋮ ([anchorContext]) takes its place.
///
/// The sheet closes before the chosen action runs; every action reports back
/// in a snackbar or opens what it names.
class MediaContextMenu {
  MediaContextMenu._();

  /// Lifts the confirmation snackbars clear of the Ink Dock.
  static const double _snackBarBottomClearance = 76;

  static const double headerArtSize = 56;
  static const double rowHeight = 56;
  static const double menuRowHeight = 48;

  /// The name of the liked-songs list everywhere ("wishlist").
  static const String likedSongs = 'Liked songs';

  /// The title the sheet, its dialogs and snackbars show: a video without
  /// its file extension, as on the video cards it opens from.
  static String shownTitle(MediaItem item) =>
      item.mediaType == MediaType.video && !item.isOnline ? videoDisplayTitle(item.title) : item.title;

  /// Opens the media sheet for [item].
  ///
  /// [anchorContext] is the ⋮ button the wide-screen popup hangs from
  /// (defaults to [context]). [without] drops actions that make no sense
  /// where the sheet is opened ("Go to album" on that album's page).
  /// [playlistEntry] adds "Remove from this playlist" for a song opened on a
  /// playlist page. [onCustomAction] is kept for older callers and is not
  /// used.
  ///
  /// Online items (`source == 'online'`, e.g. from the Online tab's watch
  /// strip) are saved to the library when they are liked or put in a
  /// playlist ([LibraryRepository.saveOnlineItem]).
  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    MediaItem item, {
    VoidCallback? onCustomAction,
    BuildContext? anchorContext,
    Set<MediaAction> without = const {},
    PlaylistEntryRef? playlistEntry,
  }) {
    return _MediaMenu(context, onlineRecordOf(item), playlistEntry).open(anchorContext ?? context, without);
  }

  /// The library row an Online item is kept as: id `yt_<video id>`, the
  /// canonical watch link as uri and the https thumbnail as artwork, whatever
  /// link or stream it came with. Other items, and Online items without a
  /// YouTube video id, are returned as they are.
  static MediaItem onlineRecordOf(MediaItem item) {
    if (!item.isOnline) return item;
    var videoId = youTubeVideoIdFromString(item.uri);
    if (videoId == null && item.id.startsWith('yt_') && isValidYouTubeVideoId(item.id.substring(3))) {
      videoId = item.id.substring(3);
    }
    if (videoId == null) return item;
    final art = item.artworkPath;
    return item.copyWith(
      id: 'yt_$videoId',
      uri: 'https://www.youtube.com/watch?v=$videoId',
      artworkPath: art != null && art.startsWith('https://') ? art : youTubeThumbnailFor(videoId),
      sizeBytes: 0,
    );
  }

  /// Whether [item] is an Online item that can be saved (it has a video).
  static bool _isSavableOnline(MediaItem item) => item.isOnline && item.id.startsWith('yt_') && _isWebLink(item.uri);

  /// The actions [item] gets, in sheet order.
  @visibleForTesting
  static List<MediaAction> actionsFor(
    MediaItem item, {
    required bool canDelete,
    required bool pipSupported,
    bool downloadsSupported = true,
    bool shareSupported = true,
    bool inPlaylist = false,
  }) {
    if (item.isOnline) {
      final link = _isWebLink(item.uri);
      final savable = _isSavableOnline(item);
      return [
        if (savable) MediaAction.favorite,
        if (savable) MediaAction.addToPlaylist,
        if (inPlaylist) MediaAction.removeFromPlaylist,
        if (link && downloadsSupported) MediaAction.download,
        if (link) MediaAction.copyLink,
        if (link && shareSupported) MediaAction.share,
        MediaAction.details,
      ];
    }
    if (item.mediaType == MediaType.video) {
      return [
        MediaAction.play,
        MediaAction.playAsAudio,
        if (pipSupported) MediaAction.pictureInPicture,
        if (shareSupported) MediaAction.share,
        MediaAction.details,
        if (canDelete) MediaAction.delete,
      ];
    }
    return [
      MediaAction.playNext,
      MediaAction.addToQueue,
      MediaAction.addToPlaylist,
      if (inPlaylist) MediaAction.removeFromPlaylist,
      MediaAction.favorite,
      if (_albumOf(item) != null) MediaAction.goToAlbum,
      if (_artistOf(item) != null) MediaAction.goToArtist,
      if (shareSupported) MediaAction.share,
      MediaAction.details,
      if (canDelete) MediaAction.delete,
    ];
  }

  /// The album name to open, or null when the song has none.
  static String? _albumOf(MediaItem item) {
    final album = item.album?.trim();
    return (album == null || album.isEmpty) ? null : item.album;
  }

  /// The artist name to open, or null for an unknown artist.
  static String? _artistOf(MediaItem item) => isUnknownArtistName(item.artist) ? null : item.artist;

  static bool _isWebLink(String uri) => uri.startsWith('https://') || uri.startsWith('http://');

  /// Icon and label of [action] for [item]; [isFavorite] picks the heart.
  static (IconData, String) describe(MediaAction action, {bool isFavorite = false}) {
    return switch (action) {
      MediaAction.play => (Icons.play_arrow_rounded, 'Play'),
      MediaAction.playAsAudio => (Icons.headphones_rounded, 'Play as audio'),
      MediaAction.pictureInPicture => (Icons.picture_in_picture_alt_rounded, 'Picture-in-picture'),
      MediaAction.playNext => (Icons.playlist_play_rounded, 'Play next'),
      MediaAction.addToQueue => (Icons.queue_music_rounded, 'Add to queue'),
      MediaAction.addToPlaylist => (Icons.playlist_add_rounded, 'Add to playlist…'),
      MediaAction.removeFromPlaylist => (Icons.playlist_remove_rounded, 'Remove from this playlist'),
      MediaAction.favorite => isFavorite
          ? (Icons.favorite_rounded, 'Remove from $likedSongs')
          : (Icons.favorite_border_rounded, 'Add to $likedSongs'),
      MediaAction.goToAlbum => (Icons.album_rounded, 'Go to album'),
      MediaAction.goToArtist => (Icons.person_rounded, 'Go to artist'),
      MediaAction.download => (Icons.file_download_rounded, 'Download'),
      MediaAction.copyLink => (Icons.link_rounded, 'Copy link'),
      MediaAction.share => (Icons.share_rounded, 'Share'),
      MediaAction.details => (Icons.info_outline_rounded, 'Details'),
      MediaAction.delete => (Icons.delete_outline_rounded, 'Delete from phone'),
    };
  }

  /// The "Details" rows for [item]: (label, value, whether it is a figure).
  @visibleForTesting
  static List<(String, String, bool)> detailRows(MediaItem item) => _MediaDetails.rowsFor(item);

  /// The MIME type to share [item] with.
  @visibleForTesting
  static String shareMimeType(MediaItem item) {
    final kind = item.mediaType == MediaType.video ? 'video' : 'audio';
    final format = item.format?.trim().toLowerCase();
    if (item.source == 'device' && format != null && format.isNotEmpty && !format.contains('/')) {
      // MediaStore songs keep their MIME subtype ("mpeg", "mp4").
      return '$kind/$format';
    }
    final fromName = ShareChannel.mimeTypeFor(item.uri, fallback: '');
    if (fromName.isNotEmpty) return fromName;
    if (format != null && format.isNotEmpty) return ShareChannel.mimeTypeFor('x.$format', fallback: '$kind/*');
    return '$kind/*';
  }

  static void showNewPlaylistDialog(BuildContext context, WidgetRef ref, {MediaItem? initialSong}) {
    _showNewPlaylistDialog(context, ProviderScope.containerOf(context, listen: false), initialSong: initialSong);
  }

  static void _showNewPlaylistDialog(BuildContext context, ProviderContainer container, {MediaItem? initialSong}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog<void>(
      context: context,
      builder: (_) => _NewPlaylistDialog(
        onCreate: (name) async {
          final repo = container.read(libraryRepositoryProvider);
          final pl = await repo.createPlaylist(name);
          if (initialSong != null) {
            final song = initialSong.isOnline ? await repo.saveOnlineItem(initialSong) : initialSong;
            await repo.addSongToPlaylist(pl.id, song.id);
          }
          if (messenger != null && messenger.mounted) {
            messenger.showSnackBar(SnackBar(content: Text('Created playlist "${pl.name}"')));
          }
        },
      ),
    );
  }
}

/// "New Playlist": a name field, Cancel and Create. Owns its text
/// controller, so the field outlives the dialog's closing animation.
class _NewPlaylistDialog extends StatefulWidget {
  final Future<void> Function(String name) onCreate;

  const _NewPlaylistDialog({required this.onCreate});

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context);
    widget.onCreate(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _create(),
        style: context.typography.body,
        decoration: InputDecoration(
          hintText: 'Playlist name',
          prefixIcon: Icon(Icons.queue_music_rounded, color: context.palette.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// One opening of the media menu: the item, where it was opened, and the
/// providers it acts through (the caller's container, which outlives the row
/// that opened it).
class _MediaMenu {
  _MediaMenu(this.context, this.item, this.playlistEntry)
      : container = ProviderScope.containerOf(context, listen: false),
        messenger = ScaffoldMessenger.maybeOf(context);

  /// Where the menu was opened: navigation ("Go to album") happens on its
  /// navigator.
  final BuildContext context;
  final MediaItem item;
  final PlaylistEntryRef? playlistEntry;
  final ProviderContainer container;
  final ScaffoldMessengerState? messenger;

  MediaMenuPlatform get _platform => container.read(mediaMenuPlatformProvider);
  LibraryRepository get _repo => container.read(libraryRepositoryProvider);
  PlaybackNotifier get _playback => container.read(playbackNotifierProvider.notifier);

  /// The app's own theme lives above the root navigator: sheets and dialogs
  /// opened from there use it even when the menu is opened from the always-ink
  /// Now Playing.
  BuildContext get _appContext => Navigator.of(context, rootNavigator: true).context;

  static bool _wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 || MediaQuery.orientationOf(context) == Orientation.landscape;

  Future<void> open(BuildContext anchor, Set<MediaAction> without) async {
    final pip = item.mediaType == MediaType.video && !item.isOnline && await _platform.isPipSupported();
    if (!context.mounted) return;
    final actions = MediaContextMenu.actionsFor(
      item,
      canDelete: container.read(mediaFileDeleterProvider).canDelete(item),
      pipSupported: pip,
      downloadsSupported: PlatformInfo.supportsDownloads,
      shareSupported: _platform.shareSupported,
      inPlaylist: playlistEntry != null,
    ).where((a) => !without.contains(a)).toList();

    final MediaAction? chosen;
    if (_wide(context)) {
      final favorite = actions.contains(MediaAction.favorite) ? await _currentFavorite() : false;
      if (!context.mounted || !anchor.mounted) return;
      chosen = await _showPopup(anchor, actions, favorite);
    } else {
      chosen = await _showSheet(actions);
    }
    if (chosen != null) await perform(chosen);
  }

  Future<MediaAction?> _showSheet(List<MediaAction> actions) {
    final appContext = _appContext;
    return showModalBottomSheet<MediaAction>(
      context: appContext,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(appContext).height * 0.9),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _MediaSheet(item: item, actions: actions),
      ),
    );
  }

  Future<MediaAction?> _showPopup(BuildContext anchor, List<MediaAction> actions, bool favorite) {
    final appContext = _appContext;
    final overlay = Navigator.of(appContext).overlay!.context.findRenderObject()! as RenderBox;
    final box = anchor.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final palette = appContext.palette;
    return showMenu<MediaAction>(
      context: appContext,
      position: position,
      items: [
        for (final action in actions) ...[
          if (action == MediaAction.delete) const PopupMenuDivider(),
          PopupMenuItem<MediaAction>(
            value: action,
            height: MediaContextMenu.menuRowHeight,
            child: _MenuItemLabel(action: action, isFavorite: favorite, palette: palette),
          ),
        ],
      ],
    );
  }

  /// The live favourite flag (the item may be an older snapshot, such as the
  /// copy the playback queue holds).
  Future<bool> _currentFavorite() async {
    final completer = Completer<bool>();
    final sub = container.listen<AsyncValue<bool>>(
      isFavoriteProvider(item.id),
      (_, next) {
        final value = next.asData?.value;
        if (value != null && !completer.isCompleted) completer.complete(value);
      },
      fireImmediately: true,
    );
    try {
      return await completer.future.timeout(const Duration(milliseconds: 500), onTimeout: () => item.isFavorite);
    } finally {
      sub.close();
    }
  }

  void _snack(String text, {SnackBarAction? action, Duration duration = const Duration(seconds: 3)}) {
    final m = messenger;
    if (m == null || !m.mounted) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      duration: duration,
      persist: action == null ? null : false,
      action: action,
    ));
  }

  Future<void> perform(MediaAction action) async {
    switch (action) {
      case MediaAction.play:
        if (!_fileIsThere()) return;
        if (context.mounted) _platform.openVideo(context, item);
      case MediaAction.playAsAudio:
        if (!_fileIsThere()) return;
        await _playback.loadQueue([item], shuffle: _playback.shuffleMode);
        _snack('Playing as audio: ${MediaContextMenu.shownTitle(item)}', duration: const Duration(seconds: 2));
      case MediaAction.pictureInPicture:
        await _pictureInPicture();
      case MediaAction.playNext:
        if (!_fileIsThere()) return;
        _playback.playNext(item);
        _snack('Playing next: ${item.title}', duration: const Duration(seconds: 2));
      case MediaAction.addToQueue:
        if (!_fileIsThere()) return;
        _addToQueue();
      case MediaAction.addToPlaylist:
        if (context.mounted) _AddToPlaylistSheet.show(_appContext, container, messenger, item);
      case MediaAction.removeFromPlaylist:
        await _removeFromPlaylist();
      case MediaAction.favorite:
        await _toggleFavorite();
      case MediaAction.goToAlbum:
        await _goToAlbum();
      case MediaAction.goToArtist:
        _goToArtist();
      case MediaAction.download:
        container.read(downloadLinkInboxProvider.notifier).send(PendingDownloadLink(item.uri, title: item.title));
        if (context.mounted) _platform.openTab(context, '/downloads');
      case MediaAction.copyLink:
        await _platform.copyText(_shareLink());
        _snack('Link copied', duration: const Duration(seconds: 2));
      case MediaAction.share:
        await _share();
      case MediaAction.details:
        if (context.mounted) await _MediaDetails.show(_appContext, item);
      case MediaAction.delete:
        await _delete();
    }
  }

  /// A download whose file has gone cannot play; device items are checked by
  /// the player itself.
  bool _fileIsThere() {
    final missing = item.availability == MediaAvailability.missing ||
        (item.source == 'download' && !item.uri.contains('://') && !File(item.uri).existsSync());
    if (missing) _snack('File is missing or unavailable on storage');
    return !missing;
  }

  void _addToQueue() {
    _playback.addToQueue(item);
    _snack(
      'Added to queue: ${item.title}',
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          // The queue updates asynchronously, so the copy just added is found
          // by id (the last one) rather than by the queue's old length.
          final state = container.read(playbackNotifierProvider);
          final index = state.queue.lastIndexWhere((m) => m.id == item.id);
          if (index >= 0 && index != state.queueIndex) _playback.removeQueueItemAt(index);
        },
      ),
    );
  }

  /// The link "Copy link" and "Share" hand out for an Online item: the
  /// short youtu.be form without tracking parameters.
  String _shareLink() => canonicalYouTubeLink(Uri.tryParse(item.uri)) ?? item.uri;

  Future<void> _share() async {
    final bool ok;
    if (item.isOnline) {
      ok = await _platform.shareText(_shareLink());
    } else {
      ok = await _platform.shareFile(
        uriOrPath: item.uri,
        mimeType: MediaContextMenu.shareMimeType(item),
        title: MediaContextMenu.shownTitle(item),
      );
    }
    if (!ok) _snack("Couldn't open the share sheet.");
  }

  Future<void> _removeFromPlaylist() async {
    final entry = playlistEntry;
    if (entry == null) return;
    final repo = _repo;
    await repo.removeSongFromPlaylist(entry.playlistId, item.id, entry.position);
    _snack(
      'Removed from ${entry.playlistName}',
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => repo.insertSongIntoPlaylist(entry.playlistId, item.id, entry.position),
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    final repo = _repo;
    var id = item.id;
    if (item.isOnline) {
      try {
        id = (await repo.saveOnlineItem(item)).id;
      } catch (_) {
        _snack("Couldn't save this video.");
        return;
      }
    }
    final next = !await _currentFavorite();
    HapticFeedback.lightImpact();
    await repo.toggleFavorite(id);
    final m = messenger;
    if (m == null || !m.mounted) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(next ? 'Added to ${MediaContextMenu.likedSongs}' : 'Removed from ${MediaContextMenu.likedSongs}'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(
        left: AppSpacing.lg16,
        right: AppSpacing.lg16,
        bottom: MediaContextMenu._snackBarBottomClearance,
      ),
      duration: const Duration(seconds: 3),
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => repo.toggleFavorite(id)),
    ));
  }

  Future<void> _goToAlbum() async {
    final name = MediaContextMenu._albumOf(item);
    if (name == null) return;
    // The album's own group (by its key, so a same-named album by someone
    // else is never opened), with the same cover as its tile; a plain group
    // if the library does not answer in time.
    AlbumGroup? group;
    try {
      group = await _repo.findAlbumOf(item).timeout(const Duration(seconds: 2));
    } catch (_) {}
    group ??= AlbumGroup(
      album: name,
      artist: item.albumArtist ?? item.artist ?? ArtistGroup.unknownArtist,
      songCount: 0,
      totalDurationMs: 0,
      coverUri: item.uri,
      coverArtworkPath: item.artworkPath,
      key: LibraryRepositoryImpl.albumKeyOfItem(item),
    );
    if (!context.mounted) return;
    final album = group;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlbumDetailScreen(album: album)));
  }

  void _goToArtist() {
    final name = MediaContextMenu._artistOf(item);
    if (name == null || !context.mounted) return;
    final artist = ArtistGroup(artist: name, songCount: 0);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistDetailScreen(artist: artist)));
  }

  Future<void> _pictureInPicture() async {
    if (!_fileIsThere() || !context.mounted) return;
    _platform.openVideo(context, item);
    // The player claims picture-in-picture as it comes on screen; enter it
    // once that claim is out (the channel keeps the calls in order).
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final ok = await _platform.enterPip();
    if (!ok) _snack('Picture-in-picture is not available on this device.');
  }

  Future<void> _delete() async {
    final playback = container.read(playbackNotifierProvider);
    if (playback.currentItemId == item.id) {
      _snack('This is playing now. Play something else first, then delete it.');
      return;
    }
    if (!context.mounted) return;
    final shown = MediaContextMenu.shownTitle(item);
    final confirmed = await showDialog<bool>(
      context: _appContext,
      builder: (ctx) {
        final palette = ctx.palette;
        return AlertDialog(
          icon: Icon(Icons.delete_outline_rounded, color: palette.error),
          title: const Text('Delete from phone?'),
          content: Text(
            '"${breakableTitle(shown)}" will be removed from this phone. This can\'t be undone.',
            semanticsLabel: '"$shown" will be removed from this phone. This can\'t be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: palette.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await container.read(mediaFileDeleterProvider).delete(item);
    } catch (_) {
      _snack('Could not delete "$shown".');
      return;
    }
    // Out of the queue too, so it is not tried later.
    try {
      await removeFromPlayQueue(container, item.id);
    } catch (_) {}
    _snack('Deleted "$shown"');
  }
}

/// The phone layout: header, then one row per action.
class _MediaSheet extends ConsumerWidget {
  final MediaItem item;
  final List<MediaAction> actions;

  const _MediaSheet({required this.item, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final isFavorite = actions.contains(MediaAction.favorite)
        ? ref.watch(isFavoriteProvider(item.id)).asData?.value ?? item.isFavorite
        : false;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(item: item),
            Divider(height: 1, thickness: 1, color: palette.divider),
            const SizedBox(height: AppSpacing.xs4),
            for (final action in actions) ...[
              if (action == MediaAction.delete)
                Divider(height: AppSpacing.sm8 * 2 + 1, thickness: 1, color: palette.divider),
              _SheetRow(
                action: action,
                isFavorite: isFavorite,
                onTap: () => Navigator.of(context).pop(action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 56 dp art, the title (two lines, wrapping after "_") and a meta line.
class _SheetHeader extends StatelessWidget {
  final MediaItem item;

  const _SheetHeader({required this.item});

  static String metaLine(MediaItem item) {
    if (item.isOnline) {
      final artist = item.artist;
      return [
        if (artist != null && artist.isNotEmpty) artist,
        if (item.durationMs > 0) formatClock(Duration(milliseconds: item.durationMs)),
        'Online',
      ].join(' · ');
    }
    if (item.mediaType == MediaType.video) {
      return [
        if (item.durationMs > 0) formatClock(Duration(milliseconds: item.durationMs)),
        if (item.sizeBytes > 0) formatFileSize(item.sizeBytes),
        if (item.source == 'download') 'Downloaded',
      ].join(' · ');
    }
    final artist = isUnknownArtistName(item.artist) ? ArtistGroup.unknownArtist : item.artist!;
    final album = item.album;
    return (album != null && album.isNotEmpty) ? '$artist · $album' : artist;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final meta = metaLine(item);
    const radius = AppSpacing.radiusArtSmall;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
      child: Row(
        children: [
          // Foreground, so the hairline sits on top of the opaque artwork.
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: palette.divider),
            ),
            child: ArtworkThumbnail(
              uri: item.uri,
              artworkPath: item.artworkPath,
              size: MediaContextMenu.headerArtSize,
              borderRadius: radius,
              placeholderIcon: item.mediaType == MediaType.video ? Icons.movie_outlined : Icons.music_note_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  breakableTitle(MediaContextMenu.shownTitle(item)),
                  semanticsLabel: MediaContextMenu.shownTitle(item),
                  style: type.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, style: type.metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 56 dp sheet row: a 24 dp textSecondary icon and a `body` label. The
/// favourite heart is filled Flare when on; Delete is in the error colour.
class _SheetRow extends StatelessWidget {
  final MediaAction action;
  final bool isFavorite;
  final VoidCallback onTap;

  const _SheetRow({required this.action, required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, label) = MediaContextMenu.describe(action, isFavorite: isFavorite);
    final color = _iconColor(action, isFavorite, palette);
    final labelColor = action == MediaAction.delete ? palette.error : palette.textPrimary;
    return ListTile(
      minTileHeight: MediaContextMenu.rowHeight,
      leading: Icon(icon, size: 24, color: color),
      title: Text(label, style: context.typography.body.copyWith(color: labelColor)),
      onTap: onTap,
    );
  }
}

Color _iconColor(MediaAction action, bool isFavorite, AppPalette palette) {
  if (action == MediaAction.delete) return palette.error;
  if (action == MediaAction.favorite && isFavorite) return palette.favorite;
  return palette.textSecondary;
}

/// The wide-screen popup's row content.
class _MenuItemLabel extends StatelessWidget {
  final MediaAction action;
  final bool isFavorite;
  final AppPalette palette;

  const _MenuItemLabel({required this.action, required this.isFavorite, required this.palette});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = MediaContextMenu.describe(action, isFavorite: isFavorite);
    return Row(
      children: [
        Icon(icon, size: 24, color: _iconColor(action, isFavorite, palette)),
        const SizedBox(width: AppSpacing.md12),
        Flexible(
          child: Text(
            label,
            style: action == MediaAction.delete ? TextStyle(color: palette.error) : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// "Add to playlist…": the same sheet shell with "Liked songs" pinned first,
/// then the playlists, and "New playlist" at the top. A playlist that already
/// holds the song shows a check; picking it says so and offers "Add anyway".
class _AddToPlaylistSheet extends StatelessWidget {
  final MediaItem item;
  final ProviderContainer container;
  final ScaffoldMessengerState? messenger;

  /// Where "New playlist" opens its dialog.
  final BuildContext hostContext;

  const _AddToPlaylistSheet({
    required this.item,
    required this.container,
    required this.messenger,
    required this.hostContext,
  });

  static void show(
    BuildContext appContext,
    ProviderContainer container,
    ScaffoldMessengerState? messenger,
    MediaItem item,
  ) {
    showModalBottomSheet<void>(
      context: appContext,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(appContext).height * 0.9),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _AddToPlaylistSheet(item: item, container: container, messenger: messenger, hostContext: appContext),
      ),
    );
  }

  void _snack(String text, {SnackBarAction? action}) {
    final m = messenger;
    if (m == null || !m.mounted) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      duration: Duration(seconds: action == null ? 2 : 4),
      persist: action == null ? null : false,
      action: action,
    ));
  }

  /// The id to file the song under: an Online item is saved first.
  Future<String?> _savedId() async {
    if (!item.isOnline) return item.id;
    try {
      return (await container.read(libraryRepositoryProvider).saveOnlineItem(item)).id;
    } catch (_) {
      _snack("Couldn't save this video.");
      return null;
    }
  }

  Future<void> _addTo(Playlist pl, {required bool alreadyThere}) async {
    final repo = container.read(libraryRepositoryProvider);
    if (alreadyThere) {
      _snack(
        'Already in ${pl.name}',
        action: SnackBarAction(
          label: 'Add anyway',
          onPressed: () => repo.addSongToPlaylist(pl.id, item.id, allowDuplicate: true),
        ),
      );
      return;
    }
    final id = await _savedId();
    if (id == null) return;
    final added = await repo.addSongToPlaylist(pl.id, id);
    if (added) {
      _snack('Added to ${pl.name}');
    } else {
      _snack(
        'Already in ${pl.name}',
        action: SnackBarAction(
          label: 'Add anyway',
          onPressed: () => repo.addSongToPlaylist(pl.id, id, allowDuplicate: true),
        ),
      );
    }
  }

  Future<void> _like(bool liked) async {
    if (liked) {
      _snack('Already in ${MediaContextMenu.likedSongs}');
      return;
    }
    final id = await _savedId();
    if (id == null) return;
    await container.read(libraryRepositoryProvider).toggleFavorite(id);
    _snack('Added to ${MediaContextMenu.likedSongs}');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final repo = container.read(libraryRepositoryProvider);
    return StreamBuilder<List<Playlist>>(
      stream: repo.watchPlaylists(),
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? const <Playlist>[];
        return StreamBuilder<Set<String>>(
          stream: repo.watchPlaylistIdsContaining(item.id),
          builder: (context, containing) {
            final holding = containing.data ?? const <String>{};
            return SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.sm8, 0),
                    // Title and "New playlist" share the row; when both do not
                    // fit (320 dp at large text) the button goes under the
                    // title instead of cutting it to "Add to ...".
                    child: OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Add to playlist',
                            key: const ValueKey('add_to_playlist_title'),
                            style: type.sectionTitle,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('New playlist'),
                          onPressed: () {
                            Navigator.pop(context);
                            if (!hostContext.mounted) return;
                            MediaContextMenu._showNewPlaylistDialog(hostContext, container, initialSong: item);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
                    child: Text(
                      item.title,
                      style: type.metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: palette.divider),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm8),
                      children: [
                        _LikedSongsRow(
                          itemId: item.id,
                          fallback: item.isFavorite,
                          onTap: (liked) {
                            Navigator.pop(context);
                            _like(liked);
                          },
                        ),
                        if (playlists.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xxl24,
                              vertical: AppSpacing.xl20,
                            ),
                            child: Text(
                              'No playlists yet. Create one above!',
                              style: type.body.copyWith(color: palette.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final pl in playlists)
                          _PlaylistPickRow(
                            playlist: pl,
                            contains: holding.contains(pl.id),
                            onTap: () {
                              Navigator.pop(context);
                              _addTo(pl, alreadyThere: holding.contains(pl.id));
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// "Liked songs" pinned first in the playlist picker: the heart cover, and
/// a check once the song is liked.
class _LikedSongsRow extends ConsumerWidget {
  final String itemId;
  final bool fallback;
  final void Function(bool liked) onTap;

  const _LikedSongsRow({required this.itemId, required this.fallback, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.typography;
    final liked = ref.watch(isFavoriteProvider(itemId)).asData?.value ?? fallback;
    return ListTile(
      minTileHeight: 64,
      leading: const LikedSongsCover(size: 48, borderRadius: AppSpacing.radiusArtSmall),
      title: Text(MediaContextMenu.likedSongs, style: type.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(liked ? 'Liked' : 'Tap to like', style: type.metadata),
      trailing: _PickMark(selected: liked),
      onTap: () => onTap(liked),
    );
  }
}

class _PlaylistPickRow extends StatelessWidget {
  final Playlist playlist;
  final bool contains;
  final VoidCallback onTap;

  const _PlaylistPickRow({required this.playlist, required this.contains, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final count = playlist.songCount == 1 ? '1 song' : '${playlist.songCount} songs';
    return Semantics(
      selected: contains,
      child: ListTile(
        minTileHeight: 64,
        leading: PlaylistCover(
          playlistId: playlist.id,
          coverSongs: playlist.coverSongs,
          size: 48,
          borderRadius: AppSpacing.radiusArtSmall,
        ),
        title: Text(playlist.name, style: type.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(contains ? '$count · Added' : count, style: type.metadata),
        trailing: _PickMark(selected: contains),
        onTap: onTap,
      ),
    );
  }
}

/// A check in primary once the song is in that list, a plus otherwise
/// (the word "Added" / "Liked" says it too, never the colour alone).
class _PickMark extends StatelessWidget {
  final bool selected;

  const _PickMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return selected
        ? Icon(Icons.check_circle_rounded, color: palette.primary)
        : Icon(Icons.add_rounded, color: palette.textSecondary);
  }
}

/// "Details": what the app knows about the item, figures in DM Mono.
class _MediaDetails {
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// (label, value, is a figure) rows for [item].
  static List<(String, String, bool)> rowsFor(MediaItem item) {
    final isVideo = item.mediaType == MediaType.video && !item.isOnline;
    final width = item.width;
    final height = item.height;
    final album = item.album;
    final artist = item.artist;
    final albumArtist = item.albumArtist;
    final lastPlayed = item.lastPlayed;
    final track = item.trackNumber;
    final disc = item.discNumber;
    final year = item.year;
    final genre = item.genre;
    return [
      ('Title', item.title, false),
      if (!isVideo && artist != null && artist.isNotEmpty) ('Artist', artist, false),
      if (!isVideo && album != null && album.isNotEmpty) ('Album', album, false),
      if (!isVideo && albumArtist != null && albumArtist.isNotEmpty && albumArtist != artist)
        ('Album artist', albumArtist, false),
      if (track != null) ('Track', disc != null && disc > 1 ? '$disc-$track' : '$track', true),
      if (year != null) ('Year', '$year', true),
      if (genre != null && genre.isNotEmpty) ('Genre', genre, false),
      if (item.durationMs > 0) ('Length', formatClock(Duration(milliseconds: item.durationMs)), true),
      if (item.sizeBytes > 0) ('Size', formatFileSize(item.sizeBytes), true),
      if (item.format != null && item.format!.isNotEmpty) ('Format', item.format!.toUpperCase(), false),
      if (isVideo && width != null && height != null && width > 0 && height > 0)
        ('Resolution', '$width × $height', true),
      ('Added', _date(item.dateAdded), false),
      if (item.playCount > 0) ('Plays', '${item.playCount}', true),
      if (lastPlayed != null) ('Last played', _date(lastPlayed), false),
      (
        'Saved',
        switch (item.source) {
          'download' => 'Downloaded to this phone',
          'online' => 'Online',
          _ => 'On this phone',
        },
        false,
      ),
      if (item.source == 'download' && !item.uri.contains('://')) ('File', item.uri, false),
    ];
  }

  static Future<void> show(BuildContext context, MediaItem item) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final palette = ctx.palette;
        final type = ctx.typography;
        return AlertDialog(
          title: const Text('Details'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value, figure) in rowsFor(item)) ...[
                Text(label, style: type.label),
                const SizedBox(height: 2),
                Text(
                  label == 'Title' ? breakableTitle(value) : value,
                  semanticsLabel: label == 'Title' ? value : null,
                  style: figure
                      ? type.tabularFigures.copyWith(fontSize: 14, height: 20 / 14, color: palette.textPrimary)
                      : type.body.copyWith(color: palette.textPrimary),
                ),
                const SizedBox(height: AppSpacing.md12),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }
}
