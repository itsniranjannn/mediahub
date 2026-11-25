// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import '../platform_info.dart';

/// A button in the video player's picture-in-picture window (Android).
enum PipAction {
  rewind,
  playPause,
  forward;

  static PipAction? fromWire(Object? raw) => switch (raw) {
        'rewind' => PipAction.rewind,
        'playPause' => PipAction.playPause,
        'forward' => PipAction.forward,
        _ => null,
      };
}

/// Volume, brightness, picture-in-picture, the headphone-unplug signal and
/// the video volume boost (Android only). Every call fails soft so the
/// gestures simply do nothing on other platforms.
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

  static final StreamController<PipAction> _pipActions = StreamController<PipAction>.broadcast();

  /// A button in the video player's picture-in-picture window was pressed
  /// (only shown while the video player owns the window, see [setPipPlaying]).
  static Stream<PipAction> get pipActions => _pipActions.stream;

  static bool _handlerSet = false;

  /// Starts listening for native events (picture-in-picture changes, volume
  /// changes, headphones unplugged). Safe to call often.
  static void init() {
    if (_handlerSet || !available) return;
    _handlerSet = true;
    _channel.setMethodCallHandler(handlePlatformCall);
    _lifecycle ??= AppLifecycleListener(onResume: handleAppResumed);
  }

  static AppLifecycleListener? _lifecycle;

  /// The app is back on screen. Android pauses an Activity in
  /// picture-in-picture, so a resumed app is never in it: a PiP layout still
  /// showing (the "left picture-in-picture" call lost, the Activity
  /// re-created while the floating window was closed in the background)
  /// ends here, and the toolbar and the Ink Dock come back.
  @visibleForTesting
  static void handleAppResumed() {
    if (inPip.value) handlePipChanged(false);
  }

  /// Applies one event from the platform. Public for tests.
  @visibleForTesting
  static Future<void> handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'pipChanged':
        handlePipChanged(call.arguments == true);
      case 'pipDismissed':
        _pipDismissed.add(null);
      case 'pipAction':
        final action = PipAction.fromWire(call.arguments);
        if (action != null) _pipActions.add(action);
      case 'volumeChanged':
        final v = call.arguments;
        if (v is num) _volumeChanges.add(v.toDouble().clamp(0.0, 1.0));
      case 'becomingNoisy':
        for (final c in _noisyWatchers.values.toList()) {
          c.add(null);
        }
    }
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

  /// Whether the video player's window shows its buttons, and with a pause
  /// (true) or a play (false) glyph; null = no buttons.
  static bool? _videoPipPlaying;
  static bool? _appliedPipPlaying;

  /// The screen whose claim is in force, or null.
  static String? get effectivePipOwner => _pipClaims.isEmpty ? null : _pipClaims.keys.last;

  @visibleForTesting
  static Map<String, double> get debugPipClaims => Map.unmodifiable(_pipClaims);

  @visibleForTesting
  static void resetPipForTests() {
    _pipClaims.clear();
    _appliedEligible = false;
    _appliedAspect = 0;
    _videoPipPlaying = null;
    _appliedPipPlaying = null;
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
    await _applyPip();
  }

  /// The play state the video player's picture-in-picture buttons show
  /// (rewind 10 s, play / pause, forward 10 s); null removes the buttons.
  /// The buttons only appear while the video player's claim is in force.
  static Future<void> setPipPlaying(bool? playing) async {
    _videoPipPlaying = playing;
    await _applyPip();
  }

  /// The buttons for the claim in force: only the video player has them.
  static bool? get _effectivePipPlaying =>
      effectivePipOwner == pipOwnerVideoPlayer ? _videoPipPlaying : null;

  static Future<void> _applyPip() async {
    final effectiveEligible = _pipClaims.isNotEmpty;
    final effectiveAspect = effectiveEligible ? _pipClaims.values.last : _appliedAspect;
    final playing = _effectivePipPlaying;
    if (effectiveEligible == _appliedEligible &&
        effectiveAspect == _appliedAspect &&
        playing == _appliedPipPlaying) {
      return;
    }
    _appliedEligible = effectiveEligible;
    _appliedAspect = effectiveAspect;
    _appliedPipPlaying = playing;
    if (!available) return;
    try {
      // The channel carries integers: scale the ratio to 1000ths.
      await _channel.invokeMethod<bool>('setPipEligible', {
        'eligible': effectiveEligible,
        'width': ((effectiveAspect > 0 ? effectiveAspect : 16 / 9) * 1000).round().clamp(1, 100000),
        'height': 1000,
        // Absent = no buttons in the window.
        'actionsPlaying': ?playing,
      });
    } catch (_) {}
  }

  /// Enters picture-in-picture now. Returns false if the device cannot.
  /// Diagnostic: what in the app's window could draw over the Flutter UI
  /// (see [UiCoverReport]); null where it cannot be checked.
  static Future<UiCoverReport?> uiCoverCheck() async {
    if (!available) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('uiCoverCheck');
      return raw == null ? null : UiCoverReport.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> enterPip() async {
    if (!available) return false;
    try {
      return (await _channel.invokeMethod<bool>('enterPip')) ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- volume ----------------------------------------------------------------

  static final StreamController<double> _volumeChanges = StreamController<double>.broadcast(
    onListen: () => _setWatch('watchVolume', true),
    onCancel: () => _setWatch('watchVolume', false),
  );

  /// The phone's media volume (0..1) each time it changes by any means: the
  /// volume keys, the system slider, another app or this one. Android
  /// reports only while someone listens.
  static Stream<double> get volumeChanges => _volumeChanges.stream;

  // --- headphones unplugged ("becoming noisy") -------------------------------

  static final Map<String, StreamController<void>> _noisyWatchers = {};

  /// Fires when the audio is about to come out of the speaker because
  /// headphones were unplugged or a Bluetooth headset disconnected: playback
  /// should pause, as every media app does. One native receiver serves every
  /// [owner] (e.g. 'video_player', 'online'); it is registered while at least
  /// one owner listens. Calling again with the same owner returns the same
  /// stream.
  static Stream<void> watchBecomingNoisy(String owner) {
    final existing = _noisyWatchers[owner];
    if (existing != null) return existing.stream;
    final controller = StreamController<void>.broadcast(
      onListen: _syncNoisyWatch,
      onCancel: _syncNoisyWatch,
    );
    _noisyWatchers[owner] = controller;
    return controller.stream;
  }

  /// Owners with a live listener (tests).
  @visibleForTesting
  static List<String> get debugNoisyOwners =>
      [for (final e in _noisyWatchers.entries) if (e.value.hasListener) e.key];

  static bool _noisyApplied = false;

  static void _syncNoisyWatch() {
    final want = _noisyWatchers.values.any((c) => c.hasListener);
    if (want == _noisyApplied) return;
    _noisyApplied = want;
    _setWatch('watchNoisy', want);
  }

  static Future<void> _setWatch(String method, bool on) async {
    if (!available) return;
    init();
    try {
      await _channel.invokeMethod<bool>(method, {'on': on});
    } catch (_) {}
  }

  // --- video volume boost ------------------------------------------------------

  /// Highest boost the video player offers (percent of full volume).
  static const int maxBoostPercent = 200;

  /// Whether this platform can try to boost a video past full volume
  /// (Android's LoudnessEnhancer on the video's own audio session).
  static bool get boostAvailable => available;

  /// Raises video [playerId]'s loudness to [percent] (100 = off, up to
  /// [maxBoostPercent]) on its own audio session; music is never touched.
  /// Returns false when the phone refuses (no LoudnessEnhancer, no session):
  /// the player then hides its boost zone.
  static Future<bool> setVideoBoost({required int playerId, required int percent}) async {
    if (!available || playerId < 0) return false;
    init();
    try {
      return (await _channel.invokeMethod<bool>('setVideoBoost', {
            'playerId': playerId,
            'percent': percent.clamp(100, maxBoostPercent),
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Drops any video boost (the player closed or switched video).
  static Future<void> releaseVideoBoost() async {
    if (!available) return;
    try {
      await _channel.invokeMethod<bool>('releaseVideoBoost');
    } catch (_) {}
  }

  // --- volume / brightness values ----------------------------------------------

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

/// What the window holds besides the Flutter UI ([DeviceControls.uiCoverCheck]).
@immutable
class UiCoverReport {
  const UiCoverReport({this.orphanWrappers = 0, this.wrappers = 0, this.flutterViews = 1, this.strayViews = const []});

  factory UiCoverReport.fromMap(Map<String, Object?> m) => UiCoverReport(
        orphanWrappers: (m['orphanWrappers'] as num?)?.toInt() ?? 0,
        wrappers: (m['wrappers'] as num?)?.toInt() ?? 0,
        flutterViews: (m['flutterViews'] as num?)?.toInt() ?? 1,
        strayViews: [for (final v in (m['strayViews'] as List?) ?? const []) '$v'],
      );

  /// Platform-view wrappers without a render target: they draw the WebView
  /// straight onto the window, over the whole Flutter UI.
  final int orphanWrappers;
  final int wrappers;
  final int flutterViews;

  /// Views in the window besides the FlutterView (a fullscreen video's view).
  final List<String> strayViews;

  /// Whether something native covers the Flutter UI. A stray view is
  /// expected only while the page shows a video fullscreen.
  bool covers({required bool pageFullscreen}) =>
      orphanWrappers > 0 || flutterViews != 1 || (!pageFullscreen && strayViews.isNotEmpty);

  Map<String, Object> toDiagnostics() => {
        'orphan_wrappers': orphanWrappers,
        'wrappers': wrappers,
        'flutter_views': flutterViews,
        'stray': strayViews.join(','),
      };
}
