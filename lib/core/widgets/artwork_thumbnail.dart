import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../services/artwork_service.dart';

class ArtworkThumbnail extends StatelessWidget {
  final String uri;
  final double size;
  final double borderRadius;
  final IconData placeholderIcon;

  const ArtworkThumbnail({
    super.key,
    required this.uri,
    this.size = 48,
    this.borderRadius = AppSpacing.buttonRadius,
    this.placeholderIcon = Icons.music_note_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: AppColors.surface,
        child: FutureBuilder<Uint8List?>(
          future: ArtworkService.instance.getArtwork(
            uri,
            size: size > 150 ? 512 : 256,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
              );
            }
            return Icon(
              placeholderIcon,
              color: AppColors.primary,
              size: size * 0.5,
            );
          },
        ),
      ),
    );
  }
}

