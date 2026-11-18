import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
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
import '../library/media_context_menu.dart';
import 'video_player_notifier.dart';
import 'video_queue.dart';

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

  /// Opens the player on [item]. [list] is what the user sees around it
  /// (the library as sorted and searched, or the Continue watching rail):
  /// the player's Next and Previous follow it, skipping videos whose file is
  /// gone.
  void _openPlayer(BuildContext context, MediaItem item, {List<MediaItem>? list}) {
    if (!_isPlayable(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is missing or unavailable on storage')),
      );
      return;
    }
    final queue = videoQueueFor(item, list ?? [item], isPlayable: _isPlayable);
    context.push('/video_player', extra: queue);
  }

  static bool _isPlayable(MediaItem item) {
    if (item.source == 'download' || item.availability == MediaAvailability.missing) {
      try {
        return File(item.uri).existsSync();
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// The media sheet for [item] (Play, Play as audio, Picture-in-picture ...).
  void _openMenu(BuildContext anchor, MediaItem item) {
    MediaContextMenu.show(context, ref, item, anchorContext: anchor);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoLibraryProvider);
    final notifier = ref.read(videoLibraryProvider.notifier);
    final progressListAsync = ref.watch(allVideoProgressStreamProvider);

    // No app bar: the screen sets the status bar icons for its own canvas.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.barsFor(context.palette),
      child: Scaffold(
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
    final palette = context.palette;

    if (state.permissionState == MediaPermissionState.denied) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.video_library_rounded,
            iconColor: palette.accent,
            title: 'Allow access to your videos',
            message: '${AppConfig.appName} shows the videos saved on this phone. Your videos stay on your phone.',
            action: FilledButton.icon(
              onPressed: () => notifier.requestPermission(),
              icon: const Icon(Icons.video_library_rounded, size: 20),
              label: const Text('Allow access'),
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
            icon: Icons.video_library_rounded,
            iconColor: palette.warning,
            title: 'Video access is off',
            message: 'To see your videos here, allow ${AppConfig.appName} to use videos in your phone settings.',
            action: FilledButton.tonalIcon(
              onPressed: () => notifier.openSettings(),
              icon: const Icon(Icons.settings_rounded, size: 20),
              label: const Text('Open settings'),
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
            iconColor: palette.error,
            title: "Couldn't load your videos",
            // A plain sentence: the raw error text is not for the screen.
            message: 'Something went wrong while reading your videos. Your files are safe.',
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
      SliverToBoxAdapter(child: _searchField(context, notifier)),

      // Continue watching rail if available
      if (showContinueWatching) ...[
        const SliverToBoxAdapter(
          child: SectionHeader(title: 'Continue watching', kicker: 'Pick up where you left off'),
        ),
        SliverToBoxAdapter(
          child: _ContinueWatchingRail(
            items: continueWatchingItems,
            progressMap: progressMap,
            onOpen: (item) => _openPlayer(context, item, list: continueWatchingItems),
            onMenu: _openMenu,
          ),
        ),
      ],

      if (state.items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.videocam_off_outlined,
            title: state.searchQuery.isNotEmpty ? 'No matching videos' : 'No videos yet',
            message: state.searchQuery.isNotEmpty
                ? 'No videos matching "${state.searchQuery}".'
                : 'Find the videos saved on this phone.',
            action: state.searchQuery.isNotEmpty
                ? null
                : FilledButton.icon(
                    onPressed: state.isScanning ? null : () => notifier.scanDevice(),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Scan device'),
                  ),
          ),
        )
      else ...[
        if (showContinueWatching)
          const SliverToBoxAdapter(child: SectionHeader(title: 'All videos', kicker: 'On this phone')),
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
                onTap: () => _openPlayer(context, video, list: state.items),
                onMore: (anchor) => _openMenu(anchor, video),
                onLongPress: () => _openMenu(context, video),
              );
            },
          ),
        ),
      ],
    ];
  }

  Widget _searchField(BuildContext context, BaseLibraryNotifier notifier) {
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
          style: context.typography.body,
          decoration: InputDecoration(
            hintText: 'Search your videos',
            prefixIcon: Icon(Icons.search_rounded, color: context.palette.textSecondary),
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
    final palette = context.palette;
    final type = context.typography;

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
                    style: type.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  _subtitle(state),
                  style: type.metadata,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (granted) ...[
            IconButton(
              icon: state.isScanning
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.primary,
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
    final palette = context.palette;
    final type = context.typography;
    return Semantics(
      selected: selected,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            child: selected ? Icon(Icons.check_rounded, size: 20, color: palette.primary) : null,
          ),
          const SizedBox(width: AppSpacing.md12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: selected ? type.bodyStrong.copyWith(color: palette.primary) : type.body,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: AppSpacing.md12),
            Icon(
              ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 16,
              color: palette.textSecondary,
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
    final palette = context.palette;
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
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: palette.divider),
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
                  color: palette.accent.withValues(alpha: 0.14),
                ),
                child: Icon(Icons.info_outline_rounded, color: palette.accent, size: 20),
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
                      style: context.typography.metadata,
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

  /// Opens the media sheet for an item (long press on its card).
  final void Function(BuildContext anchor, MediaItem item) onMenu;

  const _ContinueWatchingRail({
    required this.items,
    required this.progressMap,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    // Thumbnail + gap + up to two title lines + the "time left" line, grown
    // with the text scale so nothing is clipped at large font sizes.
    final scaler = MediaQuery.textScalerOf(context);
    final type = context.typography;
    double lineOf(TextStyle style) => scaler.scale(style.fontSize!) * style.height!;
    final railHeight = _ResumeCard.thumbHeight +
        AppSpacing.sm8 +
        lineOf(_ResumeCard.titleStyle(type)) * 2 +
        2 +
        lineOf(_ResumeCard.remainingStyle(type)) +
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
            onLongPress: () => onMenu(context, item),
          );
        },
      ),
    );
  }
}

/// A part-watched video (docs/DESIGN.md 7.9): a 16:9 thumbnail at radius 14
/// with the Volt resume line on its dark track, the title and the time left.
class _ResumeCard extends StatelessWidget {
  final MediaItem item;
  final double ratio;
  final int? remainingMs;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ResumeCard({
    required this.item,
    required this.ratio,
    required this.remainingMs,
    required this.onTap,
    required this.onLongPress,
  });

  static const double width = 200;
  static const double thumbHeight = width * 9 / 16;
  static const double _resumeHeight = 3;

  static TextStyle titleStyle(AppTextStyles type) => type.bodyStrong;

  static TextStyle remainingStyle(AppTextStyles type) => type.metadata;

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
    final palette = context.palette;
    final type = context.typography;
    final title = videoDisplayTitle(item.title);
    final remaining = _remainingLabel(remainingMs);
    final radius = BorderRadius.circular(AppSpacing.radiusThumb);

    return Semantics(
      button: true,
      label: 'Continue watching $title, $remaining',
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: palette.divider)),
                  child: ClipRRect(
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
                          // No scrim: the resume line has its own dark track,
                          // so bright frames keep their colours. The track is
                          // ink in both themes, so the line is the ink theme's
                          // Volt.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: _resumeHeight,
                              borderRadius: BorderRadius.zero,
                              backgroundColor: palette.overlay,
                              valueColor: AlwaysStoppedAnimation<Color>(AppPalette.dark.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm8),
                Text(
                  breakableTitle(title),
                  semanticsLabel: title,
                  style: titleStyle(type),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  remaining,
                  style: remainingStyle(type).copyWith(color: palette.accent, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // Ink on top so the ripple also shows over the thumbnail.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  onLongPress: onLongPress,
                  highlightColor: palette.surfacePressed.withValues(alpha: 0.5),
                ),
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
    final palette = context.palette;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: palette.surfacePressed,
              borderRadius: BorderRadius.circular(AppSpacing.radiusBadge),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(color: palette.surfaceElevated),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, AppSpacing.md12, AppSpacing.huge48, AppSpacing.lg16),
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
    );
  }
}
