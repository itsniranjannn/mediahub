// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform_info.dart';

/// The system share sheet (Android `ACTION_SEND` chooser).
///
/// - Downloads (files the app owns) are offered through the app's private,
///   read-only provider, which serves only the downloads folder; any other
///   file path is refused.
/// - Phone media pass their MediaStore `content://` URI as is.
/// - Links and other text go as plain text.
///
/// Nothing is shared without the user picking an app in the chooser. Every
/// call fails soft: false means the sheet could not open (not Android, no
/// app can receive it, or the file is not shareable).
class ShareChannel {
  ShareChannel._();

  static const MethodChannel _channel = MethodChannel('mediahub/share');

  /// Whether this platform has the share sheet (Android only for now).
  static bool get available => PlatformInfo.isAndroid;

  /// Opens the share sheet for one media file. [uriOrPath] is a MediaStore
  /// `content://` URI, a `file://` URI or a plain path inside the app's
  /// downloads folder; [mimeType] is its type (e.g. `audio/mpeg`, `video/*`).
  static Future<bool> shareFile({
    required String uriOrPath,
    required String mimeType,
    String? title,
  }) async {
    if (!available || uriOrPath.isEmpty) return false;
    try {
      return (await _channel.invokeMethod<bool>('shareFile', {
            'uriOrPath': uriOrPath,
            'mimeType': mimeType.isEmpty ? '*/*' : mimeType,
            'title': ?title,
          })) ??
          false;
    } catch (e) {
      debugPrint('[Share] file failed: $e');
      return false;
    }
  }

  /// Opens the share sheet for [text] (a link, a title).
  static Future<bool> shareText(String text, {String? subject}) async {
    if (!available || text.trim().isEmpty) return false;
    try {
      return (await _channel.invokeMethod<bool>('shareText', {
            'text': text,
            'subject': ?subject,
          })) ??
          false;
    } catch (e) {
      debugPrint('[Share] text failed: $e');
      return false;
    }
  }

  /// A MIME type for [pathOrName] from its extension, for callers that only
  /// know the file name; [fallback] (e.g. `audio/*`) otherwise.
  static String mimeTypeFor(String pathOrName, {String fallback = '*/*'}) {
    final dot = pathOrName.lastIndexOf('.');
    if (dot < 0 || dot == pathOrName.length - 1) return fallback;
    final ext = pathOrName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'm4a' || 'aac' => 'audio/mp4',
      'opus' || 'ogg' || 'oga' => 'audio/ogg',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'webm' => 'video/webm',
      'mp4' || 'm4v' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'mov' => 'video/quicktime',
      '3gp' => 'video/3gpp',
      _ => fallback,
    };
  }
}
