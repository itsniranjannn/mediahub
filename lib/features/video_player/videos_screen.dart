// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
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
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/video_progress.dart';
import '../../shared/widgets/empty_state_widget.dart';
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
  _VideoFilter _filter = _VideoFilter.all;

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
    if (item.availability == MediaAvailability.missing) return false;
    // A download moved to the phone ("Save to phone") is a MediaStore file now.
    if (item.source == 'download' && !item.uri.contains('://')) {
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
              // iPhone: no scan to run again; reopen the list.
              onPressed: () {
                if (PlatformInfo.isIOS) {
                  notifier.retry();
                } else {
                  notifier.scanDevice();
                }
              },
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

      // Continue watching: the newest as a featured card, the rest in a rail.
      if (showContinueWatching) ...[
        SliverToBoxAdapter(
          child: Builder(builder: (context) {
            final item = continueWatchingItems.first;
            final prog = progressMap[item.id];
            final timed = (prog != null && prog.durationMs > 0) ? prog : null;
            return _FeaturedResumeCard(
              item: item,
              ratio: timed == null ? 0.0 : (timed.positionMs / timed.durationMs).clamp(0.0, 1.0),
              remainingMs: timed == null ? null : timed.durationMs - timed.positionMs,
              onTap: () => _openPlayer(context, item, list: continueWatchingItems),
              onLongPress: () => _openMenu(context, item),
            );
          }),
        ),
        if (continueWatchingItems.length > 1) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Continue watching', kicker: 'Pick up where you left off'),
          ),
          SliverToBoxAdapter(
            child: _ContinueWatchingRail(
              items: continueWatchingItems.sublist(1),
              progressMap: progressMap,
              onOpen: (item) => _openPlayer(context, item, list: continueWatchingItems),
              onMenu: _openMenu,
            ),
          ),
        ],
      ],

      if (state.items.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: Icons.videocam_off_rounded,
            title: state.searchQuery.isNotEmpty ? 'No matching videos' : 'No videos yet',
            // On iPhone there is no shared video folder to scan: videos come
            // from MediaHub's own downloads.
            message: state.searchQuery.isNotEmpty
                ? 'No videos matching "${state.searchQuery}".'
                : PlatformInfo.isIOS
                    ? 'Videos you download in MediaHub show up here.'
                    : 'Find the videos saved on this phone.',
            action: state.searchQuery.isNotEmpty
                ? null
                : PlatformInfo.isIOS
                    ? (PlatformInfo.supportsDownloads
                        ? FilledButton.icon(
                            onPressed: () => GoRouter.maybeOf(context)?.go('/downloads'),
                            icon: const Icon(Icons.file_download_rounded, size: 20),
                            label: const Text('Open Downloads'),
                          )
                        : null)
                    : FilledButton.icon(
                        onPressed: state.isScanning ? null : () => notifier.scanDevice(),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Scan device'),
                      ),
          ),
        )
      else ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'All videos', kicker: 'Your library')),
        SliverToBoxAdapter(
          child: _FilterChips(value: _filter, onChanged: (v) => setState(() => _filter = v)),
        ),
        ..._grid(context, _filtered(state.items), progressMap),
      ],
    ];
  }

  List<MediaItem> _filtered(List<MediaItem> items) {
    switch (_filter) {
      case _VideoFilter.all:
        return items;
      case _VideoFilter.downloaded:
        return items.where((i) => i.source == 'download').toList();
      case _VideoFilter.onPhone:
        return items.where((i) => i.source != 'download').toList();
    }
  }

  /// The two-column grid of 16:9 video cards, or a short hint when the
  /// filter leaves nothing.
  List<Widget> _grid(BuildContext context, List<MediaItem> items, Map<String, VideoProgress> progressMap) {
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl24),
            child: Text(
              _filter == _VideoFilter.downloaded ? 'No downloaded videos yet.' : 'No videos from this phone yet.',
              textAlign: TextAlign.center,
              style: context.typography.body.copyWith(color: context.palette.textSecondary),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, AppSpacing.xxl24),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = (constraints.crossAxisExtent - AppSpacing.md12) / 2;
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.md12,
                mainAxisSpacing: AppSpacing.lg16,
                mainAxisExtent: _VideoGridCard.extent(context, cellWidth),
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final video = items[index];
                final prog = progressMap[video.id];
                final ratio = (prog != null && prog.durationMs > 0)
                    ? (prog.positionMs / prog.durationMs).clamp(0.0, 1.0)
                    : null;
                return _VideoGridCard(
                  key: ValueKey(video.id),
                  item: video,
                  ratio: ratio,
                  width: cellWidth,
                  onTap: () => _openPlayer(context, video, list: items),
                  onLongPress: () => _openMenu(context, video),
                );
              },
            );
          },
        ),
      ),
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
          // What is typed is what is searched (no curly quotes, long dashes
          // or autocorrected words from the keyboard).
          autocorrect: false,
          smartQuotesType: SmartQuotesType.disabled,
          smartDashesType: SmartDashesType.disabled,
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.lg16, AppSpacing.md12),
      child: EntranceFade(
        child: HeroBand(
          glow: true,
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl20,
            AppSpacing.lg16,
            granted ? AppSpacing.xs4 : AppSpacing.xl20,
            AppSpacing.lg16,
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
            // iPhone: nothing on the phone to scan (downloads show up by
            // themselves), so no refresh.
            if (!PlatformInfo.isIOS)
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
        ),
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
/// with the amber resume line on its dark track, the title and the time left.
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
                              valueColor: AlwaysStoppedAnimation<Color>(palette.navIndicator),
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
// Featured resume card, filter chips and the video grid (Sindur v2)
// ---------------------------------------------------------------------------

/// Which videos the grid shows.
enum _VideoFilter { all, downloaded, onPhone }

/// The amber resume line on an ink track, shared by the featured card and
/// the grid cards.
class _ResumeLine extends StatelessWidget {
  final double ratio;
  final double height;
  const _ResumeLine({required this.ratio, this.height = 3});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LinearProgressIndicator(
      value: ratio,
      minHeight: height,
      borderRadius: BorderRadius.zero,
      backgroundColor: palette.overlay,
      valueColor: AlwaysStoppedAnimation<Color>(palette.navIndicator),
    );
  }
}

/// The most recent part-watched video as a large card: a full-width 16:9
/// still with the amber resume line, then a kicker, the title and the time
/// left beside a play disc, on a plum / indigo tinted surface.
class _FeaturedResumeCard extends StatelessWidget {
  final MediaItem item;
  final double ratio;
  final int? remainingMs;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FeaturedResumeCard({
    required this.item,
    required this.ratio,
    required this.remainingMs,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final title = videoDisplayTitle(item.title);
    final remaining = _ResumeCard._remainingLabel(remainingMs);
    final radius = BorderRadius.circular(AppSpacing.cardRadius);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, AppSpacing.sm8),
      child: Semantics(
        button: true,
        label: 'Continue watching $title, $remaining',
        onTap: onTap,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: Material(
          color: palette.surfaceElevated,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: palette.secondaryContainer),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (context, c) => ArtworkThumbnail(
                            uri: item.uri,
                            artworkPath: item.artworkPath,
                            width: c.maxWidth,
                            height: c.maxHeight,
                            borderRadius: 0,
                            placeholderIcon: Icons.movie_outlined,
                          ),
                        ),
                        Positioned(left: 0, right: 0, bottom: 0, child: _ResumeLine(ratio: ratio, height: 4)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CONTINUE WATCHING',
                                style: type.overline.copyWith(color: palette.primary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.xs4),
                              Text(
                                breakableTitle(title),
                                style: type.cardTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                remaining,
                                style: type.metadata.copyWith(color: palette.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md12),
                        // Decorative: the whole card is the button.
                        ExcludeSemantics(child: VoltDisc(icon: Icons.play_arrow_rounded, onPressed: onTap)),
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

/// All / Downloaded / On this phone.
class _FilterChips extends StatelessWidget {
  final _VideoFilter value;
  final ValueChanged<_VideoFilter> onChanged;
  const _FilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      _VideoFilter.all: 'All',
      _VideoFilter.downloaded: 'Downloaded',
      _VideoFilter.onPhone: 'On this phone',
    };
    return SizedBox(
      height: 48 * MediaQuery.textScalerOf(context).scale(14) / 14,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        children: [
          for (final entry in labels.entries) ...[
            if (entry.key != _VideoFilter.all) const SizedBox(width: AppSpacing.sm8),
            Center(
              child: ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                onSelected: (_) => onChanged(entry.key),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A video in the two-column grid: a 16:9 still (radius 14) with its
/// duration badge and amber resume line, then up to two title lines.
class _VideoGridCard extends StatelessWidget {
  final MediaItem item;
  final double? ratio;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _VideoGridCard({
    super.key,
    required this.item,
    required this.ratio,
    required this.width,
    required this.onTap,
    required this.onLongPress,
  });

  static TextStyle titleStyle(AppTextStyles type) => type.bodyStrong;

  static double extent(BuildContext context, double width) {
    final style = titleStyle(context.typography);
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return width * 9 / 16 + AppSpacing.sm8 + line * 2 + AppSpacing.xs4;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = videoDisplayTitle(item.title);
    final duration = Duration(milliseconds: item.durationMs);
    final radius = BorderRadius.circular(AppSpacing.radiusThumb);
    final thumbHeight = width * 9 / 16;
    final missing = item.availability == MediaAvailability.missing;

    return Semantics(
      button: true,
      label: 'Video: $title${missing ? ', missing' : ''}',
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
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
                        Opacity(
                          opacity: missing ? 0.45 : 1,
                          child: ArtworkThumbnail(
                            uri: item.uri,
                            artworkPath: item.artworkPath,
                            width: width,
                            height: thumbHeight,
                            borderRadius: 0,
                            placeholderIcon: Icons.movie_outlined,
                          ),
                        ),
                        if (duration > Duration.zero)
                          PositionedDirectional(
                            end: AppSpacing.xs4 + 2,
                            bottom: AppSpacing.xs4 + 4,
                            child: DurationBadge(duration: duration),
                          ),
                        if (ratio != null && ratio! > 0)
                          Positioned(left: 0, right: 0, bottom: 0, child: _ResumeLine(ratio: ratio!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                breakableTitle(title),
                style: titleStyle(context.typography),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
