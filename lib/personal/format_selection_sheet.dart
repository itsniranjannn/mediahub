import 'package:flutter/material.dart';
import '../app/theme/app_palette.dart';
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
    final palette = context.palette;

    final content = ColoredBox(
      color: palette.surface,
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
                child: _SectionedChoices(
                  videoChoices: videoChoices,
                  audioChoices: audioChoices,
                  footnote: footnote,
                  onSelect: onSelect,
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
        // Our own handle: a tap closes the sheet, and a screen reader reads
        // it as the "Dismiss" button the route's handle would be.
        Semantics(
          button: true,
          label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
          onTap: () => Navigator.of(context).maybePop(),
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('format_sheet_handle'),
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: const _GrabHandle(),
          ),
        ),
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
    final palette = context.palette;
    final sheetTheme = Theme.of(context).bottomSheetTheme;
    final handleSize = sheetTheme.dragHandleSize ?? const Size(36, 4);
    final handleColor = sheetTheme.dragHandleColor ?? palette.dragHandle;
    final sheetShape = sheetTheme.shape;
    final themeRadius = sheetShape is RoundedRectangleBorder
        ? sheetShape.borderRadius.resolve(Directionality.maybeOf(context))
        : BorderRadius.zero;
    return Container(
      height: kMinInteractiveDimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
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
    final palette = context.palette;
    final type = AppTypography.of(palette);
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
        // An app string, so the sheet title role; the video's own name goes
        // in the body below (DESIGN.md 7.10).
        Semantics(
          header: true,
          child: Text('Choose quality', style: type.sectionTitle),
        ),
        const SizedBox(height: AppSpacing.md12),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusArtSmall),
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
                    style: type.bodyStrong,
                  ),
                  if (metadata.uploader.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      metadata.uploader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.metadata,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md12),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }
}

/// Which list the sheet shows.
enum FormatSection { video, audio }

/// "Video" / "Audio" switch at the top (Video first) and the options of the
/// chosen one. With only one kind on offer, the switch is left out.
class _SectionedChoices extends StatefulWidget {
  final List<FormatChoice> videoChoices;
  final List<FormatChoice> audioChoices;
  final String? footnote;
  final void Function(FormatChoice choice) onSelect;

  const _SectionedChoices({
    required this.videoChoices,
    required this.audioChoices,
    required this.footnote,
    required this.onSelect,
  });

  @override
  State<_SectionedChoices> createState() => _SectionedChoicesState();
}

class _SectionedChoicesState extends State<_SectionedChoices> {
  late FormatSection _section =
      widget.videoChoices.isEmpty ? FormatSection.audio : FormatSection.video;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final both = widget.videoChoices.isNotEmpty && widget.audioChoices.isNotEmpty;
    final audio = _section == FormatSection.audio;
    final shown = audio ? widget.audioChoices : widget.videoChoices;
    final footnote = widget.footnote;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.md12,
        AppSpacing.lg16,
        AppSpacing.lg16,
      ),
      children: [
        if (both)
          SegmentedButton<FormatSection>(
            key: const ValueKey('format-sections'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: FormatSection.video,
                label: Text('Video'),
                icon: Icon(Icons.videocam_rounded),
              ),
              ButtonSegment(
                value: FormatSection.audio,
                label: Text('Audio'),
                icon: Icon(Icons.music_note_rounded),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
          ),
        _SectionLabel(audio ? 'Audio only · saved to Music' : 'Video with sound'),
        ...shown.map((c) => _ChoiceTile(key: ValueKey('format-${c.id}'), choice: c, onSelect: widget.onSelect)),
        if (footnote != null && footnote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm8),
            child: Text(footnote, style: AppTypography.of(palette).metadata),
          ),
      ],
    );
  }
}

/// Group kicker ("VIDEO WITH SOUND", "AUDIO ONLY") in the overline role.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg16, bottom: AppSpacing.sm8),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          semanticsLabel: text,
          style: AppTypography.of(palette).overline.copyWith(color: palette.primary),
        ),
      ),
    );
  }
}

/// [text] with every " · "-separated part that starts with a figure ("12.0 MB",
/// "~48 MB") set in the figures role at 14, the rest in [base] (DESIGN.md 6:
/// in a meta line, figures are a TextSpan at 14).
TextSpan _metaSpan(String text, TextStyle base, TextStyle figures) {
  final parts = text.split(' · ');
  final figure = RegExp(r'^[~≈]?\d');
  final figureStyle = figures.copyWith(fontSize: 14, height: 20 / 14);
  return TextSpan(
    style: base,
    children: [
      for (var i = 0; i < parts.length; i++) ...[
        if (i > 0) const TextSpan(text: ' · '),
        TextSpan(text: parts[i], style: figure.hasMatch(parts[i]) ? figureStyle : null),
      ],
    ],
  );
}

/// One option card: tonal type tile, quality label, size line, download glyph.
class _ChoiceTile extends StatelessWidget {
  final FormatChoice choice;
  final void Function(FormatChoice choice) onSelect;

  const _ChoiceTile({super.key, required this.choice, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    // The same tile as a Downloads row: primary music glyph, accent video glyph.
    final glyph = choice.isAudio ? palette.primary : palette.accent;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          hint: 'Download',
          child: Material(
            color: palette.surfaceElevated,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: palette.divider),
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
                          color: palette.primaryContainer,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusArtSmall),
                        ),
                        child: Icon(
                          choice.isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
                          size: 22,
                          color: glyph,
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
                              style: type.bodyStrong,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text.rich(
                              _metaSpan(choice.subtitle, type.metadata, type.tabularFigures),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm8),
                      Icon(Icons.download_rounded, size: 22, color: palette.primary),
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
