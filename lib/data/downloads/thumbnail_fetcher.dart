// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../../core/security/safe_http_client.dart';
import '../database/app_database.dart';

/// Downloads a cover image next to a download and records its path on the row,
/// so the card (and later the library) can show a real thumbnail offline.
/// Goes through [SafeHttpClient]: https only, public addresses only, size capped.
class ThumbnailFetcher {
  final AppDatabase _db;
  final SafeHttpClient _http;
  final Directory _dir;

  ThumbnailFetcher({
    required AppDatabase db,
    required SafeHttpClient http,
    required Directory dir,
  })  : _db = db, // ignore: prefer_initializing_formals
        _http = http, // ignore: prefer_initializing_formals
        _dir = dir; // ignore: prefer_initializing_formals

  static const int maxBytes = 3 * 1024 * 1024;

  Future<void> fetchFor(String downloadId, String url) async {
    if (!url.startsWith('https://')) return;
    try {
      final res = await _http
          .request(Uri.parse(url), maxBodySize: maxBytes)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || !looksLikeImage(res.bodyBytes)) return;
      if (!_dir.existsSync()) _dir.createSync(recursive: true);
      final file = File(p.join(_dir.path, '$downloadId.thumb'));
      await file.writeAsBytes(res.bodyBytes, flush: true);
      final row = await (_db.select(_db.downloadsTable)..where((t) => t.id.equals(downloadId)))
          .getSingleOrNull();
      if (row == null) {
        // The download was deleted while the image was on its way.
        if (file.existsSync()) file.deleteSync();
        return;
      }
      await (_db.update(_db.downloadsTable)..where((t) => t.id.equals(downloadId))).write(
        DownloadsTableCompanion(thumbnailPath: Value(file.path)),
      );
    } catch (_) {
      // Thumbnails are cosmetic: never fail a download because of one.
    }
  }

  static bool looksLikeImage(List<int> b) {
    if (b.length < 12) return false;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final webp = b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50;
    return jpeg || png || webp;
  }
}
