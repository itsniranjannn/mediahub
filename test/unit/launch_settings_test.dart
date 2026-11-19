// Saved playback choices reach the music handler at launch, not only once
// the Settings screen has been opened (found by the playback package: a
// "Resume when headphones reconnect" turned off came back on after a restart
// until Settings was visited).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/settings/settings_notifier.dart';

void main() {
  test('the saved "Resume when headphones reconnect" choice is readable without Settings', () async {
    await SettingsStore.instance.setBool('resume_on_headphones_reconnect', false);
    expect(ResumeOnHeadphonesReconnectNotifier.isOn(), isFalse);
    await SettingsStore.instance.setBool('resume_on_headphones_reconnect', true);
    expect(ResumeOnHeadphonesReconnectNotifier.isOn(), isTrue);
  });

  test('main.dart hands it to the handler before the app starts', () {
    final main = File('lib/main.dart').readAsStringSync();
    final applied = main.indexOf('handler.setResumeOnHeadphonesReconnect(ResumeOnHeadphonesReconnectNotifier.isOn());');
    expect(applied, greaterThan(0));
    expect(applied, lessThan(main.indexOf('await startAudioService<MusicAudioHandler>(')));
    expect(main.indexOf('await SettingsStore.instance.load();'), lessThan(applied), reason: 'read after the file is loaded');
  });
}
