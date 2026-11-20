import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/platform_info.dart';

/// `<documents>/downloads`: where every download and its cover image are
/// saved. Not created here (the Downloads providers create it on first use).
Future<Directory> appDownloadsFolder() async {
  final appDir = await getApplicationDocumentsDirectory();
  return Directory('${appDir.path}/downloads');
}

/// The downloads folder the database checks its saved file paths against
/// when it opens (see `AppDatabase.rebaseStoredPaths`).
///
/// Only iOS moves an app's folder: an update or a reinstall over the old
/// app gives it a new container folder. Everywhere else this is null, so
/// nothing is looked up and nothing is rewritten (Android paths never move).
Future<String?> downloadsFolderToHealPaths() async {
  if (!PlatformInfo.isIOS) return null;
  return (await appDownloadsFolder()).path;
}
