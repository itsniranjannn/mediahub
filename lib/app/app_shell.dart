import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reserved slot for future mini-player
          const SizedBox(
            key: ValueKey('mini_player_slot'),
            height: 0,
          ),
          _CustomBottomNavBar(
            currentIndex: navigationShell.currentIndex,
            onTap: _onTap,
          ),
        ],
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

const _navItems = [
  _NavItemData(
    label: 'Home',
    activeIcon: Icons.home_rounded,
    inactiveIcon: Icons.home_outlined,
  ),
  _NavItemData(
    label: 'Music',
    activeIcon: Icons.music_note_rounded,
    inactiveIcon: Icons.music_note_outlined,
  ),
  _NavItemData(
    label: 'Videos',
    activeIcon: Icons.video_library_rounded,
    inactiveIcon: Icons.video_library_outlined,
  ),
  _NavItemData(
    label: 'Downloads',
    activeIcon: Icons.file_download_rounded,
    inactiveIcon: Icons.file_download_outlined,
  ),
  _NavItemData(
    label: 'Settings',
    activeIcon: Icons.settings_rounded,
    inactiveIcon: Icons.settings_outlined,
  ),
];

class _CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CustomBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.divider,
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_navItems.length, (index) {
          final isSelected = index == currentIndex;
          final item = _navItems[index];
          final feedbackDuration =
              MotionTokens.duration(context, MotionTokens.feedback);

          return Expanded(
            child: Semantics(
              label: '${item.label} Tab',
              selected: isSelected,
              button: true,
              child: InkWell(
                onTap: () => onTap(index),
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: isSelected ? 1.1 : 1.0,
                        duration: feedbackDuration,
                        curve: MotionTokens.easeOut,
                        child: AnimatedContainer(
                          duration: feedbackDuration,
                          curve: MotionTokens.easeOut,
                          padding: const EdgeInsets.all(AppSpacing.xs4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected ? item.activeIcon : item.inactiveIcon,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textMuted,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs4),
                      AnimatedDefaultTextStyle(
                        duration: feedbackDuration,
                        curve: MotionTokens.easeOut,
                        style: AppTypography.label.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textMuted,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
