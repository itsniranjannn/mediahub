import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/permissions/media_permission_service.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/media_item_tile.dart';
import '../library/library_notifier.dart';
import 'playback_notifier.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _notificationPermissionRequested = false;

  @override
  void initState() {
    super.initState();
    // Listen for playback error snackbars
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(playbackErrorStreamProvider, (previous, next) {
        next.whenData((msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: AppColors.error,
              ),
            );
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestNotificationPermissionOnce() async {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      // POST_NOTIFICATIONS is requested only when the first track plays
      // so the user has immediate context: notifications display lockscreen/status bar playback controls.
      // If denied, audio playback still continues normally without crashing.
      await Permission.notification.request();
    } catch (e) {
      debugPrint('Notification permission request error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicLibraryProvider);
    final notifier = ref.read(musicLibraryProvider.notifier);
    final playbackNotifier = ref.read(playbackNotifierProvider.notifier);

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
              tooltip: 'Sort music library',
              onSelected: (sort) => notifier.setSortOption(sort),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: MediaSortOption.title,
                  child: Text('Title'),
                ),
                const PopupMenuItem(
                  value: MediaSortOption.artist,
                  child: Text('Artist'),
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
      body: _buildBody(context, state, notifier, playbackNotifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryState state,
    BaseLibraryNotifier notifier,
    PlaybackNotifier playbackNotifier,
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

    if (state.status == LibraryStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
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
                'Failed to load library',
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
              hintText: 'Search songs or artists...',
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
        Expanded(
          child: state.items.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.music_off_outlined,
                  title: 'No Music Found',
                  message: state.searchQuery.isNotEmpty
                      ? 'No songs matching "${state.searchQuery}".'
                      : 'Tap the scan button in the top right to scan your device for audio files.',
                )
              : ListView.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final song = state.items[index];
                    return MediaItemTile(
                      item: song,
                      onTap: () async {
                        await _requestNotificationPermissionOnce();
                        await playbackNotifier.playTrack(song, state.items);
                      },
                      onPlayNext: () {
                        playbackNotifier.playNext(song);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Playing next: ${song.title}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      onAddToQueue: () {
                        playbackNotifier.addToQueue(song);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added to queue: ${song.title}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
