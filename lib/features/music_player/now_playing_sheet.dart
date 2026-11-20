import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/ink_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/services/artwork_presence.dart';
import '../../core/services/artwork_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playback_state.dart' as domain;
import '../../domain/models/playback_state.dart' show SleepTimerStatus;
import '../../shared/widgets/artwork_placeholder.dart';
import '../../shared/widgets/favorite_feedback_button.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/media_context_menu.dart';
import 'playback_notifier.dart';
import 'queue_sheet.dart';

/// Largest edge of the cover art on Now Playing (docs/DESIGN.md 7.8: screen
/// width - 32, at most 360). Phones are narrower than this, so the cover
/// takes the full content width and lines up with the 16 dp edges of the
/// title and seek bar (328 dp on a 360 dp screen).
const double _kArtworkMaxSize = 360;
const double _kArtworkRadius = AppSpacing.radiusCover;

/// The hard "print offset" under the cover: 6x6 dp, no blur.
const Offset _kPrintOffset = Offset(6, 6);

/// Top corners of the sheet (matches the global bottom sheet shape).
const double _kSheetRadius = AppSpacing.radiusSheet;

/// Strip above the app bar that holds the grabber pill, so the pill never
/// shares space with the title at any text size.
const double _kGrabberStripHeight = AppSpacing.lg16;

/// Below this body height (at 1x text) the content scrolls instead of the
/// artwork shrinking any further (landscape phones, split screen).
const double _kCompactBodyHeight = 480;

/// Vertical rhythm of the player body. The favourite snackbar is placed from
/// the same numbers, so keep them here.
const double _kBodyTopPadding = AppSpacing.sm8;
const double _kBodyBottomPadding = AppSpacing.sm8;
const double _kArtworkGap = AppSpacing.xl20;
const double _kSectionGap = AppSpacing.md12;
const double _kPlayButtonSize = VoltDisc.large;

/// The footer (speed, Up next) under the transport.
const double _kFooterGap = AppSpacing.xs4;
const double _kFooterHeight = AppSpacing.minTouchTarget;

/// How far the elapsed / remaining labels are drawn above their layout slot,
/// so they sit about 14 dp under the seek track and 24 dp above the controls.
const double _kSeekLabelLift = AppSpacing.md12;

/// Snackbar distance from the bottom while the body scrolls (the default of
/// FavoriteFeedbackButton): the title row has no fixed place there.
const double _kScrollingSnackMargin = 76;

/// A downward fling faster than this (logical px per second) closes the sheet.
const double _kCloseFlingVelocity = 250;

/// The backdrop is a tiny copy of the cover, blurred once per track and then
/// stretched over the screen, so no blur runs while frames are drawn.
const int _kBackdropSwatchSize = 64;
const double _kBackdropBlurSigma = 3;

/// Brightest the backdrop swatch may be on average (Rec. 709 luma of its
/// sRGB values, 0 to 1). A brighter cover (mostly white, a pale photo) is
/// darkened to this level, so the screen stays a deep tone of the cover
/// instead of a flat charcoal with a grey halo; colourful covers are below
/// it and keep their colours as they are.
const double _kBackdropMaxLuma = 0.40;

const List<double> _kSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// After a seek bar release the thumb stays where it was let go until the
/// player reports a time this close to it, or for at most [_kSeekHoldMax]
/// (the position stream still carries the old time for a moment).
const Duration _kSeekSettleTolerance = Duration(milliseconds: 500);
const Duration _kSeekHoldMax = Duration(milliseconds: 600);

/// A sideways swipe on the cover skips past this share of its width, or
/// faster than [_kCoverFlingVelocity] (logical px per second).
const double _kCoverSwipeShare = 0.3;
const double _kCoverFlingVelocity = 500;

/// How long after a cover swipe the song change still slides in.
const Duration _kCoverSwipeResultWindow = Duration(seconds: 2);

/// Opacity of a transport control with nowhere to go.
const double _kDisabledAlpha = 0.38;

/// Dark veil over the blurred cover and the glow. The header band stays dark
/// (82 %) so the kicker reads over any cover, even a white one; it opens up
/// (60 %) only in the band around the artwork, where the colour of the song
/// shows, and closes again towards the title and the controls. Contrast
/// where the text sits is checked in test/widget/now_playing_backdrop_test.dart.
LinearGradient _backdropScrim(AppPalette p) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        p.background.withValues(alpha: 0.82),
        p.background.withValues(alpha: 0.82),
        p.background.withValues(alpha: 0.6),
        p.background.withValues(alpha: 0.9),
        p.background,
      ],
      stops: const [0.0, 0.16, 0.26, 0.72, 1.0],
    );

/// The veil while the body scrolls (landscape, split screen): text can then
/// pass over every band, so it never opens up below the header's 82 %.
LinearGradient _scrollingBackdropScrim(AppPalette p) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        p.background.withValues(alpha: 0.82),
        p.background.withValues(alpha: 0.9),
        p.background,
      ],
      stops: const [0.0, 0.72, 1.0],
    );

/// Whether the player body scrolls instead of shrinking the artwork any
/// further. [bodyHeight] is the height inside the safe area.
bool _bodyScrolls(BuildContext context, double bodyHeight) {
  final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
  final compactBelow = _kCompactBodyHeight + (textScale - 1).clamp(0.0, 2.0) * 140;
  return bodyHeight < compactBelow;
}

/// "NOW PLAYING · 3 / 24" (docs/DESIGN.md 7.8), or just "NOW PLAYING" for a
/// queue of one.
@visibleForTesting
String nowPlayingKicker(domain.PlaybackState s) {
  final length = s.queue.length;
  if (s.currentItem == null || length <= 1) return 'NOW PLAYING';
  return 'NOW PLAYING · ${s.queueIndex + 1} / $length';
}

/// The stage (docs/DESIGN.md 7.8): always ink, in both themes, with light
/// status bar icons. The queue and media sheets it opens follow the app
/// theme.
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

    final sleepActive = ref.watch(sleepTimerProvider.select((s) => s.isActive));

    final queueLength = playbackState.queue.length;
    // Read as before the kicker: "Now Playing", then "3 of 24".
    final headerLabel = currentItem != null && queueLength > 1
        ? 'Now Playing\n${playbackState.queueIndex + 1} of $queueLength'
        : 'Now Playing';

    // Sheets opened from the stage come from this context, outside the
    // stage's dark theme below, so they use the app's theme.
    final sheetContext = context;
    void close() => Navigator.of(context).pop();

    return Theme(
      data: InkTheme.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.barsOnInk,
        child: Builder(
          builder: (context) {
            final palette = context.palette;
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
              child: Scaffold(
                backgroundColor: palette.background,
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
                            systemOverlayStyle: AppTheme.barsOnInk,
                            leading: IconButton(
                              tooltip: 'Collapse Now Playing',
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                              onPressed: close,
                            ),
                            centerTitle: true,
                            title: _StageKicker(
                              text: nowPlayingKicker(playbackState),
                              semanticsLabel: headerLabel,
                            ),
                            actions: [
                              // On a wide screen the menu hangs from this
                              // button (its own context is the anchor).
                              Builder(
                                builder: (buttonContext) => IconButton(
                                  tooltip: 'More options',
                                  icon: const Icon(Icons.more_vert_rounded),
                                  color: palette.textSecondary,
                                  onPressed: currentItem != null
                                      ? () => MediaContextMenu.show(
                                            sheetContext,
                                            ref,
                                            currentItem,
                                            anchorContext: buttonContext,
                                          )
                                      : null,
                                ),
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
                      // A shortcut: screen readers close with "Collapse Now
                      // Playing". In the tree, the detector made one
                      // sheet-sized node that merged the title, artist,
                      // heart and times into one label.
                      excludeFromSemantics: true,
                      onVerticalDragEnd: (details) {
                        if (details.primaryVelocity != null && details.primaryVelocity! > _kCloseFlingVelocity) {
                          close();
                        }
                      },
                      child: SafeArea(
                        child: _NowPlayingBody(
                          item: currentItem,
                          onClose: close,
                          sleepActive: sleepActive,
                          canSkipNext: canSkipNextIn(playbackState),
                          onNext: () => notifier.skipToNext(),
                          onPrevious: () => notifier.skipToPrevious(),
                          seekBar: _SeekBar(
                            key: ValueKey('seek_${currentItem?.id}'),
                            fallbackPosition: playbackState.position,
                            duration: duration,
                          ),
                          controls: _TransportControls(
                            isPlaying: playbackState.isPlaying,
                            shuffle: playbackState.shuffle,
                            repeatMode: playbackState.repeatMode,
                            canSkipNext: canSkipNextIn(playbackState),
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
                          footer: _StageFooter(
                            speed: playbackState.speed,
                            onSpeed: (speed) => notifier.setSpeed(speed),
                            onQueue: () => _openQueue(sheetContext),
                            onSleep: () => showSleepTimerSheet(sheetContext),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openQueue(BuildContext context) {
    // Uses the global sheet style (surface, 28 dp corners, drag handle) of
    // the app theme: [context] is outside the stage's dark theme.
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

/// The overline kicker in the top bar, in textSecondary (never textMuted on
/// the stage). A screen reader hears "Now Playing, 3 of 24" rather than the
/// dot and slash. Where it does not fit (a small phone at large text) it
/// shrinks as a whole, so the queue position is never the part cut off.
class _StageKicker extends StatelessWidget {
  final String text;
  final String semanticsLabel;

  const _StageKicker({required this.text, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        semanticsLabel: semanticsLabel,
        style: context.typography.overline.copyWith(color: palette.textSecondary),
        maxLines: 1,
        softWrap: false,
      ),
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
                color: context.palette.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glow, then a soft blurred copy of the cover (only when the track really
/// has one), then a dark scrim, so the screen takes on the colour of the song.
///
/// A song without art glows in its placeholder's palette. A song with a real
/// cover glows in the neutral brand violet, so a hash colour that has nothing
/// to do with the cover never shows around it. While a new track's cover is
/// still being looked up the glow keeps its current colours, so no random
/// hue flashes before the blurred cover arrives.
class _ArtworkBackdrop extends StatefulWidget {
  final MediaItem? item;

  const _ArtworkBackdrop({required this.item});

  @override
  State<_ArtworkBackdrop> createState() => _ArtworkBackdropState();
}

class _ArtworkBackdropState extends State<_ArtworkBackdrop> {
  /// The blurred swatch on screen; null when the track has no art.
  ui.Image? _image;

  /// The swatch that is fading out; released on the next change.
  ui.Image? _previous;

  /// Only the newest request may set the image (fast skipping).
  int _request = 0;

  /// Palette seed of the glow; null is the neutral violet.
  String? _glowSeed;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    // Nothing on screen yet that a change could flash from.
    _glowSeed = hasRealArtwork(item) ? null : item?.uri;
    _load();
  }

  @override
  void didUpdateWidget(_ArtworkBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final item = widget.item;
    if (oldWidget.item?.uri != item?.uri || oldWidget.item?.artworkPath != item?.artworkPath) {
      // Known to have art: go neutral now. Otherwise wait for the lookup.
      if (hasRealArtwork(item)) _glowSeed = null;
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
    final item = widget.item;
    if (item == null) {
      // build always follows initState / didUpdateWidget
      _replace(null);
      _glowSeed = null;
      return;
    }
    final uri = item.uri;
    _loadBlurredCover(uri, item.artworkPath).then((image) {
      if (!mounted || request != _request) {
        image?.dispose();
        return;
      }
      // Neutral under a swatch, and also when the cover is known from a
      // saved thumbnail or the art cache but no swatch could be made.
      final seed = image != null || hasRealArtwork(widget.item) ? null : uri;
      if (image == null && _image == null && seed == _glowSeed) return;
      setState(() {
        _replace(image);
        _glowSeed = seed;
      });
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
    final palette = context.palette;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = MediaQuery.paddingOf(context);
          final scrolls = _bodyScrolls(context, constraints.maxHeight - padding.vertical);
          return Stack(
            fit: StackFit.expand,
            children: [
              _PaletteGlow(seed: _glowSeed),
              // While the next swatch is being made the current one stays,
              // then the two cross-fade.
              AnimatedSwitcher(
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
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: scrolls ? _scrollingBackdropScrim(palette) : _backdropScrim(palette),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Two soft radial glows on the canvas: the light stop of a cover palette
/// around the artwork and its deep stop to the right. [seed] is the song's
/// uri, the same one its placeholder cover uses; null gives the neutral
/// violet. The colours drift over 600 ms on a change (instantly with reduced
/// motion).
class _PaletteGlow extends StatelessWidget {
  final String? seed;

  const _PaletteGlow({required this.seed});

  /// Centred on the artwork, so the colour rings the cover and stays away
  /// from the header and the title.
  static const Alignment _lightCenter = Alignment(0, -0.30);
  static const double _lightRadius = 0.9;
  static const Alignment _deepCenter = Alignment(0.9, -0.15);

  @override
  Widget build(BuildContext context) {
    // The stage is always ink: the dark palette's glows, in both themes.
    final palette = context.palette;
    final seed = this.seed;
    final fallback = palette.artworkGradients.first.colors;
    final light = seed == null ? fallback.first : ArtworkTint.light(seed, palette);
    final deep = seed == null ? fallback.last : ArtworkTint.deep(seed, palette);
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
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          glow(_deepCenter, 1.1, deep, ArtworkTint.backdropDeepAlpha),
          glow(_lightCenter, _lightRadius, light, ArtworkTint.backdropLightAlpha),
        ],
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
      final ui.Image blurred;
      try {
        blurred = await picture.toImage(_kBackdropSwatchSize, _kBackdropSwatchSize);
      } finally {
        picture.dispose();
      }
      return await _capLuma(blurred);
    } finally {
      source.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// [swatch] itself when its mean luma is at most [_kBackdropMaxLuma];
/// otherwise a copy scaled down to that level (and [swatch] is disposed).
Future<ui.Image> _capLuma(ui.Image swatch) async {
  final ByteData? pixels;
  try {
    pixels = await swatch.toByteData(format: ui.ImageByteFormat.rawRgba);
  } catch (_) {
    return swatch;
  }
  if (pixels == null) return swatch;
  final mean = meanLumaOfRgba(pixels);
  if (mean <= _kBackdropMaxLuma) return swatch;

  final k = _kBackdropMaxLuma / mean;
  final bounds = Rect.fromLTWH(0, 0, swatch.width.toDouble(), swatch.height.toDouble());
  final recorder = ui.PictureRecorder();
  Canvas(recorder, bounds).drawImage(
    swatch,
    Offset.zero,
    Paint()
      ..colorFilter = ColorFilter.matrix(<double>[
        k, 0, 0, 0, 0, //
        0, k, 0, 0, 0, //
        0, 0, k, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
  );
  final picture = recorder.endRecording();
  try {
    final darker = await picture.toImage(swatch.width, swatch.height);
    swatch.dispose();
    return darker;
  } catch (_) {
    return swatch;
  } finally {
    picture.dispose();
  }
}

/// Mean Rec. 709 luma (0 to 1) of raw RGBA pixels, computed on the sRGB
/// values as they are (no linearising), the way the eye judges "bright".
@visibleForTesting
double meanLumaOfRgba(ByteData rgba) {
  final count = rgba.lengthInBytes ~/ 4;
  if (count == 0) return 0;
  var sum = 0.0;
  for (var i = 0; i < count * 4; i += 4) {
    sum += 0.2126 * rgba.getUint8(i) + 0.7152 * rgba.getUint8(i + 1) + 0.0722 * rgba.getUint8(i + 2);
  }
  return sum / (count * 255);
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

/// Lays out artwork, track info, seek bar, controls and the footer. On tall
/// screens the artwork takes whatever height is left (up to
/// [_kArtworkMaxSize]); on short ones the content scrolls so nothing
/// overflows.
class _NowPlayingBody extends StatelessWidget {
  final MediaItem? item;
  final VoidCallback onClose;
  final Widget seekBar;
  final Widget controls;
  final Widget footer;

  /// The sleep chip shows under the artist (the info row is taller).
  final bool sleepActive;

  /// The cover's sideways swipe: Next (when there is one) and Previous.
  final bool canSkipNext;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const _NowPlayingBody({
    required this.item,
    required this.onClose,
    required this.seekBar,
    required this.controls,
    required this.footer,
    this.sleepActive = false,
    this.canSkipNext = false,
    required this.onNext,
    required this.onPrevious,
  });

  /// Height the sleep chip adds under the artist.
  static double _sleepChipHeight(TextScaler scaler, AppTextStyles type) {
    final badge = type.badge;
    return AppSpacing.sm8 + 6 + scaler.scale(badge.fontSize!) * (badge.height ?? 1);
  }

  /// Distance from the bottom of the body to just above the title row in the
  /// regular layout, so the favourite confirmation never covers the heart.
  /// Sized for the tallest row: a two-line title over the artist.
  static double _snackMarginAboveInfo(TextScaler scaler, AppTextStyles type) {
    double line(TextStyle style) => scaler.scale(style.fontSize!) * (style.height ?? 1);
    final infoHeight = math.max(
      AppSpacing.minTouchTarget,
      2 * line(type.playerTitle) + AppSpacing.xs4 + line(type.body),
    );
    final seekBarHeight = AppSpacing.minTouchTarget + line(type.tabularFigures);
    return _kBodyBottomPadding +
        _kFooterHeight +
        _kFooterGap +
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
    // Never higher than half the screen: the root messenger also lays the
    // snackbar out in the app shell behind this sheet.
    final snackMargin = math.min(
      _snackMarginAboveInfo(textScaler, context.typography) +
          (sleepActive ? _sleepChipHeight(textScaler, context.typography) : 0),
      MediaQuery.sizeOf(context).height / 2,
    );

    Widget cover(double size) => _SwipeToSkip(
          itemId: item?.id,
          width: size,
          canSkipNext: canSkipNext,
          onNext: onNext,
          onPrevious: onPrevious,
          child: _NowPlayingArtwork(item: item, size: size),
        );

    Widget info(double snackBottomMargin) => _TrackInfo(
          item: item,
          snackBottomMargin: snackBottomMargin,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_bodyScrolls(context, constraints.maxHeight)) {
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
                    cover(artSize),
                    const SizedBox(height: _kArtworkGap),
                    info(_kScrollingSnackMargin),
                    const SizedBox(height: _kSectionGap),
                    seekBar,
                    const SizedBox(height: _kSectionGap),
                    controls,
                    const SizedBox(height: _kFooterGap),
                    footer,
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
                      return Center(child: cover(size));
                    },
                  ),
                ),
                const SizedBox(height: _kArtworkGap),
                info(snackMargin),
                const SizedBox(height: _kSectionGap),
                seekBar,
                const SizedBox(height: _kSectionGap),
                controls,
                const SizedBox(height: _kFooterGap),
                footer,
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

/// The big cover: 24 dp corners on the hard 6x6 dp Volt print offset (no
/// soft shadow), and the shared Hero tag.
class _NowPlayingArtwork extends StatelessWidget {
  final MediaItem? item;
  final double size;

  const _NowPlayingArtwork({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final palette = context.palette;
    // too small to be worth drawing (very short windows)
    if (size < AppSpacing.huge48) return SizedBox.square(dimension: size);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(_kArtworkRadius),
        boxShadow: [
          BoxShadow(color: palette.printShadow, offset: _kPrintOffset, blurRadius: 0),
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
                  decoration: BoxDecoration(gradient: palette.heroGradient),
                  child: Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      size: size * 0.32,
                      color: palette.primary,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Title and artist on the left, the favourite heart on the right.
class _TrackInfo extends StatelessWidget {
  final MediaItem? item;

  /// Where the favourite confirmation sits, measured from the bottom.
  final double snackBottomMargin;

  const _TrackInfo({
    required this.item,
    required this.snackBottomMargin,
  });

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final palette = context.palette;
    final type = context.typography;
    final title = item?.title ?? 'No track playing';
    final shownTitle = breakableTitle(title);
    return Row(
      children: [
        Expanded(
          // Title and artist are one stop for a screen reader.
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The one screen built to show the full name: two lines,
                // broken after "_" in file-style names rather than mid-word.
                Text(
                  shownTitle,
                  semanticsLabel: shownTitle == title ? null : title,
                  style: type.playerTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs4),
                Text(
                  item?.artist ?? 'Unknown artist',
                  style: type.body.copyWith(color: palette.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const _SleepChip(),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm8),
        if (item != null)
          _SingleNodeHeart(
            child: FavoriteFeedbackButton(
              key: ValueKey('fav_${item.id}'),
              itemId: item.id,
              isFavorite: item.isFavorite,
              size: 26,
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              snackBottomMargin: snackBottomMargin,
            ),
          )
        else
          const SizedBox(width: AppSpacing.minTouchTarget, height: AppSpacing.minTouchTarget),
      ],
    );
  }
}

/// [FavoriteFeedbackButton] names itself twice: a Semantics label around an
/// IconButton whose tooltip says the same thing. That label is not a node of
/// its own, so it merged into whatever held the button (here the sheet-sized
/// node read "title / artist / Add to Liked songs / 1:46 / 5:00"). Merged into
/// the button's node here, with the tooltip kept out of semantics (it still
/// shows on long-press), the heart is one button that is read once.
class _SingleNodeHeart extends StatelessWidget {
  final Widget child;

  const _SingleNodeHeart({required this.child});

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: TooltipTheme(
        data: TooltipTheme.of(context).copyWith(excludeFromSemantics: true),
        child: child,
      ),
    );
  }
}

/// Seek bar (docs/DESIGN.md 7.8 / 7.12) with the elapsed time at the left and
/// the remaining time ("-2:41") at the right. The track, thumb and overlay
/// come from the dark theme's slider: 4 dp (the played part 6), Volt on
/// #382664, a 14 dp thumb growing to 20 while dragged. Only this part listens
/// to the position stream, so the cover and the backdrop are not rebuilt
/// four times a second.
class _SeekBar extends ConsumerStatefulWidget {
  final Duration fallbackPosition;
  final Duration duration;

  const _SeekBar({super.key, required this.fallbackPosition, required this.duration});

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  /// Where the finger is (dragging), or where it let go (until the player
  /// catches up): the thumb never jumps back to the old time.
  double? _dragValue;
  bool _dragging = false;
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _release(double value) {
    _dragging = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_kSeekHoldMax, () {
      if (mounted && !_dragging) setState(() => _dragValue = null);
    });
    ref.read(playbackNotifierProvider.notifier).seek(Duration(milliseconds: value.toInt()));
    setState(() => _dragValue = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final figures = context.typography.tabularFigures;
    final positionAsync = ref.watch(throttledPositionStreamProvider);
    final position = positionAsync.value ?? widget.fallbackPosition;
    final duration = widget.duration;

    // Released: hold the thumb until the player reports a nearby time.
    final held = _dragValue;
    if (held != null &&
        !_dragging &&
        (position.inMilliseconds - held).abs() <= _kSeekSettleTolerance.inMilliseconds) {
      _dragValue = null;
      _holdTimer?.cancel();
    }

    final currentPositionMs = _dragValue ?? position.inMilliseconds.toDouble();
    final maxDurationMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue = currentPositionMs.clamp(0.0, maxDurationMs);
    final isDragging = _dragging;
    final elapsed = Duration(milliseconds: sliderValue.toInt());
    final remaining = duration.inMilliseconds > 0 ? '-${formatClock(duration - elapsed)}' : formatClock(Duration.zero);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: AppSpacing.minTouchTarget,
          // One node: "Playback position, 1:46 of 5:00, slider". Without
          // the name a screen reader read only the value.
          child: MergeSemantics(
            child: Semantics(
              label: 'Playback position',
              child: Slider(
                // track spans the full content width, aligned with the title
                padding: EdgeInsets.zero,
                min: 0.0,
                max: maxDurationMs,
                value: sliderValue,
                // "1:46 of 5:00": the slider says both times, so the labels
                // under it are left out and the position is read once.
                semanticFormatterCallback: (value) {
                  final at = formatClock(Duration(milliseconds: value.toInt()));
                  return duration.inMilliseconds > 0 ? '$at of ${formatClock(duration)}' : at;
                },
                onChangeStart: (val) {
                  _holdTimer?.cancel();
                  setState(() {
                    _dragging = true;
                    _dragValue = val;
                  });
                },
                onChanged: (val) {
                  setState(() {
                    _dragging = true;
                    _dragValue = val;
                  });
                },
                onChangeEnd: _release,
              ),
            ),
          ),
        ),
        // The slider's 48 dp box centres its track, which left the labels
        // closer to the play controls than to the bar they describe. Moved
        // up by paint only: layout, the slider's touch target and the
        // snackbar margin stay the same, and the labels let touches through
        // to the slider they now overlap.
        Transform.translate(
          offset: const Offset(0, -_kSeekLabelLift),
          child: IgnorePointer(
            // The slider's value already reads "elapsed of total".
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Text(
                    formatClock(elapsed),
                    style: figures.copyWith(color: isDragging ? palette.textPrimary : palette.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    remaining,
                    style: figures.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shuffle 48, previous 56, the 72 dp Volt disc, next 56, repeat 48.
class _TransportControls extends StatelessWidget {
  final bool isPlaying;
  final bool shuffle;
  final domain.PlaybackRepeatMode repeatMode;

  /// False on the last track with repeat off: Next is shown at 38 % and
  /// disabled, as in the mini player and the notification.
  final bool canSkipNext;
  final VoidCallback onShuffle;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onRepeat;

  const _TransportControls({
    required this.isPlaying,
    required this.shuffle,
    required this.repeatMode,
    required this.canSkipNext,
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
          VoltDisc(
            size: _kPlayButtonSize,
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: onPlayPause,
          ),
          _SkipButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next track',
            onPressed: canSkipNext ? onNext : null,
          ),
          _ModeToggleButton(
            icon: repeatMode == domain.PlaybackRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            active: repeatMode != domain.PlaybackRepeatMode.off,
            tooltip: 'Repeat mode: ${repeatMode.name}',
            onPressed: onRepeat,
          ),
        ],
      ),
    );
  }
}

/// Shuffle / repeat (docs/DESIGN.md 7.2): on is a primary glyph with a 4 dp
/// primary dot 2 dp under it; off is a textPrimary glyph, no dot.
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

  static const double _glyph = 24;
  static const double _dot = 4;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The glyph is centred in the 48 dp target; the dot starts 2 dp below it.
    const dotBottom = (AppSpacing.minTouchTarget - _glyph) / 2 - 2 - _dot;
    return SizedBox.square(
      dimension: AppSpacing.minTouchTarget,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            iconSize: _glyph,
            icon: Icon(icon, color: active ? palette.primary : palette.textPrimary),
            onPressed: onPressed,
          ),
          Positioned(
            bottom: dotBottom,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: MotionTokens.duration(context, MotionTokens.feedback),
                curve: MotionTokens.easeOut,
                child: Container(
                  width: _dot,
                  height: _dot,
                  decoration: BoxDecoration(
                    color: palette.primary,
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

/// Previous / next: 36 dp glyphs on a 56 dp target; 38 % while disabled.
class _SkipButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SkipButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IconButton(
      tooltip: tooltip,
      iconSize: 36,
      style: IconButton.styleFrom(
        foregroundColor: palette.textPrimary,
        disabledForegroundColor: palette.textPrimary.withValues(alpha: _kDisabledAlpha),
        minimumSize: const Size.square(56),
      ),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// Under the transport: playback speed at the start, Up next (the queue) at
/// the end.
class _StageFooter extends StatelessWidget {
  final double speed;
  final ValueChanged<double> onSpeed;
  final VoidCallback onQueue;
  final VoidCallback onSleep;

  const _StageFooter({required this.speed, required this.onSpeed, required this.onQueue, required this.onSleep});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, minHeight: _kFooterHeight),
      child: Row(
        children: [
          _SpeedMenu(speed: speed, onSelected: onSpeed),
          const Spacer(),
          _SleepButton(onPressed: onSleep),
          IconButton(
            tooltip: 'View Queue',
            icon: const Icon(Icons.queue_music_rounded),
            color: palette.textSecondary,
            onPressed: onQueue,
          ),
        ],
      ),
    );
  }
}

/// Speed picker. At 1x it is a plain speed icon; at any other speed the
/// button shows the speed itself in a small tinted chip, sized to stay
/// inside its own touch target.
class _SpeedMenu extends StatelessWidget {
  final double speed;
  final ValueChanged<double> onSelected;

  const _SpeedMenu({required this.speed, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final isNormal = speed == 1.0;
    return PopupMenuButton<double>(
      tooltip: 'Playback Speed',
      initialValue: speed,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      icon: isNormal
          ? Icon(Icons.speed_rounded, color: palette.textSecondary)
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
                  child: s == speed ? Icon(Icons.check_rounded, size: 18, color: palette.primary) : null,
                ),
                const SizedBox(width: AppSpacing.sm8),
                Text(
                  '${s}x',
                  style: type.tabularFigures.copyWith(
                    fontSize: 16,
                    height: 24 / 16,
                    color: s == speed ? palette.primary : palette.textPrimary,
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
    final palette = context.palette;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: palette.primary.withValues(alpha: 0.16),
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
          // the footer has a fixed height; grow only a little with the text
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
          style: context.typography.tabularFigures.copyWith(color: palette.primary),
        ),
      ),
    );
  }
}

/// A sideways swipe on the big cover skips (docs/DESIGN.md 7.17): left for
/// Next (only where Next is enabled), right for Previous. The cover follows
/// the finger, springs back, and when the song really changes the new cover
/// comes in a short way from the side it was pushed to. A shortcut for the
/// transport buttons, so it adds nothing to the semantics tree.
class _SwipeToSkip extends StatefulWidget {
  final String? itemId;

  /// The cover's edge: the swipe threshold and the slide are shares of it.
  final double width;
  final bool canSkipNext;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  const _SwipeToSkip({
    required this.itemId,
    required this.width,
    required this.canSkipNext,
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  @override
  State<_SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<_SwipeToSkip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  double _from = 0;
  double? _drag;
  int _pendingDirection = 0;
  String? _swipedFromId;
  DateTime _swipedAt = DateTime.fromMillisecondsSinceEpoch(0);

  double get _offset => _drag ?? _from * (1 - Curves.easeOutCubic.transform(_controller.value));

  double get _width => widget.width > 0 ? widget.width : MediaQuery.sizeOf(context).width;

  @override
  void didUpdateWidget(_SwipeToSkip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = widget.itemId != oldWidget.itemId && widget.itemId != _swipedFromId;
    if (_pendingDirection != 0 && changed) {
      final direction = _pendingDirection;
      _pendingDirection = 0;
      if (DateTime.now().difference(_swipedAt) <= _kCoverSwipeResultWindow) {
        _drag = null;
        _from = direction * _width * 0.25;
        _animate();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animate() {
    _controller.duration = MotionTokens.duration(context, const Duration(milliseconds: 220));
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  void _springBack() {
    setState(() {
      _from = _offset;
      _drag = null;
    });
    _animate();
  }

  void _onEnd(DragEndDetails details) {
    final drag = _drag ?? 0;
    final velocity = details.primaryVelocity ?? 0;
    final threshold = _width * _kCoverSwipeShare;
    if ((drag < -threshold || velocity < -_kCoverFlingVelocity) && widget.canSkipNext) {
      _commit(widget.onNext, enterFrom: 1);
    } else if (drag > threshold || velocity > _kCoverFlingVelocity) {
      _commit(widget.onPrevious, enterFrom: -1);
    } else {
      _springBack();
    }
  }

  void _commit(VoidCallback action, {required int enterFrom}) {
    HapticFeedback.selectionClick();
    _pendingDirection = enterFrom;
    _swipedFromId = widget.itemId;
    _swipedAt = DateTime.now();
    _springBack();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('now_playing_cover_swipe'),
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onHorizontalDragStart: (_) {
        _controller.stop();
        setState(() => _drag = _offset);
      },
      onHorizontalDragUpdate: (details) => setState(() => _drag = (_drag ?? 0) + (details.primaryDelta ?? 0)),
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _springBack,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final x = _offset;
          final width = math.max(1.0, _width);
          final fade = (1 - (x.abs() / width) * 0.8).clamp(0.4, 1.0);
          return Transform.translate(
            offset: Offset(x, 0),
            child: Opacity(opacity: fade, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// "12:30" (or "1:02:30") for the sleep timer's time left.
@visibleForTesting
String sleepCountdown(Duration remaining) {
  final total = remaining.inSeconds < 0 ? 0 : (remaining.inMilliseconds + 999) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// The overline chip under the artist while the sleep timer runs:
/// "SLEEP 12:30", or "SLEEP · END OF SONG" (docs/DESIGN.md 7.8).
class _SleepChip extends ConsumerWidget {
  const _SleepChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sleepTimerProvider);
    if (!status.isActive) return const SizedBox.shrink();
    final remaining = status.remaining;
    final text = status.endOfTrack
        ? 'SLEEP · END OF SONG'
        : remaining != null
            ? 'SLEEP ${sleepCountdown(remaining)}'
            : 'SLEEP';
    final spoken = status.endOfTrack
        ? 'Sleep timer: at the end of this song'
        : 'Sleep timer: ${remaining == null ? 'on' : sleepCountdown(remaining)} left';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm8),
      child: Semantics(
        label: spoken,
        excludeSemantics: true,
        child: PillTag(key: const ValueKey('sleep_chip'), text: text, icon: Icons.bedtime_rounded),
      ),
    );
  }
}

/// The footer's moon: the sleep timer sheet. Primary while a timer runs.
class _SleepButton extends ConsumerWidget {
  final VoidCallback onPressed;

  const _SleepButton({required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final active = ref.watch(sleepTimerProvider.select((s) => s.isActive));
    return IconButton(
      tooltip: active ? 'Sleep timer on' : 'Sleep timer',
      icon: Icon(active ? Icons.bedtime_rounded : Icons.bedtime_rounded),
      color: active ? palette.primary : palette.textSecondary,
      onPressed: onPressed,
    );
  }
}

/// The sleep timer sheet, in the app theme: the time left in `figureLarge`
/// while a timer runs, the presets, "End of song" and "Turn off".
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const SleepTimerSheet(),
  );
}

class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  static String presetLabel(Duration d) =>
      d.inMinutes >= 60 && d.inMinutes % 60 == 0 ? (d.inMinutes == 60 ? '1 hour' : '${d.inMinutes ~/ 60} hours') : '${d.inMinutes} minutes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.typography;
    final status = ref.watch(sleepTimerProvider);
    final notifier = ref.read(playbackNotifierProvider.notifier);
    final remaining = status.remaining;
    void done() => Navigator.of(context).maybePop();

    Widget option(String label, IconData icon, VoidCallback onTap, {bool selected = false}) {
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: selected ? palette.primary : palette.textSecondary),
                  const SizedBox(width: AppSpacing.lg16),
                  Expanded(
                    child: Text(
                      label,
                      style: type.body.copyWith(color: selected ? palette.primary : palette.textPrimary),
                    ),
                  ),
                  if (selected) Icon(Icons.check_rounded, size: 20, color: palette.primary),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.sm8),
              child: Semantics(
                header: true,
                child: Text('Sleep timer', style: type.sectionTitle),
              ),
            ),
            if (status.isActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.sm8, AppSpacing.sm8),
                child: Row(
                  children: [
                    Expanded(
                      child: status.endOfTrack
                          ? Text('Stops at the end of this song', style: type.body)
                          : Text(
                              remaining == null ? '' : sleepCountdown(remaining),
                              key: const ValueKey('sleep_countdown'),
                              style: type.figureLarge,
                              semanticsLabel:
                                  remaining == null ? null : '${sleepCountdown(remaining)} left',
                            ),
                    ),
                    TextButton(
                      onPressed: () {
                        notifier.cancelSleepTimer();
                        done();
                      },
                      child: const Text('Turn off'),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            for (final preset in SleepTimerStatus.presets)
              option(presetLabel(preset), Icons.timer_rounded, () {
                notifier.setSleepTimer(preset);
                done();
              }),
            option('End of song', Icons.music_note_rounded, () {
              notifier.setSleepTimerAtEndOfTrack();
              done();
            }, selected: status.endOfTrack),
          ],
        ),
      ),
    );
  }
}
