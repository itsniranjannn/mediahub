import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../core/logging/diagnostics_service.dart';

/// How long the app's start waits for the phone's media session.
const Duration audioServiceStartTimeout = Duration(seconds: 8);

/// Connects [handler] to the phone's media session without ever holding the
/// app's start for longer than [timeout]. [connect] is AudioService.init with
/// the builder it is given (which returns [handler]).
///
/// The app always gets [handler] back:
/// - connected in time: as it always was;
/// - too slow: the app starts anyway. Music plays inside the app, and the
///   notification and lock-screen controls appear if the connection still
///   finishes later (it then connects this same handler, never a second one);
/// - failed: the app starts without those controls.
///
/// A slow or failed connection goes to the Diagnostics log, never a crash.
Future<T> startAudioService<T extends AudioHandler>(
  T handler, {
  required Future<T> Function(T Function() builder) connect,
  Duration timeout = audioServiceStartTimeout,
}) async {
  final watch = Stopwatch()..start();
  final Future<T> connecting;
  try {
    connecting = connect(() => handler);
  } catch (e) {
    _logFailed(e, late: false);
    return handler;
  }
  try {
    return await connecting.timeout(timeout);
  } on TimeoutException {
    DiagnosticsService.instance.logEvent('audio_service_init_timeout', {'seconds': timeout.inSeconds});
    debugPrint('[AudioService] init took longer than ${timeout.inSeconds} s: starting without it');
    unawaited(connecting.then<void>((_) {
      DiagnosticsService.instance.logEvent('audio_service_init_late', {'ms': watch.elapsedMilliseconds});
    }, onError: (Object e) => _logFailed(e, late: true)));
    return handler;
  } catch (e) {
    _logFailed(e, late: false);
    return handler;
  }
}

void _logFailed(Object e, {required bool late}) {
  DiagnosticsService.instance.logEvent('audio_service_init_failed', {
    'type': e.runtimeType.toString(),
    if (late) 'late': true,
  });
  debugPrint('[AudioService] init failed: $e');
}
