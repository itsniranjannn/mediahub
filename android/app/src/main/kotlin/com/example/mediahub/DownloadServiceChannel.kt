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

    fun cleanup() {
        channel.setMethodCallHandler(null)
        DownloadService.eventListener = null
    }
}

