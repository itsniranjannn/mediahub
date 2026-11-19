import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/storage/settings_store.dart';

/// Settings → Audio & headset → "Resume after other apps" (Android): music
/// that another app's sound paused plays again once that app stops, within
/// 30 minutes (the music handler's otherAppResumeWindow). On by default.
///
/// The music handler reads [isOn] itself each time it decides (main.dart
/// passes it in), so the setting works from launch, before Settings is ever
/// opened.
class ResumeAfterOtherAppsNotifier extends Notifier<bool> {
  static const String prefKey = 'resume_after_other_apps';

  /// The saved choice (on until the user turns it off).
  static bool isOn() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  @override
  bool build() => isOn();

  void set(bool value) {
    if (value == state) return;
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
    DiagnosticsService.instance.logEvent('setting_resume_after_other_apps_changed', {'enabled': value});
  }

  void toggle() => set(!state);
}

final resumeAfterOtherAppsProvider =
    NotifierProvider<ResumeAfterOtherAppsNotifier, bool>(ResumeAfterOtherAppsNotifier.new);
