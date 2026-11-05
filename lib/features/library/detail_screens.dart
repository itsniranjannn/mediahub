import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../library/media_context_menu.dart';
import '../library/media_song_row.dart';
import '../music_player/playback_notifier.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumGroup album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(_albumSongsProvider(album.album));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(album.album, style: AppTypography.sectionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {
              songsAsync.whenData((songs) {
                if (songs.isNotEmpty) {
                  MediaContextMenu.show(context, ref, songs.first);
                }
              });
            },
          ),
        ],
      ),
      body: songsAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return Center(child: Text('No songs in album', style: AppTypography.metadata));
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl24),
                  child: Column(
                    children: [
                      ArtworkThumbnail(
                        uri: songs.first.uri,
                        size: 180,
                        borderRadius: AppSpacing.cardRadius,
                      ),
                      const SizedBox(height: AppSpacing.lg16),
                      Text(
                        album.album,
                        style: AppTypography.screenTitle.copyWith(fontSize: 22),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs4),
                      Text(
                        album.artist,
                        style: AppTypography.metadata.copyWith(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                            onPressed: () {
                              ref.read(playbackNotifierProvider.notifier).loadQueue(songs, autoPlay: true);
                            },
                          ),
                          const SizedBox(width: AppSpacing.md12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('Shuffle'),
                            onPressed: () {
                              final shuffled = List<MediaItem>.from(songs)..shuffle();
                              ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = songs[index];
                    return MediaSongRow(
                      item: song,
                      showArtwork: false,
                      onTap: () {
                        ref.read(playbackNotifierProvider.notifier).playTrack(song, songs);
                      },
                    );
                  },
                  childCount: songs.length,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: AppTypography.metadata)),
      ),
    );
  }
}

class ArtistDetailScreen extends ConsumerWidget {
  final ArtistGroup artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(_artistSongsProvider(artist.artist));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(artist.artist, style: AppTypography.sectionTitle),
      ),
      body: songsAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return Center(child: Text('No songs for artist', style: AppTypography.metadata));
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl24),
                  child: Column(
                    children: [
                      ArtworkThumbnail(
                        uri: songs.first.uri,
                        size: 180,
                        borderRadius: 90, // Circular for artist
                      ),
                      const SizedBox(height: AppSpacing.lg16),
                      Text(
                        artist.artist,
                        style: AppTypography.screenTitle.copyWith(fontSize: 22),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs4),
                      Text(
                        '${songs.length} songs',
                        style: AppTypography.metadata.copyWith(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                            onPressed: () {
                              ref.read(playbackNotifierProvider.notifier).loadQueue(songs, autoPlay: true);
                            },
                          ),
                          const SizedBox(width: AppSpacing.md12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('Shuffle'),
                            onPressed: () {
                              final shuffled = List<MediaItem>.from(songs)..shuffle();
                              ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = songs[index];
                    return MediaSongRow(
                      item: song,
                      onTap: () {
                        ref.read(playbackNotifierProvider.notifier).playTrack(song, songs);
                      },
                    );
                  },
                  childCount: songs.length,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: AppTypography.metadata)),
      ),
    );
  }
}

class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(_playlistSongsProvider(playlist.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(playlist.name, style: AppTypography.sectionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Rename',
            onPressed: () {
              _showRenameDialog(context, ref);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete playlist',
            onPressed: () {
              _showDeleteConfirmation(context, ref);
            },
          ),
        ],
      ),
      body: songsAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return Center(child: Text('Playlist is empty', style: AppTypography.metadata));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                      onPressed: () {
                        ref.read(playbackNotifierProvider.notifier).loadQueue(songs, autoPlay: true);
                      },
                    ),
                    const SizedBox(width: AppSpacing.md12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                      onPressed: () {
                        final shuffled = List<MediaItem>.from(songs)..shuffle();
                        ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: songs.length,
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    ref.read(libraryRepositoryProvider).reorderPlaylist(playlist.id, oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return Dismissible(
                      key: ValueKey('${song.id}_$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: AppColors.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpacing.lg16),
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        ref.read(libraryRepositoryProvider).removeSongFromPlaylist(playlist.id, song.id, index);
                      },
                      child: MediaSongRow(
                        item: song,
                        trailing: const Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
                        onTap: () {
                          ref.read(playbackNotifierProvider.notifier).playTrack(song, songs);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err', style: AppTypography.metadata)),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Rename Playlist', style: AppTypography.sectionTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: AppTypography.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  Navigator.pop(dialogCtx);
                  ref.read(libraryRepositoryProvider).renamePlaylist(playlist.id, newName);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Delete Playlist', style: AppTypography.sectionTitle),
          content: Text(
            'Are you sure you want to delete this playlist? This will NOT delete the actual audio files on your device.',
            style: AppTypography.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                Navigator.pop(dialogCtx); // close dialog
                Navigator.pop(context); // close screen
                ref.read(libraryRepositoryProvider).deletePlaylist(playlist.id);
                ScaffoldMessenger.of(context).showSnackBar(
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

final _albumSongsProvider = StreamProvider.family<List<MediaItem>, String>((ref, album) {
  return ref.watch(libraryRepositoryProvider).watchAlbumSongs(album);
});

final _artistSongsProvider = StreamProvider.family<List<MediaItem>, String>((ref, artist) {
  return ref.watch(libraryRepositoryProvider).watchArtistSongs(artist);
});

final _playlistSongsProvider = StreamProvider.family<List<MediaItem>, String>((ref, playlistId) {
  return ref.watch(libraryRepositoryProvider).watchPlaylistSongs(playlistId);
});
