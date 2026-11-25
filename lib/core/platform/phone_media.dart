// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform_info.dart';

/// What the phone lets MediaHub do with its shared media folders.
class PhoneMediaCapabilities {
  const PhoneMediaCapabilities({
    required this.canSaveToPhone,
    required this.canDeletePhoneMedia,
    required this.systemAsksBeforeDelete,
  });

  /// Nothing (desktop, tests, a failed channel).
  static const none =
      PhoneMediaCapabilities(canSaveToPhone: false, canDeletePhoneMedia: false, systemAsksBeforeDelete: false);

  /// Downloads can be put where other apps see them: Android 10+ (MediaStore,
  /// no storage permission) and the iPhone (Files app / Photos).
  final bool canSaveToPhone;

  /// Songs and videos the phone already had can be deleted from MediaHub
  /// (Android only: the iPhone app never sees them).
  final bool canDeletePhoneMedia;

  /// Android 11+ shows its own "Allow MediaHub to delete…" dialog, so
  /// MediaHub does not ask a second time.
  final bool systemAsksBeforeDelete;
}

/// The native side of "Save to phone" and "Delete from phone"
/// (`mediahub/phone_media`: `PhoneMediaChannel.kt`, and `PhoneMediaChannel`
/// in ios/Runner/AppDelegate.swift).
abstract class PhoneMedia {
  Future<PhoneMediaCapabilities> capabilities();

  /// Copies the download at [path] into the phone's shared storage and
  /// returns where it is now: on Android the MediaStore `content://` URI (in
  /// Music/MediaHub or Movies/MediaHub), on the iPhone the new file path
  /// (audio: Documents/MediaHub, seen in the Files app) or the original
  /// [path] (video: a copy was added to Photos). Throws [PlatformException]
  /// when it could not.
  Future<String> saveToPhone({
    required String path,
    required bool isVideo,
    required String displayName,
    String? mimeType,
  });

  /// Deletes MediaStore items ([uris] are `content://media/...`). On
  /// Android 11+ the system asks the user first. True when they are gone,
  /// false when the user said no or it could not.
  Future<bool> deleteFromPhone(List<String> uris);

  /// For a phone song: its readable file path (for the embedded lyrics) and
  /// the text of a `.lrc` file next to it. Null values when not readable.
  Future<({String? path, String? lrc})> lyricsSidecar(String uri);
}

class MethodChannelPhoneMedia implements PhoneMedia {
  static const MethodChannel _channel = MethodChannel('mediahub/phone_media');

  PhoneMediaCapabilities? _cached;

  @override
  Future<PhoneMediaCapabilities> capabilities() async {
    final cached = _cached;
    if (cached != null) return cached;
    if (!PlatformInfo.isAndroid && !PlatformInfo.isIOS) return PhoneMediaCapabilities.none;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      return _cached = PhoneMediaCapabilities(
        canSaveToPhone: map?['canSaveToPhone'] == true,
        canDeletePhoneMedia: PlatformInfo.isAndroid,
        systemAsksBeforeDelete: map?['systemAsksBeforeDelete'] == true,
      );
    } catch (_) {
      return PhoneMediaCapabilities.none;
    }
  }

  @override
  Future<String> saveToPhone({
    required String path,
    required bool isVideo,
    required String displayName,
    String? mimeType,
  }) async {
    final uri = await _channel.invokeMethod<String>('saveToPhone', {
      'path': path,
      'kind': isVideo ? 'video' : 'audio',
      'displayName': displayName,
      'mimeType': mimeType,
    });
    if (uri == null || uri.isEmpty) {
      throw PlatformException(code: 'SAVE_FAILED', message: 'No address came back');
    }
    return uri;
  }

  @override
  Future<bool> deleteFromPhone(List<String> uris) async {
    if (uris.isEmpty) return true;
    final ok = await _channel.invokeMethod<bool>('deleteFromPhone', {'uris': uris});
    return ok ?? false;
  }

  @override
  Future<({String? path, String? lrc})> lyricsSidecar(String uri) async {
    if (!PlatformInfo.isAndroid || !uri.startsWith('content://')) return (path: null, lrc: null);
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('readLyricsSidecar', {'uri': uri});
      return (path: map?['path'] as String?, lrc: map?['lrc'] as String?);
    } catch (_) {
      return (path: null, lrc: null);
    }
  }
}

final phoneMediaProvider = Provider<PhoneMedia>((ref) => MethodChannelPhoneMedia());
