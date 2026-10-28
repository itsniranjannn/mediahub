import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../shared/widgets/empty_state_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
      ),
      body: const EmptyStateWidget(
        icon: Icons.home_outlined,
        title: 'Home',
        message: 'Welcome to ${AppConfig.appName}. Your media dashboard is ready.',
      ),
    );
  }
}
