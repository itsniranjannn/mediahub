import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/playback_state.dart' as domain;
import 'playback_notifier.dart';
import 'queue_sheet.dart';

class NowPlayingSheet extends ConsumerStatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  ConsumerState<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends ConsumerState<NowPlayingSheet> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackNotifierProvider);
    final notifier = ref.read(playbackNotifierProvider.notifier);
    final positionAsync = ref.watch(throttledPositionStreamProvider);

    final currentItem = playbackState.currentItem;
    final position = positionAsync.value ?? playbackState.position;
    final duration = playbackState.duration.inMilliseconds > 0
        ? playbackState.duration
        : Duration(milliseconds: currentItem?.durationMs ?? 0);

    final currentPositionMs = _dragValue ?? position.inMilliseconds.toDouble();
    final maxDurationMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue = currentPositionMs.clamp(0.0, maxDurationMs);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Semantics(
          label: 'Collapse Now Playing',
          button: true,
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Now Playing',
          style: AppTypography.sectionTitle,
        ),
        actions: [
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed_rounded),
            tooltip: 'Playback Speed',
            initialValue: playbackState.speed,
            onSelected: (speed) => notifier.setSpeed(speed),
            itemBuilder: (context) => [
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              2.0,
            ].map((s) => PopupMenuItem(
                  value: s,
                  child: Text('${s}x', style: AppTypography.tabularFigures),
                )).toList(),
          ),
          Semantics(
            label: 'View Queue',
            button: true,
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.queue_music_rounded),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const FractionallySizedBox(
                    heightFactor: 0.7,
                    child: QueueSheet(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Artwork placeholder
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 96,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),

              // Title & Artist
              Column(
                children: [
                  Text(
                    currentItem?.title ?? 'No track playing',
                    style: AppTypography.screenTitle.copyWith(fontSize: 22),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs4),
                  Text(
                    currentItem?.artist ?? 'Unknown Artist',
                    style: AppTypography.metadata.copyWith(fontSize: 16),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),

              // Slider & Tabular Figures Times
              Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceElevated,
                      thumbColor: AppColors.primary,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: maxDurationMs,
                      value: sliderValue,
                      onChanged: (val) {
                        setState(() {
                          _dragValue = val;
                        });
                      },
                      onChangeEnd: (val) {
                        notifier.seek(Duration(milliseconds: val.toInt()));
                        setState(() {
                          _dragValue = null;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(
                            Duration(milliseconds: sliderValue.toInt()),
                          ),
                          style: AppTypography.tabularFigures,
                        ),
                        Text(
                          formatDuration(duration),
                          style: AppTypography.tabularFigures,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Playback Controls Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Shuffle button
                  Semantics(
                    label: playbackState.shuffle ? 'Shuffle enabled' : 'Shuffle disabled',
                    button: true,
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(
                        Icons.shuffle_rounded,
                        color: playbackState.shuffle
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      onPressed: () => notifier.toggleShuffle(),
                    ),
                  ),

                  // Previous button
                  Semantics(
                    label: 'Previous track',
                    button: true,
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(
                        Icons.skip_previous_rounded,
                        size: 36,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () => notifier.skipToPrevious(),
                    ),
                  ),

                  // Play / Pause button
                  Semantics(
                    label: playbackState.isPlaying ? 'Pause' : 'Play',
                    button: true,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(
                          playbackState.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 38,
                          color: Colors.black,
                        ),
                        onPressed: () {
                          if (playbackState.isPlaying) {
                            notifier.pause();
                          } else {
                            notifier.play();
                          }
                        },
                      ),
                    ),
                  ),

                  // Next button
                  Semantics(
                    label: 'Next track',
                    button: true,
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        size: 36,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () => notifier.skipToNext(),
                    ),
                  ),

                  // Repeat button
                  Semantics(
                    label: 'Repeat mode: ${playbackState.repeatMode.name}',
                    button: true,
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(
                        playbackState.repeatMode == domain.PlaybackRepeatMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: playbackState.repeatMode != domain.PlaybackRepeatMode.off
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      onPressed: () => notifier.cycleRepeatMode(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md12),
            ],
          ),
        ),
      ),
    );
  }
}

