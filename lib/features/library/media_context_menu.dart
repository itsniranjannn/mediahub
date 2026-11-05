import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../music_player/playback_notifier.dart';

class MediaContextMenu {
  static void show(
    BuildContext context,
    WidgetRef ref,
    MediaItem item, {
    VoidCallback? onCustomAction,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
      ),
      builder: (bottomSheetContext) {
        return Material(
          color: AppColors.surfaceElevated,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: AppTypography.sectionTitle.copyWith(fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.artist ?? 'Unknown Artist',
                            style: AppTypography.metadata,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded, color: AppColors.textPrimary),
                title: Text('Play next', style: AppTypography.body),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  ref.read(playbackNotifierProvider.notifier).playNext(item);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Playing next: ${item.title}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded, color: AppColors.textPrimary),
                title: Text('Add to queue', style: AppTypography.body),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  final notifier = ref.read(playbackNotifierProvider.notifier);
                  notifier.addToQueue(item);
                  final queueLength = ref.read(playbackNotifierProvider).queue.length;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added to queue: ${item.title}'),
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: 'Undo',
                        textColor: AppColors.primary,
                        onPressed: () {
                          if (queueLength > 0) {
                            notifier.removeQueueItemAt(queueLength - 1);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: AppColors.textPrimary),
                title: Text('Add to playlist', style: AppTypography.body),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  _showAddToPlaylistSheet(context, ref, item);
                },
              ),
              ListTile(
                leading: Icon(
                  item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: item.isFavorite ? AppColors.error : AppColors.textPrimary,
                ),
                title: Text(
                  item.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                  style: AppTypography.body,
                ),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  final nextFav = !item.isFavorite;
                  HapticFeedback.lightImpact();
                  ref.read(libraryRepositoryProvider).toggleFavorite(item.id);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        nextFav
                            ? 'Added to Favorites'
                            : 'Removed from Favorites',
                      ),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 76),
                      duration: const Duration(seconds: 3),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () {
                          ref.read(libraryRepositoryProvider).toggleFavorite(item.id);
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  static void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref, MediaItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
      ),
      builder: (ctx) {
        return Material(
          color: AppColors.surfaceElevated,
          child: StreamBuilder<List<Playlist>>(
          stream: ref.watch(libraryRepositoryProvider).watchPlaylists(),
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? [];
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.md12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add to playlist', style: AppTypography.sectionTitle),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('New playlist'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            showNewPlaylistDialog(context, ref, initialSong: item);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  if (playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl24),
                      child: Text('No playlists yet. Create one above!', style: AppTypography.metadata),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final pl = playlists[index];
                          return ListTile(
                            leading: const Icon(Icons.queue_music_rounded, color: AppColors.primary),
                            title: Text(pl.name, style: AppTypography.body),
                            subtitle: Text('${pl.songCount} songs', style: AppTypography.metadata),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await ref.read(libraryRepositoryProvider).addSongToPlaylist(pl.id, item.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Added to ${pl.name}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
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
        ),
        );
      },
    );
  }

  static void showNewPlaylistDialog(BuildContext context, WidgetRef ref, {MediaItem? initialSong}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('New Playlist', style: AppTypography.sectionTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: AppTypography.metadata,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(dialogCtx);
                  final pl = await ref.read(libraryRepositoryProvider).createPlaylist(name);
                  if (initialSong != null) {
                    await ref.read(libraryRepositoryProvider).addSongToPlaylist(pl.id, initialSong.id);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Created playlist "${pl.name}"')),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
