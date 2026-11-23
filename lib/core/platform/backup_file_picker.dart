import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform_info.dart';

/// Lets the user pick where a backup is saved, or which backup to read, with
/// the system's own file picker (Android's Storage Access Framework:
/// ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT). No storage permission is
/// needed: the app only touches the one file the user picked.
abstract class BackupFilePicker {
  /// False where there is no picker yet (iPhone: no document-picker plugin).
  bool get isSupported;

  /// Asks where to save [bytes] as [fileName]. True when saved, false when
  /// the user backed out. Throws [PlatformException] when writing failed.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Asks for a backup file and returns its bytes, or null when the user
  /// backed out. A file over [maxBytes] throws [PlatformException] `TOO_LARGE`.
  Future<Uint8List?> open({required int maxBytes});
}

class MethodChannelBackupFilePicker implements BackupFilePicker {
  static const MethodChannel _channel = MethodChannel('mediahub/backup_files');

  @override
  bool get isSupported => PlatformInfo.isAndroid;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final ok = await _channel.invokeMethod<bool>('save', {'fileName': fileName, 'bytes': bytes});
    return ok ?? false;
  }

  @override
  Future<Uint8List?> open({required int maxBytes}) =>
      _channel.invokeMethod<Uint8List>('open', {'maxBytes': maxBytes});
}

final backupFilePickerProvider = Provider<BackupFilePicker>((ref) => MethodChannelBackupFilePicker());
