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
  static bool _handlerSet = false;

  /// Starts listening for native events (picture-in-picture changes). Safe to call often.
  static void init() {
    if (_handlerSet || !available) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        inPip.value = call.arguments == true;
      }
    });
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
  static Future<void> setPipEligible(bool eligible, {double aspect = 16 / 9}) async {
    if (!available) return;
    try {
      // The channel carries integers: scale the ratio to 1000ths.
      await _channel.invokeMethod<bool>('setPipEligible', {
        'eligible': eligible,
        'width': (aspect * 1000).round().clamp(1, 100000),
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
