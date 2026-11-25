// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import 'audio_effects.dart';

/// Opens the equalizer (Android only; callers hide it on the iPhone).
Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    builder: (_) => const EqualizerSheet(),
  );
}

/// On/off, the presets as chips, one slider per band (Custom once a band is
/// moved) and the loudness boost. Saved at once and applied to the music
/// player only.
class EqualizerSheet extends ConsumerStatefulWidget {
  const EqualizerSheet({super.key, this.parametersOverride});

  /// Tests: bands without a real player.
  final Future<AndroidEqualizerParameters?> Function()? parametersOverride;

  @override
  ConsumerState<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends ConsumerState<EqualizerSheet> {
  late final Future<AndroidEqualizerParameters?> _params =
      (widget.parametersOverride ?? AudioEffects.instance.parameters)();

  static String _hz(double hz) {
    // just_audio reports milliHertz on some phones; anything that large is.
    final f = hz > 100000 ? hz / 1000 : hz;
    return f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)}k' : f.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(equalizerProvider);
    final notifier = ref.read(equalizerProvider.notifier);
    final palette = context.palette;
    final type = context.typography;
    final groupLabel = type.overline.copyWith(color: palette.textMuted);
    // Landscape and tablets: a readable column in the middle of the sheet.
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.xxl24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.primaryContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusArtSmall),
                    ),
                    child: Icon(Icons.equalizer_rounded, size: 20, color: palette.primary),
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text('Equalizer', style: type.sectionTitle)),
                        Text(
                          s.enabled ? 'On · ${s.preset}' : 'Off',
                          style: type.tabularFigures.copyWith(color: s.enabled ? palette.primary : palette.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.enabled,
                    onChanged: (v) => notifier.update(s.copyWith(enabled: v)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm8),
              Text(
                'Changes the sound of your music only, not videos or other apps.',
                style: type.metadata.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg16),
              Text('PRESETS', style: groupLabel),
              const SizedBox(height: AppSpacing.sm8),
              Wrap(
                spacing: AppSpacing.sm8,
                runSpacing: AppSpacing.sm8,
                children: [
                  for (final p in EqualizerPreset.all)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: s.preset == p.name,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: s.enabled ? (_) => notifier.update(s.copyWith(preset: p.name)) : null,
                    ),
                  if (s.preset == EqualizerPreset.customName)
                    const ChoiceChip(
                      label: Text(EqualizerPreset.customName),
                      selected: true,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: null,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl20),
              Text('BANDS', style: groupLabel),
              const SizedBox(height: AppSpacing.xs4),
              _Panel(
                child: FutureBuilder<AndroidEqualizerParameters?>(
                  future: _params,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(padding: EdgeInsets.all(AppSpacing.lg16), child: CircularProgressIndicator()),
                      );
                    }
                    final params = snap.data;
                    if (params == null || params.bands.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.md12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: palette.textMuted),
                            const SizedBox(width: AppSpacing.sm8),
                            Expanded(
                              child: Text(
                                'Play a song once to adjust the bands. The preset is used meanwhile.',
                                style: type.metadata.copyWith(color: palette.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final gains = s.gainsFor(params.bands.length, min: params.minDecibels, max: params.maxDecibels);
                    return Column(
                      children: [
                        for (var i = 0; i < params.bands.length; i++)
                          _SliderRow(
                            label: '${_hz(params.bands[i].centerFrequency)} Hz',
                            value: '${gains[i] >= 0 ? '+' : ''}${gains[i].toStringAsFixed(0)} dB',
                            slider: Slider(
                              key: ValueKey('eq_band_$i'),
                              min: params.minDecibels,
                              max: params.maxDecibels,
                              value: gains[i],
                              onChanged: s.enabled
                                  ? (v) {
                                      final next = [...gains]..[i] = v;
                                      notifier.update(
                                          s.copyWith(preset: EqualizerPreset.customName, customGains: next));
                                    }
                                  : null,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xl20),
              Text('LOUDNESS', style: groupLabel),
              const SizedBox(height: AppSpacing.xs4),
              _Panel(
                child: _SliderRow(
                  label: 'Boost',
                  icon: Icons.volume_up_rounded,
                  value: '+${s.loudnessDb.toStringAsFixed(0)} dB',
                  slider: Slider(
                    key: const ValueKey('eq_loudness'),
                    min: 0,
                    max: EqualizerSettings.maxLoudnessDb,
                    divisions: 10,
                    value: s.loudnessDb,
                    label: '+${s.loudnessDb.toStringAsFixed(0)} dB',
                    onChanged: s.enabled ? (v) => notifier.update(s.copyWith(loudnessDb: v)) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A surface panel holding slider rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs4),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
        border: Border.all(color: palette.divider),
      ),
      child: child,
    );
  }
}

/// Label, slider and value on one line; the label and value columns grow
/// with the text size instead of clipping.
class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.slider, this.icon});

  final String label;
  final String value;
  final Widget slider;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.typography;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
      child: Row(
        children: [
          SizedBox(
            width: 60 * scale,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: palette.textSecondary),
                  const SizedBox(width: AppSpacing.xs4),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: type.tabularFigures.copyWith(color: palette.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: slider),
          SizedBox(
            width: 52 * scale,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: type.tabularFigures.copyWith(color: palette.textPrimary),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
