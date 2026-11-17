import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/app_config.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/widgets/artwork_placeholder.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/media_song_row.dart';
import '../music_player/playback_notifier.dart';

/// The library feeds the dashboard listens to.
enum _Feed { songs, recentlyPlayed, mostPlayed, recentlyAdded, recentVideos }

/// Home dashboard: greeting, "Continue listening" hero, quick actions and the
/// recently played / most played / recently added / recent video sections.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Song sections show this many rows until "Show all" is tapped.
  static const int _collapsedCount = 5;

  /// The feeds rendered as song sections, in screen order.
  static const List<_Feed> _songFeeds = [
    _Feed.recentlyPlayed,
    _Feed.mostPlayed,
    _Feed.recentlyAdded,
  ];

  /// Latest value of every feed. A missing key means "still loading".
  final Map<_Feed, List<MediaItem>> _data = {};
  final List<StreamSubscription<List<MediaItem>>> _subscriptions = [];
  final Set<_Feed> _expanded = {};
  DateTime? _lastShuffleTap;

  @override
  void initState() {
    super.initState();
    // Streams are opened once per repository (not on every rebuild) so playback
    // updates never re-run the library queries.
    ref.listenManual<LibraryRepository>(
      libraryRepositoryProvider,
      (_, repo) => _subscribe(repo),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  void _subscribe(LibraryRepository repo) {
    _cancelSubscriptions();
    // A new repository: drop the previous one's lists so nothing stale is shown
    // (or counted as loaded) until the new streams emit. The map is still empty
    // on the first call, which runs inside initState where setState is not
    // allowed.
    if (_data.isNotEmpty && mounted) setState(_data.clear);
    _listen(_Feed.songs, repo.watchMediaItems(mediaType: MediaType.audio));
    // 1. Recently played (last 20)
    _listen(_Feed.recentlyPlayed, repo.watchRecentlyPlayed(limit: 20));
    // 2. Most played (top 20, playCount > 0)
    _listen(_Feed.mostPlayed, repo.watchMostPlayed(limit: 20));
    // 3. Recently added (music only, last 20)
    _listen(
      _Feed.recentlyAdded,
      repo.watchRecentlyAdded(limit: 20, mediaType: MediaType.audio),
    );
    // 4. Recent videos row
    _listen(_Feed.recentVideos, repo.watchRecentVideos(limit: 10));
  }

  void _listen(_Feed feed, Stream<List<MediaItem>> stream) {
    _subscriptions.add(
      stream.listen(
        (items) {
          if (mounted) setState(() => _data[feed] = items);
        },
        // A failing feed is treated like an empty one (its section hides).
        onError: (Object _, StackTrace _) {
          if (mounted) setState(() => _data[feed] = const []);
        },
      ),
    );
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _shuffleAll(List<MediaItem> items) async {
    final now = DateTime.now();
    final last = _lastShuffleTap;
    if (last != null && now.difference(last).inMilliseconds < 500) return;
    _lastShuffleTap = now;
    final randomStart = items.isNotEmpty ? DateTime.now().microsecond % items.length : 0;
    await ref.read(playbackNotifierProvider.notifier).loadQueue(
          items,
          startIndex: randomStart,
          autoPlay: true,
          shuffle: true,
        );
  }

  void _toggleExpanded(_Feed feed) {
    setState(() {
      if (!_expanded.remove(feed)) _expanded.add(feed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrentItem = ref.watch(currentMediaItemProvider.select((item) => item != null));
    final songs = _data[_Feed.songs];
    final loaded = _data.length == _Feed.values.length;
    final nothingAtAll = loaded && !hasCurrentItem && _data.values.every((items) => items.isEmpty);
    // Skeleton rows stand in for the song sections until one of them has rows
    // to show or all three have answered (possibly with nothing).
    final sectionsPending = _songFeeds.any((feed) => !_data.containsKey(feed)) &&
        _songFeeds.every((feed) => _data[feed]?.isEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: AppSpacing.xs4),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Greeting(songCount: songs?.length)),

          // Continue listening hero
          if (hasCurrentItem) const SliverToBoxAdapter(child: _ContinueListeningCard()),

          // Quick actions (Shuffle all, Explore, Downloads)
          SliverToBoxAdapter(
            child: _QuickActions(
              songsLoading: songs == null,
              onShuffle: (songs == null || songs.isEmpty) ? null : () => _shuffleAll(songs),
            ),
          ),

          if (sectionsPending) const SliverToBoxAdapter(child: _SongSectionSkeleton()),

          ..._songSection('Recently played', _Feed.recentlyPlayed),
          ..._songSection('Most played', _Feed.mostPlayed),
          ..._songSection('Recently added', _Feed.recentlyAdded),
          ..._videoSection(context),

          if (nothingAtAll)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyHint(
                icon: Icons.queue_music_rounded,
                title: 'Nothing played yet',
                message: 'Songs and videos you play or add will show up here. '
                    'Find something new in Explore.',
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.giant40)),
        ],
      ),
    );
  }

  /// Header + rows for one song feed; nothing when the feed is empty.
  ///
  /// Long feeds (up to 20 rows) start collapsed to [_collapsedCount] rows with a
  /// "Show all" toggle so the three song sections and the video rail all fit in
  /// a few screens. Every row stays reachable and tapping one still queues the
  /// whole feed.
  List<Widget> _songSection(String title, _Feed feed) {
    final items = _data[feed];
    if (items == null || items.isEmpty) return const [];

    final canCollapse = items.length > _collapsedCount;
    final expanded = _expanded.contains(feed);
    final visibleCount = canCollapse && !expanded ? _collapsedCount : items.length;

    return [
      SliverToBoxAdapter(
        child: _SectionHeading(
          title: title,
          actionLabel: canCollapse ? (expanded ? 'Show less' : 'Show all') : null,
          // The visible label is the same in every section; the spoken one
          // says which section it expands or collapses.
          actionSemanticLabel: canCollapse
              ? (expanded ? 'Show less of $title' : 'Show all ${items.length} in $title')
              : null,
          onAction: canCollapse ? () => _toggleExpanded(feed) : null,
        ),
      ),
      SliverList.builder(
        itemCount: visibleCount,
        itemBuilder: (context, index) {
          return MediaSongRow(
            item: items[index],
            onTap: () {
              ref.read(playbackNotifierProvider.notifier).loadQueue(
                    items,
                    startIndex: index,
                    autoPlay: true,
                  );
            },
          );
        },
      ),
    ];
  }

  /// Horizontal rail of the most recent videos; nothing when there are none.
  List<Widget> _videoSection(BuildContext context) {
    final items = _data[_Feed.recentVideos];
    if (items == null || items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeading(
          title: 'Recent videos',
          actionLabel: 'See all',
          actionSemanticLabel: 'See all videos',
          onAction: () => context.go('/videos'),
        ),
      ),
      SliverToBoxAdapter(child: _RecentVideosRail(items: items)),
    ];
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// Section title with an optional trailing text action.
///
/// Same padding and type scale as the shared [SectionHeader], plus a spoken
/// label for the action so screen-reader users can tell the identical
/// "Show all" buttons apart. (Follow-up: give [SectionHeader] an
/// `actionSemanticLabel` and drop this copy.)
class _SectionHeading extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final String? actionSemanticLabel;
  final VoidCallback? onAction;

  const _SectionHeading({
    required this.title,
    this.actionLabel,
    this.actionSemanticLabel,
    this.onAction,
  });

  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    AppSpacing.lg16,
    AppSpacing.xxl24,
    AppSpacing.lg16,
    AppSpacing.sm8,
  );

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Padding(
      // With an action, its label (not the button's box) ends on the 16 dp
      // gutter, like SectionHeader.
      padding: label == null ? padding : SectionHeader.paddingWithAction(padding, Directionality.of(context)),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTypography.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (label != null)
            TextButton(
              style: SectionHeader.actionStyle,
              onPressed: onAction,
              child: Text(label, semanticsLabel: actionSemanticLabel),
            ),
        ],
      ),
    );
  }
}

/// Rounded loading placeholder bar (same tone as the Explore skeletons).
class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBar({
    required this.width,
    required this.height,
    this.radius = defaultRadius,
  });

  static const double defaultRadius = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfacePressed,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Header + a few song rows shown while the song feeds are still loading.
/// Mirrors [MediaSongRow]'s geometry so the real rows replace it in place.
class _SongSectionSkeleton extends StatelessWidget {
  const _SongSectionSkeleton();

  /// Title-bar widths (as a share of the text column) for the placeholder rows.
  static const List<double> _titleWidths = [0.72, 0.56, 0.64];
  static const double _headerBarWidth = 132;
  static const double _headerBarHeight = 14;
  static const double _titleBarHeight = 12;
  static const double _metaBarWidth = 96;
  static const double _metaBarHeight = 10;
  static const double _artworkRadius = 12;
  static const double _rowVerticalPadding = 6;

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTypography.sectionTitle;
    final headerLine = MediaQuery.textScalerOf(context).scale(titleStyle.fontSize!) * titleStyle.height!;

    return Semantics(
      container: true,
      label: 'Loading your music',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: _SectionHeading.padding,
            child: SizedBox(
              height: headerLine,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: _SkeletonBar(width: _headerBarWidth, height: _headerBarHeight),
              ),
            ),
          ),
          for (final widthFactor in _titleWidths)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg16,
                vertical: _rowVerticalPadding,
              ),
              child: Row(
                children: [
                  const _SkeletonBar(
                    width: MediaSongRow.artworkSize,
                    height: MediaSongRow.artworkSize,
                    radius: _artworkRadius,
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FractionallySizedBox(
                          widthFactor: widthFactor,
                          child: const _SkeletonBar(
                            width: double.infinity,
                            height: _titleBarHeight,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm8),
                        const _SkeletonBar(width: _metaBarWidth, height: _metaBarHeight),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Greeting
// ---------------------------------------------------------------------------

/// One subtitle line under the app bar title: "Good evening · 1,234 songs".
/// Kept to the metadata scale so the app bar title stays the only heading.
class _Greeting extends StatelessWidget {
  /// Number of songs in the library, or null while it is still loading.
  final int? songCount;

  const _Greeting({required this.songCount});

  /// Placeholder shown where the song count will appear, so the line keeps its
  /// height and position when the library answers.
  static const double _countBarWidth = 72;
  static const double _countBarHeight = 10;

  static String _greetingFor(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _greetingFor(DateTime.now().hour);
    final count = songCount;

    final String? detail;
    final String spoken;
    if (count == null) {
      detail = null;
      spoken = greeting;
    } else if (count == 0) {
      detail = 'Your music and videos, all in one place.';
      spoken = '$greeting. $detail';
    } else {
      final songs = '${_groupThousands(count)} ${count == 1 ? 'song' : 'songs'}';
      detail = songs;
      spoken = '$greeting. $songs in your library';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.sm8,
        AppSpacing.lg16,
        0,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: greeting,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(
              text: ' · ',
              style: TextStyle(color: AppColors.textMuted),
            ),
            if (detail == null)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _SkeletonBar(width: _countBarWidth, height: _countBarHeight),
              )
            else
              TextSpan(text: detail),
          ],
        ),
        style: AppTypography.metadata,
        // Every line is exactly one metadata line tall, whether it holds the
        // count or the inline placeholder.
        strutStyle: StrutStyle.fromTextStyle(
          AppTypography.metadata,
          forceStrutHeight: true,
        ),
        semanticsLabel: spoken,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue listening hero
// ---------------------------------------------------------------------------

class _ContinueListeningCard extends ConsumerWidget {
  const _ContinueListeningCard();

  static const double _artworkSize = 80;
  static const double _artworkRadius = AppSpacing.md12;

  /// Platform lookup size ArtworkThumbnail uses for an 80 dp cover (and the
  /// mini player's); the tint check shares that lookup.
  static const int _artworkLookupSize = 256;
  static const double _eyebrowIconSize = 16;
  static const double _artworkShadowAlpha = 0.35;
  static const double _artworkShadowBlur = 18;
  static const Offset _artworkShadowOffset = Offset(0, 8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    if (item == null) return const SizedBox.shrink();

    final artist = item.artist ?? 'Unknown artist';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.lg16,
        AppSpacing.lg16,
        0,
      ),
      // One node describes the card (including its state); the texts below are
      // excluded so they are not read a second time. The play/pause button
      // stays outside the exclusion as its own button.
      child: Semantics(
        container: true,
        label: 'Continue listening: ${item.title} by $artist, '
            '${isPlaying ? 'playing' : 'paused'}',
        child: ArtworkPresenceBuilder(
          item: item,
          lookupSize: _artworkLookupSize,
          builder: (context, hasArtwork, content) => SurfaceCard(
            // The card wears the song's placeholder colours, like Now Playing,
            // or the neutral violet when the song shows its own cover (a red
            // cover never sits on a teal card). It starts neutral while the
            // cover lookup runs, and SurfaceCard fades any change.
            gradient: hasArtwork ? AppColors.heroGradient : ArtworkTint.surfaceGradient(item.uri),
            padding: const EdgeInsets.all(AppSpacing.lg16),
            onTap: () {
              if (!isPlaying) {
                ref.read(playbackNotifierProvider.notifier).play();
              }
            },
            child: content!,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    const Icon(
                      Icons.headphones_rounded,
                      size: _eyebrowIconSize,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm8),
                    Expanded(
                      child: Text(
                        'Continue listening',
                        style: AppTypography.label.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm8),
                    PillTag(
                      text: isPlaying ? 'Playing' : 'Paused',
                      color: isPlaying ? AppColors.accent : AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md12),
              Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(_artworkRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: _artworkShadowAlpha),
                                  blurRadius: _artworkShadowBlur,
                                  offset: _artworkShadowOffset,
                                ),
                              ],
                            ),
                            child: ArtworkThumbnail(
                              uri: item.uri,
                              artworkPath: item.artworkPath,
                              size: _artworkSize,
                              borderRadius: _artworkRadius,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  breakableTitle(item.title),
                                  semanticsLabel: item.title,
                                  style: AppTypography.sectionTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: AppSpacing.xs4),
                                Text(
                                  artist,
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
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  _HeroPlayPauseButton(
                    isPlaying: isPlaying,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _HeroPlayPauseButton({required this.isPlaying, required this.onPressed});

  static const double _size = 56;
  static const double _iconSize = 30;
  static const double _glowAlpha = 0.35;
  static const double _glowBlur = 20;
  static const Offset _glowOffset = Offset(0, 6);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: _glowAlpha),
            blurRadius: _glowBlur,
            offset: _glowOffset,
          ),
        ],
      ),
      child: IconButton.filled(
        tooltip: isPlaying ? 'Pause' : 'Resume',
        onPressed: onPressed,
        iconSize: _iconSize,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          fixedSize: const Size.square(_size),
          minimumSize: const Size.square(_size),
          shape: const CircleBorder(),
        ),
        icon: AnimatedSwitcher(
          duration: MotionTokens.duration(context, MotionTokens.feedback),
          switchInCurve: MotionTokens.easeOut,
          switchOutCurve: MotionTokens.easeIn,
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(isPlaying),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  /// True until the songs feed first answers. The Shuffle slot then holds a
  /// placeholder of the same size so the other tiles do not reflow.
  final bool songsLoading;

  /// Null hides the Shuffle tile (no songs in the library yet).
  final VoidCallback? onShuffle;

  const _QuickActions({required this.songsLoading, required this.onShuffle});

  @override
  Widget build(BuildContext context) {
    final shuffle = onShuffle;
    final tiles = <Widget>[
      if (songsLoading)
        const _QuickActionPlaceholder()
      else if (shuffle != null)
        _QuickActionTile(
          icon: Icons.shuffle_rounded,
          label: 'Shuffle all',
          semanticLabel: 'Shuffle all songs',
          color: AppColors.primary,
          onTap: shuffle,
        ),
      _QuickActionTile(
        icon: Icons.travel_explore_rounded,
        label: 'Explore',
        semanticLabel: 'Open Explore',
        color: AppColors.accent,
        onTap: () => context.go('/explore'),
      ),
      if (PlatformInfo.supportsDownloads)
        _QuickActionTile(
          icon: Icons.file_download_rounded,
          label: 'Downloads',
          semanticLabel: 'Open Downloads',
          color: AppColors.primary,
          onTap: () => context.go('/downloads'),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.lg16,
        AppSpacing.lg16,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md12),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.color,
    required this.onTap,
  });

  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm8,
    vertical: AppSpacing.lg16,
  );
  static const double iconCircleSize = 44;
  static const double _iconSize = 22;
  static const double _iconTintAlpha = 0.16;

  /// Height of the label line at the current text scale. Every tile (and the
  /// placeholder) reserves exactly this, so the row stays level even when a
  /// long label is scaled down to fit.
  static double labelHeight(BuildContext context) {
    final style = AppTypography.button;
    return MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: SurfaceCard(
        onTap: onTap,
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: iconCircleSize,
              height: iconCircleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: _iconTintAlpha),
              ),
              child: Icon(icon, size: _iconSize, color: color),
            ),
            const SizedBox(height: AppSpacing.sm8),
            SizedBox(
              height: labelHeight(context),
              // Scales down rather than clipping on narrow phones at large text sizes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: AppTypography.button.copyWith(color: AppColors.textPrimary),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same footprint as a [_QuickActionTile]; holds the Shuffle slot while the
/// song count is loading.
class _QuickActionPlaceholder extends StatelessWidget {
  const _QuickActionPlaceholder();

  static const double _labelBarWidth = 56;
  static const double _labelBarHeight = 10;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SurfaceCard(
        padding: _QuickActionTile.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SkeletonBar(
              width: _QuickActionTile.iconCircleSize,
              height: _QuickActionTile.iconCircleSize,
              radius: _QuickActionTile.iconCircleSize / 2,
            ),
            const SizedBox(height: AppSpacing.sm8),
            SizedBox(
              height: _QuickActionTile.labelHeight(context),
              child: const Center(
                child: _SkeletonBar(width: _labelBarWidth, height: _labelBarHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent videos rail
// ---------------------------------------------------------------------------

class _RecentVideosRail extends StatelessWidget {
  final List<MediaItem> items;

  const _RecentVideosRail({required this.items});

  @override
  Widget build(BuildContext context) {
    // Thumbnail + gap + up to two title lines, grown with the text scale.
    final titleStyle = _VideoCard.titleStyle;
    final lineHeight = MediaQuery.textScalerOf(context).scale(titleStyle.fontSize!) * titleStyle.height!;
    final railHeight = _VideoCard.thumbHeight + AppSpacing.sm8 + lineHeight * 2 + AppSpacing.xs4;

    return SizedBox(
      height: railHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md12),
        itemBuilder: (context, index) => _VideoCard(item: items[index]),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final MediaItem item;

  const _VideoCard({required this.item});

  static const double width = 200;
  static const double thumbHeight = width * 9 / 16;
  static final RegExp _extension = RegExp(r'\.[a-zA-Z0-9]{2,4}$');

  static TextStyle get titleStyle => AppTypography.metadata.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) {
    final cleanTitle = item.title.replaceAll(_extension, '');
    final duration = Duration(milliseconds: item.durationMs);
    final radius = BorderRadius.circular(AppSpacing.buttonRadius);
    void open() => context.push('/video_player', extra: item);

    return Semantics(
      button: true,
      label: 'Video: $cleanTitle',
      onTap: open,
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
                        // A real 16:9 still, cropped once; the clip above
                        // rounds the corners.
                        ArtworkThumbnail(
                          uri: item.uri,
                          artworkPath: item.artworkPath,
                          width: width,
                          height: thumbHeight,
                          borderRadius: 0,
                          placeholderIcon: Icons.movie_outlined,
                        ),
                        // No scrim: the badge has its own dark chip, so
                        // bright frames keep their colours.
                        if (duration > Duration.zero)
                          Positioned(
                            right: AppSpacing.sm8,
                            bottom: AppSpacing.sm8,
                            child: DurationBadge(duration: duration),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm8),
                Text(
                  breakableTitle(cleanTitle),
                  semanticsLabel: cleanTitle,
                  style: titleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // Ink on top so the ripple shows over the thumbnail.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: open,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
