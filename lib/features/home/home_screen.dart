import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/widgets/shared_label_scale.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/media_context_menu.dart';
import '../library/media_song_row.dart';
import '../music_player/playback_notifier.dart';

/// The library feeds the dashboard listens to.
enum _Feed { songs, recentlyPlayed, mostPlayed, recentlyAdded, recentVideos }

/// Home dashboard: the "नमस्ते" greeting with the time of day, the Volt
/// "Continue listening" slab, quick actions and the recently played / most
/// played / recently added / recent video sections, each under a kicker and
/// a rule (docs/DESIGN.md 6, 7.4, 7.5).
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
        // The app's own name: an app-written heading, so Unbounded.
        title: Text(AppConfig.appName, style: context.typography.sectionTitle),
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

          // Continue listening: the one Volt block on the screen.
          if (hasCurrentItem) const SliverToBoxAdapter(child: _ContinueListeningSlab()),

          // Quick actions (Shuffle all, Online, Downloads)
          SliverToBoxAdapter(
            child: _QuickActions(
              songsLoading: songs == null,
              onShuffle: (songs == null || songs.isEmpty) ? null : () => _shuffleAll(songs),
            ),
          ),

          if (sectionsPending) const SliverToBoxAdapter(child: _SongSectionSkeleton()),

          ..._songSection('Recently played', 'Your history', _Feed.recentlyPlayed),
          ..._songSection('Most played', 'On repeat', _Feed.mostPlayed),
          ..._songSection('Recently added', 'New on this phone', _Feed.recentlyAdded),
          ..._videoSection(context),

          if (nothingAtAll)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyHint(
                icon: Icons.queue_music_rounded,
                title: 'Nothing played yet',
                message: 'Songs and videos you play or add will show up here. '
                    'Find something new in Online.',
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
  List<Widget> _songSection(String title, String kicker, _Feed feed) {
    final items = _data[feed];
    if (items == null || items.isEmpty) return const [];

    final canCollapse = items.length > _collapsedCount;
    final expanded = _expanded.contains(feed);
    final visibleCount = canCollapse && !expanded ? _collapsedCount : items.length;

    return [
      SliverToBoxAdapter(
        child: _SectionHeading(
          title: title,
          kicker: kicker,
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
          kicker: 'Latest clips',
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

/// A screen-level section heading (docs/DESIGN.md 7.5): a 2 dp rule across
/// the gutter, 12 dp, the [kicker] in `overline` / primary, 4 dp, then the
/// title in `sectionTitle` with an optional trailing text action.
///
/// Same layout as the shared [SectionHeader], plus a spoken label for the
/// action so screen-reader users can tell the identical "Show all" buttons
/// apart. (Follow-up: give [SectionHeader] an `actionSemanticLabel` and drop
/// this copy.)
class _SectionHeading extends StatelessWidget {
  final String title;
  final String? kicker;
  final String? actionLabel;
  final String? actionSemanticLabel;
  final VoidCallback? onAction;

  const _SectionHeading({
    required this.title,
    this.kicker,
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

  /// Height of the rule, the gaps and the kicker above the title row.
  static double kickerBlockHeight(BuildContext context) {
    final overline = context.typography.overline;
    return SectionHeader.ruleThickness +
        AppSpacing.md12 +
        MediaQuery.textScalerOf(context).scale(overline.fontSize!) * overline.height! +
        AppSpacing.xs4;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final label = actionLabel;
    final kicker = this.kicker;
    final direction = Directionality.of(context);
    final resolved = padding.resolve(direction);
    // With an action, its label (not the button's box) ends on the 16 dp
    // gutter, like SectionHeader; the rule and kicker keep the full gutter.
    final outer = label == null ? resolved : SectionHeader.paddingWithAction(padding, direction);
    final borrowed = resolved.horizontal - outer.horizontal;

    final row = Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: type.sectionTitle,
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
    );

    return Padding(
      padding: outer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kicker != null)
            Padding(
              padding: EdgeInsetsDirectional.only(end: borrowed),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: SectionHeader.ruleThickness, color: palette.rule),
                  const SizedBox(height: AppSpacing.md12),
                  Text(
                    kicker.toUpperCase(),
                    semanticsLabel: kicker,
                    style: type.overline.copyWith(color: palette.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs4),
                ],
              ),
            ),
          row,
        ],
      ),
    );
  }
}

/// Rounded loading placeholder bar.
class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBar({
    required this.width,
    required this.height,
    this.radius = defaultRadius,
  });

  static const double defaultRadius = AppSpacing.radiusBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.palette.surfacePressed,
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

  @override
  Widget build(BuildContext context) {
    final titleStyle = context.typography.sectionTitle;
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
              height: _SectionHeading.kickerBlockHeight(context) + headerLine,
              child: const Align(
                alignment: AlignmentDirectional.bottomStart,
                child: _SkeletonBar(width: _headerBarWidth, height: _headerBarHeight),
              ),
            ),
          ),
          for (final widthFactor in _titleWidths)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: MediaSongRow.minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
                child: Row(
                  children: [
                    const _SkeletonBar(
                      width: MediaSongRow.artworkSize,
                      height: MediaSongRow.artworkSize,
                      radius: MediaSongRow.artworkRadius,
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
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Greeting
// ---------------------------------------------------------------------------

/// "नमस्ते" in the `greeting` voice (always Nepali), and under it the time
/// of day with the library size: "Good evening · 1,234 songs".
class _Greeting extends StatelessWidget {
  /// Number of songs in the library, or null while it is still loading.
  final int? songCount;

  const _Greeting({required this.songCount});

  static const String namaste = 'नमस्ते';

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
    final palette = context.palette;
    final type = context.typography;
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

    final line = type.body.copyWith(color: palette.textSecondary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.xs4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(namaste, style: type.greeting, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: greeting, style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ' · ', style: TextStyle(color: palette.textMuted)),
                if (detail == null)
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _SkeletonBar(width: _countBarWidth, height: _countBarHeight),
                  )
                else
                  TextSpan(text: detail),
              ],
            ),
            style: line,
            // Every line is exactly one body line tall, whether it holds the
            // count or the inline placeholder.
            strutStyle: StrutStyle.fromTextStyle(line, forceStrutHeight: true),
            semanticsLabel: spoken,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue listening
// ---------------------------------------------------------------------------

/// The Volt "Continue listening" slab (docs/DESIGN.md 7.4) for what is
/// playing or paused: the title in `cardTitle`, the artist and time left,
/// the 3 dp progress line and the ink play / pause disc. Tap resumes, long
/// press opens the media sheet.
///
/// Screen readers get one node for the card (with its state) and the
/// play / pause disc as a button of its own.
class _ContinueListeningSlab extends ConsumerWidget {
  const _ContinueListeningSlab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    if (item == null) return const SizedBox.shrink();
    // The player's position, when it is known (the length comes from the
    // song itself).
    final position = ref.watch(throttledPositionStreamProvider).asData?.value;

    final artist = item.artist ?? 'Unknown artist';
    final length = item.durationMs;
    final progress = position != null && length > 0 ? position.inMilliseconds / length : null;
    final left = position != null && length > 0 ? Duration(milliseconds: length) - position : null;
    // The time left follows the artist and is never the part that gets cut.
    final timeLeft = left == null || left.isNegative ? null : '${formatClock(left)} left';

    void play() => ref.read(playbackNotifierProvider.notifier).play();
    void toggle() => isPlaying ? ref.read(playbackNotifierProvider.notifier).pause() : play();
    void resume() {
      if (!isPlaying) play();
    }

    void menu() => MediaContextMenu.show(context, ref, item);
    final playLabel = isPlaying ? 'Pause' : 'Resume';

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.lg16, 0),
      child: Stack(
        children: [
          Semantics(
            container: true,
            button: true,
            label: 'Continue listening: ${item.title} by $artist, ${isPlaying ? 'playing' : 'paused'}',
            onTap: resume,
            onLongPress: menu,
            excludeSemantics: true,
            child: VoltSlab(
              title: item.title,
              subtitle: artist,
              meta: timeLeft,
              progress: progress,
              onTap: resume,
              onLongPress: menu,
              onPlay: toggle,
              playIcon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              playSemanticLabel: playLabel,
            ),
          ),
          // The disc's own node, over the disc (VoltSlab puts it at the end,
          // 16 dp in, centred): the card node above leaves it out.
          PositionedDirectional(
            end: AppSpacing.lg16,
            top: 0,
            bottom: 0,
            child: Center(
              child: Semantics(
                button: true,
                label: playLabel,
                onTap: toggle,
                child: const SizedBox.square(dimension: VoltSlab.playDiscSize),
              ),
            ),
          ),
        ],
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

  static const double _gap = AppSpacing.md12;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shuffle = onShuffle;
    final showShuffleSlot = songsLoading || shuffle != null;
    final labels = [
      if (shuffle != null && !songsLoading) 'Shuffle all',
      'Online',
      if (PlatformInfo.supportsDownloads) 'Downloads',
    ];
    final slots = (showShuffleSlot ? 1 : 0) + 1 + (PlatformInfo.supportsDownloads ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.lg16,
        AppSpacing.lg16,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // One size for every label: when one has to shrink to fit its
          // tile (320 dp at large text), they all shrink with it.
          final tileWidth = (constraints.maxWidth - _gap * (slots - 1)) / slots;
          final labelScaler = sharedLabelScaler(
            context,
            labels: labels,
            style: _QuickActionTile.labelStyle(context),
            maxWidth: tileWidth - _QuickActionTile.padding.horizontal - 2,
          );
          final tiles = <Widget>[
            if (songsLoading)
              _QuickActionPlaceholder(labelScaler: labelScaler)
            else if (shuffle != null)
              _QuickActionTile(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle all',
                semanticLabel: 'Shuffle all songs',
                color: palette.primary,
                labelScaler: labelScaler,
                onTap: shuffle,
              ),
            _QuickActionTile(
              icon: Icons.smart_display_rounded,
              label: 'Online',
              semanticLabel: 'Open Online',
              color: palette.accent,
              labelScaler: labelScaler,
              onTap: () => context.go('/online'),
            ),
            if (PlatformInfo.supportsDownloads)
              _QuickActionTile(
                icon: Icons.file_download_rounded,
                label: 'Downloads',
                semanticLabel: 'Open Downloads',
                color: palette.primary,
                labelScaler: labelScaler,
                onTap: () => context.go('/downloads'),
              ),
          ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A quick action: the glyph ([color]: primary, or accent for Online) on a
/// primaryContainer disc, the same tile recipe as the Downloads type tiles
/// (DESIGN.md 7.14), then the label.
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;
  final TextScaler labelScaler;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.color,
    required this.labelScaler,
    required this.onTap,
  });

  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm8,
    vertical: AppSpacing.lg16,
  );
  static const double iconCircleSize = 44;
  static const double _iconSize = 22;

  static TextStyle labelStyle(BuildContext context) =>
      context.typography.button.copyWith(color: context.palette.textPrimary);

  /// Height of the label line at [scaler]. Every tile (and the placeholder)
  /// reserves exactly this, so the row stays level.
  static double labelHeight(BuildContext context, TextScaler scaler) {
    final style = labelStyle(context);
    return scaler.scale(style.fontSize!) * style.height!;
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
                color: context.palette.primaryContainer,
              ),
              child: Icon(icon, size: _iconSize, color: color),
            ),
            const SizedBox(height: AppSpacing.sm8),
            SizedBox(
              height: labelHeight(context, labelScaler),
              // The shared scaler already fits the label; this only guards
              // against sub-pixel rounding.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: labelStyle(context),
                  textScaler: labelScaler,
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
  final TextScaler labelScaler;

  const _QuickActionPlaceholder({required this.labelScaler});

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
              height: _QuickActionTile.labelHeight(context, labelScaler),
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
    final titleStyle = _VideoCard.titleStyle(context.typography);
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

/// A recent video (docs/DESIGN.md 7.9): a 16:9 still at radius 14 with its
/// duration badge, then the title. Tap plays, long press opens the media
/// sheet.
class _VideoCard extends ConsumerWidget {
  final MediaItem item;

  const _VideoCard({required this.item});

  static const double width = 200;
  static const double thumbHeight = width * 9 / 16;

  static TextStyle titleStyle(AppTextStyles type) => type.bodyStrong;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final cleanTitle = videoDisplayTitle(item.title);
    final duration = Duration(milliseconds: item.durationMs);
    final radius = BorderRadius.circular(AppSpacing.radiusThumb);
    void open() => context.push('/video_player', extra: item);
    void menu() => MediaContextMenu.show(context, ref, item);

    return Semantics(
      button: true,
      label: 'Video: $cleanTitle',
      onTap: open,
      onLongPress: menu,
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
                            PositionedDirectional(
                              end: AppSpacing.sm8,
                              bottom: AppSpacing.sm8,
                              child: DurationBadge(duration: duration),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm8),
                Text(
                  breakableTitle(cleanTitle),
                  semanticsLabel: cleanTitle,
                  style: titleStyle(context.typography),
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
                  onLongPress: menu,
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
