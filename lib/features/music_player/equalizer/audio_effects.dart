// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  static const MethodChannel _channel = MethodChannel('mediahub/device_controls');

  int? _sessionId;
  EqualizerSettings? _lastSettings;
  AndroidEqualizerParameters? _cachedParams;

  /// Called by MusicAudioHandler when ExoPlayer reports its Android audio session ID.
  void attachSession(int? sessionId) {
    if (sessionId == null || sessionId <= 0 || sessionId == _sessionId) return;
    _sessionId = sessionId;
    _cachedParams = null;
    final pending = _lastSettings ?? EqualizerSettings.load(SettingsStore.instance);
    unawaited(apply(pending));
  }

  /// Kept null: just_audio 0.10.6 calls AndroidEqualizer._activate() before
  /// load() initializes ExoPlayer's audio session. Native effects are attached
  /// directly via [attachSession] instead.
  AudioPipeline? get pipeline => null;

  AndroidEqualizer? get equalizer => null;

  /// The bands, once the player has an active audio session (null until then).
  Future<AndroidEqualizerParameters?> parameters({Duration timeout = const Duration(seconds: 2)}) async {
    if (!supported) return null;
    final sid = _sessionId;
    if (sid == null || sid <= 0) return null;
    if (_cachedParams != null) return _cachedParams;
    try {
      final raw = await _channel
          .invokeMapMethod<String, Object?>('getMusicEqParams', {'sessionId': sid})
          .timeout(timeout);
      if (raw == null) return null;
      final minDb = (raw['minDecibels'] as num?)?.toDouble() ?? -15.0;
      final maxDb = (raw['maxDecibels'] as num?)?.toDouble() ?? 15.0;
      final rawBands = (raw['bands'] as List?) ?? const [];
      final bands = <AndroidEqualizerBand>[
        for (final b in rawBands)
          if (b is Map)
            _NativeEqualizerBand(
              index: (b['index'] as num?)?.toInt() ?? 0,
              lowerFrequency: (b['lowerFrequency'] as num?)?.toDouble() ?? 0,
              upperFrequency: (b['upperFrequency'] as num?)?.toDouble() ?? 0,
              centerFrequency: (b['centerFrequency'] as num?)?.toDouble() ?? 0,
              gain: (b['gain'] as num?)?.toDouble() ?? 0,
            ),
      ];
      if (bands.isEmpty) return null;
      _cachedParams = AndroidEqualizerParameters(
        minDecibels: minDb,
        maxDecibels: maxDb,
        bands: bands,
      );
      return _cachedParams;
    } catch (_) {
      return null;
    }
  }

  /// Applies [s] to the active Android audio session.
  Future<void> apply(EqualizerSettings s) async {
    _lastSettings = s;
    if (!supported) return;
    final sid = _sessionId;
    if (sid == null || sid <= 0) return;
    try {
      final params = s.enabled ? await parameters() : null;
      final gains = params == null
          ? null
          : s.gainsFor(params.bands.length, min: params.minDecibels, max: params.maxDecibels);
      await _channel.invokeMethod<bool>('applyMusicEq', {
        'sessionId': sid,
        'enabled': s.enabled,
        'gains': ?gains,
        'loudnessDb': s.loudnessDb,
      });
    } catch (e) {
      DiagnosticsService.instance.logEvent('eq_apply_failed', {'type': e.runtimeType.toString()});
    }
  }
}

class _NativeEqualizerBand implements AndroidEqualizerBand {
  _NativeEqualizerBand({
    required this.index,
    required this.lowerFrequency,
    required this.upperFrequency,
    required this.centerFrequency,
    required double gain,
  }) : _gain = gain; // ignore: prefer_initializing_formals

  @override
  final int index;
  @override
  final double lowerFrequency;
  @override
  final double upperFrequency;
  @override
  final double centerFrequency;

  double _gain;

  @override
  double get gain => _gain;

  @override
  Future<void> setGain(double gain) async {
    _gain = gain;
  }

  @override
  Stream<double> get gainStream => Stream<double>.value(_gain);
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
