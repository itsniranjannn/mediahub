// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_typography.dart';
import '../../core/app_config.dart';
import '../../core/core_watermark.dart';

/// The MediaHub brand marks: the launch-screen logo, the wordmark and the
/// author's signature. Only bundled fonts: Fraunces for the wordmark, Great
/// Vibes (a script face) for the author's name.

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

/// The author's signature: a small italic Fraunces "Crafted by" over the
/// name set in Great Vibes (a script face) and painted with the brand
/// gradient, like a signature under a letter. [CoreWatermark] supplies the
/// name (the integrity check relies on these reads staying in the app).
class AuthorMark extends StatelessWidget {
  const AuthorMark({super.key, this.kicker = 'Crafted by', this.full = true, this.nameSize = 24, this.inline = false});

  /// The small line before the name ('' for none).
  final String kicker;

  /// [CoreWatermark.fullName] when true, else [CoreWatermark.author].
  final bool full;

  /// The signature's font size (Great Vibes is small on its em: 24 reads
  /// like 15 pt Poppins).
  final double nameSize;

  /// The kicker beside the name on one line (Home's "by Niranjan") instead
  /// of above it.
  final bool inline;

  /// The kicker: Fraunces, slanted, quiet.
  static TextStyle kickerStyle(AppPalette palette, {double fontSize = 11}) => TextStyle(
        fontFamily: AppTypography.fraunces,
        fontFamilyFallback: AppTypography.headingFallback,
        fontSize: fontSize,
        height: 1.2,
        letterSpacing: 0.02 * fontSize,
        fontWeight: FontWeight.w600,
        fontStyle: FontStyle.italic,
        color: palette.textMuted,
      );

  /// The signature itself (painted by [AuthorMark] with the brand gradient).
  static TextStyle signatureStyle(AppPalette palette, {double fontSize = 24}) => TextStyle(
        fontFamily: AppTypography.signature,
        fontFamilyFallback: AppTypography.headingFallback,
        fontSize: fontSize,
        height: 1.15,
        fontWeight: FontWeight.w400,
        color: palette.primary,
      );

  /// The brand gradient the signature is painted with.
  static LinearGradient signatureGradient(AppPalette palette) => LinearGradient(
        colors: [palette.primary, Color.lerp(palette.primary, palette.accent, 0.55)!],
      );

  /// Small mono print (the version number).
  static TextStyle nameStyle(AppPalette palette, {double fontSize = 11, Color? color}) => TextStyle(
        fontFamily: AppTypography.dmMono,
        fontFamilyFallback: AppTypography.readingFallback,
        fontSize: fontSize,
        height: 1.3,
        letterSpacing: 0.06 * fontSize,
        fontWeight: FontWeight.w500,
        color: color ?? palette.textSecondary,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = full ? CoreWatermark.fullName : CoreWatermark.author;
    final gradient = signatureGradient(palette);
    final signature = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: gradient.createShader,
      child: Text(
        name,
        style: signatureStyle(palette, fontSize: nameSize),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
    final hasKicker = kicker.isNotEmpty;
    return Semantics(
      label: hasKicker ? '$kicker $name' : name,
      excludeSemantics: true,
      child: inline
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasKicker) ...[
                  Text(kicker, style: kickerStyle(palette, fontSize: nameSize * 0.5), maxLines: 1),
                  SizedBox(width: nameSize * 0.2),
                ],
                Flexible(child: signature),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasKicker) Text(kicker, style: kickerStyle(palette), maxLines: 1),
                signature,
              ],
            ),
    );
  }
}
