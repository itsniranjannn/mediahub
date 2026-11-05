import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/logging/diagnostics_service.dart';

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
  }

  @override
  Stream<String> get actionEvents => _actionEventsController.stream;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'pauseAll':
      case 'timeout':
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
