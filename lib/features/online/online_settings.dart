import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/storage/settings_store.dart';

/// Keeps YouTube audio playing with the screen off or the app in the
/// background (Settings → Online, the Online ⋮ menu and the watch strip).
class OnlineBackgroundPlayNotifier extends Notifier<bool> {
  static const String prefKey = 'online_background_play';

  @override
  bool build() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  void set(bool value) {
    if (value == state) return;
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
    DiagnosticsService.instance.logEvent('setting_online_background_play_changed', {'enabled': value});
  }

  void toggle() => set(!state);
}

final onlineBackgroundPlayProvider =
    NotifierProvider<OnlineBackgroundPlayNotifier, bool>(OnlineBackgroundPlayNotifier.new);

/// Enters picture-in-picture by itself when the user leaves the app while a
/// YouTube video plays on screen.
class OnlineAutoPipNotifier extends Notifier<bool> {
  static const String prefKey = 'online_auto_pip';

  @override
  bool build() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  void set(bool value) {
    if (value == state) return;
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
    DiagnosticsService.instance.logEvent('setting_online_auto_pip_changed', {'enabled': value});
  }

  void toggle() => set(!state);
}

final onlineAutoPipProvider = NotifierProvider<OnlineAutoPipNotifier, bool>(OnlineAutoPipNotifier.new);
