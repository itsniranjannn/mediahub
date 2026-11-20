// The Dart side of "mediahub/other_audio" (OtherAudioChannel.kt): start and
// stop go to the phone, and its reports arrive as events.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform/other_audio_watcher.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/music_player/resume_after_other_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mediahub/other_audio_test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> fromPhone(Object? args) async {
    final data = const StandardMethodCodec().encodeMethodCall(MethodCall('otherAudio', args));
    await messenger.handlePlatformMessage(channel.name, data, (_) {});
  }

  test('start and stop reach the phone; its reports arrive as events', () async {
    final watcher = MethodChannelOtherAudioWatcher(channel: channel);
    final events = <OtherAudioState>[];
    watcher.events.listen(events.add);

    await watcher.start();
    await fromPhone({'playing': true, 'inCall': false});
    await fromPhone({'playing': false, 'inCall': true});
    await watcher.stop();
    await pumpEventQueue();

    expect(calls, ['start', 'stop']);
    expect(events, const [
      OtherAudioState(otherPlaying: true),
      OtherAudioState(otherPlaying: false, inCall: true),
    ]);
  });

  test('a report it cannot read is ignored', () {
    expect(MethodChannelOtherAudioWatcher.parse(null), isNull);
    expect(MethodChannelOtherAudioWatcher.parse({'playing': 'yes'}), isNull);
    expect(MethodChannelOtherAudioWatcher.parse({'playing': false}), const OtherAudioState(otherPlaying: false));
  });

  test('no native side (another platform): start fails, stop does not', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final watcher = MethodChannelOtherAudioWatcher(channel: channel);
    await expectLater(watcher.start(), throwsA(isA<MissingPluginException>()));
    await watcher.stop();
  });

  test('Settings: "Resume after other apps" is on by default and the choice is kept', () async {
    addTearDown(() => SettingsStore.instance.setBool(ResumeAfterOtherAppsNotifier.prefKey, true));
    final first = ProviderContainer();
    addTearDown(first.dispose);
    expect(first.read(resumeAfterOtherAppsProvider), isTrue);
    expect(ResumeAfterOtherAppsNotifier.isOn(), isTrue);

    first.read(resumeAfterOtherAppsProvider.notifier).toggle();
    expect(first.read(resumeAfterOtherAppsProvider), isFalse);
    expect(ResumeAfterOtherAppsNotifier.isOn(), isFalse, reason: 'what the music player reads');

    final later = ProviderContainer();
    addTearDown(later.dispose);
    expect(later.read(resumeAfterOtherAppsProvider), isFalse);
  });
}
