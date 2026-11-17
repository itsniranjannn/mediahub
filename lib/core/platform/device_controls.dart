import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../platform_info.dart';

/// Volume and brightness for the video player's swipe gestures (Android only).
/// Every call fails soft so the gestures simply do nothing on other platforms.
class DeviceControls {
  DeviceControls._();

  static const MethodChannel _channel = MethodChannel('mediahub/device_controls');

  static bool get available => PlatformInfo.isAndroid;

  // --- picture in picture --------------------------------------------------
  /// True while the app is shown in the small floating picture-in-picture window.
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  /// Who asked for picture-in-picture when the current window was entered
  /// ([pipOwnerVideoPlayer], [pipOwnerOnline]); null outside picture-in-picture.
  static final ValueNotifier<String?> pipOwner = ValueNotifier<String?>(null);

  static final StreamController<void> _pipDismissed = StreamController<void>.broadcast();

  /// The user closed the picture-in-picture window (its X, or swiped it away):
  /// playback in it should stop, as Android expects.
  static Stream<void> get pipDismissed => _pipDismissed.stream;

  static bool _handlerSet = false;

  /// Starts listening for native events (picture-in-picture changes). Safe to call often.
  static void init() {
    if (_handlerSet || !available) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipChanged':
          handlePipChanged(call.arguments == true);
        case 'pipDismissed':
          _pipDismissed.add(null);
      }
    });
  }

  /// Applies a picture-in-picture change reported by the platform.
  @visibleForTesting
  static void handlePipChanged(bool active) {
    pipOwner.value = active ? effectivePipOwner : null;
    inPip.value = active;
  }

  // --- picture-in-picture eligibility, shared by several screens ---------
  static const String pipOwnerVideoPlayer = 'video_player';
  static const String pipOwnerOnline = 'online';

  /// Screens that currently want picture-in-picture when the user leaves the
  /// app, oldest first. The newest claim wins; when it is withdrawn the one
  /// before it applies again (e.g. closing the video player that was opened
  /// over a playing YouTube page).
  static final LinkedHashMap<String, double> _pipClaims = LinkedHashMap<String, double>();
  static bool _appliedEligible = false;
  static double _appliedAspect = 0;

  /// The screen whose claim is in force, or null.
  static String? get effectivePipOwner => _pipClaims.isEmpty ? null : _pipClaims.keys.last;

  @visibleForTesting
  static Map<String, double> get debugPipClaims => Map.unmodifiable(_pipClaims);

  @visibleForTesting
  static void resetPipForTests() {
    _pipClaims.clear();
    _appliedEligible = false;
    _appliedAspect = 0;
    inPip.value = false;
    pipOwner.value = null;
  }

  static Future<bool> isPipSupported() async {
    if (!available) return false;
    try {
      return (await _channel.invokeMethod<bool>('isPipSupported')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// While a video is on screen Android may switch to picture-in-picture by itself
  /// when the user leaves the app. [aspect] is the video's width / height.
  ///
  /// [owner] names the screen asking; each screen withdraws only its own claim.
  static Future<void> setPipEligible(
    bool eligible, {
    double aspect = 16 / 9,
    String owner = pipOwnerVideoPlayer,
  }) async {
    final safeAspect = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
    if (eligible) {
      // A new claim (or a new aspect) moves to the end: the newest claim wins.
      // Repeating the same claim keeps its place.
      if (_pipClaims[owner] != safeAspect) {
        _pipClaims.remove(owner);
        _pipClaims[owner] = safeAspect;
      }
    } else {
      _pipClaims.remove(owner);
    }
    final effectiveEligible = _pipClaims.isNotEmpty;
    final effectiveAspect = effectiveEligible ? _pipClaims.values.last : _appliedAspect;
    if (effectiveEligible == _appliedEligible && effectiveAspect == _appliedAspect) return;
    _appliedEligible = effectiveEligible;
    _appliedAspect = effectiveAspect;
    if (!available) return;
    try {
      // The channel carries integers: scale the ratio to 1000ths.
      await _channel.invokeMethod<bool>('setPipEligible', {
        'eligible': effectiveEligible,
        'width': ((effectiveAspect > 0 ? effectiveAspect : 16 / 9) * 1000).round().clamp(1, 100000),
        'height': 1000,
      });
    } catch (_) {}
  }

  /// Enters picture-in-picture now. Returns false if the device cannot.
  static Future<bool> enterPip() async {
    if (!available) return false;
    try {
      return (await _channel.invokeMethod<bool>('enterPip')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<double> getVolume() => _read('getVolume', 0.5);
  static Future<double> getBrightness() => _read('getBrightness', 0.5);

  static Future<void> setVolume(double value) => _write('setVolume', value);
  static Future<void> setBrightness(double value) => _write('setBrightness', value);

  /// Gives control of the brightness back to the system setting.
  static Future<void> resetBrightness() async {
    if (!available) return;
    try {
      await _channel.invokeMethod<bool>('resetBrightness');
    } catch (_) {}
  }

  static Future<double> _read(String method, double fallback) async {
    if (!available) return fallback;
    try {
      final v = await _channel.invokeMethod<double>(method);
      return (v ?? fallback).clamp(0.0, 1.0);
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> _write(String method, double value) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<bool>(method, {'value': value.clamp(0.0, 1.0)});
    } catch (_) {}
  }
}
