import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../shared/widgets/empty_state_widget.dart';

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
      ),
      body: const EmptyStateWidget(
        icon: Icons.video_library_outlined,
        title: 'Video Library',
        message: 'Your video collection in ${AppConfig.appName} will appear here.',
      ),
    );
  }
}
