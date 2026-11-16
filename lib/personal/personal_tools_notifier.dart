import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/platform_info.dart';
import '../core/storage/settings_store.dart';
import 'extractor_backend.dart';

class PersonalToolsState {
  final bool isEnabled;
  final String ytDlpVersion;
  final bool isUpdating;
  final String? updateStatus;

  const PersonalToolsState({
    required this.isEnabled,
    this.ytDlpVersion = '',
    this.isUpdating = false,
    this.updateStatus,
  });

  PersonalToolsState copyWith({
    bool? isEnabled,
    String? ytDlpVersion,
    bool? isUpdating,
    String? updateStatus,
  }) {
    return PersonalToolsState(
      isEnabled: isEnabled ?? this.isEnabled,
      ytDlpVersion: ytDlpVersion ?? this.ytDlpVersion,
      isUpdating: isUpdating ?? this.isUpdating,
      updateStatus: updateStatus,
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

  /// Undo an update that broke downloads: back to the yt-dlp copy inside the app.
  Future<void> resetYtDlp() async {
    if (state.isUpdating) return;
    state = state.copyWith(isUpdating: true, updateStatus: 'Restoring the built-in yt-dlp...');
    try {
      await _backend.resetToBundled();
      final ver = await _backend.getVersion();
      state = state.copyWith(
        isUpdating: false,
        ytDlpVersion: ver,
        updateStatus: 'Restored the built-in yt-dlp',
      );
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateStatus: 'Reset failed: ${e is ExtractorException ? e.message : e.toString()}',
      );
    }
  }

  Future<void> updateYtDlp() async {
    if (state.isUpdating) return;
    state = state.copyWith(isUpdating: true, updateStatus: 'Updating yt-dlp...');
    try {
      final res = await _backend.update();
      final newVer = await _backend.getVersion();
      state = state.copyWith(
        isUpdating: false,
        ytDlpVersion: newVer,
        updateStatus: 'Updated: $res',
      );
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateStatus: 'Update failed: ${e.toString()}',
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
