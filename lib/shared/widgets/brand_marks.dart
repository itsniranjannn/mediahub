// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/core_watermark.dart';

/// The MediaHub brand marks: the launch-screen logo, the wordmark and the
/// author's line. Only bundled fonts: Fraunces for the wordmark, DM Mono in
/// spaced capitals (a small-caps look) for the author.

/// The app icon as the launch screen shows it (the crimson play-bolt on the
/// near-black-to-wine field), from `assets/brand/mediahub_mark.png`, a
/// 144 px copy of `assets/icon/app_icon.png`.
class MediaHubLogo extends StatelessWidget {
  const MediaHubLogo({super.key, this.size = 36});

  static const String asset = 'assets/brand/mediahub_mark.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.26),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        // A missing asset (some tests) never breaks the strip.
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: const Color(0xFF4A0F24),
          child: Icon(Icons.play_arrow_rounded, size: size * 0.6, color: const Color(0xFFCC324C)),
        ),
      ),
    );
  }
}

/// "MediaHub" set in Fraunces: "Media" in the text colour, "Hub" a weight
/// heavier in the brand primary, tightly tracked like a logotype.
class MediaHubWordmark extends StatelessWidget {
  const MediaHubWordmark({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = TextStyle(
      fontFamily: AppTypography.fraunces,
      fontFamilyFallback: AppTypography.headingFallback,
      fontSize: fontSize,
      height: 1.1,
      letterSpacing: -0.02 * fontSize,
      fontWeight: FontWeight.w600,
      color: palette.textPrimary,
    );
    const name = AppConfig.appName;
    final split = name.endsWith('Hub') ? name.length - 3 : name.length;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: name.substring(0, split)),
          TextSpan(
            text: name.substring(split),
            style: TextStyle(fontWeight: FontWeight.w700, color: palette.primary),
          ),
        ],
      ),
      semanticsLabel: name,
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// The author's line: a tiny spaced kicker over the name in spaced DM Mono
/// capitals. [CoreWatermark] supplies the name (the integrity check relies
/// on these reads staying in the app).
class AuthorMark extends StatelessWidget {
  const AuthorMark({super.key, this.kicker = 'Crafted by', this.full = true, this.alignEnd = false});

  /// The short line above the name ('' for none).
  final String kicker;

  /// [CoreWatermark.fullName] when true, else [CoreWatermark.author].
  final bool full;

  /// Right-aligned (the end of the footer strip).
  final bool alignEnd;

  /// The name line on its own, for one-line bylines (Home).
  static TextStyle nameStyle(AppPalette palette, {double fontSize = 11, Color? color}) => TextStyle(
        fontFamily: AppTypography.dmMono,
        fontFamilyFallback: AppTypography.readingFallback,
        fontSize: fontSize,
        height: 1.3,
        letterSpacing: 0.18 * fontSize,
        fontWeight: FontWeight.w500,
        color: color ?? palette.textSecondary,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = full ? CoreWatermark.fullName : CoreWatermark.author;
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (kicker.isNotEmpty)
            Text(
              kicker.toUpperCase(),
              style: nameStyle(palette, fontSize: 9, color: palette.textMuted),
              maxLines: 1,
            ),
          Text(
            name.toUpperCase(),
            semanticsLabel: name,
            style: nameStyle(palette, fontSize: 12, color: palette.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
