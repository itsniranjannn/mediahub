import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/backup_file_picker.dart';
import '../../core/storage/settings_store.dart';
import '../../data/backup/library_backup.dart';
import '../../data/repositories/library_repository_impl.dart' show databaseProvider;
import '../downloads/mobile_data_guard.dart';
import '../music_player/resume_after_other_apps.dart';
import '../online/online_settings.dart';
import 'settings_notifier.dart';
import 'theme_mode_setting.dart';
import 'user_name_setting.dart';

final libraryBackupServiceProvider = Provider<LibraryBackupService>(
  (ref) => LibraryBackupService(ref.watch(databaseProvider), SettingsStore.instance),
);

/// Shown on an iPhone, where there is no file picker yet.
const String backupIosMessage = 'Backups work on Android for now. On iPhone this needs a file picker MediaHub does not have yet.';

/// Settings → Backup & restore → "Save a backup".
Future<void> saveLibraryBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  final picker = ref.read(backupFilePickerProvider);
  if (!picker.isSupported) return say(backupIosMessage);
  final service = ref.read(libraryBackupServiceProvider);
  try {
    final now = DateTime.now();
    final data = await service.export(now: now);
    final saved = await picker.save(LibraryBackup.fileNameFor(now), Uint8List.fromList(data.encode()));
    if (saved) {
      DiagnosticsService.instance.logEvent('backup_saved', {'items': data.items.length, 'playlists': data.playlists.length});
      say('Backup saved');
    }
  } catch (e) {
    DiagnosticsService.instance.logEvent('backup_save_failed', {'error': e.runtimeType.toString()});
    say('Could not save the backup. Please try again.');
  }
}

/// Settings → Backup & restore → "Restore from backup": pick a file, check it,
/// confirm, merge, then say what was found.
Future<void> restoreLibraryBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  final picker = ref.read(backupFilePickerProvider);
  if (!picker.isSupported) return say(backupIosMessage);
  final service = ref.read(libraryBackupServiceProvider);

  final BackupData data;
  try {
    final bytes = await picker.open(maxBytes: LibraryBackup.maxBytes);
    if (bytes == null) return; // backed out
    data = BackupData.decode(bytes);
  } on BackupFormatException catch (e) {
    return say(e.message);
  } on PlatformException catch (e) {
    return say(e.code == 'TOO_LARGE'
        ? 'This file is too large to be a MediaHub backup.'
        : 'Could not read that file. Please try again.');
  }
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(restoreSummary(data)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final RestoreReport report;
  try {
    report = await service.restore(data);
  } catch (e) {
    DiagnosticsService.instance.logEvent('backup_restore_failed', {'error': e.runtimeType.toString()});
    return say('Could not restore the backup. Nothing was changed.');
  }
  DiagnosticsService.instance.logEvent('backup_restored', {
    'favorites': '${report.favoritesRestored}/${report.favoritesTotal}',
    'songs': '${report.playlistSongsRestored}/${report.playlistSongsTotal}',
  });
  // Settings were written behind the providers' backs: read them again.
  ref.invalidate(themeModeSettingProvider);
  ref.invalidate(appearanceSettingProvider);
  ref.invalidate(userNameProvider);
  ref.invalidate(resumeOnHeadphonesReconnectProvider);
  ref.invalidate(resumeAfterOtherAppsProvider);
  ref.invalidate(onlineBackgroundPlayProvider);
  ref.invalidate(onlineAutoPipProvider);
  ref.invalidate(onlineBlockAdsProvider);
  ref.invalidate(askBeforeBigDownloadsProvider);
  if (!context.mounted) return;
  final lines = report.lines;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Backup restored'),
      content: Text([
        if (lines.isEmpty) 'There was nothing to restore.' else ...lines,
        if (report.anyMissing) '\nSongs and videos that are not on this phone could not be matched.',
      ].join('\n')),
      actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
    ),
  );
}

/// What the confirm dialog says about [data].
String restoreSummary(BackupData data) {
  final d = data.createdAt.toLocal();
  final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final parts = [
    '${data.favoriteCount} ${data.favoriteCount == 1 ? 'favourite' : 'favourites'}',
    '${data.playlists.length} ${data.playlists.length == 1 ? 'playlist' : 'playlists'}',
    if (data.videoPositions.isNotEmpty) '${data.videoPositions.length} video positions',
  ];
  return 'Backup from $date: ${parts.join(', ')}.\n\n'
      'They are added to your library. Nothing on this phone is removed.';
}
