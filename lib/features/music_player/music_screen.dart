import '../../domain/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/permissions/media_permission_service.dart';
import '../../core/platform_info.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/database/search_text.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/artwork_placeholder.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/detail_screens.dart';
import '../library/library_notifier.dart';
import '../library/media_context_menu.dart';
import '../library/media_song_row.dart';
import '../library/playable.dart';
import '../playlists/playlist_cover.dart';
import 'playback_notifier.dart';

/// Compact toolbar buttons (40 dp tall, 48 dp touch target via padding).
/// Sizes only: the theme colours FilledButton and FilledButton.tonal.
final ButtonStyle _compactStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, AppSpacing.giant40),
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
);

/// "1 song", "12 songs".
String _count(int n, String singular, String plural) => '$n ${n == 1 ? singular : plural}';

/// The Music tab (docs/DESIGN.md 6 and 7): the "Music" masthead, the search
/// field, a pinned row of chips for Songs / Liked songs / Playlists / Albums
/// / Artists (the selected one is the Volt sticker), then song rows or the
/// playlist, album and artist grids.
///
/// The search applies to every tab: every word has to match a song's title,
/// artist or album (accents and case ignored, Devanagari as typed), a
/// playlist's name, an album or an artist.
class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  /// The chips, in order. "Liked songs" ("wishlist") comes right after the
  /// songs, as on Spotify and YouTube Music.
  static const List<String> tabs = ['Songs', MediaContextMenu.likedSongs, 'Playlists', 'Albums', 'Artists'];

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _lastShuffleAllTap;

  /// Bumped by Retry: the tab streams are opened again.
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: MusicScreen.tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _retryStreams() => setState(() => _retry++);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicLibraryProvider);
    final notifier = ref.read(musicLibraryProvider.notifier);
    final repo = ref.watch(libraryRepositoryProvider);
    final palette = context.palette;

    // "12 new songs" after the refresh button.
    ref.listen<ScanReport?>(musicLibraryProvider.select((s) => s.scanReport), (previous, next) {
      if (next == null || next.serial == previous?.serial) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(next.message), duration: const Duration(seconds: 2)));
    });

    final permission = state.permissionState;
    final hasLibrary = permission == MediaPermissionState.granted || permission == MediaPermissionState.limited;

    final header = _MusicHeader(
      actions: [
        if (permission == MediaPermissionState.granted) ...[
          IconButton(
            icon: state.isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Scan device media',
            onPressed: state.isScanning ? null : () => notifier.scanDevice(),
          ),
          PopupMenuButton<SongSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort songs',
            onSelected: (sort) => notifier.setSongSort(sort),
            itemBuilder: (context) => [
              _sortItem(context, SongSortOption.title, 'Title', state),
              _sortItem(context, SongSortOption.artist, 'Artist', state),
              _sortItem(context, SongSortOption.album, 'Album', state),
              _sortItem(context, SongSortOption.dateAdded, 'Date added', state),
              _sortItem(context, SongSortOption.duration, 'Duration', state),
              _sortItem(context, SongSortOption.mostPlayed, 'Most played', state),
            ],
          ),
        ],
      ],
    );

    final error = state.errorMessage;

    // No app bar: the screen sets the status bar icons for its own canvas.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.barsFor(palette),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: hasLibrary
              ? NestedScrollView(
                  // Scrolling back up brings the title, scan / sort actions and
                  // search field back straight away, even deep in a long list.
                  floatHeaderSlivers: true,
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverToBoxAdapter(child: header),
                    if (permission == MediaPermissionState.limited)
                      SliverToBoxAdapter(
                        child: _LimitedAccessBanner(onOpenSettings: () => notifier.openSettings()),
                      ),
                    SliverToBoxAdapter(child: _searchField(context, notifier)),
                    if (error != null && state.items.isNotEmpty)
                      SliverToBoxAdapter(child: _ErrorBanner(message: error, onRetry: () => notifier.scanDevice())),
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                      sliver: SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedChipsDelegate(
                          chips: _TabChips(controller: _tabController, labels: MusicScreen.tabs),
                          height: _TabChips.heightFor(context),
                          background: palette.background,
                          divider: innerBoxIsScrolled ? palette.divider : Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSongsTab(state, notifier),
                      _buildLikedTab(repo, state.searchQuery),
                      _buildPlaylistsTab(repo, state.searchQuery),
                      _buildAlbumsTab(repo, state.searchQuery),
                      _buildArtistsTab(repo, state.searchQuery),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: header),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildPermissionState(state, notifier),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  PopupMenuItem<SongSortOption> _sortItem(
    BuildContext context,
    SongSortOption option,
    String label,
    LibraryState state,
  ) {
    final palette = context.palette;
    final type = context.typography;
    final selected = state.songSort == option;
    return PopupMenuItem<SongSortOption>(
      value: option,
      child: Semantics(
        selected: selected,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: selected ? Icon(Icons.check_rounded, size: 20, color: palette.primary) : null,
            ),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Text(
                label,
                style: selected ? type.bodyStrong.copyWith(color: palette.primary) : type.body,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.md12),
              Icon(
                state.ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 16,
                color: palette.textSecondary,
                semanticLabel: state.ascending ? 'Ascending' : 'Descending',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context, BaseLibraryNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, AppSpacing.sm8),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          notifier.setSearchQuery(val);
          // The other tabs read the query from this state.
          setState(() {});
        },
        textInputAction: TextInputAction.search,
        style: context.typography.body,
        decoration: InputDecoration(
          // Short enough to stay whole at 320 dp and at large text.
          hintText: 'Search your music',
          prefixIcon: Icon(Icons.search_rounded, color: context.palette.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    notifier.setSearchQuery('');
                    setState(() {});
                  },
                )
              : null,
        ),
      ),
    );
  }

  /// Friendly, sentence-case permission states (the same words on the
  /// Videos tab, with "videos").
  Widget _buildPermissionState(LibraryState state, BaseLibraryNotifier notifier) {
    if (state.permissionState == MediaPermissionState.denied) {
      return EmptyHint(
        icon: Icons.library_music_rounded,
        title: 'Allow access to your music',
        message: 'MediaHub plays the songs saved on this phone. Allow access to see them here.',
        action: FilledButton.icon(
          onPressed: () => notifier.requestPermission(),
          icon: const Icon(Icons.lock_open_rounded, size: 20),
          label: const Text('Allow access'),
        ),
      );
    }

    if (state.permissionState == MediaPermissionState.permanentlyDenied) {
      return EmptyHint(
        icon: Icons.library_music_rounded,
        title: 'Music access is off',
        message: 'Turn on music access for MediaHub in Settings to see your songs here.',
        action: FilledButton.icon(
          onPressed: () => notifier.openSettings(),
          icon: const Icon(Icons.settings_rounded, size: 20),
          label: const Text('Open settings'),
        ),
      );
    }

    // Still checking the permission.
    return const SizedBox.shrink();
  }

  Widget _buildSongsTab(LibraryState state, BaseLibraryNotifier notifier) {
    if (state.status == LibraryStatus.loading || state.status == LibraryStatus.initial) {
      return const _TabScrollView(storageKey: 'songs', slivers: [_LoadingSliver()]);
    }

    if (state.status == LibraryStatus.error && state.items.isEmpty) {
      return _TabScrollView(
        storageKey: 'songs',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorHint(
              what: 'your songs',
              message: state.errorMessage,
              onRetry: () => notifier.retry(),
            ),
          ),
        ],
      );
    }

    if (state.items.isEmpty) {
      final searching = state.searchQuery.isNotEmpty;
      // On iPhone there is no shared music folder to scan: songs come from
      // MediaHub's own downloads.
      final ios = PlatformInfo.isIOS;
      return _TabScrollView(
        storageKey: 'songs',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: Icons.music_off_outlined,
              title: searching ? 'No matching songs' : 'No songs yet',
              message: searching
                  ? 'No songs matching "${state.searchQuery}".'
                  : ios
                      ? 'Songs you download in MediaHub show up here.'
                      : 'Find the songs saved on this phone.',
              action: searching
                  ? null
                  : ios
                      ? (PlatformInfo.supportsDownloads
                          ? FilledButton.icon(
                              onPressed: () => GoRouter.maybeOf(context)?.go('/downloads'),
                              icon: const Icon(Icons.file_download_rounded, size: 20),
                              label: const Text('Open Downloads'),
                            )
                          : null)
                      : FilledButton.icon(
                          onPressed: state.isScanning ? null : () => notifier.scanDevice(),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('Scan device'),
                        ),
            ),
          ),
        ],
      );
    }

    final playback = ref.read(playbackNotifierProvider.notifier);
    return _TabScrollView(
      storageKey: 'songs',
      scrollbar: true,
      slivers: [
        SliverToBoxAdapter(
          child: _ListToolbar(
            label: _count(state.items.length, 'song', 'songs'),
            actions: [
              FilledButton.tonalIcon(
                style: _compactStyle,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle all'),
                onPressed: () {
                  final now = DateTime.now();
                  if (_lastShuffleAllTap != null && now.difference(_lastShuffleAllTap!).inMilliseconds < 500) {
                    return;
                  }
                  _lastShuffleAllTap = now;
                  playCollection(playback, state.items, shuffle: true);
                },
              ),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final song = state.items[index];
            return MediaSongRow(
              item: song,
              onTap: () => playCollection(playback, state.items, start: song),
            );
          },
        ),
      ],
    );
  }

  /// "Couldn't load your albums" with a Retry, for the grid tabs.
  Widget _gridError(String storageKey, String what) {
    return _TabScrollView(
      storageKey: storageKey,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorHint(what: what, onRetry: _retryStreams),
        ),
      ],
    );
  }

  Widget _buildAlbumsTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<AlbumGroup>>(
      key: ValueKey('albums$_retry'),
      stream: repo.watchAlbums(searchQuery: query),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _gridError('albums', 'your albums');
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const _TabScrollView(storageKey: 'albums', slivers: [_LoadingSliver()]);
        }
        final albums = snapshot.data ?? [];
        if (albums.isEmpty) {
          return _TabScrollView(
            storageKey: 'albums',
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.album_rounded,
                  title: 'No albums found',
                  message: query.isNotEmpty
                      ? 'No albums matching "$query".'
                      : 'Albums appear here once your songs are scanned.',
                ),
              ),
            ],
          );
        }
        return _TabScrollView(
          storageKey: 'albums',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, 0),
              sliver: _CoverGrid(
                itemCount: albums.length,
                captionLines: (type) => [type.bodyStrong, type.metadata, type.caption],
                itemBuilder: (context, index, side) => _AlbumTile(album: albums[index], artSize: side),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistsTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<ArtistGroup>>(
      key: ValueKey('artists$_retry'),
      stream: repo.watchArtists(searchQuery: query),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _gridError('artists', 'your artists');
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const _TabScrollView(storageKey: 'artists', slivers: [_LoadingSliver()]);
        }
        final artists = snapshot.data ?? [];
        if (artists.isEmpty) {
          return _TabScrollView(
            storageKey: 'artists',
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.person_rounded,
                  title: 'No artists found',
                  message: query.isNotEmpty
                      ? 'No artists matching "$query".'
                      : 'Artists appear here once your songs are scanned.',
                ),
              ),
            ],
          );
        }
        return _TabScrollView(
          storageKey: 'artists',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, 0),
              sliver: _CoverGrid(
                itemCount: artists.length,
                // Three round faces across a phone.
                minTileWidth: 96,
                captionLines: (type) => [type.bodyStrong, type.metadata],
                itemBuilder: (context, index, side) {
                  final artist = artists[index];
                  return _GridTile(
                    cover: _ArtistAvatar(name: artist.artist, size: side),
                    title: artist.artist,
                    lines: [_artistSubtitle(artist)],
                    centered: true,
                    semanticsLabel: 'Artist ${artist.artist}, ${_count(artist.songCount, 'song', 'songs')}',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static String _artistSubtitle(ArtistGroup artist) {
    final songs = _count(artist.songCount, 'song', 'songs');
    if (artist.albumCount <= 0) return songs;
    return '$songs · ${_count(artist.albumCount, 'album', 'albums')}';
  }

  Widget _buildPlaylistsTab(LibraryRepository repo, String query) {
    final terms = searchTerms(query);
    final showLiked = matchesAllTerms(terms, [foldForSearch(MediaContextMenu.likedSongs)]);
    return StreamBuilder<List<Playlist>>(
      key: ValueKey('playlists$_retry'),
      stream: repo.watchPlaylists(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _gridError('playlists', 'your playlists');
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const _TabScrollView(storageKey: 'playlists', slivers: [_LoadingSliver()]);
        }
        final all = snapshot.data ?? [];
        final playlists =
            terms.isEmpty ? all : all.where((p) => matchesAllTerms(terms, [foldForSearch(p.name)])).toList();
        final tiles = (showLiked ? 1 : 0) + playlists.length;
        return _TabScrollView(
          storageKey: 'playlists',
          slivers: [
            SliverToBoxAdapter(
              child: _ListToolbar(
                label: _count(all.length, 'playlist', 'playlists'),
                actions: [
                  FilledButton.icon(
                    style: _compactStyle,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New playlist'),
                    onPressed: () => MediaContextMenu.showNewPlaylistDialog(context, ref),
                  ),
                ],
              ),
            ),
            if (tiles == 0)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.queue_music_rounded,
                  title: 'No matching playlists',
                  message: 'No playlists matching "$query".',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, 0),
                sliver: _CoverGrid(
                  itemCount: tiles,
                  captionLines: (type) => [type.bodyStrong, type.metadata],
                  itemBuilder: (context, index, side) {
                    // Liked songs is pinned first.
                    if (showLiked && index == 0) return _LikedSongsTile(repo: repo, artSize: side);
                    final pl = playlists[index - (showLiked ? 1 : 0)];
                    return _GridTile(
                      cover: PlaylistCover(
                        playlistId: pl.id,
                        coverSongs: pl.coverSongs,
                        size: side,
                        borderRadius: AppSpacing.radiusThumb,
                      ),
                      title: pl.name,
                      lines: [_count(pl.songCount, 'song', 'songs')],
                      semanticsLabel: 'Playlist ${pl.name}, ${_count(pl.songCount, 'song', 'songs')}',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: pl)),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLikedTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<MediaItem>>(
      key: ValueKey('liked$_retry'),
      stream: repo.watchFavorites(searchQuery: query),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _gridError('favorites', 'your liked songs');
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const _TabScrollView(storageKey: 'favorites', slivers: [_LoadingSliver()]);
        }
        final liked = snapshot.data ?? [];
        if (liked.isEmpty) {
          return _TabScrollView(
            storageKey: 'favorites',
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.favorite_border_rounded,
                  title: query.isNotEmpty ? 'No matching liked songs' : 'No liked songs yet',
                  message: query.isNotEmpty
                      ? 'No liked songs matching "$query".'
                      : 'Tap the heart on any song to keep it here.',
                ),
              ),
            ],
          );
        }
        final playback = ref.read(playbackNotifierProvider.notifier);
        final canPlay = playableOnly(liked).isNotEmpty;
        return _TabScrollView(
          storageKey: 'favorites',
          scrollbar: true,
          slivers: [
            SliverToBoxAdapter(
              child: _ListToolbar(
                label: _count(liked.length, 'liked song', 'liked songs'),
                actions: [
                  VoltButton.compact(
                    icon: Icons.play_arrow_rounded,
                    label: 'Play all',
                    onPressed: canPlay ? () => playCollection(playback, liked) : null,
                  ),
                  FilledButton.tonalIcon(
                    style: _compactStyle,
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Shuffle'),
                    onPressed: canPlay ? () => playCollection(playback, liked, shuffle: true) : null,
                  ),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: liked.length,
              itemBuilder: (context, index) {
                final song = liked[index];
                return MediaSongRow(
                  item: song,
                  onTap: () => playCollection(playback, liked, start: song),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// The "Liked songs" tile pinned first among the playlists: the heart cover
/// and how many songs it holds; it opens the Liked songs page.
class _LikedSongsTile extends StatelessWidget {
  final LibraryRepository repo;
  final double artSize;

  const _LikedSongsTile({required this.repo, required this.artSize});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MediaItem>>(
      stream: repo.watchFavorites(),
      builder: (context, snapshot) {
        final count = snapshot.data?.length;
        final countText = count == null ? '' : _count(count, 'song', 'songs');
        return _GridTile(
          cover: LikedSongsCover(size: artSize, borderRadius: AppSpacing.radiusThumb),
          title: MediaContextMenu.likedSongs,
          lines: [countText],
          semanticsLabel: count == null
              ? 'Playlist ${MediaContextMenu.likedSongs}'
              : 'Playlist ${MediaContextMenu.likedSongs}, $countText',
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LikedSongsScreen()));
          },
        );
      },
    );
  }
}

/// "Couldn't load your albums" with a Retry.
class _ErrorHint extends StatelessWidget {
  final String what;
  final String? message;
  final VoidCallback onRetry;

  const _ErrorHint({required this.what, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    return EmptyHint(
      icon: Icons.error_outline_rounded,
      title: "Couldn't load $what",
      message: message ?? 'Something went wrong reading your library.',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: const Text('Retry'),
      ),
    );
  }
}

/// A failed refresh while the list is still there: the reason and a Retry,
/// in the warning colour (icon and words, never colour alone).
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.sm8),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md12, AppSpacing.sm8, AppSpacing.xs4, AppSpacing.sm8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMenu),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: palette.warning, size: 20),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Text(message, style: context.typography.metadata.copyWith(color: palette.textPrimary)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// The tab masthead: "Music" in `display` (Unbounded), a one-line subtitle
/// and optional icon actions.
class _MusicHeader extends StatelessWidget {
  final List<Widget> actions;

  const _MusicHeader({required this.actions});

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg16,
        AppSpacing.xl20,
        actions.isEmpty ? AppSpacing.lg16 : AppSpacing.xs4,
        AppSpacing.md12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Music', style: type.display, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  'Your songs, albums and playlists.',
                  style: type.metadata,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Shown when the user granted access to selected media only.
class _LimitedAccessBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _LimitedAccessBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md12, AppSpacing.sm8, AppSpacing.xs4, AppSpacing.sm8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMenu),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: palette.accent, size: 20),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Text(
                'You gave access to selected items only. To see all your media, grant full access in Settings.',
                style: context.typography.metadata.copyWith(color: palette.textPrimary),
              ),
            ),
            TextButton(
              onPressed: onOpenSettings,
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The section chips (docs/DESIGN.md 7.3) that drive the tab view: a
/// horizontal row with 16 dp gutters, the selected chip the Volt sticker with
/// its check (from the chip theme). Swiping between tabs moves the selection,
/// and the selected chip scrolls into view. The row fades out over its last
/// 24 dp (DESIGN.md 7.13), hinting that more chips follow.
class _TabChips extends StatefulWidget {
  final TabController controller;
  final List<String> labels;

  const _TabChips({required this.controller, required this.labels});

  /// Width of the fade at the end of the row.
  static const double fadeWidth = 24;

  /// Height of the chip row: a 48 dp touch target, or the chip itself once
  /// large text makes it taller.
  static double heightFor(BuildContext context) {
    final line = context.typography.chipLabel;
    final chip = MediaQuery.textScalerOf(context).scale(line.fontSize!) * line.height! + AppSpacing.lg16;
    return chip > AppSpacing.minTouchTarget ? chip : AppSpacing.minTouchTarget;
  }

  @override
  State<_TabChips> createState() => _TabChipsState();
}

class _TabChipsState extends State<_TabChips> {
  late List<GlobalKey> _keys = _makeKeys();
  int _shown = 0;

  List<GlobalKey> _makeKeys() => [for (final _ in widget.labels) GlobalKey()];

  @override
  void initState() {
    super.initState();
    _shown = widget.controller.index;
    widget.controller.animation?.addListener(_onMove);
  }

  @override
  void didUpdateWidget(covariant _TabChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.animation?.removeListener(_onMove);
      widget.controller.animation?.addListener(_onMove);
    }
    if (oldWidget.labels.length != widget.labels.length) _keys = _makeKeys();
  }

  @override
  void dispose() {
    widget.controller.animation?.removeListener(_onMove);
    super.dispose();
  }

  void _onMove() {
    final value = widget.controller.animation?.value ?? widget.controller.index.toDouble();
    final index = value.round().clamp(0, widget.labels.length - 1);
    if (index == _shown) return;
    setState(() => _shown = index);
    final target = _keys[index].currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: MotionTokens.duration(context, MotionTokens.page),
        curve: MotionTokens.emphasized,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = rect.width <= 0 ? 0.0 : (_TabChips.fadeWidth / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 1 - fade, 1],
        ).createShader(rect);
      },
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The end gutter clears the fade, so the last chip ends fully visible.
        padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg16, end: AppSpacing.lg16 + _TabChips.fadeWidth),
        itemCount: widget.labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm8),
        itemBuilder: (context, index) => Center(
          child: ChoiceChip(
            key: _keys[index],
            label: Text(widget.labels[index]),
            selected: index == _shown,
            onSelected: (_) {
              setState(() => _shown = index);
              widget.controller.animateTo(index);
            },
          ),
        ),
      ),
    );
  }
}

/// Keeps the chip row stuck to the top while the header scrolls away.
class _PinnedChipsDelegate extends SliverPersistentHeaderDelegate {
  final Widget chips;
  final double height;
  final Color background;
  final Color divider;

  const _PinnedChipsDelegate({
    required this.chips,
    required this.height,
    required this.background,
    required this.divider,
  });

  static const double _verticalPadding = AppSpacing.xs4;

  @override
  double get minExtent => height + _verticalPadding * 2 + 1;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: _verticalPadding, bottom: _verticalPadding + 1),
        child: SizedBox(height: height, child: chips),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedChipsDelegate oldDelegate) {
    return oldDelegate.chips != chips ||
        oldDelegate.height != height ||
        oldDelegate.background != background ||
        oldDelegate.divider != divider;
  }
}

/// Scroll view for one tab inside the NestedScrollView: injects the space the
/// pinned chip row takes and remembers its scroll offset per tab. Long song
/// lists get a draggable [scrollbar].
class _TabScrollView extends StatelessWidget {
  final String storageKey;
  final List<Widget> slivers;
  final bool scrollbar;

  const _TabScrollView({required this.storageKey, required this.slivers, this.scrollbar = false});

  @override
  Widget build(BuildContext context) {
    final view = CustomScrollView(
      key: PageStorageKey<String>(storageKey),
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl24)),
      ],
    );
    if (!scrollbar) return view;
    return Scrollbar(interactive: true, notificationPredicate: (n) => n.depth == 0, child: view);
  }
}

class _LoadingSliver extends StatelessWidget {
  const _LoadingSliver();

  @override
  Widget build(BuildContext context) {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          // The theme's 3 dp primary spinner.
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// "128 SONGS" on the left in the `overline` voice, compact actions on the
/// right. When both do not fit on one line (large text on a narrow phone)
/// the actions move under the count instead of squeezing it.
class _ListToolbar extends StatelessWidget {
  final String label;
  final List<Widget> actions;

  const _ListToolbar({required this.label, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, AppSpacing.xs4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md12,
        runSpacing: AppSpacing.xs4,
        children: [
          Text(
            label.toUpperCase(),
            semanticsLabel: label,
            style: context.typography.overline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Wrap(
            spacing: AppSpacing.sm8,
            runSpacing: AppSpacing.sm8,
            children: actions,
          ),
        ],
      ),
    );
  }
}

/// A grid of square covers with captions under them; each tile's height
/// follows the text scale so the captions never overflow.
class _CoverGrid extends StatelessWidget {
  final int itemCount;

  /// Tiles are at least this wide; two columns at least.
  final double minTileWidth;

  /// The caption's line styles, top to bottom, for sizing the tiles.
  final List<TextStyle> Function(AppTextStyles type) captionLines;

  final Widget Function(BuildContext context, int index, double side) itemBuilder;

  const _CoverGrid({
    required this.itemCount,
    required this.captionLines,
    required this.itemBuilder,
    this.minTileWidth = 150,
  });

  /// Rounding allowance so a fractional line height never clips a caption.
  static const double _captionSlack = 4;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Height of one line of [style] at the user's text size, read from the
    // typography tokens so the tile grows with them.
    double line(TextStyle style) => scaler.scale(style.fontSize!) * (style.height ?? 1);
    final lines = captionLines(context.typography);
    final captionHeight = _GridTile.coverGap + lines.fold<double>(0, (sum, s) => sum + line(s)) + _captionSlack;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md12;
        final columns = ((constraints.crossAxisExtent + spacing) / (minTileWidth + spacing)).floor().clamp(2, 6);
        final tileWidth = (constraints.crossAxisExtent - spacing * (columns - 1)) / columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.lg16,
            crossAxisSpacing: spacing,
            mainAxisExtent: tileWidth + captionHeight,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => itemBuilder(context, index, tileWidth),
            childCount: itemCount,
          ),
        );
      },
    );
  }
}

/// A cover with its caption (a name in `bodyStrong`, then `metadata` lines),
/// one tappable node for screen readers.
class _GridTile extends StatelessWidget {
  final Widget cover;
  final String title;
  final List<String> lines;
  final String semanticsLabel;
  final VoidCallback onTap;
  final bool centered;

  /// The last line uses `caption` (the song count under an album).
  final bool lastLineIsCaption;

  const _GridTile({
    required this.cover,
    required this.title,
    required this.lines,
    required this.semanticsLabel,
    required this.onTap,
    this.centered = false,
    this.lastLineIsCaption = false,
  });

  static const double coverGap = AppSpacing.sm8;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final align = centered ? TextAlign.center : TextAlign.start;
    // excludeSemantics drops the InkWell's tap action, so the node carries
    // its own: TalkBack / Switch Access can open it.
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
          highlightColor: palette.surfacePressed,
          child: Column(
            crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
            children: [
              cover,
              const SizedBox(height: coverGap),
              Text(title, style: type.bodyStrong, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis),
              for (var i = 0; i < lines.length; i++)
                Text(
                  lines[i],
                  style: lastLineIsCaption && i == lines.length - 1 ? type.caption : type.metadata,
                  textAlign: align,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An album in the grid: the same song's cover (and the same placeholder
/// colours) as the album's page, at radius 14, then its name, artist and
/// song count.
class _AlbumTile extends StatelessWidget {
  final AlbumGroup album;
  final double artSize;

  const _AlbumTile({required this.album, required this.artSize});

  @override
  Widget build(BuildContext context) {
    void open() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
      );
    }

    final coverUri = album.coverUri;
    final seed = ArtworkPlaceholder.albumSeed(album.album);
    const radius = AppSpacing.radiusThumb;

    return _GridTile(
      cover: coverUri == null || coverUri.isEmpty
          ? SizedBox.square(
              dimension: artSize,
              child: ArtworkPlaceholder(
                seed: seed,
                icon: Icons.album_rounded,
                borderRadius: BorderRadius.circular(radius),
              ),
            )
          : ArtworkThumbnail(
              uri: coverUri,
              // A download's cover is its saved thumbnail.
              artworkPath: album.coverArtworkPath,
              size: artSize,
              borderRadius: radius,
              placeholderIcon: Icons.album_rounded,
              placeholderSeed: seed,
            ),
      title: album.album,
      lines: [album.artist, _count(album.songCount, 'song', 'songs')],
      lastLineIsCaption: true,
      semanticsLabel: 'Album ${album.album} by ${album.artist}, ${_count(album.songCount, 'song', 'songs')}',
      onTap: open,
    );
  }
}

/// An artist's round face: their initial on the artist's own cover colours
/// (the same ones their page uses when no song has a cover).
class _ArtistAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _ArtistAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    final gradient = ArtworkPlaceholder.gradientFor(ArtworkPlaceholder.artistSeed(name), context.palette);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      child: ExcludeSemantics(
        child: Text(
          initial,
          // A letter of the artist's name: Anek draws Latin and Devanagari
          // alike. White, like every glyph on a cover gradient.
          style: context.typography.greeting.copyWith(
            fontSize: size * 0.4,
            height: 1,
            color: Colors.white.withValues(alpha: ArtworkPlaceholder.glyphOpacity),
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}
