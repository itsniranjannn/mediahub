// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/storage/settings_store.dart';

/// Settings → Appearance: follow the phone (the default), always dark, always
/// light, or Bijuli Classic (the original lime-on-violet look, always dark).
enum AppearanceChoice {
  system,
  dark,
  light,
  classic;

  /// The `MaterialApp.themeMode` for this choice.
  ThemeMode get themeMode => switch (this) {
        AppearanceChoice.system => ThemeMode.system,
        AppearanceChoice.dark || AppearanceChoice.classic => ThemeMode.dark,
        AppearanceChoice.light => ThemeMode.light,
      };
}

/// Holds the [AppearanceChoice]. `MediaHubApp` (lib/app/app.dart) reads it
/// for `themeMode`, `darkTheme` and the Ink Dock theme, so a choice applies
/// at once (docs/DESIGN.md 8.2).
class AppearanceSettingNotifier extends Notifier<AppearanceChoice> {
  /// The same key the earlier ThemeMode-only setting used; its saved values
  /// (system, dark, light) are valid choices.
  static const String prefKey = 'appearance_theme_mode';

  /// [SettingsStore] keeps booleans and string lists; the choice is stored
  /// as a one-element list holding its name. Unknown values mean system.
  static AppearanceChoice decode(List<String> saved) {
    if (saved.isEmpty) return AppearanceChoice.system;
    return AppearanceChoice.values
        .firstWhere((c) => c.name == saved.first, orElse: () => AppearanceChoice.system);
  }

  @override
  AppearanceChoice build() => decode(SettingsStore.instance.getStringList(prefKey));

  void set(AppearanceChoice choice) {
    if (choice == state) return;
    state = choice;
    SettingsStore.instance.setStringList(prefKey, [choice.name]);
    DiagnosticsService.instance.logEvent('setting_theme_mode_changed', {'mode': choice.name});
  }
}

final appearanceSettingProvider =
    NotifierProvider<AppearanceSettingNotifier, AppearanceChoice>(AppearanceSettingNotifier.new);

/// The `MaterialApp.themeMode` derived from [appearanceSettingProvider].
final themeModeSettingProvider =
    Provider<ThemeMode>((ref) => ref.watch(appearanceSettingProvider).themeMode);
