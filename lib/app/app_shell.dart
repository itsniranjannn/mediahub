import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/platform/device_controls.dart';
import '../core/platform_info.dart';
import '../domain/models/download_state.dart';
import '../features/downloads/downloads_notifier.dart';
import '../features/music_player/mini_player.dart';
import '../features/music_player/playback_notifier.dart';
import '../shared/widgets/shared_label_scale.dart';
import '../shared/widgets/ui_kit.dart';
import 'theme/app_palette.dart';
import 'theme/app_spacing.dart';
import 'theme/app_typography.dart';
import 'theme/motion_tokens.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({
    super.key,
    required this.navigationShell,
  });

  /// Branch index of the Videos tab.
  static const int videosBranchIndex = 2;

  /// Branch index of the Online (YouTube) tab.
  static const int onlineBranchIndex = 3;

  /// The tabs that show video themselves (Videos and Online): the mini
  /// player steps aside there, so the whole screen is theirs. The music
  /// keeps playing and stays in the notification; the mini player comes
  /// back on the other tabs.
  static bool hidesMiniPlayer(int branchIndex) =>
      branchIndex == videosBranchIndex || branchIndex == onlineBranchIndex;

  void _onTap(int index) {
    if (index != navigationShell.currentIndex) HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Predictive back / Back navigation handling
    // If not on Home (index 0), back button goes to Home
    // If already on Home, back exits app
    return _PlaybackMessages(
      child: PopScope(
        canPop: navigationShell.currentIndex == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && navigationShell.currentIndex != 0) {
            _onTap(0);
          }
        },
        // In picture-in-picture the small window shows only the page's video:
        // no mini player and no navigation bar (they come back on exit).
        child: ValueListenableBuilder<bool>(
          valueListenable: DeviceControls.inPip,
          builder: (context, inPip, body) => Scaffold(
            body: body,
            // The Ink Dock (DESIGN.md 7.7): the mini player and the nav on one
            // ink slab in both themes. InkDock wraps them in the dark theme and
            // keeps the Android navigation bar's icons light over it. The body
            // ends above the dock (no extendBody), so no screen has to pad its
            // last row clear of it.
            bottomNavigationBar: inPip
                ? null
                : InkDock(
                    // Persistent mini-player above the bottom nav, except on
                    // the Videos and Online tabs (see [hidesMiniPlayer]).
                    miniPlayer: _MiniPlayerSlot(
                      hidden: hidesMiniPlayer(navigationShell.currentIndex),
                      child: const MiniPlayer(key: ValueKey('mini_player_slot')),
                    ),
                    navigation: _InkNavBar(
                      currentIndex: navigationShell.currentIndex,
                      onTap: _onTap,
                    ),
                  ),
          ),
          child: navigationShell,
        ),
      ),
    );
  }
}

/// Shows the music player's own messages ("Can't play \"Song\"", when a song
/// is missing or broken and the player moves on) as a snackbar.
///
/// It listens to the handler's stream itself rather than to
/// playbackErrorStreamProvider: Riverpod drops a value equal to the last
/// one, so the same song failing twice would show only once.
class _PlaybackMessages extends ConsumerStatefulWidget {
  const _PlaybackMessages({required this.child});

  final Widget child;

  @override
  ConsumerState<_PlaybackMessages> createState() => _PlaybackMessagesState();
}

class _PlaybackMessagesState extends ConsumerState<_PlaybackMessages> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    try {
      _sub = ref.read(audioHandlerProvider).errorEvents.listen(_show);
    } catch (_) {
      // No music player (widget tests that leave it out): nothing to show.
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The mini-player row of the dock, folded away on the Videos and Online
/// tabs. It slides down behind the navigation (and back up) in 240 ms
/// (instant with reduced motion), so the dock and the page above it change
/// height smoothly instead of jumping. While folded it takes no taps, is
/// not read by screen readers and runs no animations; the mini player stays
/// built, so it comes back at once with whatever is playing.
class _MiniPlayerSlot extends StatelessWidget {
  const _MiniPlayerSlot({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      key: const ValueKey('mini_player_fold'),
      child: AnimatedAlign(
        duration: MotionTokens.duration(context, MotionTokens.page),
        curve: MotionTokens.emphasized,
        alignment: Alignment.topCenter,
        heightFactor: hidden ? 0 : 1,
        child: IgnorePointer(
          ignoring: hidden,
          child: ExcludeSemantics(
            excluding: hidden,
            child: TickerMode(enabled: !hidden, child: child),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;

  /// Shows the active-downloads count dot.
  final bool downloads;

  const _NavItemData({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
    this.downloads = false,
  });
}

List<_NavItemData> get _navItems {
  return [
    const _NavItemData(
      label: 'Home',
      activeIcon: Icons.home_rounded,
      inactiveIcon: Icons.home_outlined,
    ),
    const _NavItemData(
      label: 'Music',
      activeIcon: Icons.music_note_rounded,
      inactiveIcon: Icons.music_note_outlined,
    ),
    const _NavItemData(
      label: 'Videos',
      activeIcon: Icons.video_library_rounded,
      inactiveIcon: Icons.video_library_outlined,
    ),
    const _NavItemData(
      label: 'Online',
      activeIcon: Icons.smart_display_rounded,
      inactiveIcon: Icons.smart_display_outlined,
    ),
    if (PlatformInfo.supportsDownloads)
      const _NavItemData(
        label: 'Downloads',
        activeIcon: Icons.file_download_rounded,
        inactiveIcon: Icons.file_download_outlined,
        downloads: true,
      ),
  ];
}

/// The dock's navigation (DESIGN.md 7.7): 64 dp plus the system inset, every
/// label shown. The selected tab sits in a 56x32 Volt pill with a filled ink
/// icon and an onDock label; the others are outline icons and labels in
/// onDockMuted.
///
/// Drawn here rather than with [NavigationBar], whose indicator is a fixed
/// 64x32 that fades in on each tab: this one is the spec's 56x32 and slides
/// from tab to tab (240 ms, [MotionTokens.emphasized]; instant with reduced
/// motion). It lives in the always-ink dock, so the Volt pill needs no ink
/// edge.
class _InkNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _InkNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  static const double height = InkDock.navigationHeight;
  static const Size indicatorSize = Size(56, 32);

  /// The pill's distance from the top of the bar: 6 + 32 + 4 + 16 + 6 = 64.
  static const double indicatorTop = 6;
  static const double labelGap = 4;

  @override
  Widget build(BuildContext context) {
    final items = _navItems;
    final palette = context.palette;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final selected = currentIndex.clamp(0, items.length - 1);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      // Grows with large text instead of clipping the labels.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / items.length;
            // One size for all five labels: when one has to shrink to fit
            // its slot (320 dp at large text), they all shrink with it.
            final labelScaler = sharedLabelScaler(
              context,
              labels: [for (final item in items) item.label],
              style: context.typography.label,
              maxWidth: slot - AppSpacing.xs4,
            );
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: MotionTokens.duration(context, MotionTokens.page),
                  curve: MotionTokens.emphasized,
                  top: indicatorTop,
                  left: slot * selected + (slot - indicatorSize.width) / 2,
                  width: indicatorSize.width,
                  height: indicatorSize.height,
                  child: DecoratedBox(
                    key: const ValueKey('nav_indicator'),
                    decoration: ShapeDecoration(color: palette.navIndicator, shape: const StadiumBorder()),
                  ),
                ),
                // Ink for the splashes: the dock's fill would hide the
                // scaffold's own.
                Material(
                  type: MaterialType.transparency,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavDestination(
                            item: items[i],
                            selected: i == selected,
                            labelScaler: labelScaler,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavDestination extends StatelessWidget {
  final _NavItemData item;
  final bool selected;
  final TextScaler labelScaler;
  final VoidCallback onTap;

  const _NavDestination({
    required this.item,
    required this.selected,
    required this.labelScaler,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final icon = Icon(
      selected ? item.activeIcon : item.inactiveIcon,
      color: selected ? palette.onNavIndicator : palette.onDockMuted,
      size: 24,
    );

    return Semantics(
      label: '${item.label} Tab',
      selected: selected,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightShape: BoxShape.circle,
        highlightColor: Colors.transparent,
        splashColor: palette.onDock.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs4 / 2,
            _InkNavBar.indicatorTop,
            AppSpacing.xs4 / 2,
            _InkNavBar.indicatorTop,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.fromSize(
                size: _InkNavBar.indicatorSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    icon,
                    if (item.downloads)
                      const PositionedDirectional(top: 0, start: 34, child: _DownloadsBadge()),
                  ],
                ),
              ),
              const SizedBox(height: _InkNavBar.labelGap),
              // One line at every text size, at the size all five labels
              // share ([labelScaler]); the FittedBox only guards against
              // sub-pixel rounding (five tabs on 320 dp never wrap or clip).
              ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: labelScaler,
                    style: type.label.copyWith(color: selected ? palette.onDock : palette.onDockMuted),
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

/// While downloads run: a 16 dp Ice dot with the count in ink DM Mono 11/16
/// on the Downloads icon (DESIGN.md 7.7).
class _DownloadsBadge extends ConsumerWidget {
  const _DownloadsBadge();

  /// Waiting or running; paused, finished and failed ones do not count.
  static final Set<String> _active = {
    DownloadTaskState.queued.name,
    DownloadTaskState.preparing.name,
    DownloadTaskState.downloading.name,
    DownloadTaskState.finalizing.name,
  };

  static const double size = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      downloadsStreamProvider.select(
        (async) => async.value?.where((d) => _active.contains(d.state)).length ?? 0,
      ),
    );
    if (count <= 0) return const SizedBox.shrink();

    final palette = context.palette;
    final label = count > 9 ? '9+' : '$count';
    return Semantics(
      label: count == 1 ? '1 download running' : '$count downloads running',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: size, minHeight: size),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: ShapeDecoration(color: palette.accent, shape: const StadiumBorder()),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            // The dot stays a dot: it grows only a little with the text.
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
            style: context.typography.badge.copyWith(
              fontSize: 11,
              height: 16 / 11,
              letterSpacing: 0,
              color: palette.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}
