import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';
import 'video_player_notifier.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem item;

  const VideoPlayerScreen({super.key, required this.item});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> with WidgetsBindingObserver {
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.inactive) {
      ref.read(videoPlayerControllerProvider(widget.item).notifier).onAppBackgrounded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      ref.read(videoPlayerControllerProvider(widget.item).notifier).onAppBackgrounded();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoPlayerControllerProvider(widget.item));
    debugPrint('VideoPlayerScreen build state: errorMessage=${state.errorMessage}, isInitialized=${state.isInitialized}');
    final notifier = ref.read(videoPlayerControllerProvider(widget.item).notifier);
    final engine = ref.watch(videoEngineProvider);

    if (state.errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: AppSpacing.lg16),
                  Text(
                    'Unable to play video',
                    style: AppTypography.screenTitle.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.sm8),
                  Text(
                    'The file could not be played (${state.errorMessage}). '
                    'Don\'t worry, your original media file is completely safe on your device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.xxl24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back to Videos'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!state.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final durationMs = state.duration.inMilliseconds.toDouble();
    final maxDuration = durationMs > 0 ? durationMs : 1.0;
    final posMs = _dragValue ?? state.position.inMilliseconds.toDouble();
    final sliderVal = posMs.clamp(0.0, maxDuration);
    final fadeDuration = MotionTokens.duration(context, const Duration(milliseconds: 160));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Video Player Surface
          Positioned.fill(
            child: engine.buildPlayerWidget(
              fit: state.fitCover ? BoxFit.cover : BoxFit.contain,
            ),
          ),

          // 2. Gesture detector for tap and double tap skip
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => notifier.toggleControls(),
              onDoubleTapDown: (details) {
                if (state.isLocked) return;
                final screenWidth = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < screenWidth / 2) {
                  // Left side double tap: -10s
                  notifier.skipSeconds(-10);
                } else {
                  // Right side double tap: +10s
                  notifier.skipSeconds(10);
                }
              },
            ),
          ),

          // 3. Controls Overlay (AnimatedFade 160ms)
          AnimatedOpacity(
            opacity: state.showControls ? 1.0 : 0.0,
            duration: fadeDuration,
            curve: MotionTokens.easeOut,
            child: IgnorePointer(
              ignoring: !state.showControls,
              child: state.isLocked
                  ? _buildLockedOverlay(context, notifier)
                  : _buildNormalControls(
                      context,
                      state,
                      notifier,
                      sliderVal,
                      maxDuration,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedOverlay(
    BuildContext context,
    VideoPlayerControllerNotifier notifier,
  ) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: AppSpacing.lg16,
            left: AppSpacing.lg16,
            child: IconButton.filled(
              icon: const Icon(Icons.lock_rounded, color: AppColors.primary),
              tooltip: 'Unlock Controls',
              onPressed: () => notifier.toggleLock(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalControls(
    BuildContext context,
    VideoPlaybackState state,
    VideoPlayerControllerNotifier notifier,
    double sliderVal,
    double maxDuration,
  ) {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm8,
                vertical: AppSpacing.xs4,
              ),
              child: Row(
                children: [
                  Semantics(
                    label: 'Exit Video Player',
                    button: true,
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.item.title,
                      style: AppTypography.screenTitle.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(
                      state.fitCover ? Icons.fit_screen_rounded : Icons.crop_free_rounded,
                      color: Colors.white,
                    ),
                    tooltip: state.fitCover ? 'Fit to Screen' : 'Fill Screen',
                    onPressed: () => notifier.toggleFitFill(),
                  ),
                  PopupMenuButton<double>(
                    icon: const Icon(Icons.speed_rounded, color: Colors.white),
                    tooltip: 'Playback Speed',
                    initialValue: state.speed,
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
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                    tooltip: 'Lock Controls',
                    onPressed: () => notifier.toggleLock(),
                  ),
                ],
              ),
            ),

            // Middle: Skip -10s, Play/Pause, Skip +10s
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.replay_10_rounded, size: 40, color: Colors.white),
                  tooltip: 'Rewind 10 seconds',
                  onPressed: () => notifier.skipSeconds(-10),
                ),
                const SizedBox(width: AppSpacing.xxl24),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(
                      state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 38,
                      color: Colors.black,
                    ),
                    tooltip: state.isPlaying ? 'Pause' : 'Play',
                    onPressed: () => notifier.togglePlayPause(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxl24),
                IconButton(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.forward_10_rounded, size: 40, color: Colors.white),
                  tooltip: 'Forward 10 seconds',
                  onPressed: () => notifier.skipSeconds(10),
                ),
              ],
            ),

            // Bottom Bar: Progress Slider & Tabular Figures Times
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg16,
                vertical: AppSpacing.sm8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: AppColors.primary,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: maxDuration,
                      value: sliderVal,
                      onChanged: (val) {
                        setState(() {
                          _dragValue = val;
                        });
                      },
                      onChangeEnd: (val) {
                        notifier.seekTo(Duration(milliseconds: val.toInt()));
                        setState(() {
                          _dragValue = null;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(Duration(milliseconds: sliderVal.toInt())),
                          style: AppTypography.tabularFigures.copyWith(color: Colors.white),
                        ),
                        Text(
                          formatDuration(state.duration),
                          style: AppTypography.tabularFigures.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
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
