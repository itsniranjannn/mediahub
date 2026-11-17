import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import 'now_playing_sheet.dart';
import 'playback_notifier.dart';

const double _kCardRadius = 20;
const double _kArtworkSize = 44;

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @visibleForTesting
  static bool isNowPlayingOpen = false;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _openNowPlaying(BuildContext context) {
    final now = DateTime.now();
    // Debounce rapid taps within 400ms
    if (now.difference(_lastTapTime).inMilliseconds < 400) {
      return;
    }
    _lastTapTime = now;

    // Single route guard: do not push if already open
    if (MiniPlayer.isNowPlayingOpen) {
      return;
    }

    MiniPlayer.isNowPlayingOpen = true;
    final sheetDuration = MotionTokens.duration(context, MotionTokens.sheet);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // Now Playing draws its own rounded top and grabber.
      showDragHandle: false,
      sheetAnimationStyle: AnimationStyle(
        duration: sheetDuration,
        reverseDuration: sheetDuration,
      ),
      builder: (_) => const NowPlayingSheet(),
    ).whenComplete(() {
      MiniPlayer.isNowPlayingOpen = false;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    setState(() {
      _dragExtent += details.primaryDelta ?? 0.0;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details, double screenWidth) {
    final threshold = screenWidth * 0.3;
    final velocity = details.primaryVelocity ?? 0.0;
    final notifier = ref.read(playbackNotifierProvider.notifier);

    if (_dragExtent < -threshold || velocity < -500) {
      // Swiped left -> skip to next
      HapticFeedback.lightImpact();
      _animateAndCommit(() => notifier.skipToNext(), fromLeft: false);
    } else if (_dragExtent > threshold || velocity > 500) {
      // Swiped right -> skip to previous
      HapticFeedback.lightImpact();
      _animateAndCommit(() => notifier.skipToPrevious(), fromLeft: true);
    } else {
      // Spring back
      setState(() {
        _dragExtent = 0.0;
      });
    }
  }

  void _animateAndCommit(VoidCallback action, {required bool fromLeft}) {
    action();
    _dragExtent = 0.0;
    // Animate title/card sliding in
    _slideAnimation = Tween<Offset>(
      begin: Offset(fromLeft ? -1.0 : 1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = ref.watch(currentMediaItemProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final notifier = ref.read(playbackNotifierProvider.notifier);

    // Hide when queue is empty or no item
    if (currentItem == null) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final artist = currentItem.artist ?? 'Unknown Artist';

    return Padding(
      // floats above the navigation bar as its own card; the 8 dp side
      // inset plus the card's 8 dp padding puts the cover on the 16 dp gutter
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm8,
        AppSpacing.sm8,
        AppSpacing.sm8,
        AppSpacing.xs4,
      ),
      // One node for the card, read once: what is playing and a tap that
      // opens Now Playing. The cover, texts and progress line are left out
      // (the line used to put its percentage in front of the label and the
      // title was read twice); Previous / Play / Next stay their own buttons.
      // The swipes are shortcuts for those buttons, so the detector itself
      // adds nothing to the tree.
      child: Semantics(
        container: true,
        button: true,
        label: 'Mini player: ${currentItem.title} by $artist',
        hint: 'Opens Now Playing',
        onTap: () => _openNowPlaying(context),
        child: GestureDetector(
          key: const ValueKey('mini_player_gesture_detector'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () => _openNowPlaying(context),
          onHorizontalDragUpdate: (details) => _handleHorizontalDragUpdate(details, screenWidth),
          onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(details, screenWidth),
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
              _openNowPlaying(context);
            }
          },
          // A plain card: nothing scrolls behind the mini player (the shell
          // does not extend its body), so a backdrop blur would cost a pass
          // every frame without changing a pixel.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kCardRadius),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(_kCardRadius),
                border: Border.all(color: AppColors.divider),
              ),
              child: Stack(
                children: [
                  // The card clips, so swiped content slides in from its edge.
                  Transform.translate(
                    offset: Offset(_dragExtent, 0),
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm8,
                          AppSpacing.sm8,
                          AppSpacing.xs4,
                          AppSpacing.sm8,
                        ),
                        child: Row(
                          children: [
                            // Artwork thumbnail with Hero
                            ExcludeSemantics(
                              child: Hero(
                                tag: 'now_playing_artwork',
                                child: ArtworkThumbnail(
                                  uri: currentItem.uri,
                                  artworkPath: currentItem.artworkPath,
                                  size: _kArtworkSize,
                                  borderRadius: AppSpacing.sm8,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md12),

                            // Title & Artist (the card's label says both)
                            Expanded(
                              child: ExcludeSemantics(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      currentItem.title,
                                      style: AppTypography.bodyStrong,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      artist,
                                      style: AppTypography.metadata,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs4),

                            // Controls: Skip previous, Play/Pause, Skip next
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded, size: 26),
                              // Same as skip-next: an enabled button never
                              // reads as disabled.
                              color: AppColors.textPrimary,
                              tooltip: 'Previous',
                              onPressed: () => notifier.skipToPrevious(),
                            ),
                            IconButton.filled(
                              icon: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 26,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                fixedSize: const Size.square(40),
                                shape: const CircleBorder(),
                              ),
                              tooltip: isPlaying ? 'Pause' : 'Play',
                              onPressed: () => notifier.togglePlayPause(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded, size: 26),
                              color: AppColors.textPrimary,
                              tooltip: 'Next',
                              onPressed: () => notifier.skipToNext(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Sits in the last 2 dp of the bottom padding, so the row
                  // stays vertically centred in the card.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // Decoration here; Now Playing's seek bar reads the time.
                    child: ExcludeSemantics(
                      child: _MiniProgressLine(durationMs: currentItem.durationMs),
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

/// 2 dp progress line along the bottom edge of the card. It is the only part
/// listening to the position stream, so the rest of the card stays still.
class _MiniProgressLine extends ConsumerWidget {
  final int durationMs;

  const _MiniProgressLine({required this.durationMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(throttledPositionStreamProvider);
    final safeDurationMs = durationMs > 0 ? durationMs : 1;
    final positionMs = positionAsync.value?.inMilliseconds ?? 0;
    final progress = (positionMs / safeDurationMs).clamp(0.0, 1.0);

    return Padding(
      // inset past the 20 dp corners so the line stays on the straight edge
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2,
        borderRadius: BorderRadius.circular(1),
        backgroundColor: AppColors.textPrimary.withValues(alpha: 0.12),
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }
}
