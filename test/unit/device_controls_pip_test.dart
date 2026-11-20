import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform/device_controls.dart';
import 'package:mediahub/core/platform_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mediahub/device_controls');
  final calls = <Map<Object?, Object?>>[];
  final watches = <MethodCall>[];

  setUp(() {
    calls.clear();
    watches.clear();
    DeviceControls.resetPipForTests();
    PlatformInfo.debugIsAndroid = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setPipEligible') calls.add(call.arguments as Map<Object?, Object?>);
      if (call.method.startsWith('watch') || call.method.contains('Boost')) watches.add(call);
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

  // MainActivity.onResume sends "not in PiP" every time the app comes back, in case the
  // "left PiP" callback was lost (the Online tab once kept its PiP layout, without a toolbar).
  test('the "not in PiP" sent on every resume clears a stuck state and is otherwise a no-op', () async {
    var changes = 0;
    void count() => changes++;
    DeviceControls.inPip.addListener(count);
    addTearDown(() => DeviceControls.inPip.removeListener(count));

    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
    DeviceControls.handlePipChanged(true); // left the app; the "left PiP" event never comes
    expect(changes, 1);

    await DeviceControls.handlePlatformCall(const MethodCall('pipChanged', false)); // onResume
    expect(DeviceControls.inPip.value, isFalse);
    expect(DeviceControls.pipOwner.value, isNull);
    expect(changes, 2);

    // Later resumes repeat it: nothing changes and nobody rebuilds.
    await DeviceControls.handlePlatformCall(const MethodCall('pipChanged', false));
    await DeviceControls.handlePlatformCall(const MethodCall('pipChanged', false));
    expect(changes, 2);
    expect(DeviceControls.inPip.value, isFalse);
  });

  test('a bad aspect falls back to 16:9', () async {
    await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline, aspect: double.nan);
    expect(calls.last, {'eligible': true, 'width': 1778, 'height': 1000});
  });

  group('picture-in-picture buttons (VID-09)', () {
    test("only the video player's window has them, with the right play / pause glyph", () async {
      await DeviceControls.setPipEligible(true);
      await DeviceControls.setPipPlaying(true);
      expect(calls.last['actionsPlaying'], true);
      await DeviceControls.setPipPlaying(false);
      expect(calls.last['actionsPlaying'], false);

      // The Online page's newer claim: its window gets no video buttons.
      await DeviceControls.setPipEligible(true, owner: DeviceControls.pipOwnerOnline);
      expect(calls.last.containsKey('actionsPlaying'), isFalse);
      await DeviceControls.setPipEligible(false, owner: DeviceControls.pipOwnerOnline);
      expect(calls.last['actionsPlaying'], false);

      await DeviceControls.setPipPlaying(null);
      expect(calls.last.containsKey('actionsPlaying'), isFalse);
    });

    test('window buttons reach Dart; unknown ones are dropped', () async {
      final got = <PipAction>[];
      final sub = DeviceControls.pipActions.listen(got.add);
      for (final raw in ['rewind', 'playPause', 'forward', 'explode', null]) {
        await DeviceControls.handlePlatformCall(MethodCall('pipAction', raw));
      }
      await Future<void>.delayed(Duration.zero);
      expect(got, [PipAction.rewind, PipAction.playPause, PipAction.forward]);
      await sub.cancel();
    });
  });

  group('headphones unplugged (VID-07 / ONL-6)', () {
    test('one native receiver for every owner, on while anyone listens', () async {
      final video = DeviceControls.watchBecomingNoisy('video_player');
      final online = DeviceControls.watchBecomingNoisy('online');
      expect(DeviceControls.watchBecomingNoisy('online'), online, reason: 'same owner, same stream');
      var videoHits = 0;
      var onlineHits = 0;
      final a = video.listen((_) => videoHits++);
      final b = online.listen((_) => onlineHits++);
      await Future<void>.delayed(Duration.zero);
      expect(watches.where((c) => c.method == 'watchNoisy').map((c) => c.arguments), [
        {'on': true},
      ]);
      expect(DeviceControls.debugNoisyOwners, unorderedEquals(['video_player', 'online']));

      await DeviceControls.handlePlatformCall(const MethodCall('becomingNoisy'));
      await Future<void>.delayed(Duration.zero);
      expect((videoHits, onlineHits), (1, 1));

      await a.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(watches.where((c) => c.method == 'watchNoisy'), hasLength(1), reason: 'Online still listens');
      await b.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(watches.where((c) => c.method == 'watchNoisy').last.arguments, {'on': false});
    });
  });

  group('volume changes (VID-02)', () {
    test('the receiver runs only while someone listens; values are clamped', () async {
      final got = <double>[];
      final sub = DeviceControls.volumeChanges.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      expect(watches.last.method, 'watchVolume');
      expect(watches.last.arguments, {'on': true});
      await DeviceControls.handlePlatformCall(const MethodCall('volumeChanged', 0.25));
      await DeviceControls.handlePlatformCall(const MethodCall('volumeChanged', 1.7));
      await DeviceControls.handlePlatformCall(const MethodCall('volumeChanged', 'loud'));
      await Future<void>.delayed(Duration.zero);
      expect(got, [0.25, 1.0]);
      await sub.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(watches.last.arguments, {'on': false});
    });
  });

  group('video boost (VID-01)', () {
    test('asks for the given player and a clamped percent; refuses bad ids without asking', () async {
      expect(await DeviceControls.setVideoBoost(playerId: 3, percent: 999), isTrue);
      expect(watches.last.method, 'setVideoBoost');
      expect(watches.last.arguments, {'playerId': 3, 'percent': DeviceControls.maxBoostPercent});
      watches.clear();
      expect(await DeviceControls.setVideoBoost(playerId: -1, percent: 150), isFalse);
      expect(watches, isEmpty);
    });

    test('off Android there is no boost', () async {
      PlatformInfo.debugIsAndroid = false;
      expect(DeviceControls.boostAvailable, isFalse);
      expect(await DeviceControls.setVideoBoost(playerId: 3, percent: 150), isFalse);
      expect(watches, isEmpty);
    });
  });
}
