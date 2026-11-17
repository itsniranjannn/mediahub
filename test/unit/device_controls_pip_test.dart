import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/core/platform_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mediahub/device_controls');
  final calls = <Map<Object?, Object?>>[];

  setUp(() {
    calls.clear();
    DeviceControls.resetPipForTests();
    PlatformInfo.debugIsAndroid = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setPipEligible') calls.add(call.arguments as Map<Object?, Object?>);
      return true;
    });
  });

  tearDown(() {
    PlatformInfo.resetForTests();
    DeviceControls.resetPipForTests();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('the video player opened over a playing YouTube page: its claim wins, then Online applies again', () async {
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline, aspect: 16 / 9);
    expect(DeviceControls.effectivePipOwner, DeviceControls.pipOwnerOnline);
    await DeviceControls.setPipEligible(true, aspect: 4 / 3); // video player (default owner)
    expect(DeviceControls.effectivePipOwner, DeviceControls.pipOwnerVideoPlayer);
    expect(calls.last, {'eligible': true, 'width': 1333, 'height': 1000});

    await DeviceControls.setPipEligible(false); // video player closes
    expect(DeviceControls.effectivePipOwner, DeviceControls.pipOwnerOnline);
    expect(calls.last, {'eligible': true, 'width': 1778, 'height': 1000});

    await DeviceControls.setPipEligible(false, owner: DeviceControls.pipOwnerOnline);
    expect(DeviceControls.effectivePipOwner, isNull);
    expect(calls.last['eligible'], false);
  });

  test('repeating the same claim neither reorders nor talks to the platform again', () async {
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    await DeviceControls.setPipEligible(true);
    final n = calls.length;
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline); // once a second while playing
    expect(DeviceControls.effectivePipOwner, DeviceControls.pipOwnerVideoPlayer);
    expect(calls.length, n);
  });

  test('withdrawing a claim that was never made changes nothing', () async {
    await DeviceControls.setPipEligible(false, owner: DeviceControls.pipOwnerOnline);
    expect(calls, isEmpty);
  });

  test('entering PiP records whose window it is; leaving clears it', () async {
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    DeviceControls.handlePipChanged(true);
    expect(DeviceControls.inPip.value, isTrue);
    expect(DeviceControls.pipOwner.value, DeviceControls.pipOwnerOnline);
    DeviceControls.handlePipChanged(false);
    expect(DeviceControls.inPip.value, isFalse);
    expect(DeviceControls.pipOwner.value, isNull);
  });

  test('a bad aspect falls back to 16:9', () async {
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline, aspect: double.nan);
    expect(calls.last, {'eligible': true, 'width': 1778, 'height': 1000});
  });
}
