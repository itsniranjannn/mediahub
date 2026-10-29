import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/permissions/media_permission_service.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/media_item_tile.dart';
import '../library/library_notifier.dart';
import 'video_player_notifier.dart';
import 'video_player_screen.dart';

class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openPlayer(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoLibraryProvider);
    final notifier = ref.read(videoLibraryProvider.notifier);
    final progressListAsync = ref.watch(allVideoProgressStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          if (state.permissionState == MediaPermissionState.granted) ...[
            IconButton(
              icon: state.isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: 'Scan device media',
              onPressed: state.isScanning ? null : () => notifier.scanDevice(),
            ),
            PopupMenuButton<MediaSortOption>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort video library',
              onSelected: (sort) => notifier.setSortOption(sort),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: MediaSortOption.title,
                  child: Text('Title'),
                ),
                const PopupMenuItem(
                  value: MediaSortOption.dateAdded,
                  child: Text('Date Added'),
                ),
                const PopupMenuItem(
                  value: MediaSortOption.duration,
                  child: Text('Duration'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _buildBody(context, state, notifier, progressListAsync.value ?? []),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryState state,
    BaseLibraryNotifier notifier,
    List<dynamic> progressList,
  ) {
    if (state.permissionState == MediaPermissionState.denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.security_rounded,
                size: 64,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.lg16),
              Text(
                'Permission Required',
                style: AppTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                '${AppConfig.appName} needs media permission to access your video files and build your video library.',
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
              const Icon(
                Icons.no_encryption_gmailerrorred_rounded,
                size: 64,
                color: AppColors.warning,
              ),
              const SizedBox(height: AppSpacing.lg16),
              Text(
                'Permission Permanently Denied',
                style: AppTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                'Media permission was permanently denied. Please grant permission in system settings to access your video library.',
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

    if (state.status == LibraryStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (state.status == LibraryStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: AppSpacing.lg16),
              Text(
                'Failed to load video library',
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                state.errorMessage ?? 'An unknown error occurred.',
                style: AppTypography.metadata,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl24),
              ElevatedButton.icon(
                onPressed: () => notifier.scanDevice(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    // Build progress map
    final progressMap = {for (var p in progressList) p.mediaId: p};

    // Find items for "Continue watching"
    final continueWatchingItems = state.items.where((item) {
      final prog = progressMap[item.id];
      return prog != null && prog.positionMs > 0;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg16,
            vertical: AppSpacing.sm8,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => notifier.setSearchQuery(val),
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: 'Search videos...',
              hintStyle: AppTypography.metadata,
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppColors.textMuted),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        notifier.setSearchQuery('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg16,
                vertical: AppSpacing.md12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Continue watching horizontal row if available
        if (continueWatchingItems.isNotEmpty && _searchController.text.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg16,
              vertical: AppSpacing.xs4,
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 20, color: AppColors.accent),
                const SizedBox(width: AppSpacing.xs4),
                Text(
                  'Continue Watching',
                  style: AppTypography.sectionTitle.copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
              scrollDirection: Axis.horizontal,
              itemCount: continueWatchingItems.length,
              separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.md12),
              itemBuilder: (context, index) {
                final item = continueWatchingItems[index];
                final prog = progressMap[item.id];
                final ratio = (prog != null && prog.durationMs > 0)
                    ? (prog.positionMs / prog.durationMs).clamp(0.0, 1.0)
                    : 0.0;

                return GestureDetector(
                  onTap: () => _openPlayer(context, item),
                  child: Container(
                    width: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                color: Colors.black26,
                                child: const Center(
                                  child: Icon(Icons.movie_outlined, color: AppColors.accent, size: 28),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 3,
                                  backgroundColor: Colors.transparent,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs4),
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.metadata.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm8),
        ],

        Expanded(
          child: state.items.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.videocam_off_outlined,
                  title: 'No Videos Found',
                  message: state.searchQuery.isNotEmpty
                      ? 'No videos matching "${state.searchQuery}".'
                      : 'Tap the scan button in the top right to scan your device for video files.',
                )
              : ListView.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final video = state.items[index];
                    final prog = progressMap[video.id];
                    final ratio = (prog != null && prog.durationMs > 0)
                        ? (prog.positionMs / prog.durationMs).clamp(0.0, 1.0)
                        : null;

                    return MediaItemTile(
                      item: video,
                      progress: ratio,
                      onTap: () => _openPlayer(context, video),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
