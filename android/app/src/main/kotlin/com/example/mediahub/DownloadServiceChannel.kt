// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DownloadServiceChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "mediahub/download_service")

    /** A notification tap the Dart side was not listening for yet (cold start). */
    private var pendingOpenDownloads = false

    init {
        channel.setMethodCallHandler(this)
        DownloadService.eventListener = { action ->
            // Post back to Dart on main thread
            channel.invokeMethod(action, null)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val count = call.argument<Int>("count") ?: 1
                val percent = call.argument<Int>("percent") ?: -1
                val fileName = call.argument<String>("fileName")
                val intent = Intent(context, DownloadService::class.java).apply {
                    action = DownloadService.ACTION_START
                    putExtra(DownloadService.EXTRA_COUNT, count)
                    putExtra(DownloadService.EXTRA_PERCENT, percent)
                    putExtra(DownloadService.EXTRA_FILE_NAME, fileName)
                }
                try {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_START_FAILED", e.localizedMessage, null)
                }
            }
            "update" -> {
                val count = call.argument<Int>("count") ?: 1
                val percent = call.argument<Int>("percent") ?: -1
                val fileName = call.argument<String>("fileName")
                val intent = Intent(context, DownloadService::class.java).apply {
                    action = DownloadService.ACTION_UPDATE
                    putExtra(DownloadService.EXTRA_COUNT, count)
                    putExtra(DownloadService.EXTRA_PERCENT, percent)
                    putExtra(DownloadService.EXTRA_FILE_NAME, fileName)
                }
                try {
                    context.startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_UPDATE_FAILED", e.localizedMessage, null)
                }
            }
            "showPaused" -> {
                DownloadService.showPausedNotice(context, call.argument<Int>("count") ?: 1)
                result.success(true)
            }
            "hidePaused" -> {
                DownloadService.cancelPausedNotice(context)
                result.success(true)
            }
            "takePendingActions" -> {
                val pending = if (pendingOpenDownloads) listOf("openDownloads") else emptyList()
                pendingOpenDownloads = false
                result.success(pending)
            }
            "stop" -> {
                val intent = Intent(context, DownloadService::class.java).apply {
                    action = DownloadService.ACTION_STOP
                }
                try {
                    context.startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_STOP_FAILED", e.localizedMessage, null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /** The download notification was tapped: Dart shows the Downloads tab. */
    fun openDownloads() {
        channel.invokeMethod("openDownloads", null, object : MethodChannel.Result {
            override fun success(result: Any?) {}

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                pendingOpenDownloads = true
            }

            // No Dart handler yet (the engine is still starting): keep it for takePendingActions.
            override fun notImplemented() {
                pendingOpenDownloads = true
            }
        })
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        DownloadService.eventListener = null
    }
}

