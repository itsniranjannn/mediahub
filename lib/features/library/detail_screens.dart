import 'package:flutter/gestures.dart' show DelayedMultiDragGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../shared/widgets/artwork_placeholder.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/media_context_menu.dart';
import '../library/media_song_row.dart';
import '../music_player/playback_notifier.dart';
import '../playlists/playlist_cover.dart';
import 'playable.dart';

/// Size of the cover in the hero header of every detail screen.
const double _kHeroArtSize = 168;

/// Corner radius of a square hero cover: the thumbnail radius, so it reads
/// as album art rather than an app icon.
const double _kHeroArtRadius = AppSpacing.radiusThumb;

/// The signature hard "print offset" under the hero cover (docs/DESIGN.md
/// 7.1): 6 x 6 dp, no blur, Volt on ink and ink on paper.
const Offset _kPrintOffset = Offset(6, 6);

/// Platform lookup size of the hero cover (ArtworkThumbnail asks for 512 px
/// art for boxes up to 300 dp); the tint check shares that lookup.
const int _kHeroLookupSize = 512;

/// Scroll distance after which the hero title is under the app bar, so the
/// app bar shows the title instead.
const double _kCollapseOffset = _kHeroArtSize + 48;

/// Placeholder seeds for album and artist covers (shared with their tiles).
String _albumSeed(AlbumGroup album) => ArtworkPlaceholder.albumSeed(album.album);
String _artistSeed(ArtistGroup artist) => ArtworkPlaceholder.artistSeed(artist.artist);

/// The song whose cover stands for [album]: the one its tile in Music >
/// Albums shows, or the first song when the tile has none.
MediaItem _albumCoverSong(AlbumGroup album, List<MediaItem> songs) {
  final coverUri = album.coverUri;
  if (coverUri == null) return songs.first;
  return songs.firstWhere((song) => song.uri == coverUri, orElse: () => songs.first);
}

PlaybackNotifier _playback(WidgetRef ref) => ref.read(playbackNotifierProvider.notifier);

/// "Couldn't load the songs" with a Retry, for every detail page.
Widget _loadError(String what, VoidCallback onRetry) => EmptyHint(
      icon: Icons.error_outline_rounded,
      title: "Couldn't load $what",
      message: 'Something went wrong reading your library.',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: const Text('Retry'),
      ),
    );

/// The ⋮ in a detail page's app bar: the collection menu for all of its
/// songs ([songs] while they load is empty, and the menu waits).
Widget _collectionMenuButton({
  required WidgetRef ref,
  required String title,
  required List<MediaItem>? songs,
  List<_CollectionExtra> extras = const [],
}) {
  return Builder(
    builder: (buttonContext) => IconButton(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'More options',
      onPressed: songs == null
          ? null
          : () => _CollectionMenu.show(buttonContext, ref, title: title, songs: songs, extras: extras),
    ),
  );
}

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumGroup album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _albumSongsProvider(album.lookupKey);
    final songsAsync = ref.watch(provider);

    return _DetailScaffold(
      title: album.album,
      // Only the song list has a hero; loading / error / empty need the bar title.
      showTitle: !songsAsync.maybeWhen(data: (songs) => songs.isNotEmpty, orElse: () => false),
      actions: [
        _collectionMenuButton(ref: ref, title: album.album, songs: songsAsync.asData?.value),
      ],
      body: songsAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return const EmptyHint(
              icon: Icons.album_rounded,
              title: 'No songs in album',
              message: 'Songs from this album are no longer in your library.',
            );
          }
          final cover = _albumCoverSong(album, songs);
          final year = album.year ?? _yearOf(songs);
          return Scrollbar(
            interactive: true,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  // A real cover gets the neutral violet glow: the placeholder's
                  // palette would clash with the cover's own colours.
                  child: ArtworkPresenceBuilder(
                    item: cover,
                    lookupSize: _kHeroLookupSize,
                    builder: (context, hasArtwork, _) => _HeroHeader(
                      tint: hasArtwork
                          ? context.palette.heroGradient
                          : ArtworkTint.surfaceGradient(_albumSeed(album), context.palette),
                      artwork: _HeroArtwork(
                        child: ArtworkThumbnail(
                          uri: cover.uri,
                          artworkPath: cover.artworkPath,
                          size: _kHeroArtSize,
                          borderRadius: _kHeroArtRadius,
                          placeholderIcon: Icons.album_rounded,
                          // Same colours as the album's tile in Music > Albums.
                          placeholderSeed: _albumSeed(album),
                        ),
                      ),
                      eyebrow: 'Album',
                      title: album.album,
                      subtitle: album.artist,
                      meta: songsMeta(songs, year: year),
                      onPlay: () => playCollection(_playback(ref), songs),
                      onShuffle: () => playCollection(_playback(ref), songs, shuffle: true),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return MediaSongRow(
                      item: song,
                      // The real track number when the song is tagged.
                      index: song.trackNumber ?? index + 1,
                      menuWithout: const {MediaAction.goToAlbum},
                      onTap: () => playCollection(_playback(ref), songs, start: song),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _loadError('the songs', () => ref.invalidate(provider)),
      ),
    );
  }

  static int? _yearOf(List<MediaItem> songs) {
    int? year;
    for (final s in songs) {
      final y = s.year;
      if (y != null && (year == null || y > year)) year = y;
    }
    return year;
  }
}

class ArtistDetailScreen extends ConsumerWidget {
  final ArtistGroup artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _artistSongsProvider(artist.artist);
    final songsAsync = ref.watch(provider);

    return _DetailScaffold(
      title: artist.artist,
      // Only the song list has a hero; loading / error / empty need the bar title.
      showTitle: !songsAsync.maybeWhen(data: (songs) => songs.isNotEmpty, orElse: () => false),
      actions: [
        _collectionMenuButton(ref: ref, title: artist.artist, songs: songsAsync.asData?.value),
      ],
      body: songsAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return const EmptyHint(
              icon: Icons.person_rounded,
              title: 'No songs for artist',
              message: 'Songs by this artist are no longer in your library.',
            );
          }
          return Scrollbar(
            interactive: true,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  // A real cover gets the neutral violet glow (see the album).
                  child: ArtworkPresenceBuilder(
                    item: songs.first,
                    lookupSize: _kHeroLookupSize,
                    builder: (context, hasArtwork, _) => _HeroHeader(
                      tint: hasArtwork
                          ? context.palette.heroGradient
                          : ArtworkTint.surfaceGradient(_artistSeed(artist), context.palette),
                      artwork: _HeroArtwork(
                        circle: true,
                        child: ArtworkThumbnail(
                          uri: songs.first.uri,
                          artworkPath: songs.first.artworkPath,
                          size: _kHeroArtSize,
                          borderRadius: _kHeroArtSize / 2, // Circular for artist
                          placeholderIcon: Icons.person_rounded,
                          placeholderSeed: _artistSeed(artist),
                        ),
                      ),
                      eyebrow: 'Artist',
                      title: artist.artist,
                      meta: songsMeta(songs),
                      onPlay: () => playCollection(_playback(ref), songs),
                      onShuffle: () => playCollection(_playback(ref), songs, shuffle: true),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return MediaSongRow(
                      item: song,
                      menuWithout: const {MediaAction.goToArtist},
                      onTap: () => playCollection(_playback(ref), songs, start: song),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _loadError('the songs', () => ref.invalidate(provider)),
      ),
    );
  }
}

/// Liked songs ("wishlist"), the playlist every song's heart adds to: newest
/// liked first, songs on the phone, downloads and liked Online videos (those
/// open in the Online tab).
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(_likedSongsProvider);
    const title = MediaContextMenu.likedSongs;

    return _DetailScaffold(
      title: title,
      showTitle: !songsAsync.maybeWhen(data: (_) => true, orElse: () => false),
      actions: [
        _collectionMenuButton(ref: ref, title: title, songs: songsAsync.asData?.value),
      ],
      body: songsAsync.when(
        data: (songs) {
          final playable = playableOnly(songs);
          final header = _HeroHeader(
            tint: LikedSongsCover.heroTint(context.palette),
            artwork: const _HeroArtwork(
              child: LikedSongsCover(size: _kHeroArtSize, borderRadius: _kHeroArtRadius),
            ),
            eyebrow: 'Playlist',
            title: title,
            meta: songsMeta(songs),
            onPlay: playable.isEmpty ? null : () => playCollection(_playback(ref), songs),
            onShuffle: playable.isEmpty ? null : () => playCollection(_playback(ref), songs, shuffle: true),
          );
          if (songs.isEmpty) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyHint(
                    icon: Icons.favorite_border_rounded,
                    title: 'No liked songs yet',
                    message: 'Tap the heart on any song to keep it here.',
                  ),
                ),
              ],
            );
          }
          return Scrollbar(
            interactive: true,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return MediaSongRow(
                      item: song,
                      onTap: () => playCollection(_playback(ref), songs, start: song),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _loadError('your liked songs', () => ref.invalidate(_likedSongsProvider)),
      ),
    );
  }
}

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  /// The order the user just dragged the rows into, shown until the database
  /// reports it (so a row does not jump back for a frame).
  List<PlaylistTrack>? _order;

  /// Reorders sent and not finished yet.
  int _pendingReorders = 0;

  /// Rows swiped away ([_trackKey]), hidden until the database no longer has
  /// them: a dismissed row has to leave the list at once.
  final Set<String> _removed = {};

  /// The page is closing (deleted here, or the playlist went away).
  bool _closing = false;

  String get _id => widget.playlist.id;

  static String _trackKey(PlaylistTrack t) => '${t.item.id}_${t.position}';

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final playlistProvider = _playlistProvider(_id);
    final tracksProvider = _playlistTracksProvider(_id);

    // The live row: its new name after a rename; the page closes when it is
    // deleted (here or anywhere else).
    ref.listen<AsyncValue<Playlist?>>(playlistProvider, (_, next) {
      if (next.hasValue && next.value == null) _close();
    });
    ref.listen<AsyncValue<List<PlaylistTrack>>>(tracksProvider, (_, next) {
      final list = next.asData?.value;
      if (list == null) return;
      final keys = {for (final t in list) _trackKey(t)};
      final clearOrder = _order != null && _pendingReorders == 0;
      final gone = _removed.where((k) => !keys.contains(k)).toList();
      if (clearOrder || gone.isNotEmpty) {
        setState(() {
          if (clearOrder) _order = null;
          _removed.removeAll(gone);
        });
      }
    });

    final playlist = ref.watch(playlistProvider).asData?.value ?? widget.playlist;
    final tracksAsync = ref.watch(tracksProvider);
    final base = _order ?? tracksAsync.asData?.value;
    final tracks = base == null ? null : [for (final t in base) if (!_removed.contains(_trackKey(t))) t];
    final songs = tracks == null ? null : [for (final t in tracks) t.item];

    return _DetailScaffold(
      title: playlist.name,
      // An empty playlist still shows its hero; loading / error need the bar title.
      showTitle: tracks == null,
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          tooltip: 'Rename',
          onPressed: () => _showRenameDialog(playlist),
        ),
        _collectionMenuButton(
          ref: ref,
          title: playlist.name,
          songs: songs,
          extras: [
            _CollectionExtra(Icons.add_rounded, 'Add songs', () => _openAddSongs(playlist)),
            _CollectionExtra(Icons.delete_outline_rounded, 'Delete playlist', () => _showDeleteConfirmation(playlist),
                destructive: true),
          ],
        ),
      ],
      body: tracks == null
          ? tracksAsync.maybeWhen(
              error: (err, _) => _loadError('this playlist', () => ref.invalidate(tracksProvider)),
              orElse: () => const Center(child: CircularProgressIndicator()),
            )
          : _buildList(context, playlist, tracks),
    );
  }

  Widget _buildList(BuildContext context, Playlist playlist, List<PlaylistTrack> tracks) {
    final songs = [for (final t in tracks) t.item];
    final playable = playableOnly(songs);
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroHeader(
          tint: PlaylistCover.heroTint(playlist.id, context.palette),
          artwork: _HeroArtwork(
            child: PlaylistCover(
              playlistId: playlist.id,
              coverSongs: playlist.coverSongs,
              size: _kHeroArtSize,
              borderRadius: _kHeroArtRadius,
            ),
          ),
          eyebrow: 'Playlist',
          title: playlist.name,
          meta: songsMeta(songs),
          onPlay: playable.isEmpty ? null : () => playCollection(_playback(ref), songs),
          onShuffle: playable.isEmpty ? null : () => playCollection(_playback(ref), songs, shuffle: true),
        ),
        if (tracks.isNotEmpty) _AddSongsRow(onTap: () => _openAddSongs(playlist)),
      ],
    );

    if (tracks.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyHint(
              icon: Icons.queue_music_rounded,
              title: 'Playlist is empty',
              message: 'Add songs from your library, or with "Add to playlist" in any song\'s menu.',
              action: FilledButton.icon(
                onPressed: () => _openAddSongs(playlist),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add songs'),
              ),
            ),
          ),
        ],
      );
    }

    final screenReader = MediaQuery.accessibleNavigationOf(context);
    return ReorderableListView.builder(
      header: header,
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl32),
      itemCount: tracks.length,
      // The rows bring their own drag starters: long-press anywhere on
      // the row, or an immediate drag from the handle (_RowDragListener
      // keeps the two from both starting a recognizer).
      buildDefaultDragHandles: false,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        _reorder(tracks, oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final track = tracks[index];
        final song = track.item;
        final entry = PlaylistEntryRef(playlistId: playlist.id, playlistName: playlist.name, position: track.position);

        // Under TalkBack / VoiceOver the swipe would become unlabelled
        // scroll actions on the row, and "scroll forward" would take the
        // song out of the playlist. So the swipe is off and the row gets
        // a real "Remove from playlist" button, like the queue's. (A
        // custom action cannot be used: it conflicts with the list's own
        // "Move up / down" actions and splits the row into two nodes.)
        return Dismissible(
          key: ValueKey('${song.id}_${track.position}'),
          direction: screenReader ? DismissDirection.none : DismissDirection.endToStart,
          background: const _RemoveBackground(),
          onDismissed: (_) => _remove(playlist, tracks, track),
          child: _RowDragListener(
            index: index,
            child: MediaSongRow(
              item: song,
              index: index + 1,
              // A long press here drags the row.
              longPressOpensMenu: false,
              playlistEntry: entry,
              keepMenu: true,
              trailing: screenReader
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RemoveFromPlaylistButton(onPressed: () => _remove(playlist, tracks, track)),
                        _DragHandle(index: index),
                      ],
                    )
                  : _DragHandle(index: index),
              onTap: () => playCollection(_playback(ref), songs, start: song),
            ),
          ),
        );
      },
    );
  }

  /// Moves the row at [from] to [to] on screen at once, and in the database
  /// by the entries' stored positions.
  void _reorder(List<PlaylistTrack> tracks, int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= tracks.length || to >= tracks.length) return;
    final oldPosition = tracks[from].position;
    final newPosition = tracks[to].position;
    final items = [for (final t in tracks) t.item];
    final moved = items.removeAt(from);
    items.insert(to, moved);
    setState(() {
      _order = [
        for (var i = 0; i < tracks.length; i++) PlaylistTrack(position: tracks[i].position, item: items[i]),
      ];
      _pendingReorders++;
    });
    ref.read(libraryRepositoryProvider).reorderPlaylist(_id, oldPosition, newPosition).whenComplete(() {
      if (mounted) _pendingReorders--;
    });
  }

  /// Takes [track] out (swipe or the screen-reader button), with an Undo
  /// that puts it back where it was.
  void _remove(Playlist playlist, List<PlaylistTrack> tracks, PlaylistTrack track) {
    final repo = ref.read(libraryRepositoryProvider);
    final key = _trackKey(track);
    setState(() => _removed.add(key));
    repo.removeSongFromPlaylist(_id, track.item.id, track.position);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text('Removed from ${playlist.name}'),
      duration: const Duration(seconds: 4),
      persist: false,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          if (mounted) setState(() => _removed.remove(key));
          repo.insertSongIntoPlaylist(_id, track.item.id, track.position);
        },
      ),
    ));
  }

  void _openAddSongs(Playlist playlist) {
    _AddSongsSheet.show(context, playlist);
  }

  void _showRenameDialog(Playlist playlist) {
    final repo = ref.read(libraryRepositoryProvider);
    showDialog<void>(
      context: context,
      builder: (_) => _RenamePlaylistDialog(
        initialName: playlist.name,
        onSave: (name) => repo.renamePlaylist(playlist.id, name),
      ),
    );
  }

  void _showDeleteConfirmation(Playlist playlist) {
    final repo = ref.read(libraryRepositoryProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final palette = dialogCtx.palette;
        return AlertDialog(
          icon: Icon(Icons.delete_outline_rounded, color: palette.error),
          title: const Text('Delete Playlist'),
          content: const Text(
            'Are you sure you want to delete this playlist? This will NOT delete the actual audio files on your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            // A destructive confirm is a TextButton in the error colour.
            TextButton(
              style: TextButton.styleFrom(foregroundColor: palette.error),
              onPressed: () {
                Navigator.pop(dialogCtx); // close dialog
                _close(); // close screen
                repo.deletePlaylist(playlist.id);
                messenger?.showSnackBar(
                  SnackBar(content: Text('Deleted playlist "${playlist.name}"')),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

/// "Rename Playlist": owns its text controller, so the field outlives the
/// dialog's closing animation and is disposed with it.
class _RenamePlaylistDialog extends StatefulWidget {
  final String initialName;
  final Future<void> Function(String name) onSave;

  const _RenamePlaylistDialog({required this.initialName, required this.onSave});

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final newName = _controller.text.trim();
    if (newName.isEmpty) return;
    Navigator.pop(context);
    widget.onSave(newName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        style: context.typography.body,
        decoration: InputDecoration(
          hintText: 'Playlist name',
          prefixIcon: Icon(Icons.edit_rounded, color: context.palette.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// "Add songs" at the top of a playlist's list, like Spotify's "Add to this
/// playlist".
class _AddSongsRow extends StatelessWidget {
  final VoidCallback onTap;

  const _AddSongsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      minTileHeight: MediaSongRow.minHeight,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
      leading: Container(
        width: MediaSongRow.artworkSize,
        height: MediaSongRow.artworkSize,
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(MediaSongRow.artworkRadius),
        ),
        child: Icon(Icons.add_rounded, color: palette.textPrimary),
      ),
      title: Text('Add songs', style: context.typography.bodyStrong),
      onTap: onTap,
    );
  }
}

/// "Add songs": every song in the library, searchable, to pick several at
/// once. Songs already in the playlist are ticked and cannot be picked again.
class _AddSongsSheet extends ConsumerStatefulWidget {
  final Playlist playlist;

  const _AddSongsSheet({required this.playlist});

  static void show(BuildContext context, Playlist playlist) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final container = ProviderScope.containerOf(context, listen: false);
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => UncontrolledProviderScope(container: container, child: _AddSongsSheet(playlist: playlist)),
    ).then((added) {
      if (added == null || messenger == null || !messenger.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(added == 0
            ? 'Those songs are already in ${playlist.name}'
            : 'Added ${added == 1 ? '1 song' : '$added songs'} to ${playlist.name}'),
        duration: const Duration(seconds: 2),
      ));
    });
  }

  @override
  ConsumerState<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<_AddSongsSheet> {
  final TextEditingController _search = TextEditingController();
  late Stream<List<MediaItem>> _songs = _query('');
  late final Stream<List<PlaylistTrack>> _present =
      ref.read(libraryRepositoryProvider).watchPlaylistTracks(widget.playlist.id);

  /// Picked song ids, in the order they were picked.
  final List<String> _picked = [];
  bool _adding = false;

  Stream<List<MediaItem>> _query(String text) =>
      ref.read(libraryRepositoryProvider).watchMediaItems(mediaType: MediaType.audio, searchQuery: text);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_picked.isEmpty || _adding) return;
    setState(() => _adding = true);
    final added = await ref.read(libraryRepositoryProvider).addSongsToPlaylist(widget.playlist.id, List.of(_picked));
    if (mounted) Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final count = _picked.length;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.sm8),
            child: Semantics(
              header: true,
              child: Text(
                'Add to ${widget.playlist.name}',
                style: type.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.sm8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              // What is typed is what is searched (no curly quotes, long
              // dashes or autocorrected words from the keyboard).
              autocorrect: false,
              smartQuotesType: SmartQuotesType.disabled,
              smartDashesType: SmartDashesType.disabled,
              style: type.body,
              onChanged: (text) => setState(() => _songs = _query(text)),
              decoration: InputDecoration(
                hintText: 'Search your music',
                prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: palette.divider),
          Expanded(
            child: StreamBuilder<List<PlaylistTrack>>(
              stream: _present,
              builder: (context, presentSnapshot) {
                final inPlaylist = {for (final t in presentSnapshot.data ?? const <PlaylistTrack>[]) t.item.id};
                return StreamBuilder<List<MediaItem>>(
                  stream: _songs,
                  builder: (context, snapshot) {
                    final songs = snapshot.data;
                    if (songs == null) return const Center(child: CircularProgressIndicator());
                    if (songs.isEmpty) {
                      return EmptyHint(
                        icon: Icons.music_off_outlined,
                        title: _search.text.isEmpty ? 'No songs yet' : 'No matching songs',
                        message: _search.text.isNotEmpty
                            ? 'No songs matching "${_search.text}".'
                            // On iPhone the library is MediaHub's own downloads.
                            : PlatformInfo.isIOS
                                ? 'Songs you download in MediaHub show up here.'
                                : 'Songs on this phone show up here.',
                      );
                    }
                    return Scrollbar(
                      interactive: true,
                      child: ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          final already = inPlaylist.contains(song.id);
                          final picked = already || _picked.contains(song.id);
                          return CheckboxListTile(
                            value: picked,
                            onChanged: already
                                ? null
                                : (on) => setState(() {
                                      if (on == true) {
                                        _picked.add(song.id);
                                      } else {
                                        _picked.remove(song.id);
                                      }
                                    }),
                            controlAffinity: ListTileControlAffinity.trailing,
                            secondary: ArtworkThumbnail(
                              uri: song.uri,
                              artworkPath: song.artworkPath,
                              size: MediaSongRow.artworkSize,
                              borderRadius: MediaSongRow.artworkRadius,
                            ),
                            title: Text(song.title, style: type.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              already ? 'In this playlist' : MediaSongRow.artistOf(song),
                              style: type.metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, AppSpacing.sm8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: count == 0 || _adding ? null : _add,
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                label: Text(count == 0 ? 'Pick songs to add' : 'Add ${count == 1 ? '1 song' : '$count songs'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An extra row in a [_CollectionMenu] (a playlist's "Add songs", "Delete
/// playlist").
class _CollectionExtra {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _CollectionExtra(this.icon, this.label, this.onTap, {this.destructive = false});
}

/// The ⋮ menu of an album, artist or playlist page: it acts on the whole
/// list (only the songs that can play go to the queue), never on one song.
class _CollectionMenu {
  _CollectionMenu._();

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required List<MediaItem> songs,
    List<_CollectionExtra> extras = const [],
  }) async {
    final playable = playableOnly(songs);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final playback = container.read(playbackNotifierProvider.notifier);
    void snack(String text) {
      if (messenger == null || !messenger.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
    }

    final hasSongs = playable.isNotEmpty;
    final count = playable.length == 1 ? '1 song' : '${playable.length} songs';
    final rows = <(IconData, String, VoidCallback?, bool)>[
      (Icons.playlist_play_rounded, 'Play next', hasSongs ? () {
        playback.playNextAll(playable);
        snack('Playing $count next');
      } : null, false),
      (Icons.queue_music_rounded, 'Add to queue', hasSongs ? () {
        playback.addAllToQueue(playable);
        snack('Added $count to the queue');
      } : null, false),
      (Icons.playlist_add_rounded, 'Add to playlist…', songs.isEmpty ? null : () {
        if (context.mounted) _PickPlaylistSheet.show(context, container, messenger, songs);
      }, false),
      (Icons.shuffle_rounded, 'Shuffle', hasSongs ? () => playCollection(playback, playable, shuffle: true) : null, false),
      for (final extra in extras) (extra.icon, extra.label, extra.onTap, extra.destructive),
    ];

    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        final type = sheetContext.typography;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(breakableTitle(title), semanticsLabel: title, style: type.bodyStrong, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(songsMeta(songs), style: type.metadata),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: palette.divider),
                const SizedBox(height: AppSpacing.xs4),
                for (var i = 0; i < rows.length; i++)
                  ListTile(
                    minTileHeight: MediaContextMenu.rowHeight,
                    enabled: rows[i].$3 != null,
                    leading: Icon(rows[i].$1, size: 24, color: rows[i].$4 ? palette.error : palette.textSecondary),
                    title: Text(
                      rows[i].$2,
                      style: type.body.copyWith(color: rows[i].$4 ? palette.error : palette.textPrimary),
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(i),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null) rows[chosen].$3?.call();
  }
}

/// "Add to playlist…" for a whole album, artist or playlist: one transaction
/// per pick, songs already in that playlist skipped.
class _PickPlaylistSheet extends StatelessWidget {
  final ProviderContainer container;
  final List<MediaItem> songs;

  const _PickPlaylistSheet({required this.container, required this.songs});

  static void show(
    BuildContext context,
    ProviderContainer container,
    ScaffoldMessengerState? messenger,
    List<MediaItem> songs,
  ) {
    showModalBottomSheet<Playlist>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _PickPlaylistSheet(container: container, songs: songs),
      ),
    ).then((pl) async {
      if (pl == null) return;
      final added = await container
          .read(libraryRepositoryProvider)
          .addSongsToPlaylist(pl.id, [for (final s in songs) s.id]);
      if (messenger == null || !messenger.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(added == 0
            ? 'All of them are already in ${pl.name}'
            : 'Added ${added == 1 ? '1 song' : '$added songs'} to ${pl.name}'),
        duration: const Duration(seconds: 2),
      ));
    });
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
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
                child: Semantics(
                  header: true,
                  child: Text('Add to playlist', style: type.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.divider),
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl24, vertical: AppSpacing.xxxl32),
                  child: Text(
                    'No playlists yet. Make one in Music > Playlists.',
                    style: type.body.copyWith(color: palette.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm8),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      return ListTile(
                        minTileHeight: 64,
                        leading: PlaylistCover(
                          playlistId: pl.id,
                          coverSongs: pl.coverSongs,
                          size: 48,
                          borderRadius: AppSpacing.radiusArtSmall,
                        ),
                        title: Text(pl.name, style: type.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(pl.songCount == 1 ? '1 song' : '${pl.songCount} songs', style: type.metadata),
                        trailing: Icon(Icons.add_rounded, color: palette.textSecondary),
                        onTap: () => Navigator.pop(context, pl),
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

/// "2019 · 12 songs · 48 min"; [year] leads when the album is tagged with one.
String songsMeta(List<MediaItem> songs, {int? year}) {
  final count = songs.length;
  final countText = count == 1 ? '1 song' : '$count songs';
  var totalMs = 0;
  for (final song in songs) {
    if (song.durationMs > 0) totalMs += song.durationMs;
  }
  final parts = <String>[if (year != null) '$year', countText];
  if (totalMs > 0) {
    final total = Duration(milliseconds: totalMs);
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);
    final String durationText;
    if (hours > 0) {
      durationText = minutes > 0 ? '$hours hr $minutes min' : '$hours hr';
    } else if (total.inMinutes > 0) {
      durationText = '${total.inMinutes} min';
    } else {
      durationText = '${total.inSeconds} sec';
    }
    parts.add(durationText);
  }
  return parts.join(' · ');
}

/// Scaffold for the detail screens: a transparent app bar over the hero glow
/// that turns solid (and shows the title) once the hero title scrolls away.
class _DetailScaffold extends StatefulWidget {
  final String title;
  final List<Widget> actions;
  final Widget body;

  /// True when [body] has no hero header (loading, error, empty): the bar
  /// then always shows the title, so the user can tell what they opened.
  final bool showTitle;

  const _DetailScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
    this.showTitle = false,
  });

  @override
  State<_DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<_DetailScaffold> {
  final ValueNotifier<bool> _collapsed = ValueNotifier<bool>(false);

  @override
  void didUpdateWidget(_DetailScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different kind of body (e.g. the playlist list turning into its empty
    // state after the last song is swiped away) starts again at offset 0, and
    // no scroll notification reports that.
    if (!Widget.canUpdate(oldWidget.body, widget.body)) {
      _collapsed.value = false;
    }
  }

  @override
  void dispose() {
    _collapsed.dispose();
    super.dispose();
  }

  void _track(int depth, ScrollMetrics metrics) {
    if (depth == 0 && metrics.axis == Axis.vertical) {
      _collapsed.value = metrics.pixels > _kCollapseOffset;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    _track(notification.depth, notification.metrics);
    return false;
  }

  /// Also fires after a scroll view's first layout and when its content
  /// changes size, which can move the offset without a scroll.
  bool _onMetrics(ScrollMetricsNotification notification) {
    _track(notification.depth, notification.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<bool>(
          valueListenable: _collapsed,
          builder: (context, collapsed, _) {
            final solid = collapsed || widget.showTitle;
            final duration = MotionTokens.duration(context, MotionTokens.feedback);
            return AnimatedContainer(
              duration: duration,
              curve: MotionTokens.easeOut,
              color: solid ? palette.background : palette.background.withValues(alpha: 0),
              child: AppBar(
                backgroundColor: Colors.transparent,
                title: AnimatedOpacity(
                  opacity: solid ? 1 : 0,
                  duration: duration,
                  curve: MotionTokens.easeOut,
                  child: Text(
                    widget.title,
                    // The album, artist or playlist name: Poppins, which draws
                    // Latin and Devanagari alike (DESIGN.md 0.5), at a size
                    // that suits the collapsed bar.
                    style: context.typography.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                actions: [
                  ...widget.actions,
                  const SizedBox(width: AppSpacing.xs4),
                ],
              ),
            );
          },
        ),
      ),
      body: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.body,
        ),
      ),
    );
  }
}

/// Cover (with the print offset), kicker, title, subtitle, song count and
/// the Play all / Shuffle pair, on the hero tint that fades into the page
/// (docs/DESIGN.md 3 and 7.1).
class _HeroHeader extends StatelessWidget {
  final Widget artwork;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final String meta;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  /// Tint behind the header; the palette's hero gradient unless the cover's
  /// own colours are passed. A change (the real cover finishing loading)
  /// cross-fades instead of snapping.
  final Gradient? tint;

  const _HeroHeader({
    required this.artwork,
    required this.eyebrow,
    required this.title,
    required this.meta,
    this.subtitle,
    this.onPlay,
    this.onShuffle,
    this.tint,
  });

  /// Width the Play all / Shuffle pair needs side by side at the user's text
  /// size: per button 24 dp padding each side, a 20 dp icon and its 8 dp gap
  /// plus the label, and 12 dp between them. Narrower, they stack.
  static double _pairWidth(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = context.typography.button;
    double label(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    const chrome = AppSpacing.xxl24 * 2 + VoltButton.iconSize + AppSpacing.sm8 + 2;
    final widest = [label('Play all'), label('Shuffle')].reduce((a, b) => a > b ? a : b);
    return (chrome + widest) * 2 + AppSpacing.md12;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    // The body sits behind the transparent app bar; this is its height.
    final topInset = MediaQuery.paddingOf(context).top;

    return AnimatedContainer(
      duration: MotionTokens.duration(context, MotionTokens.page),
      curve: MotionTokens.easeOut,
      decoration: BoxDecoration(gradient: tint ?? palette.heroGradient),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.background.withValues(alpha: 0), palette.background],
            stops: const [0.3, 1.0],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg16,
            topInset + AppSpacing.sm8,
            AppSpacing.lg16,
            AppSpacing.xl20,
          ),
          child: Column(
            children: [
              artwork,
              const SizedBox(height: AppSpacing.xxl24),
              Text(
                eyebrow.toUpperCase(),
                semanticsLabel: eyebrow,
                style: type.overline.copyWith(color: palette.primary),
              ),
              const SizedBox(height: AppSpacing.xs4),
              Semantics(
                header: true,
                child: Text(
                  breakableTitle(title),
                  semanticsLabel: title,
                  style: type.screenTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  subtitle!,
                  style: type.body.copyWith(color: palette.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 2),
              // textSecondary, never textMuted, on a tinted header.
              Text(
                meta,
                style: type.metadata,
                textAlign: TextAlign.center,
              ),
              if (onPlay != null || onShuffle != null) ...[
                const SizedBox(height: AppSpacing.xl20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  // Side by side while both labels fit, stacked on a narrow
                  // phone at large text.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final play = VoltButton(
                        label: 'Play all',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        onPressed: onPlay,
                      );
                      final shuffle = FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(VoltButton.height)),
                        onPressed: onShuffle,
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        label: const Text('Shuffle', maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                      final stacked = constraints.maxWidth < _HeroHeader._pairWidth(context);
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [play, const SizedBox(height: AppSpacing.sm8), shuffle],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: play),
                          const SizedBox(width: AppSpacing.md12),
                          Expanded(child: shuffle),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover with the hard print offset under it ([AppPalette.printShadow]: Volt
/// on ink, ink on paper), in the cover's own shape. No soft glow.
class _HeroArtwork extends StatelessWidget {
  final Widget child;
  final bool circle;

  const _HeroArtwork({required this.child, this.circle = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(_kHeroArtRadius),
        boxShadow: [
          BoxShadow(color: context.palette.printShadow, offset: _kPrintOffset, blurRadius: 0),
        ],
      ),
      child: child,
    );
  }
}

/// Long-press anywhere on a playlist row to start dragging it.
///
/// Pointers that went down on the row's [_DragHandle] are left to the handle's
/// own immediate listener: both listeners see the same pointer-down, and two
/// recognizers for one pointer would leave one of them undisposed.
class _RowDragListener extends StatelessWidget {
  final int index;
  final Widget child;

  const _RowDragListener({required this.index, required this.child});

  /// The last pointer that went down on a drag handle. Deeper widgets get a
  /// pointer-down first, so the handle sets this before the row reads it.
  static int? _handlePointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.pointer == _handlePointer) return;
        SliverReorderableList.maybeOf(context)?.startItemDragReorder(
          index: index,
          event: event,
          recognizer: DelayedMultiDragGestureRecognizer(debugOwner: this)
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
        );
      },
      child: child,
    );
  }
}

/// Grip at the end of a playlist row: dragging it moves the row right away.
class _DragHandle extends StatelessWidget {
  final int index;

  const _DragHandle({required this.index});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _RowDragListener._handlePointer = event.pointer,
      child: ReorderableDragStartListener(
        index: index,
        // Screen readers move rows with the list's own "Move up / down"
        // actions; this only tells them what the grip is.
        child: Semantics(
          label: 'Drag to reorder',
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Icon(Icons.drag_handle_rounded, color: context.palette.dragHandle),
          ),
        ),
      ),
    );
  }
}

/// Removes a song from the playlist. Shown only while a screen reader runs,
/// when the swipe is off; styled like the queue's remove button.
class _RemoveFromPlaylistButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RemoveFromPlaylistButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
      color: context.palette.textSecondary,
      tooltip: 'Remove from playlist',
      constraints: const BoxConstraints(
        minWidth: AppSpacing.minTouchTarget,
        minHeight: AppSpacing.minTouchTarget,
      ),
      onPressed: onPressed,
    );
  }
}

/// Shown behind a playlist row while it is swiped away: the destructive
/// tonal pair, with the word and the icon (never colour alone).
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      color: palette.errorContainer,
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.lg16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Remove', style: context.typography.button.copyWith(color: palette.onErrorContainer)),
          const SizedBox(width: AppSpacing.sm8),
          Icon(Icons.delete_rounded, color: palette.onErrorContainer),
        ],
      ),
    );
  }
}

final _albumSongsProvider = StreamProvider.family<List<MediaItem>, String>((ref, albumKey) {
  return ref.watch(libraryRepositoryProvider).watchAlbumSongs(albumKey);
});

final _artistSongsProvider = StreamProvider.family<List<MediaItem>, String>((ref, artist) {
  return ref.watch(libraryRepositoryProvider).watchArtistSongs(artist);
});

final _playlistTracksProvider = StreamProvider.family<List<PlaylistTrack>, String>((ref, playlistId) {
  return ref.watch(libraryRepositoryProvider).watchPlaylistTracks(playlistId);
});

final _playlistProvider = StreamProvider.family<Playlist?, String>((ref, playlistId) {
  return ref.watch(libraryRepositoryProvider).watchPlaylist(playlistId);
});

final _likedSongsProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchFavorites();
});
