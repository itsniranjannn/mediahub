// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

/// The download engines live below the providers: they call [notify] once a
/// finished download is written to the library, and main.dart points
/// [onFinished] at "Save downloads to: Phone storage"
/// (SaveToPhoneService.onDownloadFinished).
class DownloadFinishedHook {
  DownloadFinishedHook._();

  static Future<void> Function(String mediaId)? onFinished;

  static void notify(String mediaId) {
    final hook = onFinished;
    if (hook == null) return;
    unawaited(hook(mediaId).catchError((Object _) {}));
  }
}
