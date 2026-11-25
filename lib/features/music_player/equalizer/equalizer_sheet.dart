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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl24, AppSpacing.lg16, AppSpacing.xxl24, AppSpacing.xxl24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text('Equalizer', style: type.sectionTitle))),
              Switch(
                value: s.enabled,
                onChanged: (v) => notifier.update(s.copyWith(enabled: v)),
              ),
            ],
          ),
          Text(
            'Changes the sound of your music only, not videos or other apps.',
            style: type.metadata.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg16),
          Wrap(
            spacing: AppSpacing.sm8,
            runSpacing: AppSpacing.sm8,
            children: [
              for (final p in EqualizerPreset.all)
                ChoiceChip(
                  label: Text(p.name),
                  selected: s.preset == p.name,
                  onSelected: s.enabled ? (_) => notifier.update(s.copyWith(preset: p.name)) : null,
                ),
              if (s.preset == EqualizerPreset.customName)
                const ChoiceChip(label: Text(EqualizerPreset.customName), selected: true, onSelected: null),
            ],
          ),
          const SizedBox(height: AppSpacing.lg16),
          FutureBuilder<AndroidEqualizerParameters?>(
            future: _params,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
              }
              final params = snap.data;
              if (params == null || params.bands.isEmpty) {
                return Text(
                  'Play a song once to adjust the bands. The preset is used meanwhile.',
                  style: type.metadata.copyWith(color: palette.textSecondary),
                );
              }
              final gains = s.gainsFor(params.bands.length, min: params.minDecibels, max: params.maxDecibels);
              return Column(
                children: [
                  for (var i = 0; i < params.bands.length; i++)
                    Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text('${_hz(params.bands[i].centerFrequency)} Hz',
                              style: type.metadata.copyWith(color: palette.textSecondary)),
                        ),
                        Expanded(
                          child: Slider(
                            key: ValueKey('eq_band_$i'),
                            min: params.minDecibels,
                            max: params.maxDecibels,
                            value: gains[i],
                            onChanged: s.enabled
                                ? (v) {
                                    final next = [...gains]..[i] = v;
                                    notifier.update(s.copyWith(preset: EqualizerPreset.customName, customGains: next));
                                  }
                                : null,
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text('${gains[i] >= 0 ? '+' : ''}${gains[i].toStringAsFixed(0)} dB',
                              textAlign: TextAlign.end, style: type.tabularFigures),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md12),
          Text('Loudness boost', style: type.body.copyWith(fontWeight: FontWeight.w500)),
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('eq_loudness'),
                  min: 0,
                  max: EqualizerSettings.maxLoudnessDb,
                  divisions: 10,
                  value: s.loudnessDb,
                  label: '+${s.loudnessDb.toStringAsFixed(0)} dB',
                  onChanged: s.enabled ? (v) => notifier.update(s.copyWith(loudnessDb: v)) : null,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('+${s.loudnessDb.toStringAsFixed(0)} dB',
                    textAlign: TextAlign.end, style: type.tabularFigures),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
