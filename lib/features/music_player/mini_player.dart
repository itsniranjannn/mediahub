import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/ink_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/media_context_menu.dart';
import 'music_audio_handler.dart';
import 'now_playing_sheet.dart';
import 'playback_notifier.dart';

/// The mini player row of the Ink Dock (docs/DESIGN.md 7.7): 64 dp, 12 dp
/// start and 4 dp end padding.
const double _kRowHeight = InkDock.miniPlayerHeight;
const double _kArtworkSize = 44;
const double _kSkipGlyph = 28;
const double _kProgressHeight = 2;

/// The progress line stays on the straight part of the dock's top edge.
const double _kProgressInset = InkDock.topRadius;

/// Opacity of a control with nowhere to go (Next on the last track with
/// repeat off).
const double _kDisabledAlpha = 0.38;

/// The mini player: the top row of the Ink Dock, ink in both themes.
///
/// Inside the app shell's [InkDock] it draws no fill of its own (the dock
/// does, with its blur and top line). Shown anywhere else it brings its own
/// dock slab and dark theme, so it looks the same wherever it sits.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.hideExternal = false});

  /// Hides the YouTube card (and the paused local track under it). The app
  /// shell no longer sets it: on the Videos and Online tabs it folds the
  /// whole mini player away instead (AppShell.hidesMiniPlayer).
  final bool hideExternal;

  @visibleForTesting
  static bool isNowPlayingOpen = false;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

/// How long after a swipe a song change still counts as its result (and
/// slides in); later changes (the song ending) just appear.
const Duration _kSwipeResultWindow = Duration(seconds: 2);

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Runs the row's horizontal offset from [_animateFrom] back to 0: the
  /// spring back after a swipe, or the new song sliding in.
  late AnimationController _slideController;
  double _animateFrom = 0.0;

  /// The finger's offset while dragging (null when not dragging).
  double? _dragExtent;

  /// A committed swipe waiting for its song change: the side the new song
  /// comes in from (-1 left, 1 right), the song it left and when.
  int _pendingDirection = 0;
  String? _swipedFromId;
  DateTime _swipedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
  }

  /// The row's horizontal offset right now, in logical pixels.
  double get _offsetX {
    final drag = _dragExtent;
    if (drag != null) return drag;
    return _animateFrom * (1 - Curves.easeOutCubic.transform(_slideController.value));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  /// The context sheets open from: the navigator's own, outside the dock's
  /// dark theme, so Now Playing's queue and media sheets (and this row's
  /// long-press sheet) follow the app theme (DESIGN.md 7.8).
  BuildContext _sheetContext(BuildContext context) => Navigator.maybeOf(context)?.context ?? context;

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
    final sheetContext = _sheetContext(context);
    showModalBottomSheet(
      context: sheetContext,
      isScrollControlled: true,
      // Full height, under the status bar too, so the stage's light status
      // bar icons apply (DESIGN.md 7.8); Now Playing keeps its own content
      // inside the safe area.
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      // Now Playing draws its own rounded top and grabber.
      showDragHandle: false,
      sheetAnimationStyle: AnimationStyle(
        duration: sheetDuration,
        reverseDuration: sheetDuration,
      ),
      // useSafeArea: false also strips the top inset from MediaQuery, which
      // put the header under the status bar; give the real inset back.
      builder: (_) => RestoreTopInset(source: sheetContext, child: const NowPlayingSheet()),
    ).whenComplete(() {
      MiniPlayer.isNowPlayingOpen = false;
    });
  }

  void _openMediaSheet(BuildContext context, MediaItem item) {
    HapticFeedback.selectionClick();
    // The sheet follows the app theme (navigator context); a wide-screen
    // popup hangs from the mini player row itself.
    MediaContextMenu.show(_sheetContext(context), ref, item, anchorContext: context);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _slideController.stop();
    setState(() => _dragExtent = _offsetX);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent = (_dragExtent ?? 0.0) + (details.primaryDelta ?? 0.0);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details, double screenWidth) {
    final threshold = screenWidth * 0.3;
    final velocity = details.primaryVelocity ?? 0.0;
    final drag = _dragExtent ?? 0.0;
    final notifier = ref.read(playbackNotifierProvider.notifier);
    final canNext = ref.read(canSkipNextProvider);

    if ((drag < -threshold || velocity < -500) && canNext) {
      // Swiped left -> skip to next; the next song comes in from the right.
      HapticFeedback.selectionClick();
      _commitSwipe(() => notifier.skipToNext(), enterFrom: 1);
    } else if (drag > threshold || velocity > 500) {
      // Swiped right -> previous (or a restart); it comes in from the left.
      HapticFeedback.selectionClick();
      _commitSwipe(() => notifier.skipToPrevious(), enterFrom: -1);
    } else {
      // Spring back (also a swipe towards a disabled Next).
      _springBack();
    }
  }

  void _handleHorizontalDragCancel() => _springBack();

  /// The row returns from wherever it is to its place.
  void _springBack() {
    setState(() {
      _animateFrom = _offsetX;
      _dragExtent = null;
    });
    _slideController.forward(from: 0.0);
  }

  /// The row springs back at once; if the song really changes (a Previous
  /// past the first seconds only restarts it), the new one slides in.
  void _commitSwipe(VoidCallback action, {required int enterFrom}) {
    _pendingDirection = enterFrom;
    _swipedFromId = ref.read(currentMediaItemProvider)?.id;
    _swipedAt = DateTime.now();
    _springBack();
    action();
  }

  void _onSongChanged(MediaItem? previous, MediaItem? next) {
    if (_pendingDirection == 0 || next == null || next.id == _swipedFromId) return;
    final direction = _pendingDirection;
    _pendingDirection = 0;
    if (DateTime.now().difference(_swipedAt) > _kSwipeResultWindow || !mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    setState(() {
      _dragExtent = null;
      _animateFrom = direction * width;
    });
    _slideController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // While the Online tab's YouTube page owns the media session, the row
    // shows (and controls) it instead of the paused local track.
    final external = ref.watch(externalMediaProvider);
    ref.listen<MediaItem?>(currentMediaItemProvider, _onSongChanged);
    final Widget Function(BuildContext context) row;
    if (external != null) {
      if (widget.hideExternal) return const SizedBox.shrink();
      row = (context) => _ExternalMiniPlayer(media: external);
    } else {
      final currentItem = ref.watch(currentMediaItemProvider);
      // Hide when queue is empty or no item
      if (currentItem == null) return const SizedBox.shrink();
      final isPlaying = ref.watch(isPlayingProvider);
      final canNext = ref.watch(canSkipNextProvider);
      row = (context) => _buildLocal(context, currentItem, isPlaying: isPlaying, canNext: canNext);
    }

    final inDock = context.findAncestorWidgetOfExactType<InkDock>() != null;
    if (inDock) return row(context);
    return _StandaloneDock(builder: row);
  }

  /// The local track's row. [context] is inside the dock's dark theme.
  Widget _buildLocal(
    BuildContext context,
    MediaItem currentItem, {
    required bool isPlaying,
    required bool canNext,
  }) {
    final notifier = ref.read(playbackNotifierProvider.notifier);
    final palette = context.palette;
    final type = context.typography;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final artist = currentItem.artist ?? 'Unknown artist';

    // One node for the row, read once: what is playing, a tap that opens Now
    // Playing and a long press for the song's sheet. The cover, texts and
    // progress line are left out (the line used to put its percentage in
    // front of the label and the title was read twice); Previous / Play /
    // Next stay their own buttons. The swipes are shortcuts for those
    // buttons, so the detector itself adds nothing to the tree.
    return Semantics(
      container: true,
      button: true,
      label: 'Mini player: ${currentItem.title} by $artist',
      hint: 'Opens Now Playing',
      onTap: () => _openNowPlaying(context),
      onLongPressHint: 'Song options',
      onLongPress: () => _openMediaSheet(context, currentItem),
      child: GestureDetector(
        key: const ValueKey('mini_player_gesture_detector'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => _openNowPlaying(context),
        onLongPress: () => _openMediaSheet(context, currentItem),
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(details, screenWidth),
        onHorizontalDragCancel: _handleHorizontalDragCancel,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
            _openNowPlaying(context);
          }
        },
        // The row clips, so swiped content slides in from the dock's edge.
        child: ClipRect(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _kRowHeight),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _slideController,
                  builder: (context, child) => Transform.translate(
                    key: const ValueKey('mini_player_slide'),
                    offset: Offset(_offsetX, 0),
                    child: child,
                  ),
                  child: RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md12,
                        10,
                        AppSpacing.xs4,
                        10,
                      ),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Hero(
                              tag: 'now_playing_artwork',
                              child: ArtworkThumbnail(
                                uri: currentItem.uri,
                                artworkPath: currentItem.artworkPath,
                                size: _kArtworkSize,
                                borderRadius: AppSpacing.radiusArtSmall,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md12),

                          // Title & Artist (the row's label says both)
                          Expanded(
                            child: ExcludeSemantics(
                              child: _TitleLines(
                                title: Text(
                                  currentItem.title,
                                  style: _titleStyle(type, palette),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  artist,
                                  style: _artistStyle(type, palette),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs4),

                          // Previous / Play-Pause / Next
                          _DockSkipButton(
                            icon: Icons.skip_previous_rounded,
                            tooltip: 'Previous',
                            onPressed: () => notifier.skipToPrevious(),
                          ),
                          VoltDisc(
                            size: VoltDisc.small,
                            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            onPressed: () => notifier.togglePlayPause(),
                          ),
                          // The last track with repeat off has no next: shown at
                          // 38 % and disabled, as in Now Playing and the
                          // notification.
                          _DockSkipButton(
                            icon: Icons.skip_next_rounded,
                            tooltip: 'Next',
                            onPressed: canNext ? () => notifier.skipToNext() : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Along the dock's top edge, over its line. Decoration here;
                // Now Playing's seek bar reads the time.
                PositionedDirectional(
                  start: _kProgressInset,
                  end: _kProgressInset,
                  top: 0,
                  child: ExcludeSemantics(
                    child: _MiniProgressLine(durationMs: currentItem.durationMs),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _titleStyle(AppTextStyles type, AppPalette palette) =>
    type.bodyStrong.copyWith(fontSize: 15, height: 20 / 15, color: palette.onDock);

TextStyle _artistStyle(AppTextStyles type, AppPalette palette) =>
    type.metadata.copyWith(fontSize: 13, height: 18 / 13, color: palette.onDockMuted);

/// Puts the status bar inset back for a sheet shown with
/// `showModalBottomSheet(useSafeArea: false)`.
///
/// That flag lets the sheet paint under the status bar, but Flutter also
/// removes the top padding from the sheet's MediaQuery, so a SafeArea inside
/// it reads 0 and the header lands under the clock. [source] is a context
/// above the sheet route (the navigator's), whose MediaQuery still has the
/// real inset. Reading it does not register a dependency there; the sheet's
/// own MediaQuery changes with it (rotation, cutout), so this rebuilds then.
class RestoreTopInset extends StatelessWidget {
  const RestoreTopInset({super.key, required this.source, required this.child});

  final BuildContext source;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inner = MediaQuery.of(context);
    final outer = source.mounted ? source.getInheritedWidgetOfExactType<MediaQuery>()?.data : null;
    // Always the same tree shape (no early return), so an inset that comes
    // and goes never rebuilds Now Playing from scratch.
    return MediaQuery(
      data: inner.copyWith(
        padding: inner.padding.copyWith(top: math.max(inner.padding.top, outer?.padding.top ?? 0)),
        viewPadding: inner.viewPadding.copyWith(top: math.max(inner.viewPadding.top, outer?.viewPadding.top ?? 0)),
      ),
      child: child,
    );
  }
}

class _TitleLines extends StatelessWidget {
  final Widget title;
  final Widget subtitle;

  const _TitleLines({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [title, subtitle],
    );
  }
}

/// Previous / next in the dock: a 28 dp glyph on a 48 dp target, onDock, and
/// 38 % when there is nowhere to go.
class _DockSkipButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _DockSkipButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IconButton(
      icon: Icon(icon),
      iconSize: _kSkipGlyph,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: palette.onDock,
        disabledForegroundColor: palette.onDock.withValues(alpha: _kDisabledAlpha),
        highlightColor: palette.onDock.withValues(alpha: 0.12),
        minimumSize: const Size.square(AppSpacing.minTouchTarget),
      ),
      onPressed: onPressed,
    );
  }
}

/// 2 dp Volt line along the top edge of the dock, over its line. It is the
/// only part listening to the position stream, so the rest of the row stays
/// still.
class _MiniProgressLine extends ConsumerWidget {
  final int durationMs;

  const _MiniProgressLine({required this.durationMs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final positionAsync = ref.watch(throttledPositionStreamProvider);
    final safeDurationMs = durationMs > 0 ? durationMs : 1;
    final positionMs = positionAsync.value?.inMilliseconds ?? 0;
    final progress = (positionMs / safeDurationMs).clamp(0.0, 1.0);

    return LinearProgressIndicator(
      value: progress,
      minHeight: _kProgressHeight,
      borderRadius: BorderRadius.circular(_kProgressHeight / 2),
      // The dock is ink in both themes: primary is Volt here.
      color: palette.primary,
      backgroundColor: palette.dockLine,
    );
  }
}

/// The mini player away from the shell's [InkDock] (a preview, a test): the
/// same ink slab and dark theme the dock would give it.
class _StandaloneDock extends StatelessWidget {
  final WidgetBuilder builder;

  const _StandaloneDock({required this.builder});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: InkTheme.of(context),
      child: Builder(
        builder: (context) {
          final palette = context.palette;
          return Material(
            color: palette.dock,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(InkDock.topRadius)),
              side: BorderSide(color: palette.dockLine),
            ),
            clipBehavior: Clip.antiAlias,
            child: Builder(builder: builder),
          );
        },
      ),
    );
  }
}

/// The mini player while YouTube (the Online tab) owns the media session:
/// thumbnail, title, an accent "YOUTUBE" tag with the channel, play/pause
/// and, when the page has one, next. Tapping the row opens the Online tab.
/// The buttons go through the audio handler, which routes them to the page
/// (exactly what the notification does).
class _ExternalMiniPlayer extends ConsumerWidget {
  const _ExternalMiniPlayer({required this.media});

  final ExternalMediaSnapshot media;

  void _openOnline(BuildContext context) {
    GoRouter.maybeOf(context)?.go('/online');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.typography;
    final channel = media.artist;
    final art = media.artUri;
    final source = media.albumOrDefault;
    final fromOnline = media.id.startsWith('online:') || media.album == null;
    return Semantics(
      container: true,
      button: true,
      label: 'Mini player: $source: ${media.title}${channel == null ? '' : ' by $channel'}',
      // Only the Online tab's page is opened from here; another source (a
      // video in picture-in-picture) is on screen already.
      hint: fromOnline ? 'Opens Online' : null,
      onTap: fromOnline ? () => _openOnline(context) : null,
      child: GestureDetector(
        key: const ValueKey('mini_player_external'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: fromOnline ? () => _openOnline(context) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kRowHeight),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md12, 10, AppSpacing.xs4, 10),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusArtSmall),
                    child: SizedBox(
                      width: _kArtworkSize,
                      height: _kArtworkSize,
                      child: art == null
                          ? const _ExternalArtFallback()
                          : Image.network(
                              art.toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => const _ExternalArtFallback(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md12),
                Expanded(
                  child: ExcludeSemantics(
                    child: _TitleLines(
                      title: Text(
                        media.title,
                        style: _titleStyle(type, palette),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        children: [
                          PillTag(text: source.toUpperCase(), color: palette.accent),
                          if (channel != null) ...[
                            const SizedBox(width: AppSpacing.xs4 + 2),
                            Expanded(
                              child: Text(
                                channel,
                                style: _artistStyle(type, palette),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs4),
                VoltDisc(
                  size: VoltDisc.small,
                  icon: media.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  tooltip: media.playing ? 'Pause' : 'Play',
                  onPressed: () {
                    final handler = ref.read(audioHandlerProvider);
                    media.playing ? handler.pause() : handler.play();
                  },
                ),
                if (media.canSkipNext)
                  _DockSkipButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Next',
                    onPressed: () => ref.read(audioHandlerProvider).skipToNext(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalArtFallback extends StatelessWidget {
  const _ExternalArtFallback();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.surfacePressed,
      child: Center(child: Icon(Icons.smart_display_rounded, color: palette.textSecondary)),
    );
  }
}
