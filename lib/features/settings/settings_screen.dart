import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../shared/widgets/empty_state_widget.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: const EmptyStateWidget(
        icon: Icons.settings_outlined,
        title: 'Settings',
        message: 'Configure your ${AppConfig.appName} preferences.',
      ),
    );
  }
}
