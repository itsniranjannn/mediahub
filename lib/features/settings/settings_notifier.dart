// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/storage/settings_store.dart';
import '../music_player/music_audio_handler.dart';
import '../music_player/playback_notifier.dart';

class ResumeOnHeadphonesReconnectNotifier extends Notifier<bool> {
  MusicAudioHandler get _handler => ref.read(audioHandlerProvider);

  static const String _prefKey = 'resume_on_headphones_reconnect';

  /// The saved choice (on until the user turns it off). main.dart hands it
  /// to the music handler at launch, so it holds before Settings is opened.
  static bool isOn() => SettingsStore.instance.getBool(_prefKey, defaultValue: true);

  @override
  bool build() {
    final saved = isOn();
    if (saved != _handler.resumeOnHeadphonesReconnect) {
      _handler.setResumeOnHeadphonesReconnect(saved);
    }
    return saved;
  }

  void toggle() {
    state = !state;
    _handler.setResumeOnHeadphonesReconnect(state);
    SettingsStore.instance.setBool(_prefKey, state);
    DiagnosticsService.instance.logEvent('setting_resume_on_reconnect_changed', {'enabled': state});
  }
}

final resumeOnHeadphonesReconnectProvider =
    NotifierProvider<ResumeOnHeadphonesReconnectNotifier, bool>(
  ResumeOnHeadphonesReconnectNotifier.new,
);
