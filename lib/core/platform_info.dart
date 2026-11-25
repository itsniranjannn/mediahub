// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';

/// Thin wrapper around `dart:io` Platform checks so UI gating can be
/// overridden in tests (desktop test hosts are neither Android nor iOS).
class PlatformInfo {
  PlatformInfo._();

  /// Test hooks. Leave null in production.
  static bool? debugIsAndroid;
  static bool? debugIsIOS;

  static bool get isAndroid => debugIsAndroid ?? Platform.isAndroid;
  static bool get isIOS => debugIsIOS ?? Platform.isIOS;

  /// Direct-URL downloads are pure Dart and work on both mobile platforms.
  static bool get supportsDownloads => isAndroid || isIOS;

  /// The yt-dlp based web link downloader is Android only.
  static bool get supportsWebLinkDownloader => isAndroid;

  static void resetForTests() {
    debugIsAndroid = null;
    debugIsIOS = null;
  }
}
