import 'package:flutter/material.dart';
import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';
import '../app/theme/app_typography.dart';
import '../core/utils/formatters.dart';
import '../shared/widgets/artwork_placeholder.dart';
import '../shared/widgets/ui_kit.dart';
import 'extractor_backend.dart';
import 'format_options.dart';

/// Bottom sheet listing every quality yt-dlp reported for a link, or (with
/// [choices]) a ready-made list such as the files YouTube serves directly.
class FormatSelectionSheet extends StatelessWidget {
  final ExtractorMetadata metadata;
  final void Function(FormatChoice choice) onSelect;

  /// The options to list. Null = built from [metadata]'s yt-dlp formats.
  final List<FormatChoice>? choices;

  /// Optional short note under the list (e.g. why only some qualities show).
  final String? footnote;

  const FormatSelectionSheet({
    super.key,
    required this.metadata,
    required this.onSelect,
    this.choices,
    this.footnote,
  });

  static List<FormatChoice> getPresets(ExtractorMetadata meta) => FormatOptions.build(meta);

  /// Whether the modal route already reserves a drag-handle strip above this
  /// sheet (the theme turns handles on). The caller opens the sheet with a
  /// transparent background, so in that case the sheet paints that strip
  /// itself; otherwise it draws its own handle on top.
  static bool _routeDrawsDragHandle(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is! ModalBottomSheetRoute) return false;
    return route.showDragHandle ??
        (route.enableDrag && (Theme.of(context).bottomSheetTheme.showDragHandle ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final choices = this.choices ?? getPresets(metadata);
    final videoChoices = choices.where((c) => !c.isAudio).toList();
    final audioChoices = choices.where((c) => c.isAudio).toList();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    final content = ColoredBox(
      color: AppColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg16,
                  0,
                  AppSpacing.lg16,
                  AppSpacing.xs4,
                ),
                child: _Header(metadata: metadata),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg16,
                    0,
                    AppSpacing.lg16,
                    AppSpacing.lg16,
                  ),
                  children: [
                    if (videoChoices.isNotEmpty) ...[
                      const _SectionLabel('Video (with sound)'),
                      ...videoChoices.map((c) => _ChoiceTile(choice: c, onSelect: onSelect)),
                    ],
                    if (audioChoices.isNotEmpty) ...[
                      const _SectionLabel('Audio only'),
                      ...audioChoices.map((c) => _ChoiceTile(choice: c, onSelect: onSelect)),
                    ],
                    if (footnote != null && footnote!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm8),
                        child: Text(footnote!, style: AppTypography.metadata),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_routeDrawsDragHandle(context)) {
      // The route's handle sits in a transparent strip right above us: paint
      // the strip (with an identical handle) so the sheet reads as one surface.
      // Touches there still reach the route's own handle.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: -kMinInteractiveDimension,
            height: kMinInteractiveDimension,
            child: _GrabHandle(),
          ),
          content,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        Flexible(child: content),
      ],
    );
  }
}

/// Rounded top edge of the sheet with the drag handle pill. Corner radius and
/// handle come from the app's bottom sheet theme so the sheet matches every
/// other sheet in the app.
class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    final sheetTheme = Theme.of(context).bottomSheetTheme;
    final handleSize = sheetTheme.dragHandleSize ?? const Size(32, 4);
    final handleColor = sheetTheme.dragHandleColor ?? AppColors.surfacePressed;
    final sheetShape = sheetTheme.shape;
    final themeRadius = sheetShape is RoundedRectangleBorder
        ? sheetShape.borderRadius.resolve(Directionality.maybeOf(context))
        : BorderRadius.zero;
    return Container(
      height: kMinInteractiveDimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: themeRadius.topLeft,
          topRight: themeRadius.topRight,
        ),
      ),
      child: Container(
        width: handleSize.width,
        height: handleSize.height,
        decoration: BoxDecoration(
          color: handleColor,
          borderRadius: BorderRadius.circular(handleSize.height / 2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ExtractorMetadata metadata;

  const _Header({required this.metadata});

  @override
  Widget build(BuildContext context) {
    final duration = metadata.durationSec > 0 ? Duration(seconds: metadata.durationSec) : null;
    // Seeded by the video id, so the same video always gets the same
    // placeholder cover wherever it shows.
    final placeholder = ArtworkPlaceholder(
      seed: metadata.id.isNotEmpty ? metadata.id : metadata.title,
      icon: Icons.play_circle_outline_rounded,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Choose quality', style: AppTypography.sectionTitle),
        ),
        const SizedBox(height: AppSpacing.md12),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.md12),
              child: SizedBox(
                width: 112,
                height: 63,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (metadata.thumbnailUrl.isEmpty)
                      placeholder
                    else
                      Image.network(
                        metadata.thumbnailUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 336,
                        errorBuilder: (_, _, _) => placeholder,
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : placeholder,
                      ),
                    if (duration != null)
                      Positioned(
                        right: AppSpacing.xs4,
                        bottom: AppSpacing.xs4,
                        child: DurationBadge(duration: duration),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    breakableTitle(metadata.title),
                    semanticsLabel: metadata.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyStrong,
                  ),
                  if (metadata.uploader.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs4),
                    Text(
                      metadata.uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.metadata,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl20, bottom: AppSpacing.sm8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: AppTypography.label.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One option card: tinted type icon, quality label, size line, download glyph.
class _ChoiceTile extends StatelessWidget {
  final FormatChoice choice;
  final void Function(FormatChoice choice) onSelect;

  const _ChoiceTile({required this.choice, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tint = choice.isAudio ? AppColors.primary : AppColors.accent;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          hint: 'Download',
          child: Material(
            color: AppColors.surfaceElevated,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: const BorderSide(color: AppColors.divider),
            ),
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                onSelect(choice);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md12,
                    vertical: AppSpacing.md12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppSpacing.md12),
                        ),
                        child: Icon(
                          choice.isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
                          size: 22,
                          color: tint,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              choice.label,
                              style: AppTypography.bodyStrong,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.xs4),
                            Text(
                              choice.subtitle,
                              style: AppTypography.metadata,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm8),
                      const Icon(Icons.download_rounded, size: 22, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
