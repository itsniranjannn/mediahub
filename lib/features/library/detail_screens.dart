import 'package:flutter/gestures.dart' show DelayedMultiDragGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
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

/// Size of the cover in the hero header of every detail screen.
const double _kHeroArtSize = 168;

/// Corner radius of a square hero cover (about 10 % of its side, so it reads
/// as album art rather than an app icon).
const double _kHeroArtRadius = AppSpacing.lg16;

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

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumGroup album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(_albumSongsProvider(album.album));

    return _DetailScaffold(
      title: album.album,
      // Only the song list has a hero; loading / error / empty need the bar title.
      showTitle: !songsAsync.maybeWhen(data: (songs) => songs.isNotEmpty, orElse: () => false),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'More options',
          onPressed: () {
            songsAsync.whenData((songs) {
              if (songs.isNotEmpty) {
                MediaContextMenu.show(context, ref, songs.first);
              }
            });
          },
        ),
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
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                // A real cover gets the neutral violet glow: the placeholder's
                // palette would clash with the cover's own colours.
                child: ArtworkPresenceBuilder(
                  item: cover,
                  lookupSize: _kHeroLookupSize,
                  builder: (context, hasArtwork, _) => _HeroHeader(
                    tint: hasArtwork ? AppColors.heroGradient : ArtworkTint.surfaceGradient(_albumSeed(album)),
                    artwork: _HeroArtwork(
                      glowColor: hasArtwork ? null : ArtworkTint.glow(_albumSeed(album)),
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
                    meta: _songsMeta(songs),
                    onPlay: () {
                      ref.read(playbackNotifierProvider.notifier).loadQueue(songs, autoPlay: true);
                    },
                    onShuffle: () {
                      final shuffled = List<MediaItem>.from(songs)..shuffle();
                      ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                    },
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return MediaSongRow(
                    item: song,
                    showArtwork: false,
                    onTap: () {
                      ref.read(playbackNotifierProvider.notifier).playTrack(song, songs);
                    },
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => EmptyHint(
          icon: Icons.error_outline_rounded,
          title: 'Could not load songs',
          message: 'Error: $err',
        ),
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

    return _DetailScaffold(
      title: artist.artist,
      // Only the song list has a hero; loading / error / empty need the bar title.
      showTitle: !songsAsync.maybeWhen(data: (songs) => songs.isNotEmpty, orElse: () => false),
      body: songsAsync.when(
        data: (songs) {
          if (songs.isEmpty) {
            return const EmptyHint(
              icon: Icons.person_rounded,
              title: 'No songs for artist',
              message: 'Songs by this artist are no longer in your library.',
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                // A real cover gets the neutral violet glow (see the album).
                child: ArtworkPresenceBuilder(
                  item: songs.first,
                  lookupSize: _kHeroLookupSize,
                  builder: (context, hasArtwork, _) => _HeroHeader(
                    tint: hasArtwork ? AppColors.heroGradient : ArtworkTint.surfaceGradient(_artistSeed(artist)),
                    artwork: _HeroArtwork(
                      circle: true,
                      glowColor: hasArtwork ? null : ArtworkTint.glow(_artistSeed(artist)),
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
                    meta: _songsMeta(songs),
                    onPlay: () {
                      ref.read(playbackNotifierProvider.notifier).loadQueue(songs, autoPlay: true);
                    },
                    onShuffle: () {
                      final shuffled = List<MediaItem>.from(songs)..shuffle();
                      ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                    },
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return MediaSongRow(
                    item: song,
                    onTap: () {
                      ref.read(playbackNotifierProvider.notifier).playTrack(song, songs);
                    },
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => EmptyHint(
          icon: Icons.error_outline_rounded,
          title: 'Could not load songs',
          message: 'Error: $err',
        ),
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

    return _DetailScaffold(
      title: playlist.name,
      // An empty playlist still shows its hero; loading / error need the bar title.
      showTitle: !songsAsync.maybeWhen(data: (_) => true, orElse: () => false),
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
      body: songsAsync.when(
        data: (songs) {
          final header = _HeroHeader(
            artwork: const _HeroArtwork(child: _PlaylistCover(size: _kHeroArtSize)),
            eyebrow: 'Playlist',
            title: playlist.name,
            meta: _songsMeta(songs),
            onPlay: songs.isEmpty
                ? null
                : () {
                    ref.read(playbackNotifierProvider.notifier).loadQueue(songs, autoPlay: true);
                  },
            onShuffle: songs.isEmpty
                ? null
                : () {
                    final shuffled = List<MediaItem>.from(songs)..shuffle();
                    ref.read(playbackNotifierProvider.notifier).loadQueue(shuffled, autoPlay: true);
                  },
          );

          if (songs.isEmpty) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyHint(
                    icon: Icons.queue_music_rounded,
                    title: 'Playlist is empty',
                    message: 'Add songs with "Add to playlist" in any song\'s menu.',
                  ),
                ),
              ],
            );
          }

          return ReorderableListView.builder(
            header: header,
            padding: const EdgeInsets.only(bottom: AppSpacing.xxxl32),
            itemCount: songs.length,
            // The rows bring their own drag starters: long-press anywhere on
            // the row, or an immediate drag from the handle (_RowDragListener
            // keeps the two from both starting a recognizer).
            buildDefaultDragHandles: false,
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              ref.read(libraryRepositoryProvider).reorderPlaylist(playlist.id, oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final song = songs[index];
              void remove() {
                ref.read(libraryRepositoryProvider).removeSongFromPlaylist(playlist.id, song.id, index);
              }

              // Under TalkBack / VoiceOver the swipe would become unlabelled
              // scroll actions on the row, and "scroll forward" would take the
              // song out of the playlist. So the swipe is off and the row gets
              // a real "Remove from playlist" button, like the queue's. (A
              // custom action cannot be used: it conflicts with the list's own
              // "Move up / down" actions and splits the row into two nodes.)
              final screenReader = MediaQuery.accessibleNavigationOf(context);
              return Dismissible(
                key: ValueKey('${song.id}_$index'),
                direction: screenReader ? DismissDirection.none : DismissDirection.endToStart,
                background: const _RemoveBackground(),
                onDismissed: (_) => remove(),
                child: _RowDragListener(
                  index: index,
                  child: MediaSongRow(
                    item: song,
                    trailing: screenReader
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RemoveFromPlaylistButton(onPressed: remove),
                              _DragHandle(index: index),
                            ],
                          )
                        : _DragHandle(index: index),
                    onTap: () {
                      ref.read(playbackNotifierProvider.notifier).playTrack(song, songs);
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => EmptyHint(
          icon: Icons.error_outline_rounded,
          title: 'Could not load songs',
          message: 'Error: $err',
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: AppTypography.body,
            decoration: const InputDecoration(
              hintText: 'Playlist name',
              prefixIcon: Icon(Icons.edit_rounded, color: AppColors.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
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
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
          title: const Text('Delete Playlist'),
          content: const Text(
            'Are you sure you want to delete this playlist? This will NOT delete the actual audio files on your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.background,
              ),
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

/// "12 songs · 48 min"
String _songsMeta(List<MediaItem> songs) {
  final count = songs.length;
  final countText = count == 1 ? '1 song' : '$count songs';
  var totalMs = 0;
  for (final song in songs) {
    if (song.durationMs > 0) totalMs += song.durationMs;
  }
  if (totalMs <= 0) return countText;
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
  return '$countText · $durationText';
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
    return Scaffold(
      backgroundColor: AppColors.background,
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
              color: solid ? AppColors.background : AppColors.background.withValues(alpha: 0),
              child: AppBar(
                backgroundColor: Colors.transparent,
                title: AnimatedOpacity(
                  opacity: solid ? 1 : 0,
                  duration: duration,
                  curve: MotionTokens.easeOut,
                  child: Text(
                    widget.title,
                    style: AppTypography.sectionTitle,
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

/// Cover, eyebrow, title, subtitle, song count and the Play / Shuffle pair,
/// on a soft violet glow that fades into the page.
class _HeroHeader extends StatelessWidget {
  final Widget artwork;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final String meta;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  /// Glow behind the header; the violet hero gradient unless the cover's
  /// own colours are passed. A change (the real cover finishing loading)
  /// cross-fades instead of snapping.
  final Gradient tint;

  const _HeroHeader({
    required this.artwork,
    required this.eyebrow,
    required this.title,
    required this.meta,
    this.subtitle,
    this.onPlay,
    this.onShuffle,
    this.tint = AppColors.heroGradient,
  });

  @override
  Widget build(BuildContext context) {
    // The body sits behind the transparent app bar; this is its height.
    final topInset = MediaQuery.paddingOf(context).top;

    return AnimatedContainer(
      duration: MotionTokens.duration(context, MotionTokens.page),
      curve: MotionTokens.easeOut,
      decoration: BoxDecoration(gradient: tint),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background.withValues(alpha: 0), AppColors.background],
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
              const SizedBox(height: AppSpacing.xl20),
              Text(
                eyebrow.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.xs4),
              Semantics(
                header: true,
                child: Text(
                  breakableTitle(title),
                  semanticsLabel: title,
                  style: AppTypography.screenTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  subtitle!,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: AppSpacing.xs4),
              Text(
                meta,
                style: AppTypography.metadata.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              if (onPlay != null || onShuffle != null) ...[
                const SizedBox(height: AppSpacing.xl20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onPlay,
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: onShuffle,
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          label: const Text('Shuffle'),
                        ),
                      ),
                    ],
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

/// Cover with a soft glow underneath: neutral violet, or the placeholder's
/// own colour when there is no real cover. A change cross-fades.
class _HeroArtwork extends StatelessWidget {
  final Widget child;
  final bool circle;
  final Color? glowColor;

  const _HeroArtwork({required this.child, this.circle = false, this.glowColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MotionTokens.duration(context, MotionTokens.page),
      curve: MotionTokens.easeOut,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(_kHeroArtRadius),
        boxShadow: [
          BoxShadow(
            color: glowColor ?? AppColors.primaryBase.withValues(alpha: 0.28),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Gradient tile standing in for a playlist cover.
class _PlaylistCover extends StatelessWidget {
  final double size;

  const _PlaylistCover({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(_kHeroArtRadius),
      ),
      child: Icon(Icons.queue_music_rounded, size: size * 0.42, color: AppColors.onPrimary),
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
          child: const SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
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
      color: AppColors.textMuted,
      tooltip: 'Remove from playlist',
      constraints: const BoxConstraints(
        minWidth: AppSpacing.minTouchTarget,
        minHeight: AppSpacing.minTouchTarget,
      ),
      onPressed: onPressed,
    );
  }
}

/// Shown behind a playlist row while it is swiped away: the same inset pill
/// as the row (and as the queue's swipe-to-remove).
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8, vertical: 1),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Remove', style: AppTypography.button.copyWith(color: AppColors.error)),
            const SizedBox(width: AppSpacing.sm8),
            const Icon(Icons.delete_rounded, color: AppColors.error),
          ],
        ),
      ),
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
