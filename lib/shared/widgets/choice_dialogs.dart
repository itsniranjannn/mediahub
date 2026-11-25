// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// One option of [showChoiceDialog].
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.title, {this.subtitle, this.icon});

  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
}

/// The settings pickers ("Save downloads to", "What it locks", "Lock
/// again"): a titled dialog of rounded option tiles, the chosen one tonal
/// with a check. Scrolls on a short (landscape) screen, at most 420 dp wide.
/// Returns the picked value, or null when dismissed.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<ChoiceOption<T>> options,
  required T current,
  String? footnote,
  IconData? icon,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => _ChoiceDialog<T>(
      title: title,
      options: options,
      current: current,
      footnote: footnote,
      icon: icon,
    ),
  );
}

class _ChoiceDialog<T> extends StatelessWidget {
  const _ChoiceDialog({
    required this.title,
    required this.options,
    required this.current,
    this.footnote,
    this.icon,
  });

  final String title;
  final List<ChoiceOption<T>> options;
  final T current;
  final String? footnote;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl24, vertical: AppSpacing.lg16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xl20, AppSpacing.lg16, AppSpacing.sm8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: palette.primary),
                      const SizedBox(width: AppSpacing.sm8),
                    ],
                    Expanded(
                      child: Semantics(header: true, child: Text(title, style: type.sectionTitle)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md12),
              for (final o in options) ...[
                _ChoiceTile<T>(option: o, selected: o.value == current),
                const SizedBox(height: AppSpacing.xs4),
              ],
              if (footnote != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm8, AppSpacing.sm8, AppSpacing.sm8, 0),
                  child: Text(footnote!, style: type.caption),
                ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({required this.option, required this.selected});

  final ChoiceOption<T> option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final radius = BorderRadius.circular(AppSpacing.radiusThumb);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? palette.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? Colors.transparent : palette.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(option.value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget + 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12, vertical: AppSpacing.sm8),
              child: Row(
                children: [
                  if (option.icon != null) ...[
                    Icon(option.icon, size: 20, color: selected ? palette.onPrimaryContainer : palette.textSecondary),
                    const SizedBox(width: AppSpacing.md12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: type.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: selected ? palette.onPrimaryContainer : palette.textPrimary,
                          ),
                        ),
                        if (option.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              option.subtitle!,
                              style: type.metadata.copyWith(
                                fontSize: 13,
                                height: 18 / 13,
                                color: selected ? palette.onPrimaryContainer : palette.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm8),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: selected ? palette.primary : palette.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A destructive confirmation ("Delete from phone?", "Delete download?"):
/// an error-tinted badge, the question, the consequence, then Cancel and a
/// filled error button. Scrolls when the screen is short. True on confirm.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String? messageSemantics,
  String confirmLabel = 'Delete',
  IconData icon = Icons.delete_outline_rounded,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final palette = ctx.palette;
      final type = AppTypography.of(palette);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl24, vertical: AppSpacing.lg16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxl24, AppSpacing.xxl24, AppSpacing.xxl24, AppSpacing.lg16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: palette.errorContainer, shape: BoxShape.circle),
                    child: Icon(icon, size: 26, color: palette.onErrorContainer),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg16),
                Semantics(
                  header: true,
                  child: Text(title, textAlign: TextAlign.center, style: type.sectionTitle),
                ),
                const SizedBox(height: AppSpacing.sm8),
                Text(
                  message,
                  semanticsLabel: messageSemantics,
                  textAlign: TextAlign.center,
                  style: type.metadata.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm8,
                  runSpacing: AppSpacing.sm8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    // A destructive confirm in the error colour (DESIGN.md 7.10).
                    FilledButton.icon(
                      key: const ValueKey('confirm_destructive'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.error,
                        foregroundColor: palette.onError,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: Icon(icon, size: 18),
                      label: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok ?? false;
}
