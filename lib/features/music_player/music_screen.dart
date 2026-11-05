import '../../domain/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/permissions/media_permission_service.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../library/detail_screens.dart';
import '../library/library_notifier.dart';
import '../library/media_context_menu.dart';
import '../library/media_song_row.dart';
import 'playback_notifier.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _notificationPermissionRequested = false;
  DateTime? _lastShuffleAllTap;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
        actions: [
          if (state.permissionState == MediaPermissionState.granted) ...[
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
                const PopupMenuItem(value: MediaSortOption.title, child: Text('Title')),
                const PopupMenuItem(value: MediaSortOption.artist, child: Text('Artist')),
                const PopupMenuItem(value: MediaSortOption.dateAdded, child: Text('Date Added')),
                const PopupMenuItem(value: MediaSortOption.duration, child: Text('Duration')),
              ],
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Songs'),
            Tab(text: 'Albums'),
            Tab(text: 'Artists'),
            Tab(text: 'Playlists'),
            Tab(text: 'Favorites'),
          ],
        ),
      ),
      body: _buildBody(context, state, notifier, repo),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryState state,
    BaseLibraryNotifier notifier,
    LibraryRepository repo,
  ) {
    if (state.permissionState == MediaPermissionState.checking) {
      return const SizedBox.shrink();
    }

    if (state.permissionState == MediaPermissionState.denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security_rounded, size: 64, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.lg16),
              Text('Permission Required', style: AppTypography.sectionTitle, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                '${AppConfig.appName} needs media permission to access your audio files and build your music library.',
                style: AppTypography.metadata,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl24),
              ElevatedButton.icon(
                onPressed: () => notifier.requestPermission(),
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Allow Access'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.permissionState == MediaPermissionState.permanentlyDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_encryption_gmailerrorred_rounded, size: 64, color: AppColors.warning),
              const SizedBox(height: AppSpacing.lg16),
              Text('Permission Permanently Denied', style: AppTypography.sectionTitle, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                'Media permission was permanently denied. Please grant permission in system settings to access your music library.',
                style: AppTypography.metadata,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl24),
              ElevatedButton.icon(
                onPressed: () => notifier.openSettings(),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (state.permissionState == MediaPermissionState.limited)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.xs4),
            padding: const EdgeInsets.all(AppSpacing.md12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
                const SizedBox(width: AppSpacing.sm8),
                Expanded(
                  child: Text(
                    'You gave access to selected items only. To see all your media, grant full access in Settings.',
                    style: AppTypography.metadata,
                  ),
                ),
                TextButton(
                  onPressed: () => notifier.openSettings(),
                  child: const Text('Settings'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => notifier.setSearchQuery(val),
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: 'Search songs, albums, artists...',
              hintStyle: AppTypography.metadata,
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        notifier.setSearchQuery('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.md12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSongsTab(state),
              _buildAlbumsTab(repo, state.searchQuery),
              _buildArtistsTab(repo, state.searchQuery),
              _buildPlaylistsTab(repo),
              _buildFavoritesTab(repo, state.searchQuery),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSongsTab(LibraryState state) {
    if (state.items.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.music_off_outlined,
        title: 'No Music Found',
        message: state.searchQuery.isNotEmpty
            ? 'No songs matching "${state.searchQuery}".'
            : 'Tap the scan button in the top right to scan your device for audio files.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.xs4),
          child: Row(
            children: [
              Text('${state.items.length} songs', style: AppTypography.metadata),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle all'),
                onPressed: () {
                  final now = DateTime.now();
                  if (_lastShuffleAllTap != null && now.difference(_lastShuffleAllTap!).inMilliseconds < 500) {
                    return;
                  }
                  _lastShuffleAllTap = now;
                  final shuffled = List<MediaItem>.from(state.items)..shuffle();
                  final randomStart = (shuffled.isNotEmpty)
                      ? DateTime.now().microsecond % shuffled.length
                      : 0;
                  ref.read(playbackNotifierProvider.notifier).loadQueue(
                    shuffled,
                    startIndex: randomStart,
                    autoPlay: true,
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
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
        ),
      ],
    );
  }

  Widget _buildAlbumsTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<AlbumGroup>>(
      stream: repo.watchAlbums(searchQuery: query),
      builder: (context, snapshot) {
        final albums = snapshot.data ?? [];
        if (albums.isEmpty) {
          return Center(child: Text('No albums found', style: AppTypography.metadata));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.md12,
            crossAxisSpacing: AppSpacing.md12,
            childAspectRatio: 0.8,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                padding: const EdgeInsets.all(AppSpacing.sm8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                        child: Container(
                          width: double.infinity,
                          color: AppColors.surface,
                          child: const Icon(Icons.album_rounded, size: 56, color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm8),
                    Text(album.album, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(album.artist, style: AppTypography.metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${album.songCount} songs', style: AppTypography.metadata.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildArtistsTab(LibraryRepository repo, String query) {
    return StreamBuilder<List<ArtistGroup>>(
      stream: repo.watchArtists(searchQuery: query),
      builder: (context, snapshot) {
        final artists = snapshot.data ?? [];
        if (artists.isEmpty) {
          return Center(child: Text('No artists found', style: AppTypography.metadata));
        }
        return ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.surfaceElevated,
                child: const Icon(Icons.person_rounded, color: AppColors.primary),
              ),
              title: Text(artist.artist, style: AppTypography.body),
              subtitle: Text('${artist.songCount} songs', style: AppTypography.metadata),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist)),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab(LibraryRepository repo) {
    return StreamBuilder<List<Playlist>>(
      stream: repo.watchPlaylists(),
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? [];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${playlists.length} playlists', style: AppTypography.metadata),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New playlist'),
                    onPressed: () => MediaContextMenu.showNewPlaylistDialog(context, ref),
                  ),
                ],
              ),
            ),
            if (playlists.isEmpty)
              Expanded(
                child: Center(
                  child: Text('No playlists yet. Tap "New playlist" to create one!', style: AppTypography.metadata),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                        ),
                        child: const Icon(Icons.queue_music_rounded, color: AppColors.primary),
                      ),
                      title: Text(pl.name, style: AppTypography.body),
                      subtitle: Text('${pl.songCount} songs', style: AppTypography.metadata),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
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
        final favs = snapshot.data ?? [];
        if (favs.isEmpty) {
          return Center(child: Text('No favorite songs yet', style: AppTypography.metadata));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.xs4),
              child: Row(
                children: [
                  Text('${favs.length} favorites', style: AppTypography.metadata),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play all'),
                    onPressed: () {
                      ref.read(playbackNotifierProvider.notifier).loadQueue(favs, autoPlay: true);
                    },
                  ),
                  TextButton.icon(
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
            Expanded(
              child: ListView.builder(
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
            ),
          ],
        );
      },
    );
  }
}
