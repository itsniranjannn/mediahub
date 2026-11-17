import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist_and_groups.dart';
import '../music_player/playback_notifier.dart';

/// Song actions as a bottom sheet: an artwork header, then one clear row per action.
class MediaContextMenu {
  /// Lifts the Favorites snackbar clear of the bottom navigation bar.
  static const double _snackBarBottomClearance = 76;

  static void show(
    BuildContext context,
    WidgetRef ref,
    MediaItem item, {
    VoidCallback? onCustomAction,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SongHeader(item: item),
                const Divider(indent: AppSpacing.lg16, endIndent: AppSpacing.lg16),
                const SizedBox(height: AppSpacing.sm8),
                _MenuAction(
                  icon: Icons.playlist_play_rounded,
                  label: 'Play next',
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
                _MenuAction(
                  icon: Icons.queue_music_rounded,
                  label: 'Add to queue',
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    final notifier = ref.read(playbackNotifierProvider.notifier);
                    notifier.addToQueue(item);
                    final queueLength = ref.read(playbackNotifierProvider).queue.length;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added to queue: ${item.title}'),
                        duration: const Duration(seconds: 4),
                        persist: false,
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
                _MenuAction(
                  icon: Icons.playlist_add_rounded,
                  label: 'Add to playlist',
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _showAddToPlaylistSheet(context, ref, item);
                  },
                ),
                _MenuAction(
                  icon: item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: item.isFavorite ? AppColors.favorite : AppColors.textPrimary,
                  label: item.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
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
                        margin: const EdgeInsets.only(
                          left: AppSpacing.lg16,
                          right: AppSpacing.lg16,
                          bottom: _snackBarBottomClearance,
                        ),
                        duration: const Duration(seconds: 3),
                        persist: false,
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StreamBuilder<List<Playlist>>(
          stream: ref.watch(libraryRepositoryProvider).watchPlaylists(),
          builder: (sheetContext, snapshot) {
            final playlists = snapshot.data ?? [];
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.sm8, AppSpacing.xs4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Add to playlist',
                                style: AppTypography.sectionTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('New playlist'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              if (!context.mounted) return;
                              showNewPlaylistDialog(context, ref, initialSong: item);
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12),
                      child: Text(
                        item.title,
                        style: AppTypography.metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Divider(indent: AppSpacing.lg16, endIndent: AppSpacing.lg16),
                    if (playlists.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl24, vertical: AppSpacing.xxxl32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.queue_music_rounded, size: 36, color: AppColors.primary),
                            const SizedBox(height: AppSpacing.md12),
                            Text(
                              'No playlists yet. Create one above!',
                              style: AppTypography.metadata,
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
                              leading: const _PlaylistGlyph(),
                              title: Text(
                                pl.name,
                                style: AppTypography.bodyStrong,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                pl.songCount == 1 ? '1 song' : '${pl.songCount} songs',
                                style: AppTypography.metadata,
                              ),
                              trailing: const Icon(Icons.add_rounded, color: AppColors.textMuted),
                              onTap: () async {
                                // The app-wide messenger outlives this sheet, so the
                                // confirmation still shows after the sheet has closed.
                                final messenger = ScaffoldMessenger.of(itemContext);
                                Navigator.pop(ctx);
                                await ref.read(libraryRepositoryProvider).addSongToPlaylist(pl.id, item.id);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Added to ${pl.name}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
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
          title: const Text('New Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: AppTypography.body,
            decoration: const InputDecoration(
              hintText: 'Playlist name',
              prefixIcon: Icon(Icons.queue_music_rounded, color: AppColors.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
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

/// Artwork, title and artist / album of the song the menu acts on.
class _SongHeader extends StatelessWidget {
  final MediaItem item;

  const _SongHeader({required this.item});

  static const double _artSize = 60;
  static const double _artRadius = AppSpacing.sm8;
  static const double _titleGap = 2;

  @override
  Widget build(BuildContext context) {
    final artist = item.artist ?? 'Unknown Artist';
    final album = item.album;
    final subtitle = (album != null && album.isNotEmpty) ? '$artist · $album' : artist;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.lg16),
      child: Row(
        children: [
          // Foreground, so the hairline sits on top of the opaque artwork
          // instead of being hidden under it.
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_artRadius),
              border: Border.all(color: AppColors.divider),
            ),
            child: ArtworkThumbnail(
              uri: item.uri,
              artworkPath: item.artworkPath,
              size: _artSize,
              borderRadius: _artRadius,
            ),
          ),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  breakableTitle(item.title),
                  semanticsLabel: item.title,
                  style: AppTypography.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: _titleGap),
                Text(
                  subtitle,
                  style: AppTypography.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One sheet action: icon in a soft rounded square, then the label.
class _MenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = AppColors.textPrimary,
  });

  static const double _tileHeight = 56;
  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: _tileHeight,
      leading: Container(
        width: AppSpacing.giant40,
        height: AppSpacing.giant40,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.md12),
        ),
        child: Icon(icon, color: iconColor, size: _iconSize),
      ),
      title: Text(label, style: AppTypography.body),
      onTap: onTap,
    );
  }
}

/// Small violet tile that stands in for a playlist cover.
class _PlaylistGlyph extends StatelessWidget {
  const _PlaylistGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppSpacing.md12),
      ),
      child: const Icon(Icons.queue_music_rounded, color: AppColors.onPrimary, size: 22),
    );
  }
}
