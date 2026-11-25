// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform_info.dart';

/// Where MediaHub keeps its own files that no person or other app should
/// see or edit: `settings.json` (with the App lock switch), the database and
/// `diagnostics.log`.
///
/// - **iPhone**: Library/Application Support. `Info.plist` turns on file
///   sharing so the Files app shows Documents (the downloaded songs in
///   Documents/downloads); Application Support is never shown there, so
///   nobody can edit `settings.json` to turn the App lock off, or delete the
///   database (docs/IOS.md).
/// - **Android**: the app's private `app_flutter` folder as before (nothing
///   moves; no other app can read it).
Future<Directory> appPrivateDataDir() async {
  final hook = debugPrivateDataDir;
  if (hook != null) return hook();
  if (PlatformInfo.isIOS) {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
  return getApplicationDocumentsDirectory();
}

/// Test hook for [appPrivateDataDir].
@visibleForTesting
Future<Directory> Function()? debugPrivateDataDir;

/// The private files that used to sit in Documents on the iPhone.
@visibleForTesting
const List<String> privateFileNames = [
  'settings.json',
  'settings.json.bad',
  'settings.json.tmp',
  'diagnostics.log',
  'media_hub_db.sqlite',
  'media_hub_db.sqlite-wal',
  'media_hub_db.sqlite-shm',
  'media_hub_db.sqlite-journal',
];

/// One-time move (iPhone) of [privateFileNames] from Documents to
/// Application Support. Runs at start before anything opens them. A file
/// already in the new place wins (the old copy is then deleted, so the Files
/// app no longer shows it). Never throws; returns how many files moved.
Future<int> migratePrivateFilesOutOfDocuments() async {
  if (!PlatformInfo.isIOS && debugPrivateDataDir == null) return 0;
  try {
    final from = await (debugDocumentsDir ?? getApplicationDocumentsDirectory)();
    final to = await appPrivateDataDir();
    return await moveFiles(from: from, to: to, names: privateFileNames);
  } catch (_) {
    return 0;
  }
}

/// Test hook: the old (Documents) folder.
@visibleForTesting
Future<Directory> Function()? debugDocumentsDir;

/// Moves each of [names] from [from] to [to] (rename, else copy + delete).
@visibleForTesting
Future<int> moveFiles({required Directory from, required Directory to, required List<String> names}) async {
  if (p.equals(from.path, to.path)) return 0;
  var moved = 0;
  if (!await to.exists()) await to.create(recursive: true);
  for (final name in names) {
    final src = File(p.join(from.path, name));
    try {
      if (!await src.exists()) continue;
      final dst = File(p.join(to.path, name));
      if (await dst.exists()) {
        await src.delete();
        continue;
      }
      try {
        await src.rename(dst.path);
      } on FileSystemException {
        await src.copy(dst.path);
        await src.delete();
      }
      moved++;
    } catch (_) {
      // Left where it was; tried again on the next start.
    }
  }
  return moved;
}
