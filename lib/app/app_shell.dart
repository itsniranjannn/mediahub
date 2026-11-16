import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/platform_info.dart';
import '../features/music_player/mini_player.dart';
import '../shared/widgets/ui_kit.dart';
import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_typography.dart';
import 'theme/motion_tokens.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({
    super.key,
    required this.navigationShell,
  });

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
    return PopScope(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && navigationShell.currentIndex != 0) {
          _onTap(0);
        }
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Persistent mini-player above the bottom nav
            const MiniPlayer(
              key: ValueKey('mini_player_slot'),
            ),
            _CustomBottomNavBar(
              currentIndex: navigationShell.currentIndex,
              onTap: _onTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;

  const _NavItemData({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
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
      label: 'Explore',
      activeIcon: Icons.travel_explore_rounded,
      inactiveIcon: Icons.travel_explore_outlined,
    ),
    if (PlatformInfo.supportsDownloads)
      const _NavItemData(
        label: 'Downloads',
        activeIcon: Icons.file_download_rounded,
        inactiveIcon: Icons.file_download_outlined,
      ),
  ];
}

class _CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CustomBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = _navItems;
    final feedbackDuration = MotionTokens.duration(context, MotionTokens.feedback);

    return GlassContainer(
      border: const Border(top: BorderSide(color: AppColors.divider)),
      child: Padding(
        padding: EdgeInsets.only(
          top: AppSpacing.sm8,
          bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xs4,
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final isSelected = index == currentIndex;
            final item = items[index];

            return Expanded(
              child: Semantics(
                label: '${item.label} Tab',
                selected: isSelected,
                button: true,
                child: InkResponse(
                  onTap: () => onTap(index),
                  radius: 36,
                  highlightShape: BoxShape.circle,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pill indicator behind the icon, like Material 3 navigation.
                      AnimatedContainer(
                        duration: feedbackDuration,
                        curve: MotionTokens.easeOut,
                        width: isSelected ? 56 : 40,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          isSelected ? item.activeIcon : item.inactiveIcon,
                          color: isSelected ? AppColors.primary : AppColors.textMuted,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: feedbackDuration,
                        curve: MotionTokens.easeOut,
                        style: AppTypography.label.copyWith(
                          fontSize: 11,
                          color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
