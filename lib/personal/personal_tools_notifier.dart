import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  PersonalToolsState build() {
    return const PersonalToolsState(isEnabled: false);
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(isEnabled: enabled);
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
