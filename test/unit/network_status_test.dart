// The Dart side of "mediahub/network" (Android: NetworkChannel in
// MainActivity.kt; iPhone: AppDelegate.swift) and the mobile-data question
// reading it without the personal tools.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform/network_status.dart';
import 'package:mediahub/features/downloads/mobile_data_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mediahub/network_test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call)? handler) => messenger.setMockMethodCallHandler(
        channel,
        handler == null ? null : (call) async => handler(call),
      );

  tearDown(() => answer(null));

  test('asks the phone with isMetered and passes its answer on', () async {
    final calls = <String>[];
    for (final value in [true, false, null]) {
      answer((call) {
        calls.add(call.method);
        return value;
      });
      expect(await NetworkStatus(channel: channel).isMetered(), value);
    }
    expect(calls, ['isMetered', 'isMetered', 'isMetered']);
  });

  test('an error or no native side means unknown (null), never a throw', () async {
    answer((_) => throw PlatformException(code: 'ERR'));
    expect(await NetworkStatus(channel: channel).isMetered(), isNull);
    answer(null);
    expect(await NetworkStatus(channel: channel).isMetered(), isNull);
  });

  test('the mobile-data check reads this channel (no yt-dlp needed)', () async {
    answer((_) => true);
    final container = ProviderContainer(overrides: [
      networkStatusProvider.overrideWithValue(NetworkStatus(channel: channel)),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(meteredNetworkCheckProvider)(), isTrue);

    answer((_) => throw PlatformException(code: 'ERR'));
    expect(await container.read(meteredNetworkCheckProvider)(), isNull, reason: 'no question then');
  });
}
