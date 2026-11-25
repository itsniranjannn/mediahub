// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/motion_tokens.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/widgets/brand_marks.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/detail_screens.dart';
import '../library/media_context_menu.dart';
import '../library/playable.dart';
import '../music_player/playback_notifier.dart';
import '../settings/user_name_setting.dart';
import 'greeting_name.dart';

/// The library feeds the dashboard listens to.
enum _Feed { songs, recentlyPlayed, mostPlayed, recentlyAdded, liked, recentVideos }

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
  /// The feeds rendered as song sections, in screen order.
  static const List<_Feed> _songFeeds = [_Feed.recentlyPlayed, _Feed.mostPlayed, _Feed.recentlyAdded, _Feed.liked];

  /// Latest value of every feed. A missing key means "still loading".
  final Map<_Feed, List<MediaItem>> _data = {};
  final List<StreamSubscription<List<MediaItem>>> _subscriptions = [];
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
    _listen(_Feed.recentlyAdded, repo.watchRecentlyAdded(limit: 20, mediaType: MediaType.audio));
    // 4. Liked songs rail
    _listen(_Feed.liked, repo.watchFavorites());
    // 5. Recent videos row
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
    await playCollection(ref.read(playbackNotifierProvider.notifier), items, shuffle: true);
  }

  void _openLiked() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LikedSongsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrentItem = ref.watch(currentMediaItemProvider.select((item) => item != null));
    final songs = _data[_Feed.songs];
    final loaded = _data.length == _Feed.values.length;
    final nothingAtAll = loaded && !hasCurrentItem && _data.values.every((items) => items.isEmpty);
    // Skeleton rows stand in for the song sections until one of them has rows
    // to show or all three have answered (possibly with nothing).
    final sectionsPending =
        _songFeeds.any((feed) => !_data.containsKey(feed)) && _songFeeds.every((feed) => _data[feed]?.isEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        // The app's wordmark and the author's signature, as in the Settings
        // footer: Fraunces "MediaHub", "by" in italic Fraunces, the name in
        // Great Vibes with the brand gradient.
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaHubWordmark(fontSize: 21),
            AuthorMark(kicker: 'by', full: false, nameSize: 17, inline: true),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: AppSpacing.xs4),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Greeting(songCount: songs?.length, name: ref.watch(userNameProvider))),

          // Continue listening: the one Volt block on the screen.
          if (hasCurrentItem) const SliverToBoxAdapter(child: _ContinueListeningSlab()),

          // Quick actions (Shuffle all, Liked, Online, Downloads)
          SliverToBoxAdapter(
            child: EntranceFade(
              index: 1,
              child: _QuickActions(
                songsLoading: songs == null,
                onShuffle: (songs == null || songs.isEmpty) ? null : () => _shuffleAll(songs),
                onLiked: _openLiked,
              ),
            ),
          ),

          if (sectionsPending) const SliverToBoxAdapter(child: _RailSkeleton()),

          ..._railSection('Recently played', 'Your history', _Feed.recentlyPlayed),
          ..._railSection('Most played', 'On repeat', _Feed.mostPlayed),
          ..._railSection('Recently added', 'New on this phone', _Feed.recentlyAdded),
          ..._railSection(
            'Favourites',
            'Your hearts',
            _Feed.liked,
            actionLabel: 'See all',
            actionSemanticLabel: 'See all Favourites',
            onAction: _openLiked,
          ),
          ..._videoSection(context),

          if (nothingAtAll)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyHint(
                icon: Icons.queue_music_rounded,
                title: 'Nothing played yet',
                message:
                    'Songs and videos you play or add will show up here. '
                    'Find something new in Online.',
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.giant40)),
        ],
      ),
    );
  }

  /// One horizontal rail of large rounded covers; nothing when the feed is empty.
  List<Widget> _railSection(
    String title,
    String kicker,
    _Feed feed, {
    String? actionLabel,
    String? actionSemanticLabel,
    VoidCallback? onAction,
  }) {
    final items = _data[feed];
    if (items == null || items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeading(
          title: title,
          kicker: kicker,
          actionLabel: actionLabel,
          actionSemanticLabel: actionSemanticLabel,
          onAction: onAction,
        ),
      ),
      SliverToBoxAdapter(
        child: _CoverRail(
          items: items,
          onPlay: (item) => playCollection(ref.read(playbackNotifierProvider.notifier), items, start: item),
        ),
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

  const _SectionHeading({required this.title, this.kicker, this.actionLabel, this.actionSemanticLabel, this.onAction});

  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    AppSpacing.lg16,
    AppSpacing.xxl24,
    AppSpacing.lg16,
    AppSpacing.sm8,
  );

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
        const SparkMark(height: 22),
        const SizedBox(width: AppSpacing.sm8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: type.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  const _SkeletonBar({required this.width, required this.height, this.radius = defaultRadius});

  static const double defaultRadius = AppSpacing.radiusBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.palette.surfacePressed, borderRadius: BorderRadius.circular(radius)),
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

  /// The name from Settings → You, or empty for the plain greeting.
  final String name;

  const _Greeting({required this.songCount, this.name = ''});

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
    // A phone turned sideways: a slimmer band, so the rails start on screen.
    final compact = InkDock.isCompactLandscape(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xs4, AppSpacing.lg16, AppSpacing.sm8),
      child: EntranceFade(
        child: HeroBand(
          glow: true,
          padding: compact
              ? const EdgeInsets.fromLTRB(AppSpacing.xl20, AppSpacing.md12, AppSpacing.xl20, AppSpacing.md12)
              : const EdgeInsets.fromLTRB(AppSpacing.xl20, AppSpacing.xxl24, AppSpacing.xl20, AppSpacing.xl20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SparkMark(height: 4),
              SizedBox(height: compact ? AppSpacing.sm8 : AppSpacing.md12),
              if (name.isEmpty)
                Semantics(
                  header: true,
                  child: Text(namaste, style: type.greeting, maxLines: 1, overflow: TextOverflow.ellipsis),
                )
              else
                GreetingName(name: name),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: greeting,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: ' · ',
                      style: TextStyle(color: palette.textMuted),
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
        ),
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
// Cover rails
// ---------------------------------------------------------------------------

/// A horizontal rail of songs as large rounded covers (radius 24) with the
/// title and artist under each. Tap plays the rail from that song, long press
/// opens the media sheet.
class _CoverRail extends ConsumerWidget {
  final List<MediaItem> items;
  final void Function(MediaItem item) onPlay;

  const _CoverRail({required this.items, required this.onPlay});

  static const double cover = 136;

  static double height(BuildContext context) {
    final type = context.typography;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle s) => scaler.scale(s.fontSize!) * s.height!;
    return cover + AppSpacing.sm8 + line(type.bodyStrong) + line(type.metadata) + AppSpacing.xs4;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.typography;
    final radius = BorderRadius.circular(AppSpacing.radiusCover);
    return SizedBox(
      height: height(context),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md12),
        itemBuilder: (context, index) {
          final item = items[index];
          final artist = item.artist ?? 'Unknown artist';
          return Semantics(
            button: true,
            label: '${item.title} by $artist',
            onTap: () => onPlay(item),
            excludeSemantics: true,
            child: SizedBox(
              width: cover,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => onPlay(item),
                  onLongPress: () => MediaContextMenu.show(context, ref, item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(color: palette.divider),
                        ),
                        child: ArtworkThumbnail(
                          uri: item.uri,
                          artworkPath: item.artworkPath,
                          size: cover,
                          borderRadius: AppSpacing.radiusCover,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm8),
                      Text(item.title, style: type.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        artist,
                        style: type.metadata.copyWith(color: palette.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder rail while the song feeds load.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Loading your music',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl24),
        child: SizedBox(
          height: _CoverRail.cover,
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md12),
                const _SkeletonBar(width: _CoverRail.cover, height: _CoverRail.cover, radius: AppSpacing.radiusCover),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions (bento)
// ---------------------------------------------------------------------------

/// Quick actions as a bento grid: a tall Volt "Shuffle all" block on the
/// start side, Liked and Online stacked beside it, then a full-width tonal
/// Downloads strip. Without songs the Shuffle block goes and Liked / Online
/// sit side by side.
class _QuickActions extends StatelessWidget {
  /// True until the songs feed first answers; the Shuffle block is then a
  /// placeholder of the same size so nothing reflows.
  final bool songsLoading;

  /// Null hides the Shuffle block (no songs in the library yet).
  final VoidCallback? onShuffle;
  final VoidCallback onLiked;

  const _QuickActions({required this.songsLoading, required this.onShuffle, required this.onLiked});

  static const double _gap = AppSpacing.md12;

  static double tileHeight(BuildContext context) {
    final style = context.typography.button;
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final h = line + AppSpacing.md12 * 2;
    return h < 56 ? 56 : h;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shuffle = onShuffle;
    final small = tileHeight(context);
    final liked = _BentoTile(
      icon: Icons.favorite_rounded,
      label: 'Favourites',
      semanticLabel: 'Open Favourites',
      fill: palette.surfaceElevated,
      iconColor: palette.favorite,
      labelColor: palette.textPrimary,
      height: small,
      onTap: onLiked,
    );
    final online = _BentoTile(
      icon: Icons.smart_display_rounded,
      label: 'Online',
      semanticLabel: 'Open Online',
      fill: palette.surfaceElevated,
      iconColor: palette.accent,
      labelColor: palette.textPrimary,
      height: small,
      onTap: () => context.go('/online'),
    );

    final Widget top;
    if (songsLoading || shuffle != null) {
      final tall = small * 2 + _gap;
      top = Row(
        children: [
          Expanded(
            child: songsLoading || shuffle == null
                ? ExcludeSemantics(
                    child: _SkeletonBar(width: double.infinity, height: tall, radius: AppSpacing.cardRadius),
                  )
                : VoltTile(
                    icon: Icons.shuffle_rounded,
                    label: 'Shuffle all',
                    semanticLabel: 'Shuffle all songs',
                    height: tall,
                    onTap: shuffle,
                  ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              children: [
                liked,
                const SizedBox(height: _gap),
                online,
              ],
            ),
          ),
        ],
      );
    } else {
      top = Row(
        children: [
          Expanded(child: liked),
          const SizedBox(width: _gap),
          Expanded(child: online),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.lg16, AppSpacing.lg16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          top,
          if (PlatformInfo.supportsDownloads) ...[
            const SizedBox(height: _gap),
            _BentoTile(
              icon: Icons.file_download_rounded,
              label: 'Downloads',
              semanticLabel: 'Open Downloads',
              fill: palette.secondaryContainer,
              iconColor: palette.onSecondaryContainer,
              labelColor: palette.onSecondaryContainer,
              height: small,
              trailing: true,
              gradient: true,
              onTap: () => context.go('/downloads'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One bento tile: a rounded fill with an icon and a one-line label (the big
/// tile stacks a large icon over a Fraunces label).
///
/// A press scales it to 0.97 with a ripple and gives the icon a small turn;
/// on ink a soft glow in the icon's colour sits under it. [gradient] lays a
/// subtle sheen over the fill (the Downloads strip).
class _BentoTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color fill;
  final Color iconColor;
  final Color labelColor;
  final double height;
  final bool trailing;
  final bool gradient;
  final VoidCallback onTap;

  const _BentoTile({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.fill,
    required this.iconColor,
    required this.labelColor,
    required this.height,
    required this.onTap,
    this.trailing = false,
    this.gradient = false,
  });

  @override
  State<_BentoTile> createState() => _BentoTileState();
}

class _BentoTileState extends State<_BentoTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (value != _pressed) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    final text = Text(
      widget.label,
      style: type.button.copyWith(color: widget.labelColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final Widget body = Row(
      children: [
        PressGlyph(pressed: _pressed, child: Icon(widget.icon, size: 22, color: widget.iconColor)),
        const SizedBox(width: AppSpacing.sm8),
        Expanded(child: text),
        if (widget.trailing) Icon(Icons.chevron_right_rounded, color: widget.iconColor),
      ],
    );
    // Only a whisper of the icon colour, so the label keeps its contrast.
    final sheen = widget.gradient
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [widget.fill, Color.alphaBlend(widget.iconColor.withValues(alpha: 0.08), widget.fill)],
          )
        : null;
    final glow = palette.isDark
        ? [
            BoxShadow(
              color: widget.iconColor.withValues(alpha: _pressed ? 0.10 : 0.18),
              blurRadius: _pressed ? 8 : 16,
              offset: Offset(0, _pressed ? 2 : 6),
              spreadRadius: -4,
            ),
          ]
        : const <BoxShadow>[];
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: AnimatedScale(
        key: const ValueKey('bento_press_scale'),
        scale: _pressed ? MotionTokens.pressedScale : 1,
        duration: MotionTokens.duration(context, MotionTokens.micro),
        curve: MotionTokens.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, boxShadow: glow),
          child: Material(
            color: widget.fill,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(gradient: sheen),
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: _setPressed,
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: Padding(padding: const EdgeInsets.all(AppSpacing.md12), child: body),
                ),
              ),
            ),
          ),
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
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: palette.divider),
                  ),
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
