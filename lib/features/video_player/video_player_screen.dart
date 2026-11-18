import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/platform/device_controls.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/video_engine.dart';
import '../../shared/widgets/ui_kit.dart';
import 'video_player_notifier.dart';

/// The stage behind the picture: pure black in both themes (DESIGN.md 7.9).
const Color _kStage = Color(0xFF000000);

/// A light dimming layer over the whole picture while the controls show. The
/// controls themselves sit on `overlay` scrims (top and bottom) or discs
/// (the skip buttons), so they read on any frame, even a white one.
const Color _kControlsVeil = Color(0x33000000);

/// How far a control scrim fades out past its controls.
const double _kScrimFade = 40;

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
      label: '${formatClock(Duration(milliseconds: _seekTargetMs.round()))}  ($sign${formatClock(Duration(milliseconds: diff.abs().round()))})',
      value: durationMs > 0 ? _seekTargetMs / durationMs : 0,
    ));
  }

  void _onHorizontalDragEnd(VideoPlayerControllerNotifier notifier) {
    if (!_seeking) return;
    _seeking = false;
    notifier.seekTo(Duration(milliseconds: _seekTargetMs.round()));
    _hideHudSoon();
  }

  /// Brightness / volume / seek feedback: white on the ink overlay chip, a
  /// Volt bar on a white 24 % track.
  Widget _buildHud(AppPalette palette, AppTextStyles type, _GestureHud hud) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(minWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hud.icon, color: palette.onOverlay, size: 32),
                const SizedBox(height: 8),
                Text(hud.label, style: type.tabularFigures.copyWith(color: palette.onOverlay)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 130,
                  child: LinearProgressIndicator(
                    value: hud.value.clamp(0.0, 1.0),
                    backgroundColor: palette.onOverlay.withValues(alpha: 0.24),
                    color: palette.primary,
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

  /// The video stage is ink in both themes, with light system bar icons
  /// (DESIGN.md 7.9 and 8.2): everything below reads the dark palette.
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoPlayerControllerProvider(widget.item));
    final notifier = ref.read(videoPlayerControllerProvider(widget.item).notifier);
    final engine = ref.watch(videoEngineProvider);
    final inPip = ref.watch(_pipProvider);

    return Theme(
      data: AppTheme.darkTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.barsOnInk,
        child: Builder(
          builder: (context) => _buildStage(context, state, notifier, engine, inPip),
        ),
      ),
    );
  }

  Widget _buildStage(
    BuildContext context,
    VideoPlaybackState state,
    VideoPlayerControllerNotifier notifier,
    VideoEngine engine,
    bool inPip,
  ) {
    final palette = context.palette;
    final type = context.typography;

    if (state.errorMessage != null) {
      // Only a plain message by cause: the raw exception goes to the
      // diagnostics log (see VideoPlayerControllerNotifier._handleError).
      final kind = classifyVideoError(state.errorMessage!);
      return Scaffold(
        backgroundColor: _kStage,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: palette.error,
                  ),
                  const SizedBox(height: AppSpacing.lg16),
                  // One heading node that is a live region: when this view
                  // replaces the spinner (or a retry fails again) TalkBack /
                  // VoiceOver read the title and the cause once, instead of
                  // leaving a screen-reader user in silence.
                  MergeSemantics(
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            header: true,
                            // An app string: the app's own heading voice.
                            child: Text(
                              'Unable to play video',
                              textAlign: TextAlign.center,
                              style: type.sectionTitle,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm8),
                          Text(
                            kind.message,
                            textAlign: TextAlign.center,
                            style: type.body.copyWith(color: palette.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.xs4),
                          Text(
                            'Your file is safe.',
                            textAlign: TextAlign.center,
                            style: type.metadata,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl24),
                  FilledButton.icon(
                    // The notifier ignores taps while a retry is running.
                    onPressed: () => unawaited(notifier.retry()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: AppSpacing.sm8),
                  OutlinedButton.icon(
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
        backgroundColor: _kStage,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final durationMs = state.duration.inMilliseconds.toDouble();
    final maxDuration = durationMs > 0 ? durationMs : 1.0;
    final posMs = _dragValue ?? state.position.inMilliseconds.toDouble();
    final sliderVal = posMs.clamp(0.0, maxDuration);
    final fadeDuration = MotionTokens.duration(context, const Duration(milliseconds: 160));

    return Scaffold(
      backgroundColor: _kStage,
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
          if (!inPip && _hud != null) _buildHud(palette, type, _hud!),
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
            // A Volt lock on the ink overlay chip. (IconButton.filled took the
            // theme's primary fill, Volt, under the Volt glyph: invisible.)
            child: IconButton(
              icon: const Icon(Icons.lock_rounded),
              tooltip: 'Unlock Controls',
              style: IconButton.styleFrom(
                backgroundColor: context.palette.overlay,
                foregroundColor: context.palette.primary,
                minimumSize: const Size.square(AppSpacing.minTouchTarget),
              ),
              onPressed: () => notifier.toggleLock(),
            ),
          ),
        ],
      ),
    );
  }

  /// Controls over the picture (DESIGN.md 7.9): white glyphs on `overlay`
  /// scrims, the title in `playerTitle` under the top row, a Volt disc for play /
  /// pause and a Volt scrubber with the times in DM Mono.
  Widget _buildNormalControls(
    BuildContext context,
    VideoPlaybackState state,
    VideoPlayerControllerNotifier notifier,
    double sliderVal,
    double maxDuration,
  ) {
    final palette = context.palette;
    final type = context.typography;
    final onVideo = palette.onOverlay;
    // The name as on the video cards: no file extension.
    final title = videoDisplayTitle(widget.item.title);
    final shownTitle = breakableTitle(title);

    Widget overlayButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      double size = 24,
      bool onChip = false,
    }) {
      return IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(icon, size: size, color: onVideo),
        tooltip: tooltip,
        onPressed: onPressed,
        // The skip buttons float mid-picture, away from the scrims: they
        // carry their own overlay disc.
        style: onChip ? IconButton.styleFrom(backgroundColor: palette.overlay) : null,
      );
    }

    // White controls on `overlay` (DESIGN.md 7.9), whatever the frame: a
    // scrim behind the top row and title and one behind the scrubber and
    // times, each solid behind its controls and fading out past them; only
    // a light veil over the middle of the picture. Every layer ignores
    // touches, so taps and swipes on empty areas still reach the gesture
    // detector underneath (tap hides the controls, swipes seek).
    final insets = MediaQuery.paddingOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    double lineOf(TextStyle style) => scaler.scale(style.fontSize!) * style.height!;
    // Top: inset, 4 + a 48 dp icon row, up to two title lines, 4.
    final topSolid = insets.top + AppSpacing.xs4 * 2 + 48 + lineOf(type.playerTitle) * 2;
    // Bottom: 8 + the 48 dp slider, the times line, 8, inset.
    final bottomSolid = insets.bottom + AppSpacing.sm8 * 2 + 48 + lineOf(type.tabularFigures);
    final overlay = palette.overlay;
    Widget scrim({required bool top, required double solid}) {
      final height = solid + _kScrimFade;
      return Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: 0,
        right: 0,
        height: height,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [overlay, overlay, overlay.withValues(alpha: 0)],
                stops: [0, solid / height, 1],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: _kControlsVeil)),
        ),
        scrim(top: true, solid: topSolid),
        scrim(top: false, solid: bottomSolid),
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top: back and the actions, then the title on its own lines.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm8,
                  vertical: AppSpacing.xs4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Semantics(
                          label: 'Exit Video Player',
                          button: true,
                          child: IconButton(
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            icon: Icon(Icons.arrow_back_rounded, color: onVideo),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const Spacer(),
                        if (DeviceControls.available)
                          overlayButton(
                            icon: Icons.picture_in_picture_alt_rounded,
                            tooltip: 'Picture in picture',
                            onPressed: _enterPip,
                          ),
                        overlayButton(
                          icon: state.isLandscape
                              ? Icons.stay_current_portrait_rounded
                              : Icons.stay_current_landscape_rounded,
                          tooltip: state.isLandscape ? 'Portrait' : 'Landscape',
                          onPressed: () => notifier.toggleOrientation(),
                        ),
                        PopupMenuButton<double>(
                          icon: Icon(Icons.speed_rounded, color: onVideo),
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
                          ]
                              .map((s) => PopupMenuItem(
                                    value: s,
                                    child: Text(
                                      '${s}x',
                                      style: type.tabularFigures.copyWith(
                                        fontSize: 16,
                                        height: 24 / 16,
                                        color: s == state.speed ? palette.primary : palette.textPrimary,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, color: onVideo),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8),
                      // The video's own name: Anek, two lines at most, broken
                      // after "_" in file-style names; read as written.
                      child: Text(
                        shownTitle,
                        semanticsLabel: shownTitle == title ? null : title,
                        style: type.playerTitle.copyWith(color: onVideo),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Middle: Skip -10s, Play/Pause, Skip +10s
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  overlayButton(
                    icon: Icons.replay_10_rounded,
                    size: 40,
                    tooltip: 'Rewind 10 seconds',
                    onChip: true,
                    onPressed: () => notifier.skipSeconds(-10),
                  ),
                  const SizedBox(width: AppSpacing.xxl24),
                  VoltDisc(
                    size: 64,
                    icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    tooltip: state.isPlaying ? 'Pause' : 'Play',
                    onPressed: () => notifier.togglePlayPause(),
                  ),
                  const SizedBox(width: AppSpacing.xxl24),
                  overlayButton(
                    icon: Icons.forward_10_rounded,
                    size: 40,
                    tooltip: 'Forward 10 seconds',
                    onChip: true,
                    onPressed: () => notifier.skipSeconds(10),
                  ),
                ],
              ),

              // Bottom: the Volt scrubber and the times.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg16,
                  vertical: AppSpacing.sm8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      // The theme's Volt track and thumb; the unplayed part is
                      // white, as dark violet would vanish on a dark frame.
                      data: SliderTheme.of(context).copyWith(
                        inactiveTrackColor: onVideo.withValues(alpha: 0.3),
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
                          // Same short clock as the music player ('1:14', '1:02:03').
                          Text(
                            formatClock(Duration(milliseconds: sliderVal.toInt())),
                            style: type.tabularFigures.copyWith(color: onVideo),
                          ),
                          Text(
                            formatClock(state.duration),
                            style: type.tabularFigures.copyWith(color: onVideo.withValues(alpha: 0.78)),
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
