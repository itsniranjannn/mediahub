// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/storage/settings_store.dart';

/// Settings → You: the name Home greets ("नमस्ते, `name`"). Empty means no
/// name, and Home keeps the plain greeting.
class UserNameNotifier extends Notifier<String> {
  static const String prefKey = 'user_name';

  /// Longest name kept, in user-perceived characters (Devanagari clusters
  /// count once).
  static const int maxLength = 24;

  /// Trims, folds inner whitespace runs to one space and cuts to [maxLength].
  static String normalize(String raw) {
    final folded = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final chars = folded.characters;
    return chars.length <= maxLength ? folded : chars.take(maxLength).toString().trimRight();
  }

  @override
  String build() {
    final saved = SettingsStore.instance.getStringList(prefKey);
    return saved.isEmpty ? '' : normalize(saved.first);
  }

  void set(String raw) {
    final name = normalize(raw);
    if (name == state) return;
    state = name;
    if (name.isEmpty) {
      SettingsStore.instance.remove(prefKey);
    } else {
      SettingsStore.instance.setStringList(prefKey, [name]);
    }
    // Never the name itself: only whether one is set.
    DiagnosticsService.instance.logEvent('setting_user_name_changed', {'set': name.isNotEmpty});
  }

  void clear() => set('');
}

final userNameProvider = NotifierProvider<UserNameNotifier, String>(UserNameNotifier.new);
