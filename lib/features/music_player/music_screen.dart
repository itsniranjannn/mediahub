import '../../domain/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/permissions/media_permission_service.dart';
import '../../core/widgets/artwork_thumbnail.dart';
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
import 'playback_notifier.dart';

/// Compact toolbar buttons (40 dp tall, 48 dp touch target via padding).
/// Sizes only: the theme colours FilledButton and FilledButton.tonal.
final ButtonStyle _compactStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, AppSpacing.giant40),
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
);

/// "1 song", "12 songs".
String _count(int n, String singular, String plural) => '$n ${n == 1 ? singular : plural}';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> with SingleTickerProviderStateMixin {
  static const List<String> _tabs = ['Songs', 'Albums', 'Artists', 'Playlists', 'Favorites'];

  /// Gap above and below the selected-tab pill: a 48 dp tab gets a 36 dp pill.
  static const double _tabPillInset = 6;

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _notificationPermissionRequested = false;
  DateTime? _lastShuffleAllTap;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestNotificationPermissionOnce() async {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      await Permission.notification.request();
    } catch (e) {
      debugPrint('Notification permission request error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicLibraryProvider);
    final notifier = ref.read(musicLibraryProvider.notifier);
    final repo = ref.watch(libraryRepositoryProvider);

    final permission = state.permissionState;
    final hasLibrary =
        permission == MediaPermissionState.granted || permission == MediaPermissionState.limited;

    final header = _MusicHeader(
      actions: [
        if (permission == MediaPermissionState.granted) ...[
          IconButton(
            icon: state.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Scan device media',
            onPressed: state.isScanning ? null : () => notifier.scanDevice(),
          ),
          PopupMenuButton<MediaSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort songs',
            onSelected: (sort) => notifier.setSortOption(sort),
            itemBuilder: (context) => [
              _sortItem(MediaSortOption.title, 'Title', state),
              _sortItem(MediaSortOption.artist, 'Artist', state),
              _sortItem(MediaSortOption.dateAdded, 'Date Added', state),
              _sortItem(MediaSortOption.duration, 'Duration', state),
            ],
          ),
        ],
      ],
    );

    return Scaffold(
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
                  SliverToBoxAdapter(child: _searchField(notifier)),
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                    sliver: SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedTabBarDelegate(
                        tabBar: _tabBar(),
                        showDivider: innerBoxIsScrolled,
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSongsTab(state),
                    _buildAlbumsTab(repo, state.searchQuery),
                    _buildArtistsTab(repo, state.searchQuery),
                    _buildPlaylistsTab(repo),
                    _buildFavoritesTab(repo, state.searchQuery),
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
    );
  }

  PopupMenuItem<MediaSortOption> _sortItem(MediaSortOption option, String label, LibraryState state) {
    final selected = state.sortBy == option;
    return PopupMenuItem<MediaSortOption>(
      value: option,
      child: Semantics(
        selected: selected,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: selected ? const Icon(Icons.check_rounded, size: 20, color: AppColors.primary) : null,
            ),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Text(
                label,
                style: selected
                    ? AppTypography.bodyStrong.copyWith(color: AppColors.primary)
                    : AppTypography.body,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.md12),
              Icon(
                state.ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 16,
                color: AppColors.textSecondary,
                semanticLabel: state.ascending ? 'Ascending' : 'Descending',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchField(BaseLibraryNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, AppSpacing.sm8),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => notifier.setSearchQuery(val),
        textInputAction: TextInputAction.search,
        style: AppTypography.body,
        decoration: InputDecoration(
          // Short enough to stay whole at 320 dp and at large text.
          hintText: 'Search your music',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    notifier.setSearchQuery('');
                  },
                )
              : null,
        ),
      ),
    );
  }

  TabBar _tabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: const EdgeInsets.symmetric(vertical: _tabPillInset),
      indicator: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.xxl24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      dividerColor: Colors.transparent,
      dividerHeight: 0,
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      labelStyle: AppTypography.button,
      unselectedLabelStyle: AppTypography.button.copyWith(fontWeight: FontWeight.w500),
      // The sliding pill is the feedback; an ink box (taller than the pill) would fight it.
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      tabs: [
        for (final label in _tabs) Tab(text: label, height: AppSpacing.minTouchTarget),
      ],
    );
  }

  Widget _buildPermissionState(LibraryState state, BaseLibraryNotifier notifier) {
    if (state.permissionState == MediaPermissionState.denied) {
      return EmptyHint(
        icon: Icons.security_rounded,
        title: 'Permission Required',
        message:
            '${AppConfig.appName} needs media permission to access your audio files and build your music library.',
        action: FilledButton.icon(
          onPressed: () => notifier.requestPermission(),
          icon: const Icon(Icons.lock_open_rounded, size: 20),
          label: const Text('Allow Access'),
        ),
      );
    }

    if (state.permissionState == MediaPermissionState.permanentlyDenied) {
      return EmptyHint(
        icon: Icons.no_encryption_gmailerrorred_rounded,
        title: 'Permission Permanently Denied',
        message:
            'Media permission was permanently denied. Please grant permission in system settings to access your music library.',
        action: FilledButton.icon(
          onPressed: () => notifier.openSettings(),
          icon: const Icon(Icons.settings_rounded, size: 20),
          label: const Text('Open Settings'),
        ),
      );
    }

    // Still checking the permission.
    return const SizedBox.shrink();
  }

  Widget _buildSongsTab(LibraryState state) {
    if (state.status == LibraryStatus.loading || state.status == LibraryStatus.initial) {
      return const _TabScrollView(
        storageKey: 'songs',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            ),
          ),
        ],
      );
    }

    if (state.items.isEmpty) {
      return _TabScrollView(
        storageKey: 'songs',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: Icons.music_off_outlined,
              title: 'No Music Found',
              message: state.searchQuery.isNotEmpty
                  ? 'No songs matching "${state.searchQuery}".'
                  : 'Find the songs saved on this phone.',
              action: state.searchQuery.isNotEmpty
                  ? null
                  : FilledButton.tonalIcon(
                      onPressed: state.isScanning
                          ? null
                          : () => ref.read(musicLibraryProvider.notifier).scanDevice(),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Scan device'),
                    ),
            ),
          ),
        ],
      );
    }

    return _TabScrollView(
      storageKey: 'songs',
      slivers: [
        SliverToBoxAdapter(
          child: _ListToolbar(
            label: _count(state.items.length, 'song', 'songs'),
            actions: [
              FilledButton.icon(
                style: _compactStyle,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle all'),
                onPressed: () {
                  final now = DateTime.now();
                  if (_lastShuffleAllTap != null && now.difference(_lastShuffleAllTap!).inMilliseconds < 500) {
                    return;
                  }
                  _lastShuffleAllTap = now;
                  final randomStart = (state.items.isNotEmpty)
                      ? DateTime.now().microsecond % state.items.length
                      : 0;
                  ref.read(playbackNotifierProvider.notifier).loadQueue(
                    state.items,
                    startIndex: randomStart,
                    autoPlay: true,
                    shuffle: true,
                  );
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
              onTap: () async {
                await _requestNotificationPermissionOnce();
                await ref.read(playbackNotifierProvider.notifier).playTrack(song, state.items);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAlbumsTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<AlbumGroup>>(
      stream: repo.watchAlbums(searchQuery: query),
      builder: (context, snapshot) {
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
              sliver: _AlbumGrid(albums: albums),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistsTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<ArtistGroup>>(
      stream: repo.watchArtists(searchQuery: query),
      builder: (context, snapshot) {
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
              sliver: SliverList.separated(
                itemCount: artists.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm8),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return _GroupCard(
                    leading: _ArtistAvatar(name: artist.artist),
                    title: artist.artist,
                    subtitle: _artistSubtitle(artist),
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

  Widget _buildPlaylistsTab(LibraryRepository repo) {
    return StreamBuilder<List<Playlist>>(
      stream: repo.watchPlaylists(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const _TabScrollView(storageKey: 'playlists', slivers: [_LoadingSliver()]);
        }
        final playlists = snapshot.data ?? [];
        return _TabScrollView(
          storageKey: 'playlists',
          slivers: [
            SliverToBoxAdapter(
              child: _ListToolbar(
                label: _count(playlists.length, 'playlist', 'playlists'),
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
            if (playlists.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.queue_music_rounded,
                  title: 'No playlists yet',
                  message: 'Tap "New playlist" to create one!',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, 0),
                sliver: SliverList.separated(
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm8),
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    return _GroupCard(
                      leading: const _PlaylistGlyph(),
                      title: pl.name,
                      subtitle: _count(pl.songCount, 'song', 'songs'),
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

  Widget _buildFavoritesTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<MediaItem>>(
      stream: repo.watchFavorites(searchQuery: query),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const _TabScrollView(storageKey: 'favorites', slivers: [_LoadingSliver()]);
        }
        final favs = snapshot.data ?? [];
        if (favs.isEmpty) {
          return _TabScrollView(
            storageKey: 'favorites',
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.favorite_border_rounded,
                  title: 'No favorite songs yet',
                  message: query.isNotEmpty
                      ? 'No favorites matching "$query".'
                      : 'Tap the heart on any song to keep it here.',
                ),
              ),
            ],
          );
        }
        return _TabScrollView(
          storageKey: 'favorites',
          slivers: [
            SliverToBoxAdapter(
              child: _ListToolbar(
                label: _count(favs.length, 'favorite', 'favorites'),
                actions: [
                  FilledButton.icon(
                    style: _compactStyle,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play all'),
                    onPressed: () {
                      ref.read(playbackNotifierProvider.notifier).loadQueue(favs, autoPlay: true);
                    },
                  ),
                  FilledButton.tonalIcon(
                    style: _compactStyle,
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Shuffle'),
                    onPressed: () {
                      final shuffled = List<MediaItem>.from(favs)..shuffle();
                      ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                    },
                  ),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: favs.length,
              itemBuilder: (context, index) {
                final song = favs[index];
                return MediaSongRow(
                  item: song,
                  onTap: () {
                    ref.read(playbackNotifierProvider.notifier).playTrack(song, favs);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Large screen title with a one-line subtitle and optional icon actions.
class _MusicHeader extends StatelessWidget {
  final List<Widget> actions;

  const _MusicHeader({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
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
                Semantics(header: true, child: Text('Music', style: AppTypography.display)),
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  'Your songs, albums and playlists.',
                  style: AppTypography.metadata,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md12, AppSpacing.sm8, AppSpacing.xs4, AppSpacing.sm8),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSpacing.lg16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Text(
                'You gave access to selected items only. To see all your media, grant full access in Settings.',
                style: AppTypography.metadata.copyWith(color: AppColors.textPrimary),
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

/// Keeps the pill tab bar stuck to the top while the header scrolls away.
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final bool showDivider;

  const _PinnedTabBarDelegate({required this.tabBar, required this.showDivider});

  static const double _verticalPadding = AppSpacing.xs4;

  @override
  double get minExtent => tabBar.preferredSize.height + _verticalPadding * 2;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: showDivider ? AppColors.divider : Colors.transparent),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.showDivider != showDivider;
  }
}

/// Scroll view for one tab inside the NestedScrollView: injects the space the
/// pinned tab bar takes and remembers its scroll offset per tab.
class _TabScrollView extends StatelessWidget {
  final String storageKey;
  final List<Widget> slivers;

  const _TabScrollView({required this.storageKey, required this.slivers});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: PageStorageKey<String>(storageKey),
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl24)),
      ],
    );
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
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      ),
    );
  }
}

/// "128 songs" on the left, compact actions on the right. When both do not
/// fit on one line (large text on a narrow phone) the actions move under the
/// count instead of squeezing it to "12 favo…".
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
            label,
            style: AppTypography.label.copyWith(color: AppColors.textSecondary),
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

/// Two-column album grid; each tile's height follows the text scale so the
/// captions never overflow.
class _AlbumGrid extends StatelessWidget {
  final List<AlbumGroup> albums;

  const _AlbumGrid({required this.albums});

  /// Rounding allowance so a fractional line height never clips a caption.
  static const double _captionSlack = 4;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Height of one line of [style] at the user's text size, read from the
    // typography tokens so the tile grows with them.
    double line(TextStyle style) => scaler.scale(style.fontSize!) * (style.height ?? 1);
    // _AlbumCard caption: title, artist, gap, song count, padding.
    final captionHeight = line(AppTypography.bodyStrong) +
        line(AppTypography.metadata) +
        _AlbumCard.countGap +
        line(AppTypography.caption) +
        _AlbumCard.captionPadding * 2 +
        _captionSlack;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md12;
        final columns = (constraints.crossAxisExtent / 200).floor().clamp(2, 5);
        final tileWidth = (constraints.crossAxisExtent - spacing * (columns - 1)) / columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: tileWidth + captionHeight,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _AlbumCard(album: albums[index], artSize: tileWidth),
            childCount: albums.length,
          ),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final AlbumGroup album;
  final double artSize;

  const _AlbumCard({required this.album, required this.artSize});

  /// Padding around the caption and the gap above the song count; [_AlbumGrid]
  /// sizes the tiles from these.
  static const double captionPadding = AppSpacing.md12;
  static const double countGap = 2;

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

    // excludeSemantics drops the InkWell's tap action, so the node carries
    // its own: TalkBack / Switch Access can open the album.
    return Semantics(
      button: true,
      label: 'Album ${album.album} by ${album.artist}, ${_count(album.songCount, 'song', 'songs')}',
      onTap: open,
      excludeSemantics: true,
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
              child: SizedBox(
                width: double.infinity,
                height: artSize,
                // The same song's cover (and the same placeholder colours)
                // as the album's detail screen, so the tile and its page match.
                child: coverUri == null || coverUri.isEmpty
                    ? ArtworkPlaceholder(seed: seed, icon: Icons.album_rounded)
                    : ArtworkThumbnail(
                        uri: coverUri,
                        // A download's cover is its saved thumbnail.
                        artworkPath: album.coverArtworkPath,
                        width: artSize,
                        height: artSize,
                        borderRadius: 0,
                        placeholderIcon: Icons.album_rounded,
                        placeholderSeed: seed,
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(captionPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.album,
                      style: AppTypography.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      album.artist,
                      style: AppTypography.metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: countGap),
                    Text(
                      _count(album.songCount, 'song', 'songs'),
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card row used for artists and playlists.
class _GroupCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String semanticsLabel;
  final VoidCallback onTap;

  const _GroupCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // excludeSemantics drops the InkWell's tap action, so the node carries
    // its own: TalkBack / Switch Access can open the artist or playlist.
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md12, AppSpacing.md12, AppSpacing.sm8, AppSpacing.md12),
        onTap: onTap,
        child: Row(
          children: [
            leading,
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Round initial on a soft violet glow.
class _ArtistAvatar extends StatelessWidget {
  final String name;

  const _ArtistAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.heroGradient,
      ),
      child: Text(
        initial,
        // A letter of the artist's name: Anek draws Latin and Devanagari alike.
        style: AppTypography.cardTitle.copyWith(color: AppColors.primary),
        textScaler: TextScaler.noScaling,
      ),
    );
  }
}

/// Small violet tile standing in for a playlist cover.
class _PlaylistGlyph extends StatelessWidget {
  const _PlaylistGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppSpacing.md12),
      ),
      child: const Icon(Icons.queue_music_rounded, color: AppColors.onPrimary),
    );
  }
}
