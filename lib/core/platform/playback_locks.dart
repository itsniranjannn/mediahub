// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform_info.dart';

/// Android: the Wi-Fi and wake locks held while the Online tab's page plays
/// (see PlaybackLocksChannel.kt). A no-op elsewhere.
class PlaybackLocks {
  PlaybackLocks._();

  static const MethodChannel _channel = MethodChannel('mediahub/playback_locks');

  /// The last value asked for, so the same one is not sent twice.
  static bool? _last;

  static Future<void> setStreaming(bool streaming) async {
    if (!PlatformInfo.isAndroid || _last == streaming) return;
    _last = streaming;
    try {
      await _channel.invokeMethod<bool>('setStreaming', streaming);
    } catch (e) {
      debugPrint('[PlaybackLocks] setStreaming($streaming) failed: $e');
    }
  }
}
