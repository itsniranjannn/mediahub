import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../shared/widgets/empty_state_widget.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: const EmptyStateWidget(
        icon: Icons.file_download_outlined,
        title: 'Downloads',
        message: 'Active and completed downloads in ${AppConfig.appName} will appear here.',
      ),
    );
  }
}
