import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../library/media_song_row.dart';
import '../music_player/playback_notifier.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(libraryRepositoryProvider);
    final playback = ref.watch(playbackNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
      ),
      body: CustomScrollView(
        slivers: [
          // Header / Shuffle All bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg16,
                vertical: AppSpacing.md12,
              ),
              child: Row(
                children: [
                  Text('Dashboard', style: AppTypography.screenTitle),
                  const Spacer(),
                  StreamBuilder<List<MediaItem>>(
                    stream: repo.watchRecentlyAdded(limit: 50, mediaType: MediaType.audio),
                    builder: (context, snapshot) {
                      final items = snapshot.data ?? [];
                      if (items.isEmpty) return const SizedBox.shrink();
                      DateTime? lastShuffleTap;
                      return Semantics(
                        button: true,
                        label: 'Shuffle all songs',
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          label: const Text('Shuffle all'),
                          onPressed: () async {
                            final now = DateTime.now();
                            if (lastShuffleTap != null && now.difference(lastShuffleTap!).inMilliseconds < 500) {
                              return;
                            }
                            lastShuffleTap = now;
                            final shuffled = List<MediaItem>.from(items)..shuffle();
                            final randomStart = (shuffled.isNotEmpty)
                                ? DateTime.now().microsecond % shuffled.length
                                : 0;
                            await ref.read(playbackNotifierProvider.notifier).loadQueue(
                              shuffled,
                              startIndex: randomStart,
                              autoPlay: true,
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 1. Continue Listening
          if (playback.currentItem != null)
            SliverToBoxAdapter(
              child: _buildContinueListening(context, ref, playback.currentItem!, playback.isPlaying),
            ),

          // 2. Recently Played (last 20)
          _buildStreamSection(
            title: 'Recently played',
            stream: repo.watchRecentlyPlayed(limit: 20),
            builder: (items) => _buildSongList(context, ref, items),
          ),

          // 3. Most Played (top 20, playCount > 0)
          _buildStreamSection(
            title: 'Most played',
            stream: repo.watchMostPlayed(limit: 20),
            builder: (items) => _buildSongList(context, ref, items),
          ),

          // 4. Recently Added (music only, last 20)
          _buildStreamSection(
            title: 'Recently added',
            stream: repo.watchRecentlyAdded(limit: 20, mediaType: MediaType.audio),
            builder: (items) => _buildSongList(context, ref, items),
          ),

          // 5. Recent videos row (hidden when empty)
          _buildStreamSection(
            title: 'Recent videos',
            stream: repo.watchRecentVideos(limit: 10),
            builder: (items) => _buildRecentVideosRow(context, items),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 80), // Mini-player clearance
          ),
        ],
      ),
    );
  }

  Widget _buildContinueListening(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
    bool isPlaying,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Continue listening', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm8),
          Material(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              onTap: () {
                if (!isPlaying) {
                  ref.read(playbackNotifierProvider.notifier).play();
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md12),
                child: Row(
                  children: [
                    ArtworkThumbnail(
                      uri: item.uri,
                      size: 56,
                      borderRadius: AppSpacing.buttonRadius,
                    ),
                    const SizedBox(width: AppSpacing.md12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.artist ?? 'Unknown artist',
                            style: AppTypography.metadata,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                        size: 40,
                        color: AppColors.primary,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          ref.read(playbackNotifierProvider.notifier).pause();
                        } else {
                          ref.read(playbackNotifierProvider.notifier).play();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamSection({
    required String title,
    required Stream<List<MediaItem>> stream,
    required Widget Function(List<MediaItem> items) builder,
  }) {
    return StreamBuilder<List<MediaItem>>(
      stream: stream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          // Hide empty sections as required
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.xs4),
                  child: Text(title, style: AppTypography.sectionTitle),
                ),
                builder(items),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentVideosRow(BuildContext context, List<MediaItem> items) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.xs4),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md12),
        itemBuilder: (context, index) {
          final item = items[index];
          final cleanTitle = item.title.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
          return InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            onTap: () => context.push('/video_player', extra: item),
            child: SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArtworkThumbnail(
                    uri: item.uri,
                    size: 80,
                    borderRadius: AppSpacing.buttonRadius,
                    placeholderIcon: Icons.movie_outlined,
                  ),
                  const SizedBox(height: AppSpacing.xs4),
                  Text(
                    cleanTitle,
                    style: AppTypography.metadata.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongList(BuildContext context, WidgetRef ref, List<MediaItem> items) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaSongRow(
          item: item,
          onTap: () {
            ref.read(playbackNotifierProvider.notifier).loadQueue(
              items,
              startIndex: index,
              autoPlay: true,
            );
          },
        );
      },
    );
  }
}
