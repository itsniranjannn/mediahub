import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/logging/diagnostics_service.dart';
import '../music_player/music_audio_handler.dart';
import '../music_player/playback_notifier.dart';

class ResumeOnHeadphonesReconnectNotifier extends Notifier<bool> {
  MusicAudioHandler get _handler => ref.read(audioHandlerProvider);

  @override
  bool build() {
    return _handler.resumeOnHeadphonesReconnect;
  }

  void toggle() {
    state = !state;
    _handler.setResumeOnHeadphonesReconnect(state);
    DiagnosticsService.instance.logEvent('setting_resume_on_reconnect_changed', {'enabled': state});
  }
}

final resumeOnHeadphonesReconnectProvider =
    NotifierProvider<ResumeOnHeadphonesReconnectNotifier, bool>(
  ResumeOnHeadphonesReconnectNotifier.new,
);
