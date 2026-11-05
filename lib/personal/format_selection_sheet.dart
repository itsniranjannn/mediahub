import 'package:flutter/material.dart';
import 'extractor_backend.dart';

class FormatPreset {
  final String label;
  final String formatSelector;
  final String description;
  final bool isAudio;

  const FormatPreset({
    required this.label,
    required this.formatSelector,
    required this.description,
    required this.isAudio,
  });
}

class FormatSelectionSheet extends StatelessWidget {
  final ExtractorMetadata metadata;
  final void Function(FormatPreset preset) onSelect;

  const FormatSelectionSheet({
    super.key,
    required this.metadata,
    required this.onSelect,
  });

  static List<FormatPreset> getPresets(ExtractorMetadata meta) {
    return [
      const FormatPreset(
        label: 'Best Video & Audio (Auto)',
        formatSelector: 'bestvideo+bestaudio/best',
        description: 'Highest quality combined video and audio',
        isAudio: false,
      ),
      const FormatPreset(
        label: 'Balanced 720p',
        formatSelector: 'bestvideo[height<=720]+bestaudio/best[height<=720]',
        description: 'Standard HD video (faster download)',
        isAudio: false,
      ),
      const FormatPreset(
        label: 'Audio Only (Best Quality)',
        formatSelector: 'bestaudio/best',
        description: 'Extracts highest quality audio stream',
        isAudio: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final presets = getPresets(metadata);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF131720),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (metadata.thumbnailUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      metadata.thumbnailUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.video_library, size: 40),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (metadata.uploader.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          metadata.uploader,
                          style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Quality / Preset',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9E86FF),
              ),
            ),
            const SizedBox(height: 12),
            ...presets.map((preset) => Card(
                  color: const Color(0xFF1B202D),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF282F40)),
                  ),
                  child: ListTile(
                    leading: Icon(
                      preset.isAudio ? Icons.music_note : Icons.video_file,
                      color: const Color(0xFF9E86FF),
                    ),
                    title: Text(
                      preset.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      preset.description,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    trailing: const Icon(Icons.download, color: Colors.white70),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelect(preset);
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

