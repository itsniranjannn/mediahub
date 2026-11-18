import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/platform_info.dart';
import '../core/storage/settings_store.dart';
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

  const PersonalToolsState({
    required this.isEnabled,
    this.ytDlpVersion = '',
    this.isUpdating = false,
    this.updateStatus,
    this.updateFailed = false,
  });

  PersonalToolsState copyWith({
    bool? isEnabled,
    String? ytDlpVersion,
    bool? isUpdating,
    String? updateStatus,
    bool updateFailed = false,
  }) {
    return PersonalToolsState(
      isEnabled: isEnabled ?? this.isEnabled,
      ytDlpVersion: ytDlpVersion ?? this.ytDlpVersion,
      isUpdating: isUpdating ?? this.isUpdating,
      updateStatus: updateStatus,
      updateFailed: updateFailed,
    );
  }
}

class PersonalToolsNotifier extends Notifier<PersonalToolsState> {
  ExtractorBackend get _backend => ref.read(extractorBackendProvider);

  static const String _prefKey = 'personal_tools_enabled';

  @override
  PersonalToolsState build() {
    // Remembered across restarts: it used to reset to "off" on every launch.
    // On by default on Android: this app is built around downloading. The
    // first download still shows the notice, and Settings can switch it off.
    final enabled = SettingsStore.instance.getBool(_prefKey, defaultValue: PlatformInfo.supportsWebLinkDownloader);
    if (enabled) {
      Future.microtask(() async {
        try {
          await _backend.init();
          await _fetchVersion();
        } catch (_) {}
      });
    }
    return PersonalToolsState(isEnabled: enabled);
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

  Future<void> _fetchVersion() async {
    try {
      final v = await _backend.getVersion();
      state = state.copyWith(ytDlpVersion: v);
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
      final res = await _backend.update();
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

final personalToolsProvider = NotifierProvider<PersonalToolsNotifier, PersonalToolsState>(
  PersonalToolsNotifier.new,
);
