import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter/services.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/platform/device_controls.dart';
import '../../core/storage/settings_store.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/video_engine.dart';
import '../../shared/widgets/ui_kit.dart';
import 'video_player_notifier.dart';
import 'video_queue.dart';

/// The stage behind the picture: pure black in both themes (DESIGN.md 7.9).
const Color _kStage = Color(0xFF000000);

/// A light dimming layer over the whole picture while the controls show. The
/// controls themselves sit on `overlay` scrims (top and bottom) or discs
/// (the skip buttons), so they read on any frame, even a white one.
const Color _kControlsVeil = Color(0x33000000);

/// How far a control scrim fades out past its controls.
const double _kScrimFade = 40;

/// The phone's volume counts as "at full" from here (the boost zone starts).
const double _kFullVolume = 0.999;

/// Settings key: the hearing note above 150 % was shown once.
const String _kHearingNoteKey = 'video_boost_hearing_note_shown';

/// Width of one top-row action (a 48 dp touch target).
const double _kAction = 48;

/// The Volume panel's width (it stands at the right edge, over the picture).
const double _kVolumePanelWidth = 72;

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem item;

  /// The list [item] was picked from, for Next / Previous (null = just this).
  final VideoQueue? queue;

  const VideoPlayerScreen({super.key, required this.item, this.queue});

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

  /// 0..1 bar; null for a plain message (a mode change).
  final double? value;

  /// The bar is in the boost zone (warning colour).
  final bool boost;
  const _GestureHud({required this.icon, required this.label, this.value, this.boost = false});
}

enum _Side { left, right }

/// The "−10 s" / "+20 s" bubble after double taps.
class _SkipBubble {
  final _Side side;
  final int seconds;
  const _SkipBubble(this.side, this.seconds);
}

/// One button of the top row; the ones that do not fit go into More.
class _TopAction {
  final String id;
  final IconData icon;
  final String tooltip;

  /// The More menu's wording.
  final String menuLabel;
  final Color? color;

  /// Gets the button's own context (menus open under it).
  final void Function(BuildContext anchor) onPressed;
  const _TopAction({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.menuLabel,
    required this.onPressed,
    this.color,
  });
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> with WidgetsBindingObserver {
  late final VideoPlayerControllerNotifier _notifier;
  double? _dragValue;

  // --- swipe gestures (brightness / volume / seek) ---
  static const double _seekFullWidthMs = 120000; // a full-width swipe scrubs up to 2 minutes
  double _brightness = 0.5;
  double _volume = 0.5;
  int _lastVolumeStep = -1;
  bool _verticalActive = false;
  bool _verticalIsBrightness = true;

  /// The level when the swipe started (re-read from the phone) and how far
  /// the finger has moved since, in levels.
  double _dragBase = 0;
  double _dragDelta = 0;

  /// The fresh value has arrived (or 150 ms passed): movement applies.
  bool _baseReady = false;
  Timer? _baseTimer;
  bool _seeking = false;
  double _seekStartMs = 0;
  double _seekTargetMs = 0;
  _GestureHud? _hud;
  Timer? _hudTimer;

  /// When this screen last set the phone's volume: the system echoes each
  /// write back as a "volume changed" event, possibly after the swipe has
  /// ended, and an old echo must not undo the boost.
  DateTime? _ownVolumeWriteAt;
  static const Duration _ownEchoWindow = Duration(milliseconds: 700);

  // --- volume panel (the top-row Volume button) ---
  bool _volumePanelOpen = false;
  bool _volumeSliding = false;
  Timer? _volumePanelTimer;

  // --- two-finger pinch: fill / fit ---
  final Map<int, Offset> _pointers = {};
  double _pinchStartDistance = 0;
  bool _pinching = false;
  bool _pinchApplied = false;

  // --- double-tap skip bubble ---
  Offset? _doubleTapAt;
  _SkipBubble? _bubble;
  Timer? _bubbleTimer;

  StreamSubscription<double>? _volumeSub;
  StreamSubscription<void>? _noisySub;
  StreamSubscription<PipAction>? _pipActionSub;
  StreamSubscription<void>? _pipDismissSub;
  bool _lastPipWasOurs = false;

  ProviderListenable<VideoPlaybackState> get _provider => videoPlayerControllerProvider(widget.item);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cached: Riverpod 3 forbids ref.read in dispose, where Back saves.
    _notifier = ref.read(videoPlayerControllerProvider(widget.item).notifier);
    final queue = widget.queue;
    if (queue != null) _notifier.attachQueue(queue);

    DeviceControls.init();
    if (DeviceControls.available) {
      DeviceControls.getBrightness().then((v) {
        if (mounted) _brightness = v;
      });
      DeviceControls.getVolume().then((v) {
        if (mounted) _volume = v;
      });
      _volumeSub = DeviceControls.volumeChanges.listen(_onSystemVolume);
    }
    // Headphones unplugged / Bluetooth gone: pause, like every media app.
    _noisySub = DeviceControls.watchBecomingNoisy(DeviceControls.pipOwnerVideoPlayer).listen((_) {
      _notifier.pause();
    });
    _pipActionSub = DeviceControls.pipActions.listen(_onPipAction);
    // The picture-in-picture window was closed: no sound must be left playing.
    _pipDismissSub = DeviceControls.pipDismissed.listen((_) {
      if (_lastPipWasOurs) _notifier.pause();
    });
    DeviceControls.inPip.addListener(_onPipChanged);

    // Picture-in-picture: offered while the video plays (and while its own
    // window is open, so its buttons stay).
    ref.listenManual(_provider, (prev, next) {
      _syncPip(next);
      if (prev != null && prev.showControls && !next.showControls) _closeVolumePanel();
    }, fireImmediately: true);
  }

  // --- picture in picture -------------------------------------------------------

  void _onPipChanged() {
    if (DeviceControls.inPip.value) {
      _lastPipWasOurs = DeviceControls.pipOwner.value == DeviceControls.pipOwnerVideoPlayer;
    }
    if (mounted) _syncPip(ref.read(_provider));
  }

  void _syncPip(VideoPlaybackState s) {
    final ready = s.isInitialized && s.errorMessage == null;
    final ownWindow =
        DeviceControls.inPip.value && DeviceControls.pipOwner.value == DeviceControls.pipOwnerVideoPlayer;
    DeviceControls.setPipPlaying(ready ? s.isPlaying : null);
    DeviceControls.setPipEligible(ready && (s.isPlaying || ownWindow), aspect: _videoAspect());
  }

  double _videoAspect() {
    final size = ref.read(videoEngineProvider).videoSize;
    return (size.width > 0 && size.height > 0) ? size.width / size.height : 16 / 9;
  }

  void _onPipAction(PipAction action) {
    if (DeviceControls.pipOwner.value != DeviceControls.pipOwnerVideoPlayer) return;
    switch (action) {
      case PipAction.rewind:
        _notifier.skipSeconds(-10);
      case PipAction.playPause:
        _notifier.togglePlayPause();
      case PipAction.forward:
        _notifier.skipSeconds(10);
    }
  }

  Future<void> _enterPip() async {
    // Claim first, so the window is the video player's even while paused.
    await DeviceControls.setPipEligible(true, aspect: _videoAspect());
    final ok = await DeviceControls.enterPip();
    if (!mounted) return;
    if (!ok) {
      _syncPip(ref.read(_provider));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picture-in-picture is not available on this device.')),
      );
    }
  }

  // --- HUD ---------------------------------------------------------------------

  void _showHud(_GestureHud hud) {
    _hudTimer?.cancel();
    setState(() => _hud = hud);
  }

  void _hideHudSoon([Duration after = const Duration(milliseconds: 700)]) {
    _hudTimer?.cancel();
    _hudTimer = Timer(after, () {
      if (mounted) setState(() => _hud = null);
    });
  }

  /// A short centred message after a mode change ("Fill screen").
  void _toast(IconData icon, String label) {
    _showHud(_GestureHud(icon: icon, label: label));
    _hideHudSoon(const Duration(milliseconds: 1100));
  }

  // --- volume and boost --------------------------------------------------------

  /// One scale for the phone's volume and the boost: 0..1 is the media
  /// volume, above 1 the video's boost (1.5 = 150 %) at full volume.
  double _levelOf(double volume, int boostPercent) =>
      volume < _kFullVolume || boostPercent <= 100 ? volume : boostPercent / 100;

  double get _currentLevel => _levelOf(_volume, ref.read(_provider).boostPercent);

  double _maxLevel(VideoPlaybackState s) =>
      s.boostSupported ? DeviceControls.maxBoostPercent / 100 : 1.0;

  IconData _volumeIcon(double level) {
    if (level <= 0) return Icons.volume_off_rounded;
    if (level < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  String _levelLabel(double level) =>
      level > 1 ? 'Boost ${(level * 100).round()}%' : '${(level * 100).round()}%';

  /// Sets the level: the phone's volume up to full, then the video's boost.
  void _applyLevel(double level) {
    final s = ref.read(_provider);
    final l = level.clamp(0.0, _maxLevel(s));
    if (l <= 1.0) {
      if (s.boostPercent > 100) _notifier.setBoost(100);
      _volume = l;
      final step = (l * 30).round();
      if (step != _lastVolumeStep) {
        _lastVolumeStep = step;
        _ownVolumeWriteAt = DateTime.now();
        DeviceControls.setVolume(l);
      }
    } else {
      if (_volume < _kFullVolume) {
        _volume = 1.0;
        _lastVolumeStep = 30;
        _ownVolumeWriteAt = DateTime.now();
        DeviceControls.setVolume(1.0);
      }
      final percent = (l * 100).round();
      if (percent != s.boostPercent) {
        _notifier.setBoost(percent).then((ok) {
          if (!ok && mounted) _toast(Icons.volume_up_rounded, "Volume boost isn't available on this phone");
        });
      }
      if (percent > 150) _maybeShowHearingNote();
    }
  }

  void _showLevelHud(double level) {
    final s = ref.read(_provider);
    _showHud(_GestureHud(
      icon: _volumeIcon(level),
      label: _levelLabel(level),
      value: level / _maxLevel(s),
      boost: level > 1,
    ));
  }

  /// The phone's volume changed (the volume keys, the system slider, or our
  /// own writes): keep in step, and show it as a swipe would.
  void _onSystemVolume(double v) {
    if (!mounted) return;
    if (_verticalActive && !_verticalIsBrightness) return; // our own swipe
    if (_volumeSliding) return; // our own slider
    final ownWrite = _ownVolumeWriteAt;
    if (ownWrite != null && DateTime.now().difference(ownWrite) < _ownEchoWindow) return; // an echo
    _volume = v;
    final s = ref.read(_provider);
    // The keys took the volume below full: no boost on top of a quieter phone.
    if (v < _kFullVolume && s.boostPercent > 100) _notifier.setBoost(100);
    if (_volumePanelOpen) {
      setState(() {});
      return;
    }
    if (ref.read(_pipProvider) || !s.isInitialized) return;
    _showLevelHud(_levelOf(v, v < _kFullVolume ? 100 : s.boostPercent));
    _hideHudSoon();
  }

  void _maybeShowHearingNote() {
    if (SettingsStore.instance.getBool(_kHearingNoteKey)) return;
    SettingsStore.instance.setBool(_kHearingNoteKey, true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Loud sound can harm your hearing, especially with headphones. Keep the boost for quiet videos.'),
      ),
    );
  }

  void _toggleVolumePanel() {
    if (_volumePanelOpen) {
      _closeVolumePanel();
      return;
    }
    _notifier.holdControls();
    setState(() => _volumePanelOpen = true);
    DeviceControls.getVolume().then((v) {
      if (mounted && !_volumeSliding) setState(() => _volume = v);
    });
    _scheduleVolumePanelClose();
  }

  void _scheduleVolumePanelClose() {
    _volumePanelTimer?.cancel();
    _volumePanelTimer = Timer(const Duration(seconds: 3), _closeVolumePanel);
  }

  void _closeVolumePanel() {
    _volumePanelTimer?.cancel();
    if (!_volumePanelOpen || !mounted) return;
    setState(() => _volumePanelOpen = false);
    _notifier.releaseControls();
  }

  // --- swipes -------------------------------------------------------------------

  void _onVerticalDragStart(DragStartDetails d, VideoPlaybackState state) {
    _verticalActive = false;
    // Brightness and volume are Android-only (iOS keeps its own controls).
    if (state.isLocked || _pinching || !DeviceControls.available) return;
    _verticalActive = true;
    // left half = brightness, right half = volume (like most video players)
    _verticalIsBrightness = d.globalPosition.dx < MediaQuery.sizeOf(context).width / 2;
    _dragDelta = 0;
    _lastVolumeStep = -1;
    _notifier.holdControls();
    // Start from what the phone has NOW (the volume keys or the shade may
    // have changed it since the player opened): the finger's movement is
    // collected and applied on top once the fresh value arrives, so not even
    // the first frame jumps from a stale level. The cached value stands in
    // if the phone takes longer than 150 ms to answer.
    _baseReady = false;
    final brightness = _verticalIsBrightness;
    _dragBase = brightness ? _brightness : _currentLevel;
    void ready() {
      _baseTimer?.cancel();
      if (_baseReady || !mounted || !_verticalActive || _verticalIsBrightness != brightness) return;
      _baseReady = true;
      if (_dragDelta != 0) brightness ? _applyBrightness() : _applyVolumeDrag();
    }

    _baseTimer?.cancel();
    _baseTimer = Timer(const Duration(milliseconds: 150), ready);
    if (brightness) {
      DeviceControls.getBrightness().then((v) {
        if (_baseReady || !mounted) return;
        _dragBase = v;
        _brightness = v;
        ready();
      });
    } else {
      DeviceControls.getVolume().then((v) {
        if (_baseReady || !mounted) return;
        _volume = v;
        _dragBase = _levelOf(v, v < _kFullVolume ? 100 : ref.read(_provider).boostPercent);
        ready();
      });
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_verticalActive || _pinching) return;
    if (ref.read(_provider).isLocked) return;
    final height = MediaQuery.sizeOf(context).height;
    _dragDelta += -d.delta.dy / (height * 0.5);
    if (!_baseReady) return;
    if (_verticalIsBrightness) {
      _applyBrightness();
    } else {
      _applyVolumeDrag();
    }
  }

  void _onVerticalDragEnd() {
    _baseTimer?.cancel();
    if (!_verticalActive) return;
    _verticalActive = false;
    _notifier.releaseControls();
    _hideHudSoon();
  }

  void _applyBrightness() {
    _brightness = (_dragBase + _dragDelta).clamp(0.02, 1.0);
    DeviceControls.setBrightness(_brightness);
    _showHud(_GestureHud(
      icon: Icons.brightness_6_rounded,
      label: '${(_brightness * 100).round()}%',
      value: _brightness,
    ));
  }

  void _applyVolumeDrag() {
    final s = ref.read(_provider);
    final level = (_dragBase + _dragDelta).clamp(0.0, _maxLevel(s));
    _applyLevel(level);
    _showLevelHud(level);
  }

  void _onHorizontalDragStart(VideoPlaybackState state) {
    if (state.isLocked || _pinching || state.duration <= Duration.zero) return;
    _seeking = true;
    _seekStartMs = state.position.inMilliseconds.toDouble();
    _seekTargetMs = _seekStartMs;
    _notifier.holdControls();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d, VideoPlaybackState state) {
    if (!_seeking || _pinching) return;
    final width = MediaQuery.sizeOf(context).width;
    final durationMs = state.duration.inMilliseconds.toDouble();
    final spanMs = math.min(durationMs, _seekFullWidthMs);
    _seekTargetMs = (_seekTargetMs + d.delta.dx / width * spanMs).clamp(0.0, durationMs);
    final diff = _seekTargetMs - _seekStartMs;
    final sign = diff >= 0 ? '+' : '−';
    _showHud(_GestureHud(
      icon: diff >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      label:
          '${formatClock(Duration(milliseconds: _seekTargetMs.round()))}  ($sign${formatClock(Duration(milliseconds: diff.abs().round()))})',
      value: durationMs > 0 ? _seekTargetMs / durationMs : 0,
    ));
  }

  void _onHorizontalDragEnd() {
    if (!_seeking) return;
    _seeking = false;
    _notifier.releaseControls();
    if (_pinching) {
      _hideHudSoon(Duration.zero);
      return;
    }
    _notifier.seekTo(Duration(milliseconds: _seekTargetMs.round()));
    _hideHudSoon();
  }

  // --- pinch (raw pointers, so it never fights the swipes) ----------------------

  double _pointerSpread() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinching = true;
      _pinchApplied = false;
      _pinchStartDistance = _pointerSpread();
      // A second finger turns a swipe into a pinch: drop the swipe.
      if (_seeking) {
        _seeking = false;
        _notifier.releaseControls();
      }
      if (_verticalActive) {
        _verticalActive = false;
        _notifier.releaseControls();
      }
      if (_hud != null) _hideHudSoon(Duration.zero);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_pinching || _pinchApplied || _pointers.length != 2 || _pinchStartDistance <= 0) return;
    if (ref.read(_provider).isLocked) return;
    final ratio = _pointerSpread() / _pinchStartDistance;
    VideoFit? fit;
    if (ratio > 1.08) fit = VideoFit.fill;
    if (ratio < 0.92) fit = VideoFit.fit;
    if (fit == null) return;
    _pinchApplied = true;
    if (fit != ref.read(_provider).fit) {
      _notifier.setFit(fit);
      _toast(_fitIcon(fit), fit.label);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) _pinching = false;
  }

  // --- taps -----------------------------------------------------------------------

  _Side _sideOf(Offset globalPosition) =>
      globalPosition.dx < MediaQuery.sizeOf(context).width / 2 ? _Side.left : _Side.right;

  void _skipFromTap(_Side side) {
    final bubble = _bubble;
    final total = bubble != null && bubble.side == side ? bubble.seconds + 10 : 10;
    _notifier.skipSeconds(side == _Side.left ? -10 : 10);
    _bubbleTimer?.cancel();
    setState(() => _bubble = _SkipBubble(side, total));
    _bubbleTimer = Timer(VideoPlayerControllerNotifier.skipBurstWindow, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _onTapUp(TapUpDetails d, VideoPlaybackState state) {
    if (_volumePanelOpen) {
      _closeVolumePanel();
      return;
    }
    // More taps on the same side right after a double tap keep skipping.
    final bubble = _bubble;
    if (bubble != null && !state.isLocked && _sideOf(d.globalPosition) == bubble.side) {
      _skipFromTap(bubble.side);
      return;
    }
    _notifier.toggleControls();
  }

  void _onDoubleTap(VideoPlaybackState state) {
    final at = _doubleTapAt;
    if (state.isLocked || at == null || _pinching) return;
    _skipFromTap(_sideOf(at));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // `inactive` also happens while the notification shade is pulled down or a
    // dialog shows, and while in picture-in-picture: the video keeps playing then.
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      if (!DeviceControls.inPip.value) {
        _notifier.onAppBackgrounded();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceControls.inPip.removeListener(_onPipChanged);
    _hudTimer?.cancel();
    _baseTimer?.cancel();
    _volumePanelTimer?.cancel();
    _bubbleTimer?.cancel();
    _volumeSub?.cancel();
    _noisySub?.cancel();
    _pipActionSub?.cancel();
    _pipDismissSub?.cancel();
    DeviceControls.setPipPlaying(null);
    DeviceControls.setPipEligible(false);
    DeviceControls.resetBrightness(); // hand brightness back to the system
    // Back saves where the video was, playing or paused.
    try {
      _notifier.saveProgressNow();
      _notifier.onAppBackgrounded();
    } catch (_) {}
    VideoPlayerControllerNotifier.restoreSystemUi();
    super.dispose();
  }

  /// The video stage is ink in both themes, with light system bar icons
  /// (DESIGN.md 7.9 and 8.2): everything below reads the dark palette.
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final engine = ref.watch(videoEngineProvider);
    final inPip = ref.watch(_pipProvider);
    final lockedOnStage = state.isLocked && state.isInitialized && state.errorMessage == null;

    return PopScope(
      // Locked: Back shows the lock instead of leaving.
      canPop: !lockedOnStage,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Nothing may start playing again while the screen animates away.
          _notifier.markClosing();
          // Free the orientation before the list underneath lays out.
          VideoPlayerControllerNotifier.restoreSystemUi();
        } else if (lockedOnStage) {
          _notifier.showControlsNow();
        }
      },
      child: Theme(
        data: AppTheme.darkTheme,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.barsOnInk,
          child: Builder(
            builder: (context) => _buildStage(context, state, engine, inPip),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(
    BuildContext context,
    VideoPlaybackState state,
    VideoEngine engine,
    bool inPip,
  ) {
    final palette = context.palette;
    final type = context.typography;
    final notifier = _notifier;

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
                  // A format the phone cannot read never plays on a retry
                  // (iOS only), so there is no Try again for it.
                  if (kind != VideoErrorKind.unsupportedFormat) ...[
                    FilledButton.icon(
                      // The notifier ignores taps while a retry is running.
                      onPressed: () => unawaited(notifier.retry()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                    const SizedBox(height: AppSpacing.sm8),
                  ],
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
    final metrics = _OverlayMetrics.of(context);

    return Scaffold(
      backgroundColor: _kStage,
      body: Stack(
        children: [
          // 1. Video Player Surface
          Positioned.fill(
            child: engine.buildPlayerWidget(fit: state.fit.boxFit),
          ),

          // 2. Taps, double taps, swipes and the two-finger pinch.
          if (!inPip)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTapUp(d, state),
                  onVerticalDragStart: (d) => _onVerticalDragStart(d, state),
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: (_) => _onVerticalDragEnd(),
                  onVerticalDragCancel: _onVerticalDragEnd,
                  onHorizontalDragStart: (_) => _onHorizontalDragStart(state),
                  onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, state),
                  onHorizontalDragEnd: (_) => _onHorizontalDragEnd(),
                  onHorizontalDragCancel: _onHorizontalDragEnd,
                  onDoubleTapDown: (details) => _doubleTapAt = details.globalPosition,
                  onDoubleTap: () => _onDoubleTap(state),
                ),
              ),
            ),

          // 3. Subtitles: always on top of the picture, above the scrubber
          // while the controls show.
          if (state.subtitlesOn && state.caption.isNotEmpty)
            _buildCaption(context, state, metrics, controlsUp: state.showControls && !state.isLocked && !inPip),

          // 4. Controls Overlay (AnimatedFade 160ms)
          if (!inPip)
            AnimatedOpacity(
              opacity: state.showControls ? 1.0 : 0.0,
              duration: fadeDuration,
              curve: MotionTokens.easeOut,
              child: IgnorePointer(
                ignoring: !state.showControls,
                child: state.isLocked
                    ? _buildLockedOverlay(context, notifier)
                    : _buildNormalControls(context, state, notifier, sliderVal, maxDuration, metrics),
              ),
            ),

          // 5. "Up next" at the end of a video with more after it.
          if (!inPip && state.upNextSeconds != null && !state.isLocked)
            _buildUpNext(context, state, metrics),

          // 6. The double-tap bubble.
          if (!inPip && _bubble != null) _buildSkipBubble(context, _bubble!),

          // 7. The volume panel from the top row.
          if (!inPip && _volumePanelOpen && !state.isLocked) _buildVolumePanel(context, state, metrics),

          // 8. Brightness / volume / seek feedback while swiping
          if (!inPip && _hud != null) _buildHud(palette, type, _hud!),
        ],
      ),
    );
  }

  /// Brightness / volume / seek feedback: white on the ink overlay chip, a
  /// Volt bar on a white 24 % track (warning in the boost zone).
  Widget _buildHud(AppPalette palette, AppTextStyles type, _GestureHud hud) {
    final value = hud.value;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hud.icon, color: hud.boost ? palette.warning : palette.onOverlay, size: 32),
                const SizedBox(height: 8),
                Text(
                  hud.label,
                  textAlign: TextAlign.center,
                  style: type.tabularFigures.copyWith(color: hud.boost ? palette.warning : palette.onOverlay),
                ),
                if (value != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 130,
                    child: LinearProgressIndicator(
                      value: value.clamp(0.0, 1.0),
                      backgroundColor: palette.onOverlay.withValues(alpha: 0.24),
                      color: hud.boost ? palette.warning : palette.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaption(BuildContext context, VideoPlaybackState state, _OverlayMetrics m, {required bool controlsUp}) {
    final palette = context.palette;
    final type = context.typography;
    return Positioned(
      left: AppSpacing.lg16 + m.insets.left,
      right: AppSpacing.lg16 + m.insets.right,
      bottom: controlsUp ? m.bottomSolid + AppSpacing.sm8 : m.insets.bottom + AppSpacing.xxl24,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8, vertical: AppSpacing.xs4),
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: BorderRadius.circular(AppSpacing.radiusBadge),
            ),
            child: Text(
              state.caption,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: type.body.copyWith(color: palette.onOverlay),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkipBubble(BuildContext context, _SkipBubble bubble) {
    final palette = context.palette;
    final type = context.typography;
    final left = bubble.side == _Side.left;
    final width = MediaQuery.sizeOf(context).width;
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      width: width * 0.36,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay.withValues(alpha: 0.35),
            borderRadius: left
                ? const BorderRadius.horizontal(right: Radius.circular(400))
                : const BorderRadius.horizontal(left: Radius.circular(400)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(left ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, color: palette.onOverlay, size: 32),
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  left ? '−${bubble.seconds} s' : '+${bubble.seconds} s',
                  style: type.tabularFigures.copyWith(color: palette.onOverlay),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumePanel(BuildContext context, VideoPlaybackState state, _OverlayMetrics m) {
    final palette = context.palette;
    final type = context.typography;
    final maxLevel = _maxLevel(state);
    final level = _levelOf(_volume, state.boostPercent).clamp(0.0, maxLevel);
    final boost = level > 1;
    final tint = boost ? palette.warning : palette.onOverlay;
    return Positioned(
      right: m.insets.right + AppSpacing.sm8,
      top: m.insets.top + AppSpacing.xs4 + _kAction + AppSpacing.xs4,
      bottom: m.insets.bottom + AppSpacing.sm8 + _kAction,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = math.min(constraints.maxHeight, 280.0);
            final roomy = height >= 160;
            return Container(
              key: const ValueKey('video-volume-panel'),
              width: _kVolumePanelWidth,
              height: height,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm8),
              decoration: BoxDecoration(
                color: palette.overlay,
                borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
              ),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${(level * 100).round()}%',
                      style: type.tabularFigures.copyWith(color: tint),
                    ),
                  ),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: boost ? palette.warning : null,
                          thumbColor: boost ? palette.warning : null,
                          inactiveTrackColor: palette.onOverlay.withValues(alpha: 0.3),
                        ),
                        child: Slider(
                          min: 0,
                          max: maxLevel,
                          value: level,
                          semanticFormatterCallback: (v) =>
                              v > 1 ? 'Volume boost ${(v * 100).round()} percent' : 'Volume ${(v * 100).round()} percent',
                          onChangeStart: (_) {
                            _volumeSliding = true;
                            _volumePanelTimer?.cancel();
                          },
                          onChanged: (v) {
                            setState(() => _applyLevel(v));
                          },
                          onChangeEnd: (_) {
                            _volumeSliding = false;
                            _scheduleVolumePanelClose();
                          },
                        ),
                      ),
                    ),
                  ),
                  if (roomy) ...[
                    if (state.boostSupported)
                      Text('Boost', style: type.caption.copyWith(color: boost ? palette.warning : palette.textMuted)),
                    Icon(_volumeIcon(level), color: tint, size: 20),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUpNext(BuildContext context, VideoPlaybackState state, _OverlayMetrics m) {
    final palette = context.palette;
    final type = context.typography;
    final queue = _notifier.queue;
    final nextIndex = state.queueIndex + 1;
    if (nextIndex >= queue.items.length) return const SizedBox.shrink();
    final next = queue.items[nextIndex];
    final title = videoDisplayTitle(next.title);
    final seconds = state.upNextSeconds ?? 0;
    return Positioned(
      right: AppSpacing.lg16 + m.insets.right,
      left: AppSpacing.lg16 + m.insets.left,
      bottom: m.bottomSolid + AppSpacing.sm8,
      child: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.sm8, AppSpacing.sm8),
              decoration: BoxDecoration(
                color: palette.overlay,
                borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'UP NEXT IN $seconds S',
                    semanticsLabel: 'Up next in $seconds seconds',
                    style: type.overline.copyWith(color: palette.onOverlay.withValues(alpha: 0.78)),
                  ),
                  const SizedBox(height: AppSpacing.xs4),
                  Text(
                    breakableTitle(title),
                    semanticsLabel: title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(color: palette.onOverlay),
                  ),
                  const SizedBox(height: AppSpacing.sm8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm8,
                    runSpacing: AppSpacing.xs4,
                    children: [
                      TextButton(
                        onPressed: _notifier.cancelUpNext,
                        style: TextButton.styleFrom(foregroundColor: palette.onOverlay),
                        child: const Text('Cancel'),
                      ),
                      VoltButton.compact(
                        label: 'Play now',
                        icon: Icons.skip_next_rounded,
                        onPressed: () {
                          _notifier.cancelUpNext();
                          _notifier.playNext();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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

  // --- the top row's actions -------------------------------------------------------

  static IconData _fitIcon(VideoFit fit) => switch (fit) {
        VideoFit.fit => Icons.fit_screen_rounded,
        VideoFit.fill => Icons.zoom_out_map_rounded,
        VideoFit.stretch => Icons.aspect_ratio_rounded,
        VideoFit.original => Icons.crop_free_rounded,
      };

  static IconData _orientationIcon(OrientationMode mode) => switch (mode) {
        OrientationMode.auto => Icons.screen_rotation_rounded,
        OrientationMode.landscape => Icons.stay_current_landscape_rounded,
        OrientationMode.portrait => Icons.stay_current_portrait_rounded,
      };

  List<_TopAction> _topActions(BuildContext context, VideoPlaybackState state) {
    final palette = context.palette;
    final level = _levelOf(_volume, state.boostPercent);
    return [
      if (DeviceControls.available)
        _TopAction(
          id: 'volume',
          icon: _volumeIcon(level),
          tooltip: 'Volume',
          menuLabel: 'Volume',
          color: state.boostPercent > 100 ? palette.warning : null,
          onPressed: (_) => _toggleVolumePanel(),
        ),
      if (DeviceControls.available)
        _TopAction(
          id: 'pip',
          icon: Icons.picture_in_picture_alt_rounded,
          tooltip: 'Picture in picture',
          menuLabel: 'Picture-in-picture',
          onPressed: (_) => _enterPip(),
        ),
      _TopAction(
        id: 'rotate',
        icon: _orientationIcon(state.orientationMode),
        tooltip: 'Rotation: ${state.orientationMode.label}',
        menuLabel: 'Rotation: ${state.orientationMode.label}',
        onPressed: (_) {
          final mode = _notifier.cycleOrientation();
          _toast(_orientationIcon(mode), mode.label);
        },
      ),
      _TopAction(
        id: 'fit',
        icon: _fitIcon(state.fit),
        tooltip: 'Picture size: ${state.fit.label}',
        menuLabel: 'Picture size: ${state.fit.label}',
        onPressed: (_) {
          final fit = _notifier.cycleFit();
          _toast(_fitIcon(fit), fit.label);
        },
      ),
      if (state.subtitlesAvailable)
        _TopAction(
          id: 'subtitles',
          icon: state.subtitlesOn ? Icons.closed_caption_rounded : Icons.closed_caption_off_rounded,
          tooltip: state.subtitlesOn ? 'Turn subtitles off' : 'Turn subtitles on',
          menuLabel: state.subtitlesOn ? 'Subtitles off' : 'Subtitles on',
          onPressed: (_) => _notifier.toggleSubtitles(),
        ),
      _TopAction(
        id: 'audio',
        icon: Icons.headphones_rounded,
        tooltip: 'Play as audio',
        menuLabel: 'Play as audio',
        onPressed: (_) => _continueAsAudio(),
      ),
      _TopAction(
        id: 'speed',
        icon: Icons.speed_rounded,
        tooltip: 'Playback Speed',
        menuLabel: 'Playback speed (${_speedLabel(state.speed)})',
        onPressed: (anchor) => _showSpeedMenu(anchor, state),
      ),
    ];
  }

  static String _speedLabel(double s) => s == s.roundToDouble() ? '${s.toInt()}x' : '${s}x';

  Future<void> _continueAsAudio() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final ok = await _notifier.continueAsAudio();
    if (!mounted) return;
    if (ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Playing as audio. It keeps going with the screen off.'), duration: Duration(seconds: 3)),
      );
      navigator.maybePop();
    } else {
      messenger?.showSnackBar(const SnackBar(content: Text("Couldn't switch to audio. Try again.")));
    }
  }

  RelativeRect _menuPosition(BuildContext anchor) {
    final button = anchor.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
  }

  /// Opens a menu under [anchor]; the controls stay up while it is open.
  Future<T?> _openMenu<T>(BuildContext anchor, List<PopupMenuEntry<T>> items, {T? initialValue}) async {
    _notifier.holdControls();
    try {
      return await showMenu<T>(
        context: anchor,
        position: _menuPosition(anchor),
        items: items,
        initialValue: initialValue,
      );
    } finally {
      if (mounted) _notifier.releaseControls();
    }
  }

  Future<void> _showSpeedMenu(BuildContext anchor, VideoPlaybackState state) async {
    final palette = context.palette;
    final type = context.typography;
    final speed = await _openMenu<double>(
      anchor,
      [
        for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem(
            value: s,
            child: Text(
              '${s}x',
              style: type.tabularFigures.copyWith(
                fontSize: 16,
                height: 24 / 16,
                color: s == state.speed ? palette.primary : palette.textPrimary,
              ),
            ),
          ),
      ],
      initialValue: state.speed,
    );
    if (speed != null) _notifier.setSpeed(speed);
  }

  Future<void> _showAudioTracks(BuildContext anchor) async {
    final tracks = await _notifier.audioTracks();
    if (!mounted || !anchor.mounted || tracks.isEmpty) return;
    final palette = context.palette;
    final id = await _openMenu<String>(anchor, [
      for (final t in tracks)
        PopupMenuItem(
          value: t.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                child: t.isSelected ? Icon(Icons.check_rounded, size: 20, color: palette.primary) : null,
              ),
              Flexible(child: Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ]);
    if (id != null) _notifier.selectAudioTrack(id);
  }

  Future<void> _showMore(BuildContext anchor, VideoPlaybackState state, List<_TopAction> overflow) async {
    final choice = await _openMenu<String>(anchor, [
      for (final a in overflow)
        PopupMenuItem(
          value: a.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(a.icon, size: 20, color: a.color),
              const SizedBox(width: AppSpacing.md12),
              Flexible(child: Text(a.menuLabel, maxLines: 2, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      if (state.hasAudioTracks) const PopupMenuItem(value: 'tracks', child: Text('Audio track')),
      const PopupMenuItem(value: 'lock', child: Text('Lock controls')),
    ]);
    if (choice == null || !mounted || !anchor.mounted) return;
    switch (choice) {
      case 'lock':
        _closeVolumePanel();
        _notifier.toggleLock();
      case 'tracks':
        await _showAudioTracks(anchor);
      default:
        for (final a in overflow) {
          if (a.id == choice) a.onPressed(anchor);
        }
    }
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
    _OverlayMetrics m,
  ) {
    final palette = context.palette;
    final type = context.typography;
    final onVideo = palette.onOverlay;
    // The name as on the video cards: no file extension.
    final title = videoDisplayTitle(state.item.title);
    final shownTitle = breakableTitle(title);

    Widget overlayButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      double size = 24,
      bool onChip = false,
      Color? color,
    }) {
      return IconButton(
        constraints: const BoxConstraints(minWidth: _kAction, minHeight: _kAction),
        icon: Icon(icon, size: size, color: onPressed == null ? onVideo.withValues(alpha: 0.38) : (color ?? onVideo)),
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

    final actions = _topActions(context, state);
    final queued = state.queueLength > 1;
    final ended = state.isCompleted;

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: _kControlsVeil)),
        ),
        scrim(top: true, solid: m.topSolid),
        scrim(top: false, solid: m.bottomSolid),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Back, then as many actions as fit; the rest go
                        // into More (always last: it holds Lock too).
                        final slots = ((constraints.maxWidth - _kAction) / _kAction).floor() - 1;
                        final shown = actions.length <= slots ? actions : actions.take(math.max(0, slots)).toList();
                        final overflow = actions.skip(shown.length).toList();
                        return Row(
                          children: [
                            Semantics(
                              label: 'Exit Video Player',
                              button: true,
                              child: IconButton(
                                constraints: const BoxConstraints(minWidth: _kAction, minHeight: _kAction),
                                icon: Icon(Icons.arrow_back_rounded, color: onVideo),
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ),
                            const Spacer(),
                            for (final a in shown)
                              Builder(
                                builder: (anchor) => overlayButton(
                                  icon: a.icon,
                                  tooltip: a.tooltip,
                                  color: a.color,
                                  onPressed: () => a.onPressed(anchor),
                                ),
                              ),
                            Builder(
                              builder: (anchor) => overlayButton(
                                icon: Icons.more_vert_rounded,
                                tooltip: 'More',
                                onPressed: () => _showMore(anchor, state, overflow),
                              ),
                            ),
                          ],
                        );
                      },
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

              // Middle: previous, -10 s, play / pause (Replay at the end),
              // +10 s, next. Shrinks rather than overflow on narrow phones.
              // While the Volume panel is open (at the right edge) the row
              // makes room for it instead of sitting under it.
              AnimatedPadding(
                duration: MotionTokens.duration(context, const Duration(milliseconds: 160)),
                curve: MotionTokens.easeOut,
                padding: EdgeInsets.only(
                  left: AppSpacing.lg16,
                  right: _volumePanelOpen ? _kVolumePanelWidth + AppSpacing.sm8 * 2 : AppSpacing.lg16,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (queued) ...[
                        overlayButton(
                          icon: Icons.skip_previous_rounded,
                          size: 32,
                          tooltip: 'Previous video',
                          onChip: true,
                          onPressed: state.hasPrevious ? notifier.playPrevious : null,
                        ),
                        const SizedBox(width: AppSpacing.sm8),
                      ],
                      overlayButton(
                        icon: Icons.replay_10_rounded,
                        size: 40,
                        tooltip: 'Rewind 10 seconds',
                        onChip: true,
                        onPressed: () => notifier.skipSeconds(-10),
                      ),
                      SizedBox(width: queued ? AppSpacing.lg16 : AppSpacing.xxl24),
                      VoltDisc(
                        size: 64,
                        icon: ended
                            ? Icons.replay_rounded
                            : (state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        tooltip: ended ? 'Replay' : (state.isPlaying ? 'Pause' : 'Play'),
                        onPressed: () => notifier.togglePlayPause(),
                      ),
                      SizedBox(width: queued ? AppSpacing.lg16 : AppSpacing.xxl24),
                      overlayButton(
                        icon: Icons.forward_10_rounded,
                        size: 40,
                        tooltip: 'Forward 10 seconds',
                        onChip: true,
                        onPressed: () => notifier.skipSeconds(10),
                      ),
                      if (queued) ...[
                        const SizedBox(width: AppSpacing.sm8),
                        overlayButton(
                          icon: Icons.skip_next_rounded,
                          size: 32,
                          tooltip: 'Next video',
                          onChip: true,
                          onPressed: state.hasNext ? notifier.playNext : null,
                        ),
                      ],
                    ],
                  ),
                ),
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
                        onChangeStart: (_) => notifier.holdControls(),
                        onChanged: (val) {
                          setState(() {
                            _dragValue = val;
                          });
                        },
                        onChangeEnd: (val) {
                          notifier.seekTo(Duration(milliseconds: val.toInt()));
                          notifier.releaseControls();
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

/// Heights of the solid parts of the top and bottom scrims, from the insets
/// and the text scale (the subtitles and the Up next card sit above them).
class _OverlayMetrics {
  final EdgeInsets insets;
  final double topSolid;
  final double bottomSolid;
  const _OverlayMetrics(this.insets, this.topSolid, this.bottomSolid);

  factory _OverlayMetrics.of(BuildContext context) {
    final type = context.typography;
    final insets = MediaQuery.paddingOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    double lineOf(TextStyle style) => scaler.scale(style.fontSize!) * style.height!;
    // Top: inset, 4 + a 48 dp icon row, up to two title lines, 4.
    final topSolid = insets.top + AppSpacing.xs4 * 2 + _kAction + lineOf(type.playerTitle) * 2;
    // Bottom: 8 + the 48 dp slider, the times line, 8, inset.
    final bottomSolid = insets.bottom + AppSpacing.sm8 * 2 + _kAction + lineOf(type.tabularFigures);
    return _OverlayMetrics(insets, topSolid, bottomSolid);
  }
}
