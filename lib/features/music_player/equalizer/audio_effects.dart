// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/logging/diagnostics_service.dart';
import '../../../core/platform_info.dart';
import '../../../core/storage/settings_store.dart';

/// An equalizer preset: gains in dB at five evenly spread points from the
/// lowest band to the highest, spread over however many bands the phone has.
@immutable
class EqualizerPreset {
  const EqualizerPreset(this.name, this.points);

  final String name;
  final List<double> points;

  static const String customName = 'Custom';

  static const List<EqualizerPreset> all = [
    EqualizerPreset('Flat', [0, 0, 0, 0, 0]),
    EqualizerPreset('Bass boost', [6, 4, 0, 0, 0]),
    EqualizerPreset('Treble boost', [0, 0, 0, 3, 6]),
    EqualizerPreset('Vocal', [-2, 0, 4, 3, 0]),
    EqualizerPreset('Rock', [5, 2, -2, 2, 5]),
    EqualizerPreset('Pop', [-1, 2, 4, 2, -1]),
    EqualizerPreset('Classical', [4, 2, 0, 2, 4]),
  ];

  static EqualizerPreset? named(String name) {
    for (final p in all) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// The gain of band [index] of [count], interpolated from [points] and
  /// kept within [min]..[max].
  double gainFor(int index, int count, {required double min, required double max}) {
    final double g;
    if (count <= 1) {
      g = points[points.length ~/ 2];
    } else {
      final x = index / (count - 1) * (points.length - 1);
      final lo = x.floor().clamp(0, points.length - 1);
      final hi = (lo + 1).clamp(0, points.length - 1);
      final t = x - lo;
      g = points[lo] * (1 - t) + points[hi] * t;
    }
    return g.clamp(min, max).toDouble();
  }
}

/// The saved equalizer: on/off, the preset (or Custom with its own gains)
/// and the loudness boost.
@immutable
class EqualizerSettings {
  const EqualizerSettings({
    this.enabled = false,
    this.preset = 'Flat',
    this.customGains = const [],
    this.loudnessDb = 0,
  });

  final bool enabled;
  final String preset;

  /// Custom: one gain (dB) per band, in the phone's band order.
  final List<double> customGains;

  /// LoudnessEnhancer target gain in dB, 0 (off) to [maxLoudnessDb].
  final double loudnessDb;

  static const double maxLoudnessDb = 10;

  static const String enabledKey = 'eq_enabled';
  static const String presetKey = 'eq_preset';
  static const String customKey = 'eq_custom_gains';
  static const String loudnessKey = 'eq_loudness_db';

  static EqualizerSettings load(SettingsStore store) {
    final custom = (store.getString(customKey) ?? '')
        .split(',')
        .map((s) => double.tryParse(s.trim()))
        .whereType<double>()
        .where((g) => g.isFinite && g.abs() <= 30)
        .toList();
    final loud = double.tryParse(store.getString(loudnessKey) ?? '') ?? 0;
    final preset = store.getString(presetKey) ?? 'Flat';
    return EqualizerSettings(
      enabled: store.getBool(enabledKey),
      preset: preset == EqualizerPreset.customName || EqualizerPreset.named(preset) != null ? preset : 'Flat',
      customGains: List.unmodifiable(custom),
      loudnessDb: loud.isFinite ? loud.clamp(0, maxLoudnessDb).toDouble() : 0,
    );
  }

  Future<void> save(SettingsStore store) async {
    await store.setBool(enabledKey, enabled);
    await store.setString(presetKey, preset);
    await store.setString(customKey, customGains.map((g) => g.toStringAsFixed(1)).join(','));
    await store.setString(loudnessKey, loudnessDb.toStringAsFixed(1));
  }

  EqualizerSettings copyWith({bool? enabled, String? preset, List<double>? customGains, double? loudnessDb}) =>
      EqualizerSettings(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        customGains: customGains ?? this.customGains,
        loudnessDb: loudnessDb ?? this.loudnessDb,
      );

  /// The gain of every band for [bandCount] bands within [min]..[max].
  List<double> gainsFor(int bandCount, {required double min, required double max}) {
    if (preset == EqualizerPreset.customName && customGains.length == bandCount) {
      return [for (final g in customGains) g.clamp(min, max).toDouble()];
    }
    final p = EqualizerPreset.named(preset) ?? EqualizerPreset.all.first;
    return [for (var i = 0; i < bandCount; i++) p.gainFor(i, bandCount, min: min, max: max)];
  }
}

/// The music player's Android audio effects (just_audio's AndroidEqualizer
/// and AndroidLoudnessEnhancer on the player's own audio session, so videos
/// and other apps are never changed). The iPhone has no equivalent in
/// just_audio: [pipeline] is null there and the screens hide the equalizer.
class AudioEffects {
  AudioEffects._();

  static final AudioEffects instance = AudioEffects._();

  /// Whether this phone gets the equalizer (Android only).
  static bool get supported => PlatformInfo.isAndroid;

  AndroidEqualizer? _equalizer;
  AndroidLoudnessEnhancer? _loudness;
  AudioPipeline? _pipeline;

  /// For the music player's constructor; null on the iPhone and in tests.
  AudioPipeline? get pipeline {
    if (!supported) return null;
    if (_pipeline == null) {
      _equalizer = AndroidEqualizer();
      _loudness = AndroidLoudnessEnhancer();
      _pipeline = AudioPipeline(androidAudioEffects: [_equalizer!, _loudness!]);
    }
    return _pipeline;
  }

  AndroidEqualizer? get equalizer => _equalizer;

  /// The bands, once the player has played something (null until then).
  Future<AndroidEqualizerParameters?> parameters({Duration timeout = const Duration(seconds: 2)}) async {
    final eq = _equalizer;
    if (eq == null) return null;
    try {
      return await eq.parameters.timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Applies [s]. The gains reach the phone once the player is active
  /// (just_audio keeps and restores them).
  Future<void> apply(EqualizerSettings s) async {
    final eq = _equalizer;
    final loud = _loudness;
    if (eq == null || loud == null) return;
    try {
      await eq.setEnabled(s.enabled);
      await loud.setEnabled(s.enabled && s.loudnessDb > 0);
      await loud.setTargetGain(s.loudnessDb); // dB (just_audio turns it into millibels)
    } catch (e) {
      DiagnosticsService.instance.logEvent('eq_apply_failed', {'type': e.runtimeType.toString()});
    }
    // The bands are known only after the first song loaded: wait for them.
    unawaited(eq.parameters.then((params) async {
      final gains = s.gainsFor(params.bands.length, min: params.minDecibels, max: params.maxDecibels);
      for (var i = 0; i < params.bands.length; i++) {
        await params.bands[i].setGain(gains[i]);
      }
    }).catchError((Object e) {
      DiagnosticsService.instance.logEvent('eq_bands_failed', {'type': e.runtimeType.toString()});
    }));
  }
}

class EqualizerNotifier extends Notifier<EqualizerSettings> {
  @override
  EqualizerSettings build() => EqualizerSettings.load(SettingsStore.instance);

  void update(EqualizerSettings next) {
    state = next;
    next.save(SettingsStore.instance);
    AudioEffects.instance.apply(next);
  }
}

final equalizerProvider = NotifierProvider<EqualizerNotifier, EqualizerSettings>(EqualizerNotifier.new);
