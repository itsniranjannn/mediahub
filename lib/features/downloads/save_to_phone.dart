// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/phone_media.dart';
import '../../core/platform_info.dart';
import '../../core/storage/settings_store.dart';
import '../../data/database/app_database.dart';
import '../../domain/models/media_item.dart';
import '../music_player/playback_notifier.dart' show appDatabaseProvider;
import 'download_providers.dart' show downloadDirectoryProvider;

/// Settings → Downloads → "Save downloads to".
enum DownloadSaveLocation {
  /// Inside MediaHub (private): the files stay in the app's own folder. The default.
  app,

  /// Phone storage: visible in Gallery, Files and other apps.
  phone;

  static DownloadSaveLocation parse(String? raw) =>
      raw == DownloadSaveLocation.phone.name ? DownloadSaveLocation.phone : DownloadSaveLocation.app;
}

class DownloadSaveLocationNotifier extends Notifier<DownloadSaveLocation> {
  static const String prefKey = 'download_save_location';

  /// Read where there is no Ref (the download engines' completion hook).
  static DownloadSaveLocation current() => DownloadSaveLocation.parse(SettingsStore.instance.getString(prefKey));

  @override
  DownloadSaveLocation build() => current();

  void set(DownloadSaveLocation value) {
    state = value;
    SettingsStore.instance.setString(prefKey, value.name);
  }
}

final downloadSaveLocationProvider =
    NotifierProvider<DownloadSaveLocationNotifier, DownloadSaveLocation>(DownloadSaveLocationNotifier.new);

/// How a "save to phone" ended.
enum SaveToPhoneResult {
  /// Moved (Android) or copied to Photos (iPhone video).
  saved,

  /// Already in the phone's storage (an Android download moved before, or
  /// iPhone audio, which the Files app already shows).
  alreadyThere,

  /// Not a download whose file is in MediaHub's folder (or it is missing).
  notPossible,

  /// The phone refused (full, no Photos access, an old Android).
  failed,
}

/// Puts a finished download where other apps see it.
///
/// **Android: a move, not a copy.** The file is copied into MediaStore
/// (Music/MediaHub for sound, Movies/MediaHub for video, with IS_PENDING so
/// other apps never see half a file); then the library row (same id, so
/// favourites, play counts, playlists and video progress stay) and the
/// download's card point at the new `content://` address, and the app's own
/// copy is deleted. The phone's file is therefore the only copy, and the
/// library scan skips it ([LibraryRepositoryImpl] ignores MediaStore rows a
/// download already points at): it is shown once. Deleting it from MediaHub
/// deletes the phone's file.
///
/// **iPhone**: audio is already in the Files app (Documents is shared, see
/// docs/IOS.md), so nothing moves; a video is also added to Photos (a copy:
/// MediaHub needs its own to play it, and never reads Photos, so the library
/// still shows it once).
class SaveToPhoneService {
  SaveToPhoneService({
    required AppDatabase db,
    required PhoneMedia phoneMedia,
    required Future<Directory> Function() downloadsDir,
  })  : _db = db, // ignore: prefer_initializing_formals
        _phone = phoneMedia,
        _dir = downloadsDir;

  final AppDatabase _db;
  final PhoneMedia _phone;
  final Future<Directory> Function() _dir;

  /// Library rows being saved right now (a second tap waits for nothing).
  final Set<String> _busy = {};

  /// Whether [item] can be offered "Save to phone".
  static bool canOffer(MediaItem item) =>
      item.source == 'download' && item.uri.isNotEmpty && !item.uri.contains('://');

  Future<SaveToPhoneResult> save(String mediaId) async {
    if (!_busy.add(mediaId)) return SaveToPhoneResult.alreadyThere;
    try {
      return await _save(mediaId);
    } finally {
      _busy.remove(mediaId);
    }
  }

  Future<SaveToPhoneResult> _save(String mediaId) async {
    final row = await (_db.select(_db.mediaItemsTable)..where((t) => t.id.equals(mediaId))).getSingleOrNull();
    if (row == null || row.source != 'download') return SaveToPhoneResult.notPossible;
    if (row.uri.startsWith('content://')) return SaveToPhoneResult.alreadyThere;
    if (row.uri.contains('://')) return SaveToPhoneResult.notPossible;
    final caps = await _phone.capabilities();
    if (!caps.canSaveToPhone) return SaveToPhoneResult.failed;

    final Directory dir;
    try {
      dir = await _dir();
    } catch (_) {
      return SaveToPhoneResult.notPossible;
    }
    final file = File(row.uri);
    if (!p.isWithin(p.normalize(dir.path), p.normalize(file.path)) || !file.existsSync()) {
      return SaveToPhoneResult.notPossible;
    }
    final isVideo = row.mediaType == MediaType.video.name;
    final downloads = await (_db.select(_db.downloadsTable)..where((t) => t.mediaId.equals(mediaId))).get();
    final mime = downloads.map((d) => d.mimeType).whereType<String>().firstOrNull;

    final String where;
    try {
      where = await _phone.saveToPhone(
        path: file.path,
        isVideo: isVideo,
        displayName: p.basename(file.path),
        mimeType: mime,
      );
    } catch (e) {
      DiagnosticsService.instance.logEvent('save_to_phone_failed', {'type': e.runtimeType.toString()});
      return SaveToPhoneResult.failed;
    }

    if (!where.startsWith('content://')) {
      // iPhone: the file stays where it is (audio: already in Files; video:
      // a copy went to Photos).
      DiagnosticsService.instance.logEvent('save_to_phone', {'kind': isVideo ? 'video' : 'audio', 'mode': 'ios'});
      return isVideo ? SaveToPhoneResult.saved : SaveToPhoneResult.alreadyThere;
    }

    final folder = isVideo ? 'Movies/MediaHub/' : 'Music/MediaHub/';
    try {
      await _db.transaction(() async {
        await (_db.update(_db.mediaItemsTable)..where((t) => t.id.equals(mediaId))).write(
          MediaItemsTableCompanion(uri: Value(where), relativePath: Value(folder)),
        );
        await (_db.update(_db.downloadsTable)..where((t) => t.mediaId.equals(mediaId))).write(
          DownloadsTableCompanion(finalPath: Value(where), updatedAt: Value(DateTime.now())),
        );
      });
    } catch (e) {
      // Nothing points at the phone's copy: remove it, or the library scan
      // would show the song twice. The app's own file is untouched.
      final removed = await _phone.discardSavedCopy(where).catchError((_) => false);
      DiagnosticsService.instance.logEvent('save_to_phone_failed', {
        'type': e.runtimeType.toString(),
        'stage': 'database',
        'rolled_back': removed,
      });
      return SaveToPhoneResult.failed;
    }
    // The phone's copy is the file now: the app's own goes (a leftover is
    // swept as an orphan, never played twice: no row points at it).
    try {
      await file.delete();
    } catch (_) {}
    DiagnosticsService.instance.logEvent('save_to_phone', {'kind': isVideo ? 'video' : 'audio', 'mode': 'mediastore'});
    return SaveToPhoneResult.saved;
  }

  /// Called by both download engines once a download is in the library:
  /// moves it when Settings say "Phone storage". Never throws.
  Future<void> onDownloadFinished(String mediaId) async {
    if (DownloadSaveLocationNotifier.current() != DownloadSaveLocation.phone) return;
    if (!PlatformInfo.isAndroid && !PlatformInfo.isIOS) return;
    try {
      await save(mediaId);
    } catch (e) {
      DiagnosticsService.instance.logEvent('save_to_phone_failed', {'type': e.runtimeType.toString()});
    }
  }
}

final saveToPhoneServiceProvider = Provider<SaveToPhoneService>((ref) => SaveToPhoneService(
      db: ref.watch(appDatabaseProvider),
      phoneMedia: ref.watch(phoneMediaProvider),
      downloadsDir: () => ref.read(downloadDirectoryProvider.future),
    ));
