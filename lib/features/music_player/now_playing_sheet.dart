import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/services/artwork_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_state.dart' as domain;
import '../../shared/widgets/artwork_placeholder.dart';
import '../../shared/widgets/favorite_feedback_button.dart';
import '../library/media_context_menu.dart';
import 'playback_notifier.dart';
import 'queue_sheet.dart';

/// Largest edge of the cover art on Now Playing.
const double _kArtworkMaxSize = 300;
const double _kArtworkRadius = 24;

/// Top corners of the sheet (matches the global bottom sheet shape).
const double _kSheetRadius = 28;

/// Strip above the app bar that holds the grabber pill, so the pill never
/// shares space with the title at any text size.
const double _kGrabberStripHeight = AppSpacing.lg16;

/// Below this body height (at 1x text) the content scrolls instead of the
/// artwork shrinking any further (landscape phones, split screen).
const double _kCompactBodyHeight = 440;

/// Vertical rhythm of the player body. The favourite snackbar is placed from
/// the same numbers, so keep them here.
const double _kBodyTopPadding = AppSpacing.sm8;
const double _kBodyBottomPadding = AppSpacing.xxl24;
const double _kArtworkGap = AppSpacing.xxl24;
const double _kSectionGap = AppSpacing.md12;
const double _kPlayButtonSize = 72;

/// Snackbar distance from the bottom while the body scrolls (the default of
/// FavoriteFeedbackButton): the title row has no fixed place there.
const double _kScrollingSnackMargin = 76;

/// A downward fling faster than this (logical px per second) closes the sheet.
const double _kCloseFlingVelocity = 250;

/// The backdrop is a tiny copy of the cover, blurred once per track and then
/// stretched over the screen, so no blur runs while frames are drawn.
const int _kBackdropSwatchSize = 64;
const double _kBackdropBlurSigma = 3;

const List<double> _kSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Dark veil over the blurred cover: light at the top so the colour of the
/// song shows through, solid canvas at the bottom where text and controls sit.
final LinearGradient _kBackdropScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    AppColors.background.withValues(alpha: 0.5),
    AppColors.background.withValues(alpha: 0.62),
    AppColors.background.withValues(alpha: 0.9),
    AppColors.background,
  ],
  stops: const [0.0, 0.42, 0.72, 1.0],
);

class NowPlayingSheet extends ConsumerWidget {
  const NowPlayingSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackNotifierProvider);
    final notifier = ref.read(playbackNotifierProvider.notifier);

    final currentItem = playbackState.currentItem;
    final duration = playbackState.duration.inMilliseconds > 0
        ? playbackState.duration
        : Duration(milliseconds: currentItem?.durationMs ?? 0);

    final queueLength = playbackState.queue.length;
    final queuePosition = currentItem != null && queueLength > 1
        ? '${playbackState.queueIndex + 1} of $queueLength'
        : null;

    void close() => Navigator.of(context).pop();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + _kGrabberStripHeight),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _Grabber(),
                Expanded(
                  child: AppBar(
                    // the SafeArea above already handles the top inset
                    primary: false,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    automaticallyImplyLeading: false,
                    leading: IconButton(
                      tooltip: 'Collapse Now Playing',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                      onPressed: close,
                    ),
                    centerTitle: true,
                    title: _SheetTitle(subtitle: queuePosition),
                    actions: [
                      _SpeedMenu(
                        speed: playbackState.speed,
                        onSelected: (speed) => notifier.setSpeed(speed),
                      ),
                      IconButton(
                        tooltip: 'View Queue',
                        icon: const Icon(Icons.queue_music_rounded),
                        color: AppColors.textSecondary,
                        onPressed: () => _openQueue(context),
                      ),
                      const SizedBox(width: AppSpacing.xs4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _ArtworkBackdrop(item: currentItem),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > _kCloseFlingVelocity) {
                  close();
                }
              },
              child: SafeArea(
                child: _NowPlayingBody(
                  item: currentItem,
                  onMore: currentItem != null
                      ? () => MediaContextMenu.show(context, ref, currentItem)
                      : null,
                  onClose: close,
                  seekBar: _SeekBar(
                    fallbackPosition: playbackState.position,
                    duration: duration,
                  ),
                  controls: _TransportControls(
                    isPlaying: playbackState.isPlaying,
                    shuffle: playbackState.shuffle,
                    repeatMode: playbackState.repeatMode,
                    onShuffle: () => notifier.toggleShuffle(),
                    onPrevious: () => notifier.skipToPrevious(),
                    onPlayPause: () {
                      if (playbackState.isPlaying) {
                        notifier.pause();
                      } else {
                        notifier.play();
                      }
                    },
                    onNext: () => notifier.skipToNext(),
                    onRepeat: () => notifier.cycleRepeatMode(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openQueue(BuildContext context) {
    // Uses the global sheet style (surface, 28 dp corners, drag handle).
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.7,
        child: QueueSheet(),
      ),
    );
  }
}

/// "Now Playing" with the queue position underneath.
class _SheetTitle extends StatelessWidget {
  final String? subtitle;

  const _SheetTitle({this.subtitle});

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Now Playing',
          style: AppTypography.bodyStrong,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// Small pill at the top edge that says "this sheet can be pulled down". It
/// has its own strip above the app bar.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kGrabberStripHeight,
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glow in the colours of the song's cover palette, then a soft blurred
/// copy of the cover (only when the track really has one), then a dark
/// scrim, so the screen takes on the colour of the song.
class _ArtworkBackdrop extends StatelessWidget {
  final MediaItem? item;

  const _ArtworkBackdrop({required this.item});

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PaletteGlow(seed: item?.uri),
          _BlurredCover(uri: item?.uri, artworkPath: item?.artworkPath),
          DecoratedBox(decoration: BoxDecoration(gradient: _kBackdropScrim)),
        ],
      ),
    );
  }
}

/// Two soft radial glows on the canvas: the light stop of the song's cover
/// palette behind the artwork and its deep stop to the right. The seed is the
/// song's uri, the same one its placeholder cover uses, so a song without art
/// glows in its cover's colours. The colours drift to the next song's on a
/// track change (instantly with reduced motion).
class _PaletteGlow extends StatelessWidget {
  final String? seed;

  const _PaletteGlow({required this.seed});

  static const Alignment _lightCenter = Alignment(-0.35, -0.72);
  static const Alignment _deepCenter = Alignment(0.9, -0.15);

  @override
  Widget build(BuildContext context) {
    final seed = this.seed;
    final fallback = AppColors.artworkGradients.first.colors;
    final light = seed == null ? fallback.first : ArtworkTint.light(seed);
    final deep = seed == null ? fallback.last : ArtworkTint.deep(seed);
    final duration = MotionTokens.duration(context, MotionTokens.ambient);

    Widget glow(Alignment center, double radius, Color color, double alpha) {
      return AnimatedContainer(
        duration: duration,
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          glow(_deepCenter, 1.1, deep, ArtworkTint.backdropDeepAlpha),
          glow(_lightCenter, 1.05, light, ArtworkTint.backdropLightAlpha),
        ],
      ),
    );
  }
}

/// Draws the pre-blurred cover swatch. While the next track's swatch is being
/// made the current one stays, then the two cross-fade. Tracks without art
/// draw nothing, so the gradient underneath shows.
class _BlurredCover extends StatefulWidget {
  final String? uri;
  final String? artworkPath;

  const _BlurredCover({required this.uri, required this.artworkPath});

  @override
  State<_BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<_BlurredCover> {
  ui.Image? _image;

  /// The swatch that is fading out; released on the next change.
  ui.Image? _previous;

  /// Only the newest request may set the image (fast skipping).
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_BlurredCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.artworkPath != widget.artworkPath) {
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _image?.dispose();
    _previous?.dispose();
    super.dispose();
  }

  void _load() {
    final request = ++_request;
    final uri = widget.uri;
    if (uri == null) {
      // build always follows initState / didUpdateWidget
      _replace(null);
      return;
    }
    _loadBlurredCover(uri, widget.artworkPath).then((image) {
      if (!mounted || request != _request) {
        image?.dispose();
        return;
      }
      if (image == null && _image == null) return;
      setState(() => _replace(image));
    });
  }

  void _replace(ui.Image? image) {
    _previous?.dispose();
    _previous = _image;
    _image = image;
  }

  static Widget _fill(Widget? current, List<Widget> previous) {
    return Stack(fit: StackFit.expand, children: [...previous, ?current]);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return AnimatedSwitcher(
      duration: MotionTokens.duration(context, MotionTokens.page),
      switchInCurve: MotionTokens.easeOut,
      switchOutCurve: MotionTokens.easeIn,
      layoutBuilder: _fill,
      child: image == null
          ? const SizedBox.shrink(key: ValueKey('no_cover'))
          : RawImage(
              key: ObjectKey(image),
              image: image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
    );
  }
}

/// Reads the cover (local file, online thumbnail or art embedded in the song)
/// and returns a small, already blurred square copy of it, or null when there
/// is no real artwork.
Future<ui.Image?> _loadBlurredCover(String uri, String? artworkPath) async {
  try {
    final bytes = await _coverBytes(uri, artworkPath);
    if (bytes == null || bytes.isEmpty) return null;

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: _kBackdropSwatchSize);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final source = frame.image;
    try {
      final side = math.min(source.width, source.height).toDouble();
      final from = Rect.fromCenter(
        center: Offset(source.width / 2, source.height / 2),
        width: side,
        height: side,
      );
      final to = Rect.fromLTWH(
        0,
        0,
        _kBackdropSwatchSize.toDouble(),
        _kBackdropSwatchSize.toDouble(),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, to)
        ..saveLayer(
          to,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: _kBackdropBlurSigma,
              sigmaY: _kBackdropBlurSigma,
              tileMode: TileMode.clamp,
            ),
        );
      canvas
        ..drawImageRect(source, from, to, Paint()..filterQuality = FilterQuality.medium)
        ..restore();
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(_kBackdropSwatchSize, _kBackdropSwatchSize);
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Same sources, in the same order, as [ArtworkThumbnail].
Future<Uint8List?> _coverBytes(String uri, String? artworkPath) async {
  if (artworkPath != null && artworkPath.isNotEmpty) {
    try {
      if (artworkPath.startsWith('http://') || artworkPath.startsWith('https://')) {
        final data = await NetworkAssetBundle(Uri.parse(artworkPath)).load(artworkPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
      final file = File(artworkPath);
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {
      // fall back to the art embedded in the song
    }
  }
  return ArtworkService.instance.getArtwork(uri, size: 512);
}

/// Lays out artwork, track info, seek bar and controls. On tall screens the
/// artwork takes whatever height is left (up to 300 dp); on short ones the
/// content scrolls so nothing overflows.
class _NowPlayingBody extends StatelessWidget {
  final MediaItem? item;
  final VoidCallback? onMore;
  final VoidCallback onClose;
  final Widget seekBar;
  final Widget controls;

  const _NowPlayingBody({
    required this.item,
    required this.onMore,
    required this.onClose,
    required this.seekBar,
    required this.controls,
  });

  /// Distance from the bottom of the body to just above the title row in the
  /// regular layout, so the favourite confirmation never covers the heart.
  static double _snackMarginAboveInfo(TextScaler scaler) {
    double line(TextStyle style) => scaler.scale(style.fontSize!) * (style.height ?? 1);
    final infoHeight = math.max(
      AppSpacing.minTouchTarget,
      line(AppTypography.playerTitle) + AppSpacing.xs4 + line(AppTypography.metadata),
    );
    final seekBarHeight = AppSpacing.minTouchTarget + line(AppTypography.tabularFigures);
    return _kBodyBottomPadding +
        _kPlayButtonSize +
        _kSectionGap +
        seekBarHeight +
        _kSectionGap +
        infoHeight +
        _kSectionGap;
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textScale = textScaler.scale(100) / 100;
    final compactBelow = _kCompactBodyHeight + (textScale - 1).clamp(0.0, 2.0) * 140;
    // Never higher than half the screen: the root messenger also lays the
    // snackbar out in the app shell behind this sheet.
    final snackMargin = math.min(
      _snackMarginAboveInfo(textScaler),
      MediaQuery.sizeOf(context).height / 2,
    );

    Widget info(double snackBottomMargin) => _TrackInfo(
          item: item,
          onMore: onMore,
          snackBottomMargin: snackBottomMargin,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < compactBelow) {
          final artSize = math.min(
            220.0,
            math.max(0.0, constraints.maxWidth - 2 * AppSpacing.lg16),
          );
          return _FlingDownToClose(
            onClose: onClose,
            child: SingleChildScrollView(
              // Clamping on every platform: a drag released at the top then
              // ends at once and reports its velocity to _FlingDownToClose.
              physics: const ClampingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg16,
                _kBodyTopPadding,
                AppSpacing.lg16,
                _kBodyBottomPadding,
              ),
              child: _WidthLimit(
                child: Column(
                  children: [
                    _NowPlayingArtwork(item: item, size: artSize),
                    const SizedBox(height: _kArtworkGap),
                    info(_kScrollingSnackMargin),
                    const SizedBox(height: _kSectionGap),
                    seekBar,
                    const SizedBox(height: _kSectionGap),
                    controls,
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg16,
            _kBodyTopPadding,
            AppSpacing.lg16,
            _kBodyBottomPadding,
          ),
          child: _WidthLimit(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = math.max(
                        0.0,
                        math.min(_kArtworkMaxSize, math.min(box.maxWidth, box.maxHeight - AppSpacing.lg16)),
                      );
                      return Center(child: _NowPlayingArtwork(item: item, size: size));
                    },
                  ),
                ),
                const SizedBox(height: _kArtworkGap),
                info(snackMargin),
                const SizedBox(height: _kSectionGap),
                seekBar,
                const SizedBox(height: _kSectionGap),
                controls,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// In the scrolling layout the scroll view wins every vertical drag, so the
/// sheet's own swipe-down never fires. A fast downward fling that starts and
/// ends with the content at its top closes the sheet here instead.
class _FlingDownToClose extends StatefulWidget {
  final VoidCallback onClose;
  final Widget child;

  const _FlingDownToClose({required this.onClose, required this.child});

  @override
  State<_FlingDownToClose> createState() => _FlingDownToCloseState();
}

class _FlingDownToCloseState extends State<_FlingDownToClose> {
  bool _dragFromTop = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final atTop = notification.metrics.extentBefore < 1;
    if (notification is ScrollStartNotification) {
      _dragFromTop = notification.dragDetails != null && atTop;
    } else if (notification is ScrollEndNotification) {
      final velocity = notification.dragDetails?.primaryVelocity ?? 0;
      final close = _dragFromTop && atTop && velocity > _kCloseFlingVelocity;
      _dragFromTop = false;
      if (close) widget.onClose();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    );
  }
}

/// Keeps the player readable on tablets.
class _WidthLimit extends StatelessWidget {
  final Widget child;

  const _WidthLimit({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: child,
      ),
    );
  }
}

/// The big cover: 24 dp corners, a soft shadow, and the shared Hero tag.
class _NowPlayingArtwork extends StatelessWidget {
  final MediaItem? item;
  final double size;

  const _NowPlayingArtwork({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    // too small to be worth drawing (very short windows)
    if (size < AppSpacing.huge48) return SizedBox.square(dimension: size);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(_kArtworkRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kArtworkRadius),
        child: Hero(
          tag: 'now_playing_artwork',
          child: item != null
              ? ArtworkThumbnail(
                  uri: item.uri,
                  artworkPath: item.artworkPath,
                  size: size,
                  borderRadius: _kArtworkRadius,
                )
              : DecoratedBox(
                  decoration: const BoxDecoration(gradient: AppColors.heroGradient),
                  child: Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      size: size * 0.32,
                      color: AppColors.primary,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Title and artist on the left, favourite and "more" on the right.
class _TrackInfo extends StatelessWidget {
  final MediaItem? item;
  final VoidCallback? onMore;

  /// Where the favourite confirmation sits, measured from the bottom.
  final double snackBottomMargin;

  const _TrackInfo({
    required this.item,
    required this.onMore,
    required this.snackBottomMargin,
  });

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item?.title ?? 'No track playing',
                style: AppTypography.playerTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs4),
              Text(
                item?.artist ?? 'Unknown Artist',
                style: AppTypography.metadata,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm8),
        if (item != null)
          FavoriteFeedbackButton(
            key: ValueKey('fav_${item.id}'),
            itemId: item.id,
            isFavorite: item.isFavorite,
            size: 26,
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget,
            ),
            snackBottomMargin: snackBottomMargin,
          )
        else
          const SizedBox(width: AppSpacing.minTouchTarget, height: AppSpacing.minTouchTarget),
        IconButton(
          tooltip: 'More options',
          icon: const Icon(Icons.more_vert_rounded),
          color: AppColors.textSecondary,
          onPressed: onMore,
        ),
      ],
    );
  }
}

/// Seek bar with elapsed / total time. Only this part listens to the position
/// stream, so the cover and the backdrop are not rebuilt four times a second.
class _SeekBar extends ConsumerStatefulWidget {
  final Duration fallbackPosition;
  final Duration duration;

  const _SeekBar({required this.fallbackPosition, required this.duration});

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(throttledPositionStreamProvider);
    final position = positionAsync.value ?? widget.fallbackPosition;
    final duration = widget.duration;

    final currentPositionMs = _dragValue ?? position.inMilliseconds.toDouble();
    final maxDurationMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue = currentPositionMs.clamp(0.0, maxDurationMs);
    final isDragging = _dragValue != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.textPrimary.withValues(alpha: 0.16),
            thumbColor: AppColors.textPrimary,
            overlayColor: AppColors.primary.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: AppSpacing.lg16),
          ),
          child: SizedBox(
            height: AppSpacing.minTouchTarget,
            child: Slider(
              // track spans the full content width, aligned with the title
              padding: EdgeInsets.zero,
              min: 0.0,
              max: maxDurationMs,
              value: sliderValue,
              semanticFormatterCallback: (value) =>
                  formatDuration(Duration(milliseconds: value.toInt())),
              onChanged: (val) {
                setState(() {
                  _dragValue = val;
                });
              },
              onChangeEnd: (val) {
                ref.read(playbackNotifierProvider.notifier).seek(Duration(milliseconds: val.toInt()));
                setState(() {
                  _dragValue = null;
                });
              },
            ),
          ),
        ),
        Row(
          children: [
            Text(
              formatDuration(Duration(milliseconds: sliderValue.toInt())),
              style: AppTypography.tabularFigures.copyWith(
                color: isDragging ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              formatDuration(duration),
              style: AppTypography.tabularFigures,
            ),
          ],
        ),
      ],
    );
  }
}

/// Shuffle, previous, play / pause, next, repeat.
class _TransportControls extends StatelessWidget {
  final bool isPlaying;
  final bool shuffle;
  final domain.PlaybackRepeatMode repeatMode;
  final VoidCallback onShuffle;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onRepeat;

  const _TransportControls({
    required this.isPlaying,
    required this.shuffle,
    required this.repeatMode,
    required this.onShuffle,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ModeToggleButton(
            icon: Icons.shuffle_rounded,
            active: shuffle,
            tooltip: shuffle ? 'Shuffle enabled' : 'Shuffle disabled',
            onPressed: onShuffle,
          ),
          _SkipButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Previous track',
            onPressed: onPrevious,
          ),
          _PlayPauseButton(isPlaying: isPlaying, onPressed: onPlayPause),
          _SkipButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next track',
            onPressed: onNext,
          ),
          _ModeToggleButton(
            icon: repeatMode == domain.PlaybackRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            active: repeatMode != domain.PlaybackRepeatMode.off,
            tooltip: 'Repeat mode: ${repeatMode.name}',
            onPressed: onRepeat,
          ),
        ],
      ),
    );
  }
}

/// Shuffle / repeat: violet with a dot underneath while on.
class _ModeToggleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  const _ModeToggleButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppSpacing.minTouchTarget,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            iconSize: 24,
            icon: Icon(icon, color: active ? AppColors.primary : AppColors.textSecondary),
            onPressed: onPressed,
          ),
          Positioned(
            bottom: AppSpacing.xs4,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: MotionTokens.duration(context, MotionTokens.feedback),
                curve: MotionTokens.easeOut,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Previous / next: 32 dp glyphs on a 56 dp target.
class _SkipButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _SkipButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 32,
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.square(56),
      ),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// 72 dp violet disc with dark ink, glowing softly.
class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _PlayPauseButton({required this.isPlaying, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: IconButton.filled(
        tooltip: isPlaying ? 'Pause' : 'Play',
        iconSize: 40,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          fixedSize: const Size.square(_kPlayButtonSize),
          shape: const CircleBorder(),
        ),
        icon: AnimatedSwitcher(
          duration: MotionTokens.duration(context, MotionTokens.feedback),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(isPlaying),
            color: AppColors.onPrimary,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// Speed picker. At 1x it is a plain speed icon; at any other speed the
/// button shows the speed itself in a small violet chip, sized to stay inside
/// its own touch target.
class _SpeedMenu extends StatelessWidget {
  final double speed;
  final ValueChanged<double> onSelected;

  const _SpeedMenu({required this.speed, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final isNormal = speed == 1.0;
    return PopupMenuButton<double>(
      tooltip: 'Playback Speed',
      initialValue: speed,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      icon: isNormal
          ? const Icon(Icons.speed_rounded, color: AppColors.textSecondary)
          : _SpeedChip(label: '${speed}x'),
      itemBuilder: (context) => [
        for (final s in _kSpeeds)
          PopupMenuItem<double>(
            value: s,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: AppSpacing.xxl24,
                  child: s == speed
                      ? const Icon(Icons.check_rounded, size: 18, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm8),
                Text(
                  '${s}x',
                  style: AppTypography.body.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: s == speed ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "1.25x" in a tinted stadium, the same height as a 24 dp icon.
class _SpeedChip extends StatelessWidget {
  final String label;

  const _SpeedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm8,
          vertical: AppSpacing.xs4,
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          // the app bar has a fixed height; grow only a little with the text
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
          style: AppTypography.label.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
