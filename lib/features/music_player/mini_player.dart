import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import 'now_playing_sheet.dart';
import 'playback_notifier.dart';

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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 280),
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
    final positionAsync = ref.watch(throttledPositionStreamProvider);
    final notifier = ref.read(playbackNotifierProvider.notifier);

    // Hide when queue is empty or no item
    if (currentItem == null) {
      return const SizedBox.shrink();
    }

    final durationMs = currentItem.durationMs > 0 ? currentItem.durationMs : 1;
    final positionMs = positionAsync.value?.inMilliseconds ?? 0;
    final progress = (positionMs / durationMs).clamp(0.0, 1.0);
    final screenWidth = MediaQuery.of(context).size.width;

    return Semantics(
      label: 'Mini player: ${currentItem.title}',
      child: GestureDetector(
        key: const ValueKey('mini_player_gesture_detector'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openNowPlaying(context),
        onHorizontalDragUpdate: (details) => _handleHorizontalDragUpdate(details, screenWidth),
        onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(details, screenWidth),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
            _openNowPlaying(context);
          }
        },
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceElevated,
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thin progress line
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              Transform.translate(
                offset: Offset(_dragExtent, 0),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md12,
                      vertical: AppSpacing.xs4,
                    ),
                    child: Row(
                      children: [
                        // Artwork thumbnail with Hero
                        Hero(
                          tag: 'now_playing_artwork',
                          child: ArtworkThumbnail(
                            uri: currentItem.uri,
                            size: 44,
                            borderRadius: AppSpacing.buttonRadius,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md12),

                        // Title & Artist
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentItem.title,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                currentItem.artist ?? 'Unknown Artist',
                                style: AppTypography.metadata.copyWith(
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Controls: Skip previous, Play/Pause, Skip next
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, size: 24),
                          tooltip: 'Previous',
                          onPressed: () => notifier.skipToPrevious(),
                        ),
                        IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 28,
                            color: AppColors.primary,
                          ),
                          tooltip: isPlaying ? 'Pause' : 'Play',
                          onPressed: () => notifier.togglePlayPause(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 24),
                          tooltip: 'Next',
                          onPressed: () => notifier.skipToNext(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
