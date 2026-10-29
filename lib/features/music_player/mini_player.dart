import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import 'now_playing_sheet.dart';
import 'playback_notifier.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  void _openNowPlaying(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: MotionTokens.duration(context, const Duration(milliseconds: 280)),
      ),
      builder: (_) => const NowPlayingSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Semantics(
      label: 'Mini player: ${currentItem.title}',
      child: GestureDetector(
        onTap: () => _openNowPlaying(context),
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md12,
                  vertical: AppSpacing.xs4,
                ),
                child: Row(
                  children: [
                    // Artwork placeholder
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.primary,
                        size: 24,
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
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            currentItem.artist ?? 'Unknown Artist',
                            style: AppTypography.metadata,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause button with 48dp touch target
                    Semantics(
                      label: isPlaying ? 'Pause' : 'Play',
                      button: true,
                      child: IconButton(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: AppColors.textPrimary,
                          size: 30,
                        ),
                        onPressed: () {
                          if (isPlaying) {
                            notifier.pause();
                          } else {
                            notifier.play();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

