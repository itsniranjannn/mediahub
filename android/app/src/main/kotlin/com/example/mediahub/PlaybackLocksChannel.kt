// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "mediahub/playback_locks": setStreaming(true) while the Online tab's page
 * plays as the phone's media session, setStreaming(false) once it stops.
 *
 * The page's video is fetched by the WebView, not by a media player that
 * holds its own locks, so while it plays this holds a Wi-Fi lock (Wi-Fi must
 * not doze with the screen off and the task swiped away from recents) and a
 * partial wake lock (the CPU keeps feeding the WebView while audio_service
 * re-enters the foreground). Nothing is held while paused. Engine-scoped:
 * it outlives the Activity, and cleanup() lets everything go.
 */
class PlaybackLocksChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val app = context.applicationContext
    private val channel = MethodChannel(messenger, "mediahub/playback_locks")
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setStreaming" -> {
                if (call.arguments == true) acquire() else release()
                result.success(isHeld())
            }
            "isHeld" -> result.success(isHeld())
            else -> result.notImplemented()
        }
    }

    private fun isHeld(): Boolean = wifiLock?.isHeld == true || wakeLock?.isHeld == true

    private fun acquire() {
        runCatching {
            val wifi = wifiLock ?: (app.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.let { wm ->
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wm.createWifiLock(mode, "MediaHub:online").apply { setReferenceCounted(false) }
            }
            wifiLock = wifi
            if (wifi != null && !wifi.isHeld) wifi.acquire()
        }
        runCatching {
            val wake = wakeLock ?: (app.getSystemService(Context.POWER_SERVICE) as? PowerManager)
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MediaHub:online")
                ?.apply { setReferenceCounted(false) }
            wakeLock = wake
            if (wake != null && !wake.isHeld) wake.acquire()
        }
    }

    private fun release() {
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
    }
}
