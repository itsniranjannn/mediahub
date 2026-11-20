// The app's start never waits for ever on the phone's media session
// (AudioService.init): it starts with the same handler, and says so in the
// Diagnostics log.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/features/music_player/audio_service_start.dart';

class _Handler extends BaseAudioHandler {}

bool _logged(String event) => DiagnosticsService.instance.logs.any((line) => line.contains(event));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);
  setUp(() => DiagnosticsService.instance.clear());

  test('connected in time: the handler the builder gave, nothing logged', () async {
    final handler = _Handler();
    Object? built;
    final result = await startAudioService<_Handler>(handler, connect: (builder) async {
      built = builder();
      return built! as _Handler;
    });
    expect(result, same(handler));
    expect(built, same(handler), reason: 'audio_service connects this handler, not a new one');
    expect(_logged('audio_service_init'), isFalse);
  });

  test('a connection that hangs: the app starts anyway with the same handler', () async {
    final handler = _Handler();
    final never = Completer<_Handler>();
    final result = await startAudioService<_Handler>(
      handler,
      connect: (_) => never.future,
      timeout: const Duration(milliseconds: 50),
    ).timeout(const Duration(seconds: 2));
    expect(result, same(handler));
    expect(_logged('audio_service_init_timeout'), isTrue);

    // It finishes later: the media session comes then, and the log says so.
    never.complete(handler);
    await pumpEventQueue();
    expect(_logged('audio_service_init_late'), isTrue);
  });

  test('a connection that fails: the app starts with the handler, no crash', () async {
    final handler = _Handler();
    final result = await startAudioService<_Handler>(
      handler,
      connect: (_) async => throw StateError('no service'),
    );
    expect(result, same(handler));
    expect(_logged('audio_service_init_failed'), isTrue);
  });

  test('a connection that throws at once is caught too', () async {
    final handler = _Handler();
    final result = await startAudioService<_Handler>(
      handler,
      connect: (_) => throw UnsupportedError('no plugin'),
    );
    expect(result, same(handler));
  });

  test('failing after the timeout is logged, never thrown', () async {
    final handler = _Handler();
    final late = Completer<_Handler>();
    final result = await startAudioService<_Handler>(
      handler,
      connect: (_) => late.future,
      timeout: const Duration(milliseconds: 20),
    );
    expect(result, same(handler));
    late.completeError(StateError('gave up'));
    await pumpEventQueue();
    expect(DiagnosticsService.instance.logs.where((l) => l.contains('audio_service_init_failed') && l.contains('late')),
        isNotEmpty);
  });
}
