// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/logging/diagnostics_service.dart';

/// The events [DownloadServiceController.actionEvents] carries.
abstract final class DownloadServiceActions {
  /// The notification's "Pause all".
  static const String pauseAll = 'pauseAll';

  /// Android 15 stopped the data-sync service after its time limit.
  static const String timeout = 'timeout';

  /// The notification itself was tapped: show the Downloads tab.
  static const String openDownloads = 'openDownloads';
}

abstract class DownloadServiceController {
  Future<void> startService({required int count, int percent = -1, String? fileName});
  Future<void> updateProgress({required int count, int percent = -1, String? fileName});
  Future<void> stopService();
  Stream<String> get actionEvents;
  void dispose();
}

class AndroidDownloadServiceController implements DownloadServiceController {
  static const MethodChannel _channel = MethodChannel('mediahub/download_service');
  final StreamController<String> _actionEventsController = StreamController<String>.broadcast();
  DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isServiceRunning = false;

  AndroidDownloadServiceController() {
    _channel.setMethodCallHandler(_handleMethodCall);
    // A notification tap that arrived before this side was listening (the
    // Activity started from it) waits natively until asked for.
    _takePendingActions();
  }

  Future<void> _takePendingActions() async {
    try {
      final pending = await _channel.invokeMethod<List<Object?>>('takePendingActions');
      for (final action in pending ?? const <Object?>[]) {
        if (action == DownloadServiceActions.openDownloads && !_actionEventsController.isClosed) {
          _actionEventsController.add(DownloadServiceActions.openDownloads);
        }
      }
    } catch (_) {
      // Not Android (no channel) or an older native side.
    }
  }

  @override
  Stream<String> get actionEvents => _actionEventsController.stream;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case DownloadServiceActions.pauseAll:
      case DownloadServiceActions.timeout:
      case DownloadServiceActions.openDownloads:
        _actionEventsController.add(call.method);
        break;
      case 'wake_lock_acquired':
        DiagnosticsService.instance.logEvent('wake_lock_acquired', {});
        break;
      case 'wake_lock_released':
        DiagnosticsService.instance.logEvent('wake_lock_released', {});
        break;
      default:
        break;
    }
  }

  @override
  Future<void> startService({required int count, int percent = -1, String? fileName}) async {
    try {
      await _channel.invokeMethod('start', {
        'count': count,
        'percent': percent,
        'fileName': fileName,
      });
      _isServiceRunning = true;
      DiagnosticsService.instance.logEvent('download_service_started', {
        'count': count,
      });
    } catch (_) {
      // Ignored if platform channel fails or desktop
    }
  }

  @override
  Future<void> updateProgress({required int count, int percent = -1, String? fileName}) async {
    if (!_isServiceRunning) return;
    final now = DateTime.now();
    // Strict 1-second throttle for EVERY value (including -1, 0, and 100)
    if (now.difference(_lastUpdateTime).inMilliseconds < 1000) {
      return;
    }
    _lastUpdateTime = now;

    try {
      await _channel.invokeMethod('update', {
        'count': count,
        'percent': percent,
        'fileName': fileName,
      });
    } catch (_) {}
  }

  @override
  Future<void> stopService() async {
    if (!_isServiceRunning) return;
    _isServiceRunning = false;
    try {
      await _channel.invokeMethod('stop');
      DiagnosticsService.instance.logEvent('download_service_stopped', {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _actionEventsController.close();
  }
}
