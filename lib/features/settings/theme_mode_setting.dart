import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/storage/settings_store.dart';

/// Settings → Appearance: follow the phone (the default), or always dark or
/// always light (docs/DESIGN.md 8.2). `MediaHubApp` (lib/app/app.dart) passes
/// [themeModeSettingProvider] to `MaterialApp.themeMode`, so a choice applies
/// at once.
class ThemeModeSettingNotifier extends Notifier<ThemeMode> {
  static const String prefKey = 'appearance_theme_mode';

  /// [SettingsStore] keeps booleans and string lists; the choice is stored
  /// as a one-element list holding its [ThemeMode.name].
  static ThemeMode decode(List<String> saved) {
    if (saved.isEmpty) return ThemeMode.system;
    return ThemeMode.values.firstWhere((m) => m.name == saved.first, orElse: () => ThemeMode.system);
  }

  @override
  ThemeMode build() => decode(SettingsStore.instance.getStringList(prefKey));

  void set(ThemeMode mode) {
    if (mode == state) return;
    state = mode;
    SettingsStore.instance.setStringList(prefKey, [mode.name]);
    DiagnosticsService.instance.logEvent('setting_theme_mode_changed', {'mode': mode.name});
  }
}

final themeModeSettingProvider =
    NotifierProvider<ThemeModeSettingNotifier, ThemeMode>(ThemeModeSettingNotifier.new);
