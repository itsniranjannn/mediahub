import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../shared/widgets/empty_state_widget.dart';

class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
      ),
      body: const EmptyStateWidget(
        icon: Icons.music_note_outlined,
        title: 'Music Library',
        message: 'Your music collection in ${AppConfig.appName} will appear here.',
      ),
    );
  }
}
