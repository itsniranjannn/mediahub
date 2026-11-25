import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// MediaHub ships a newer yt-dlp than the one inside youtubedl-android 0.18.1
/// (2025.11.12, which YouTube no longer serves well: 1080p fails part-way with
/// HTTP 403). tools/device/update_ytdlp_asset.py makes the asset; the native
/// channel installs it when it is newer than the phone's copy.
const _assetDir = 'android/app/src/main/assets/ytdlp';
const _libraryVersion = '2025.11.12';

final _versionRe = RegExp(r'^\d{4}\.\d{1,2}\.\d{1,2}(\.\d+)?$');

int _compare(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final c = (i < pa.length ? pa[i] : 0).compareTo(i < pb.length ? pb[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

/// The stored or deflated bytes of [name] inside the zip [bytes] (local headers).
Uint8List? _zipEntry(Uint8List bytes, String name) {
  final data = ByteData.sublistView(bytes);
  var i = 0;
  while (i + 30 <= bytes.length) {
    if (data.getUint32(i, Endian.little) != 0x04034b50) {
      i++;
      continue;
    }
    final method = data.getUint16(i + 8, Endian.little);
    final compressed = data.getUint32(i + 18, Endian.little);
    final nameLen = data.getUint16(i + 26, Endian.little);
    final extraLen = data.getUint16(i + 28, Endian.little);
    final entryName = String.fromCharCodes(bytes.sublist(i + 30, i + 30 + nameLen));
    final start = i + 30 + nameLen + extraLen;
    if (entryName == name) {
      final raw = bytes.sublist(start, start + compressed);
      if (method == 0) return raw;
      return Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
    }
    i = start + compressed;
  }
  return null;
}

void main() {
  final versionFile = File('$_assetDir/version.txt');
  final appFile = File('$_assetDir/yt-dlp');

  test('a yt-dlp newer than the library\'s is shipped, with its version beside it', () {
    expect(versionFile.existsSync(), isTrue, reason: 'run tools/device/update_ytdlp_asset.py');
    final version = versionFile.readAsStringSync().trim();
    expect(version, matches(_versionRe));
    expect(_compare(version, _libraryVersion), greaterThan(0));
  });

  test('the asset is a Python zip application of that very version', () {
    final bytes = appFile.readAsBytesSync();
    const shebang = '#!/usr/bin/env python3\n';
    expect(String.fromCharCodes(bytes.sublist(0, shebang.length)), shebang);
    expect(String.fromCharCodes(bytes.sublist(shebang.length, shebang.length + 2)), 'PK');
    expect(_zipEntry(bytes, '__main__.py'), isNotNull);
    final versionPy = _zipEntry(bytes, 'yt_dlp/version.py');
    expect(versionPy, isNotNull);
    final declared = RegExp(r"__version__ = '([^']+)'").firstMatch(String.fromCharCodes(versionPy!))!.group(1);
    expect(declared, versionFile.readAsStringSync().trim());
    // The YouTube challenge scripts yt-dlp pins come along (the library passes QuickJS to it).
    expect(_zipEntry(bytes, 'yt_dlp_ejs/__init__.py'), isNotNull);
    expect(bytes.length, inInclusiveRange(1000000, 8000000), reason: 'about 3 MB');
  });

  group('ExtractorChannel.kt', () {
    late String src;
    setUp(() => src = File('android/app/src/main/kotlin/com/example/mediahub/personal/ExtractorChannel.kt')
        .readAsStringSync()
        .replaceAll('\r\n', '\n'));

    test('every run installs the shipped copy first, outside the read lock', () {
      final runs = RegExp(r'installShippedYtDlpOnce\(\)\n\s*val readLock = engineLock\.readLock\(\)\n\s*readLock\.lock\(\)')
          .allMatches(src)
          .length;
      expect(runs, 4, reason: 'init, version, lookup, download');
      expect(src, contains('if (!writeLock.tryLock()) return'), reason: 'never while yt-dlp runs');
    });

    test('only a newer version replaces the phone\'s copy, by a rename, and is recorded like an update', () {
      expect(src, contains('private const val LIBRARY_YTDLP_VERSION = "$_libraryVersion"'));
      expect(src, contains('if (compareYtDlpVersions(shipped, current) <= 0) return false'));
      expect(src, contains('if (!tmp.renameTo(target)) return false'));
      expect(src, contains('.putString("dlpVersion", shipped)'));
      expect(src, contains('.putString("dlpVersionName", "yt-dlp \$shipped (shipped with MediaHub)")'));
    });

    test('Update compares against it and "Use the built-in yt-dlp" means it', () {
      expect(src, contains('ensureInitialized()\n                installShippedYtDlpLocked()'));
      // The library's unchecked updateYoutubeDL is never called: the update is
      // checked against the release's SHA2-256SUMS first.
      expect(src, contains('val statusName = verifiedYtDlpUpdateLocked()'));
      expect(src, isNot(contains('getInstance().updateYoutubeDL(')));
      expect(src, contains('"SHA2-256SUMS" -> sumsUrl = url'));
      expect(src, contains('does not match its published checksum'));
      expect(src, contains('YoutubeDL.getInstance().init_ytdlp(app, ytdlpDir)\n                bundledVersion = null\n                installShippedYtDlpLocked()'));
    });
  });
}
