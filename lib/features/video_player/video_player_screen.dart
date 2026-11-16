import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/platform/device_controls.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';
import 'video_player_notifier.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem item;

  const VideoPlayerScreen({super.key, required this.item});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

/// Mirrors [DeviceControls.inPip] into Riverpod so the screen rebuilds.
final _pipProvider = Provider.autoDispose<bool>((ref) {
  void listener() => ref.invalidateSelf();
  DeviceControls.inPip.addListener(listener);
  ref.onDispose(() => DeviceControls.inPip.removeListener(listener));
  return DeviceControls.inPip.value;
});

class _GestureHud {
  final IconData icon;
  final String label;
  final double value; // 0..1 bar
  const _GestureHud({required this.icon, required this.label, required this.value});
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> with WidgetsBindingObserver {
  double? _dragValue;

  // --- swipe gestures (brightness / volume / seek) ---
  static const double _seekFullWidthMs = 120000; // a full-width swipe scrubs up to 2 minutes
  double _brightness = 0.5;
  double _volume = 0.5;
  int _lastVolumeStep = -1;
  bool _verticalIsBrightness = true;
  bool _seeking = false;
  double _seekStartMs = 0;
  double _seekTargetMs = 0;
  _GestureHud? _hud;
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceControls.getBrightness().then((v) {
      if (mounted) _brightness = v;
    });
    DeviceControls.getVolume().then((v) {
      if (mounted) _volume = v;
    });

    // Picture-in-picture: allowed from the moment a video is on screen.
    DeviceControls.init();
    DeviceControls.setPipEligible(true);
    ref.listenManual(videoPlayerControllerProvider(widget.item), (prev, next) {
      if (!(prev?.isInitialized ?? false) && next.isInitialized) _updatePipAspect();
    });
  }

  void _showHud(_GestureHud hud) {
    _hudTimer?.cancel();
    setState(() => _hud = hud);
  }

  void _hideHudSoon() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  void _onVerticalDragStart(DragStartDetails d, VideoPlaybackState state) {
    if (state.isLocked) return;
    // left half = brightness, right half = volume (like most video players)
    _verticalIsBrightness = d.globalPosition.dx < MediaQuery.of(context).size.width / 2;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (ref.read(videoPlayerControllerProvider(widget.item)).isLocked) return;
    final height = MediaQuery.of(context).size.height;
    final delta = -d.delta.dy / (height * 0.5);
    if (_verticalIsBrightness) {
      _brightness = (_brightness + delta).clamp(0.02, 1.0);
      DeviceControls.setBrightness(_brightness);
      _showHud(_GestureHud(
        icon: Icons.brightness_6_rounded,
        label: '${(_brightness * 100).round()}%',
        value: _brightness,
      ));
    } else if (DeviceControls.available) {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      final step = (_volume * 30).round();
      if (step != _lastVolumeStep) {
        _lastVolumeStep = step;
        DeviceControls.setVolume(_volume);
      }
      _showHud(_GestureHud(
        icon: _volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        label: '${(_volume * 100).round()}%',
        value: _volume,
      ));
    }
  }

  void _onHorizontalDragStart(VideoPlaybackState state) {
    if (state.isLocked || state.duration <= Duration.zero) return;
    _seeking = true;
    _seekStartMs = state.position.inMilliseconds.toDouble();
    _seekTargetMs = _seekStartMs;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d, VideoPlaybackState state) {
    if (!_seeking) return;
    final width = MediaQuery.of(context).size.width;
    final durationMs = state.duration.inMilliseconds.toDouble();
    final spanMs = math.min(durationMs, _seekFullWidthMs);
    _seekTargetMs = (_seekTargetMs + d.delta.dx / width * spanMs).clamp(0.0, durationMs);
    final diff = _seekTargetMs - _seekStartMs;
    final sign = diff >= 0 ? '+' : '-';
    _showHud(_GestureHud(
      icon: diff >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      label: '${formatDuration(Duration(milliseconds: _seekTargetMs.round()))}  ($sign${formatDuration(Duration(milliseconds: diff.abs().round()))})',
      value: durationMs > 0 ? _seekTargetMs / durationMs : 0,
    ));
  }

  void _onHorizontalDragEnd(VideoPlayerControllerNotifier notifier) {
    if (!_seeking) return;
    _seeking = false;
    notifier.seekTo(Duration(milliseconds: _seekTargetMs.round()));
    _hideHudSoon();
  }

  Widget _buildHud(_GestureHud hud) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(minWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hud.icon, color: Colors.white, size: 32),
                const SizedBox(height: 8),
                Text(hud.label, style: AppTypography.tabularFigures.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 130,
                  child: LinearProgressIndicator(
                    value: hud.value.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // `inactive` also happens while the notification shade is pulled down or a
    // dialog shows, and while in picture-in-picture: the video keeps playing then.
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      if (!DeviceControls.inPip.value) {
        ref.read(videoPlayerControllerProvider(widget.item).notifier).onAppBackgrounded();
      }
    }
  }

  void _updatePipAspect() {
    final size = ref.read(videoEngineProvider).videoSize;
    final aspect = (size.width > 0 && size.height > 0) ? size.width / size.height : 16 / 9;
    DeviceControls.setPipEligible(true, aspect: aspect);
  }

  Future<void> _enterPip() async {
    _updatePipAspect();
    final ok = await DeviceControls.enterPip();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picture-in-picture is not available on this device.')),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hudTimer?.cancel();
    DeviceControls.setPipEligible(false);
    DeviceControls.resetBrightness(); // hand brightness back to the system
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
    final inPip = ref.watch(_pipProvider);

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
          if (!inPip) Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => notifier.toggleControls(),
              onVerticalDragStart: (d) => _onVerticalDragStart(d, state),
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: (_) => _hideHudSoon(),
              onHorizontalDragStart: (_) => _onHorizontalDragStart(state),
              onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, state),
              onHorizontalDragEnd: (_) => _onHorizontalDragEnd(notifier),
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
          if (!inPip) AnimatedOpacity(
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

          // 4. Brightness / volume / seek feedback while swiping
          if (!inPip && _hud != null) _buildHud(_hud!),
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
    // The dimming layer ignores touches, so taps and swipes on empty areas still
    // reach the gesture detector underneath (tap hides the controls, swipes seek).
    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Color(0x66000000))),
        ),
        SafeArea(
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
                  if (DeviceControls.available)
                    IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
                      tooltip: 'Picture in picture',
                      onPressed: _enterPip,
                    ),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(
                      state.isLandscape
                          ? Icons.stay_current_portrait_rounded
                          : Icons.stay_current_landscape_rounded,
                      color: Colors.white,
                    ),
                    tooltip: state.isLandscape ? 'Portrait' : 'Landscape',
                    onPressed: () => notifier.toggleOrientation(),
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                    tooltip: 'More',
                    onSelected: (value) {
                      if (value == 'fit') notifier.toggleFitFill();
                      if (value == 'lock') notifier.toggleLock();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'fit',
                        child: Text(state.fitCover ? 'Fit to screen' : 'Fill screen'),
                      ),
                      const PopupMenuItem(value: 'lock', child: Text('Lock controls')),
                    ],
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
      ],
    );
  }
}
