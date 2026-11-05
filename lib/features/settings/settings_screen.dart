import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import 'settings_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumeOnReconnect = ref.watch(resumeOnHeadphonesReconnectProvider);
    final resumeNotifier = ref.read(resumeOnHeadphonesReconnectProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg16,
              vertical: AppSpacing.sm8,
            ),
            child: Text(
              'Audio & Headset',
              style: AppTypography.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Resume when headphones reconnect'),
            subtitle: const Text(
              'Auto-resume playback if headphones reconnect within 10 minutes of being disconnected.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            value: resumeOnReconnect,
            onChanged: (_) => resumeNotifier.toggle(),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg16,
              vertical: AppSpacing.sm8,
            ),
            child: Text(
              'Troubleshooting',
              style: AppTypography.label.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Diagnostics Log'),
            subtitle: const Text(
              'View bounded in-app event history, audio focus, and player transitions.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              context.push('/diagnostics');
            },
          ),
        ],
      ),
    );
  }
}
