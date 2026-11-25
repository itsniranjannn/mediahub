// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * "Resume all" on the paused-downloads notification ([DownloadService.showPausedNotice]).
 * Not exported: only that notification's PendingIntent reaches it. Dart queues every paused
 * download again; with no Dart side alive (the app was closed) the notification just goes and
 * the downloads stay paused for the Downloads screen.
 */
class DownloadActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadService.ACTION_RESUME_ALL) return
        DownloadService.cancelPausedNotice(context)
        DownloadService.eventListener?.invoke("resumeAll")
    }
}
