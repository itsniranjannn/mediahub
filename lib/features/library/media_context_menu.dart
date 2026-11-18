import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/widgets/favorite_feedback_button.dart' show isFavoriteProvider;
import '../downloads/download_link_inbox.dart';
import '../music_player/playback_notifier.dart';
import '../playlists/playlist_cover.dart';
import 'detail_screens.dart';

/// Everything the media sheet can do with an item (docs/DESIGN.md 7.10).
///
/// Which of them an item gets is decided by [MediaContextMenu.actionsFor]:
/// - songs: [playNext], [addToQueue], [addToPlaylist], [favorite],
///   [goToAlbum], [goToArtist], [details], then [delete];
/// - videos: [play], [playAsAudio], [pictureInPicture], [details], [delete];
/// - online items: [download], [copyLink], [details].
///
/// "Share" is not offered: the app has no share sheet yet (it needs a native
/// `ACTION_SEND` / `UIActivityViewController` bridge or the share_plus
/// plugin). "Delete" is offered only for downloads, the files the app owns;
/// removing a file another app put on the phone needs Android's
/// `MediaStore.createDeleteRequest`, which the native side does not expose.
enum MediaAction {
  play,
  playAsAudio,
  pictureInPicture,
  playNext,
  addToQueue,
  addToPlaylist,
  favorite,
  goToAlbum,
  goToArtist,
  download,
  copyLink,
  details,
  delete,
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

/// Deletes downloads: their file lives in the app's own storage, so the app
/// may remove it. Then its saved cover, its rows in Downloads, its playlist
/// entries (each playlist renumbered, as reordering works on positions), its
/// video progress and its library row go too.
class _DownloadedFileDeleter implements MediaFileDeleter {
  final Ref _ref;

  _DownloadedFileDeleter(this._ref);

  static bool _isLocalPath(String? path) =>
      path != null && path.isNotEmpty && !path.contains('://');

  @override
  bool canDelete(MediaItem item) => item.source == 'download' && _isLocalPath(item.uri);

  @override
  Future<void> delete(MediaItem item) async {
    if (!canDelete(item)) throw StateError('${item.id} is not a download');
    final db = _ref.read(appDatabaseProvider);
    final repo = _ref.read(libraryRepositoryProvider);

    final downloads = await (db.select(db.downloadsTable)..where((t) => t.mediaId.equals(item.id))).get();

    // The media file first: if it cannot go, the library keeps its row and
    // the song still plays.
    final media = File(item.uri);
    if (await media.exists()) await media.delete();
    for (final path in {item.artworkPath, for (final d in downloads) ...[d.finalPath, d.thumbnailPath]}) {
      if (!_isLocalPath(path) || path == item.uri) continue;
      try {
        final file = File(path!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A leftover cover is harmless; the startup sweep may still get it.
      }
    }

    final entries = await (db.select(db.playlistItemsTable)..where((t) => t.mediaId.equals(item.id))).get();
    // Highest position first, so removing one never moves the next.
    entries.sort((a, b) => b.position.compareTo(a.position));
    for (final entry in entries) {
      await repo.removeSongFromPlaylist(entry.playlistId, entry.mediaId, entry.position);
    }
    await (db.delete(db.videoProgressTable)..where((t) => t.mediaId.equals(item.id))).go();
    await (db.delete(db.downloadsTable)..where((t) => t.mediaId.equals(item.id))).go();
    await (db.delete(db.mediaItemsTable)..where((t) => t.id.equals(item.id))).go();
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

  /// The title the sheet, its dialogs and snackbars show: a video without
  /// its file extension, as on the video cards it opens from.
  static String shownTitle(MediaItem item) =>
      item.mediaType == MediaType.video ? videoDisplayTitle(item.title) : item.title;

  /// Opens the media sheet for [item].
  ///
  /// [anchorContext] is the ⋮ button the wide-screen popup hangs from
  /// (defaults to [context]). [without] drops actions that make no sense
  /// where the sheet is opened ("Go to album" on that album's page).
  /// [onCustomAction] is kept for older callers and is not used.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    MediaItem item, {
    VoidCallback? onCustomAction,
    BuildContext? anchorContext,
    Set<MediaAction> without = const {},
  }) {
    return _MediaMenu(context, item).open(anchorContext ?? context, without);
  }

  /// The actions [item] gets, in sheet order.
  @visibleForTesting
  static List<MediaAction> actionsFor(
    MediaItem item, {
    required bool canDelete,
    required bool pipSupported,
    bool downloadsSupported = true,
  }) {
    if (item.source == 'online') {
      final link = _isWebLink(item.uri);
      return [
        if (link && downloadsSupported) MediaAction.download,
        if (link) MediaAction.copyLink,
        MediaAction.details,
      ];
    }
    if (item.mediaType == MediaType.video) {
      return [
        MediaAction.play,
        MediaAction.playAsAudio,
        if (pipSupported) MediaAction.pictureInPicture,
        MediaAction.details,
        if (canDelete) MediaAction.delete,
      ];
    }
    return [
      MediaAction.playNext,
      MediaAction.addToQueue,
      MediaAction.addToPlaylist,
      MediaAction.favorite,
      if (_albumOf(item) != null) MediaAction.goToAlbum,
      if (_artistOf(item) != null) MediaAction.goToArtist,
      MediaAction.details,
      if (canDelete) MediaAction.delete,
    ];
  }

  /// The album name to open, or null when the song has none.
  static String? _albumOf(MediaItem item) {
    final album = item.album?.trim();
    return (album == null || album.isEmpty) ? null : item.album;
  }

  /// The artist name to open, or null for an unknown artist (the scan stores
  /// "Unknown Artist" for those).
  static String? _artistOf(MediaItem item) {
    final artist = item.artist?.trim();
    if (artist == null || artist.isEmpty) return null;
    final lower = artist.toLowerCase();
    if (lower == 'unknown artist' || lower == '<unknown>') return null;
    return item.artist;
  }

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
      MediaAction.favorite => isFavorite
          ? (Icons.favorite_rounded, 'Remove from favorites')
          : (Icons.favorite_border_rounded, 'Add to favorites'),
      MediaAction.goToAlbum => (Icons.album_rounded, 'Go to album'),
      MediaAction.goToArtist => (Icons.person_rounded, 'Go to artist'),
      MediaAction.download => (Icons.file_download_rounded, 'Download'),
      MediaAction.copyLink => (Icons.link_rounded, 'Copy link'),
      MediaAction.details => (Icons.info_outline_rounded, 'Details'),
      MediaAction.delete => (Icons.delete_outline_rounded, 'Delete from phone'),
    };
  }

  /// The "Details" rows for [item]: (label, value, whether it is a figure).
  @visibleForTesting
  static List<(String, String, bool)> detailRows(MediaItem item) => _MediaDetails.rowsFor(item);

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
          if (initialSong != null) await repo.addSongToPlaylist(pl.id, initialSong.id);
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
  _MediaMenu(this.context, this.item)
      : container = ProviderScope.containerOf(context, listen: false),
        messenger = ScaffoldMessenger.maybeOf(context);

  /// Where the menu was opened: navigation ("Go to album") happens on its
  /// navigator.
  final BuildContext context;
  final MediaItem item;
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
    final pip = item.mediaType == MediaType.video && item.source != 'online' && await _platform.isPipSupported();
    if (!context.mounted) return;
    final actions = MediaContextMenu.actionsFor(
      item,
      canDelete: container.read(mediaFileDeleterProvider).canDelete(item),
      pipSupported: pip,
      downloadsSupported: PlatformInfo.supportsDownloads,
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
        await _playback.loadQueue([item]);
        _snack('Playing as audio: ${MediaContextMenu.shownTitle(item)}', duration: const Duration(seconds: 2));
      case MediaAction.pictureInPicture:
        await _pictureInPicture();
      case MediaAction.playNext:
        _playback.playNext(item);
        _snack('Playing next: ${item.title}', duration: const Duration(seconds: 2));
      case MediaAction.addToQueue:
        _addToQueue();
      case MediaAction.addToPlaylist:
        if (context.mounted) _AddToPlaylistSheet.show(_appContext, container, messenger, item);
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
        await _platform.copyText(item.uri);
        _snack('Link copied', duration: const Duration(seconds: 2));
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

  Future<void> _toggleFavorite() async {
    final next = !await _currentFavorite();
    HapticFeedback.lightImpact();
    final repo = _repo;
    await repo.toggleFavorite(item.id);
    final m = messenger;
    if (m == null || !m.mounted) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(next ? 'Added to Favorites' : 'Removed from Favorites'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(
        left: AppSpacing.lg16,
        right: AppSpacing.lg16,
        bottom: MediaContextMenu._snackBarBottomClearance,
      ),
      duration: const Duration(seconds: 3),
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => repo.toggleFavorite(item.id)),
    ));
  }

  Future<void> _goToAlbum() async {
    final name = MediaContextMenu._albumOf(item);
    if (name == null) return;
    // The album's own group, so its page shows the same cover as its tile;
    // a plain group if the library does not answer in time.
    AlbumGroup? group;
    try {
      final albums = await _repo.watchAlbums(searchQuery: name).first.timeout(const Duration(seconds: 2));
      group = albums.where((a) => a.album == name).firstOrNull;
    } catch (_) {}
    group ??= AlbumGroup(
      album: name,
      artist: item.artist ?? 'Unknown artist',
      songCount: 0,
      totalDurationMs: 0,
      coverUri: item.uri,
      coverArtworkPath: item.artworkPath,
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
    final queue = container.read(playbackNotifierProvider);
    for (var i = queue.queue.length - 1; i >= 0; i--) {
      if (queue.queue[i].id == item.id && i != queue.queueIndex) await _playback.removeQueueItemAt(i);
    }
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
    if (item.mediaType == MediaType.video) {
      return [
        if (item.durationMs > 0) formatClock(Duration(milliseconds: item.durationMs)),
        if (item.sizeBytes > 0) formatFileSize(item.sizeBytes),
        if (item.source == 'download') 'Downloaded',
      ].join(' · ');
    }
    final artist = item.artist ?? 'Unknown artist';
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

/// "Add to playlist…": the same sheet shell with the playlists, and "New
/// playlist" at the top.
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    return StreamBuilder<List<Playlist>>(
      stream: container.read(libraryRepositoryProvider).watchPlaylists(),
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? const <Playlist>[];
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.sm8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Add to playlist',
                          style: type.sectionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl24, vertical: AppSpacing.xxxl32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.queue_music_rounded, size: 36, color: palette.primary),
                      const SizedBox(height: AppSpacing.md12),
                      Text(
                        'No playlists yet. Create one above!',
                        style: type.body.copyWith(color: palette.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm8),
                    itemCount: playlists.length,
                    itemBuilder: (itemContext, index) {
                      final pl = playlists[index];
                      return ListTile(
                        minTileHeight: 64,
                        leading: PlaylistCover(
                          playlistId: pl.id,
                          size: 48,
                          borderRadius: AppSpacing.radiusArtSmall,
                        ),
                        title: Text(pl.name, style: type.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          pl.songCount == 1 ? '1 song' : '${pl.songCount} songs',
                          style: type.metadata,
                        ),
                        trailing: Icon(Icons.add_rounded, color: palette.textSecondary),
                        onTap: () async {
                          Navigator.pop(context);
                          await container.read(libraryRepositoryProvider).addSongToPlaylist(pl.id, item.id);
                          final m = messenger;
                          if (m != null && m.mounted) {
                            m.showSnackBar(SnackBar(
                              content: Text('Added to ${pl.name}'),
                              duration: const Duration(seconds: 2),
                            ));
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
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
    final isVideo = item.mediaType == MediaType.video;
    final width = item.width;
    final height = item.height;
    final album = item.album;
    final artist = item.artist;
    final lastPlayed = item.lastPlayed;
    return [
      ('Title', item.title, false),
      if (!isVideo && artist != null && artist.isNotEmpty) ('Artist', artist, false),
      if (!isVideo && album != null && album.isNotEmpty) ('Album', album, false),
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
