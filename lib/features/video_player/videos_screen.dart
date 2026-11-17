import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/permissions/media_permission_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/video_progress.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/media_item_tile.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/library_notifier.dart';
import 'video_player_notifier.dart';

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
    if (item.source == 'download' || item.availability == MediaAvailability.missing) {
      final file = File(item.uri);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is missing or unavailable on storage')),
        );
        return;
      }
    }
    context.push('/video_player', extra: item);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoLibraryProvider);
    final notifier = ref.read(videoLibraryProvider.notifier);
    final progressListAsync = ref.watch(allVideoProgressStreamProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: _VideosHeader(state: state, notifier: notifier),
            ),
            ..._buildBody(
              context,
              state,
              notifier,
              progressListAsync.value ?? const <VideoProgress>[],
            ),
          ],
        ),
      ),
    );
  }

  /// Slivers below the header for the current permission / loading state.
  List<Widget> _buildBody(
    BuildContext context,
    LibraryState state,
    BaseLibraryNotifier notifier,
    List<VideoProgress> progressList,
  ) {
    if (state.permissionState == MediaPermissionState.checking) {
      return const [];
    }

    if (state.permissionState == MediaPermissionState.denied) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.lock_outline_rounded,
            iconColor: AppColors.accent,
            title: 'Permission Required',
            message:
                '${AppConfig.appName} needs media permission to access your video files and build your video library.',
            action: FilledButton.icon(
              onPressed: () => notifier.requestPermission(),
              icon: const Icon(Icons.lock_open_rounded, size: 20),
              label: const Text('Allow Access'),
            ),
          ),
        ),
      ];
    }

    if (state.permissionState == MediaPermissionState.permanentlyDenied) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.no_encryption_gmailerrorred_rounded,
            iconColor: AppColors.warning,
            title: 'Permission Permanently Denied',
            message:
                'Media permission was permanently denied. Please grant permission in system settings to access your video library.',
            action: FilledButton.tonalIcon(
              onPressed: () => notifier.openSettings(),
              icon: const Icon(Icons.settings_rounded, size: 20),
              label: const Text('Open Settings'),
            ),
          ),
        ),
      ];
    }

    if (state.status == LibraryStatus.loading || state.status == LibraryStatus.initial) {
      return [
        SliverList.builder(
          itemCount: 3,
          itemBuilder: (_, index) => _VideoCardSkeleton(announce: index == 0),
        ),
      ];
    }

    if (state.status == LibraryStatus.error) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.error,
            title: 'Failed to load video library',
            message: state.errorMessage ?? 'An unknown error occurred.',
            action: FilledButton.tonalIcon(
              onPressed: () => notifier.scanDevice(),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try again'),
            ),
          ),
        ),
      ];
    }

    // Build progress map
    final progressMap = <String, VideoProgress>{
      for (final p in progressList) p.mediaId: p,
    };

    // Find items for "Continue watching"
    final continueWatchingItems = state.items.where((item) {
      final prog = progressMap[item.id];
      return prog != null && prog.positionMs > 0;
    }).toList();
    final showContinueWatching =
        continueWatchingItems.isNotEmpty && _searchController.text.isEmpty;

    return [
      if (state.permissionState == MediaPermissionState.limited)
        SliverToBoxAdapter(
          child: _LimitedAccessBanner(onOpenSettings: () => notifier.openSettings()),
        ),
      SliverToBoxAdapter(child: _searchField(notifier)),

      // Continue watching rail if available
      if (showContinueWatching) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Continue watching')),
        SliverToBoxAdapter(
          child: _ContinueWatchingRail(
            items: continueWatchingItems,
            progressMap: progressMap,
            onOpen: (item) => _openPlayer(context, item),
          ),
        ),
      ],

      if (state.items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.videocam_off_outlined,
            iconColor: AppColors.accent,
            title: 'No Videos Found',
            message: state.searchQuery.isNotEmpty
                ? 'No videos matching "${state.searchQuery}".'
                : 'Find the videos saved on this phone.',
            action: state.searchQuery.isNotEmpty
                ? null
                : FilledButton.tonalIcon(
                    onPressed: state.isScanning ? null : () => notifier.scanDevice(),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Scan device'),
                  ),
          ),
        )
      else ...[
        if (showContinueWatching)
          const SliverToBoxAdapter(child: SectionHeader(title: 'All videos')),
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpacing.xs4, bottom: AppSpacing.xxl24),
          sliver: SliverList.builder(
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final video = state.items[index];
              final prog = progressMap[video.id];
              final ratio = (prog != null && prog.durationMs > 0)
                  ? (prog.positionMs / prog.durationMs).clamp(0.0, 1.0)
                  : null;

              return MediaItemTile(
                key: ValueKey(video.id),
                item: video,
                progress: ratio,
                onTap: () => _openPlayer(context, video),
              );
            },
          ),
        ),
      ],
    ];
  }

  Widget _searchField(BaseLibraryNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.sm8,
        AppSpacing.lg16,
        AppSpacing.sm8,
      ),
      // Rebuilds only the field, so the clear button shows as soon as you type.
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) => TextField(
          controller: _searchController,
          onChanged: (val) => notifier.setSearchQuery(val),
          textInputAction: TextInputAction.search,
          style: AppTypography.body,
          decoration: InputDecoration(
            hintText: 'Search your videos',
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchController.clear();
                      notifier.setSearchQuery('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _VideosHeader extends StatelessWidget {
  final LibraryState state;
  final BaseLibraryNotifier notifier;

  const _VideosHeader({required this.state, required this.notifier});

  static const String _tagline = 'Movies, clips and downloads in one place.';

  @override
  Widget build(BuildContext context) {
    final granted = state.permissionState == MediaPermissionState.granted;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.xl20,
        granted ? AppSpacing.xs4 : AppSpacing.lg16,
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
                  child: Text(
                    'Videos',
                    style: AppTypography.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  _subtitle(state),
                  style: AppTypography.metadata,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (granted) ...[
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
                for (final (option, label) in const [
                  (MediaSortOption.title, 'Title'),
                  (MediaSortOption.dateAdded, 'Date Added'),
                  (MediaSortOption.duration, 'Duration'),
                ])
                  PopupMenuItem(
                    value: option,
                    child: _SortOptionLabel(
                      label: label,
                      selected: state.sortBy == option,
                      ascending: state.ascending,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(LibraryState state) {
    final hasAccess = state.permissionState == MediaPermissionState.granted ||
        state.permissionState == MediaPermissionState.limited;
    if (!hasAccess || state.status != LibraryStatus.success) return _tagline;
    if (state.isScanning) return 'Scanning your device for videos…';

    final count = state.items.length;
    if (state.searchQuery.isNotEmpty) {
      return count == 1 ? '1 match' : '$count matches';
    }
    if (count == 0) return _tagline;
    final videos = count == 1 ? '1 video' : '$count videos';
    return '$videos · ${_sortLabel(state.sortBy, state.ascending)}';
  }

  static String _sortLabel(MediaSortOption sort, bool ascending) {
    switch (sort) {
      case MediaSortOption.title:
        return ascending ? 'Title A–Z' : 'Title Z–A';
      case MediaSortOption.artist:
        return ascending ? 'Artist A–Z' : 'Artist Z–A';
      case MediaSortOption.dateAdded:
        return ascending ? 'Oldest first' : 'Newest first';
      case MediaSortOption.duration:
        return ascending ? 'Shortest first' : 'Longest first';
    }
  }
}

/// Sort menu entry: a check on the active option plus its direction arrow.
class _SortOptionLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final bool ascending;

  const _SortOptionLabel({
    required this.label,
    required this.selected,
    required this.ascending,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: selected
                ? const Icon(Icons.check_rounded, size: 20, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: AppSpacing.md12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: selected
                  ? AppTypography.bodyStrong.copyWith(color: AppColors.primary)
                  : AppTypography.body,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: AppSpacing.md12),
            Icon(
              ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 16,
              color: AppColors.textSecondary,
              semanticLabel: ascending ? 'Ascending' : 'Descending',
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Limited access banner
// ---------------------------------------------------------------------------

class _LimitedAccessBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _LimitedAccessBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.xs4,
        AppSpacing.lg16,
        AppSpacing.sm8,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md12,
          AppSpacing.md12,
          AppSpacing.lg16,
          AppSpacing.xs4,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.14),
                ),
                child: const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
              ),
            ),
            const SizedBox(width: AppSpacing.md12),
            // Text gets the full width; the action sits under it so the
            // banner stays short on narrow phones and at large text sizes.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm8),
                    child: Text(
                      'You gave access to selected items only. To see all your media, grant full access in Settings.',
                      style: AppTypography.metadata,
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenSettings,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8),
                      minimumSize: const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue watching rail
// ---------------------------------------------------------------------------

class _ContinueWatchingRail extends StatelessWidget {
  final List<MediaItem> items;
  final Map<String, VideoProgress> progressMap;
  final ValueChanged<MediaItem> onOpen;

  const _ContinueWatchingRail({
    required this.items,
    required this.progressMap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // Thumbnail + gap + up to two title lines + the "time left" line, grown
    // with the text scale so nothing is clipped at large font sizes.
    final scaler = MediaQuery.textScalerOf(context);
    double lineOf(TextStyle style) => scaler.scale(style.fontSize!) * style.height!;
    final railHeight = _ResumeCard.thumbHeight +
        AppSpacing.sm8 +
        lineOf(_ResumeCard.titleStyle) * 2 +
        2 +
        lineOf(_ResumeCard.remainingStyle) +
        AppSpacing.xs4;

    return SizedBox(
      height: railHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.md12),
        itemBuilder: (context, index) {
          final item = items[index];
          final prog = progressMap[item.id];
          final timed = (prog != null && prog.durationMs > 0) ? prog : null;

          return _ResumeCard(
            item: item,
            ratio: timed == null ? 0.0 : (timed.positionMs / timed.durationMs).clamp(0.0, 1.0),
            remainingMs: timed == null ? null : timed.durationMs - timed.positionMs,
            onTap: () => onOpen(item),
          );
        },
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  final MediaItem item;
  final double ratio;
  final int? remainingMs;
  final VoidCallback onTap;

  const _ResumeCard({
    required this.item,
    required this.ratio,
    required this.remainingMs,
    required this.onTap,
  });

  static const double width = 200;
  static const double thumbHeight = width * 9 / 16;
  static final RegExp _extension = RegExp(r'\.[a-zA-Z0-9]{2,4}$');

  static TextStyle get titleStyle => AppTypography.metadata.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get remainingStyle => AppTypography.label.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w600,
      );

  static String _remainingLabel(int? remainingMs) {
    if (remainingMs == null) return 'Resume';
    final left = Duration(milliseconds: remainingMs < 0 ? 0 : remainingMs);
    if (left.inMinutes < 1) return 'Almost done';
    if (left.inHours < 1) return '${left.inMinutes} min left';
    final minutes = left.inMinutes.remainder(60);
    return minutes == 0 ? '${left.inHours} h left' : '${left.inHours} h $minutes min left';
  }

  @override
  Widget build(BuildContext context) {
    final title = item.title.replaceAll(_extension, '');
    final remaining = _remainingLabel(remainingMs);
    final radius = BorderRadius.circular(AppSpacing.buttonRadius);

    return Semantics(
      button: true,
      label: 'Continue watching $title, $remaining',
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: radius,
                  child: SizedBox(
                    width: width,
                    height: thumbHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ArtworkThumbnail(
                          uri: item.uri,
                          artworkPath: item.artworkPath,
                          width: width,
                          height: thumbHeight,
                          borderRadius: 0,
                          placeholderIcon: Icons.movie_outlined,
                        ),
                        // No scrim: the resume bar has its own dark track, so
                        // bright frames keep their colours.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 3,
                            backgroundColor: AppColors.overlay,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm8),
                Text(
                  breakableTitle(title),
                  semanticsLabel: title,
                  style: titleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  remaining,
                  style: remainingStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // Ink on top so the ripple also shows over the thumbnail.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(borderRadius: radius, onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

class _VideoCardSkeleton extends StatelessWidget {
  /// Only the first placeholder speaks, so screen readers hear "Loading" once.
  final bool announce;

  const _VideoCardSkeleton({this.announce = false});

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surfacePressed,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );

    return Semantics(
      label: announce ? 'Loading videos' : null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg16,
          vertical: AppSpacing.sm8,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(color: AppColors.surfaceElevated),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg16,
                      AppSpacing.lg16,
                      AppSpacing.lg16,
                      AppSpacing.xl20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(0.75, 14),
                        const SizedBox(height: 10),
                        bar(0.45, 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
