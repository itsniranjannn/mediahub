import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import 'online_models.dart';

/// Quality picker used when the yt-dlp downloader is not available (iOS, or
/// switched off): lists the ready-made streams YouTube offers directly.
class OnlineStreamSheet extends StatelessWidget {
  final OnlineVideo video;
  final OnlineStreams streams;
  final void Function(OnlineStream stream) onSelect;

  const OnlineStreamSheet({
    super.key,
    required this.video,
    required this.streams,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final videos = [...streams.video]..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    final audio = streams.bestAudio;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.xxl24),
          children: [
            Text(video.title, style: AppTypography.sectionTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(video.author, style: AppTypography.metadata),
            if (videos.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl20),
              Text('Video (with sound)', style: AppTypography.label.copyWith(color: AppColors.primary)),
              const SizedBox(height: AppSpacing.sm8),
              for (final s in videos) _tile(context, Icons.videocam_rounded, s.label, s),
            ],
            if (audio != null) ...[
              const SizedBox(height: AppSpacing.lg16),
              Text('Audio only', style: AppTypography.label.copyWith(color: AppColors.primary)),
              const SizedBox(height: AppSpacing.sm8),
              _tile(context, Icons.music_note_rounded, 'Best audio (${audio.label})', audio),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, OnlineStream stream) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: AppTypography.bodyStrong),
        subtitle: Text(
          '${stream.container.toUpperCase()} • ${stream.sizeBytes > 0 ? formatFileSize(stream.sizeBytes) : 'size unknown'}',
          style: AppTypography.metadata,
        ),
        trailing: const Icon(Icons.download_rounded),
        onTap: () {
          Navigator.of(context).pop();
          onSelect(stream);
        },
      ),
    );
  }
}
