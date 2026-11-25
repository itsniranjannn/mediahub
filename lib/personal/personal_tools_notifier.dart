// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/platform_info.dart';
import '../core/storage/settings_store.dart';
import 'extractor_auto_updater.dart';
import 'extractor_backend.dart';

class PersonalToolsState {
  final bool isEnabled;
  final String ytDlpVersion;
  final bool isUpdating;

  /// One plain line about the last Update or Reset ("Already up to date",
  /// "Updated to 2026.11.01", "Could not update. Check your connection.").
  final String? updateStatus;

  /// [updateStatus] reports a failure (shown in the error colour).
  final bool updateFailed;

  /// When a new yt-dlp was last installed (by MediaHub itself or Update).
  final DateTime? lastUpdated;

  /// When yt-dlp was last checked for a new version.
  final DateTime? lastChecked;

  const PersonalToolsState({
    required this.isEnabled,
    this.ytDlpVersion = '',
    this.isUpdating = false,
    this.updateStatus,
    this.updateFailed = false,
    this.lastUpdated,
    this.lastChecked,
  });

  PersonalToolsState copyWith({
    bool? isEnabled,
    String? ytDlpVersion,
    bool? isUpdating,
    String? updateStatus,
    bool updateFailed = false,
    DateTime? lastUpdated,
    DateTime? lastChecked,
  }) {
    return PersonalToolsState(
      isEnabled: isEnabled ?? this.isEnabled,
      ytDlpVersion: ytDlpVersion ?? this.ytDlpVersion,
      isUpdating: isUpdating ?? this.isUpdating,
      updateStatus: updateStatus,
      updateFailed: updateFailed,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  /// The Settings row under "yt-dlp engine version": the version and when it
  /// was last updated or checked, e.g. "2026.11.10 · Updated today".
  String versionLine({DateTime? now}) => formatVersionLine(
        ytDlpVersion,
        lastUpdated: lastUpdated,
        lastChecked: lastChecked,
        now: now ?? DateTime.now(),
      );

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  /// "today", "yesterday", "3 days ago" or "19 Nov 2026".
  static String formatWhen(DateTime when, DateTime now) {
    final day = DateTime(when.year, when.month, when.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return 'on ${when.day} ${_months[when.month - 1]} ${when.year}';
  }

  /// See [versionLine]. A check after the last update says "Checked": the
  /// version shown is then known to be the newest.
  static String formatVersionLine(
    String version, {
    DateTime? lastUpdated,
    DateTime? lastChecked,
    required DateTime now,
  }) {
    final v = version.trim();
    if (v.isEmpty) return 'Loading...';
    final checkedLater = lastChecked != null &&
        (lastUpdated == null || lastChecked.difference(lastUpdated) > const Duration(minutes: 1));
    if (checkedLater) return '$v · Checked ${formatWhen(lastChecked, now)}';
    if (lastUpdated != null) return '$v · Updated ${formatWhen(lastUpdated, now)}';
    return v;
  }
}

class PersonalToolsNotifier extends Notifier<PersonalToolsState> {
  ExtractorBackend get _backend => ref.read(extractorBackendProvider);
  ExtractorAutoUpdater get _updater => ref.read(extractorAutoUpdaterProvider);

  static const String _prefKey = 'personal_tools_enabled';

  @override
  PersonalToolsState build() {
    // Remembered across restarts: it used to reset to "off" on every launch.
    // On by default on Android: this app is built around downloading. The
    // first download still shows the notice, and Settings can switch it off.
    final enabled = SettingsStore.instance.getBool(_prefKey, defaultValue: PlatformInfo.supportsWebLinkDownloader);

    // MediaHub updates yt-dlp by itself (after a failure, and once a week):
    // Settings then shows the new version and when it happened.
    final updater = ref.watch(extractorAutoUpdaterProvider);
    void onAutoUpdate() {
      if (!ref.mounted) return;
      state = state.copyWith(
        lastUpdated: updater.lastUpdated,
        lastChecked: updater.lastChecked,
        updateStatus: state.updateStatus,
        updateFailed: state.updateFailed,
      );
      if (state.isEnabled && !state.isUpdating) unawaited(_fetchVersion(keepStatus: true));
    }

    updater.addListener(onAutoUpdate);
    ref.onDispose(() => updater.removeListener(onAutoUpdate));

    if (enabled) {
      Future.microtask(() async {
        try {
          await _backend.init();
          await _fetchVersion();
          // The quiet weekly check (only in release builds; never on metered data).
          await updater.backgroundCheck();
        } catch (_) {}
      });
    }
    return PersonalToolsState(
      isEnabled: enabled,
      lastUpdated: updater.lastUpdated,
      lastChecked: updater.lastChecked,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(isEnabled: enabled);
    await SettingsStore.instance.setBool(_prefKey, enabled);
    if (enabled) {
      try {
        await _backend.init();
        await _fetchVersion();
      } catch (_) {}
    }
  }

  Future<void> _fetchVersion({bool keepStatus = false}) async {
    try {
      final v = await _backend.getVersion();
      if (!ref.mounted) return;
      state = keepStatus
          ? state.copyWith(ytDlpVersion: v, updateStatus: state.updateStatus, updateFailed: state.updateFailed)
          : state.copyWith(ytDlpVersion: v);
    } catch (_) {}
  }

  /// Shown when yt-dlp is busy with a download (the native side refuses).
  static const String busyMessage = 'Wait for your web link downloads to finish first.';
  static const String upToDateMessage = 'Already up to date';
  static const String updateFailedMessage = 'Could not update. Check your connection.';
  static const String restoredMessage = 'Restored the built-in yt-dlp';
  static const String restoreFailedMessage = 'Could not restore the built-in yt-dlp. Try again.';

  /// The plain line for an update that finished with native status [status]
  /// ('ALREADY_UP_TO_DATE' or 'DONE') and left [version] in place.
  static String updatedMessage(String status, String version) {
    if (status.toUpperCase() == 'ALREADY_UP_TO_DATE') return upToDateMessage;
    final v = version.trim();
    return v.isEmpty ? 'Updated' : 'Updated to $v';
  }

  static bool _isBusy(Object e) => e is ExtractorException && e.code == 'BUSY';

  /// Undo an update that broke downloads: back to the yt-dlp copy inside the app.
  Future<void> resetYtDlp() async {
    if (state.isUpdating) return;
    state = state.copyWith(isUpdating: true, updateStatus: 'Restoring the built-in yt-dlp...');
    try {
      await _backend.resetToBundled();
      final ver = await _backend.getVersion();
      state = state.copyWith(isUpdating: false, ytDlpVersion: ver, updateStatus: restoredMessage);
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateStatus: _isBusy(e) ? busyMessage : restoreFailedMessage,
        updateFailed: true,
      );
    }
  }

  Future<void> updateYtDlp() async {
    if (state.isUpdating) return;
    state = state.copyWith(isUpdating: true, updateStatus: 'Updating yt-dlp...');
    try {
      // Through the auto-updater, so the time of this update is remembered too.
      final res = await _updater.updateNow();
      final newVer = await _backend.getVersion();
      state = state.copyWith(isUpdating: false, ytDlpVersion: newVer, updateStatus: updatedMessage(res, newVer));
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateStatus: _isBusy(e) ? busyMessage : updateFailedMessage,
        updateFailed: true,
      );
    }
  }
}

final extractorBackendProvider = Provider<ExtractorBackend>((ref) {
  return AndroidExtractorBackend();
});

/// Keeps yt-dlp current (see [ExtractorAutoUpdater]). The quiet weekly check
/// runs only in release builds, so tests and development runs never download
/// a new yt-dlp by themselves.
final extractorAutoUpdaterProvider = Provider<ExtractorAutoUpdater>((ref) {
  final updater = ExtractorAutoUpdater(
    backend: ref.watch(extractorBackendProvider),
    backgroundChecks: !kDebugMode,
  );
  ref.onDispose(updater.dispose);
  return updater;
});

final personalToolsProvider = NotifierProvider<PersonalToolsNotifier, PersonalToolsState>(
  PersonalToolsNotifier.new,
);
