// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "mediahub/network": isMetered -> true on mobile data or a metered hotspot,
 * false on an unmetered network, null when the phone cannot tell (no active
 * network, no ACCESS_NETWORK_STATE). Used by "Ask before big downloads on
 * mobile data", with or without the personal tools.
 */
class NetworkChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val app = context.applicationContext
    private val channel = MethodChannel(messenger, "mediahub/network")

    init {
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isMetered" -> result.success(isMetered())
            else -> result.notImplemented()
        }
    }

    private fun isMetered(): Boolean? {
        return try {
            val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
            val active = cm.activeNetwork ?: return null
            val caps = cm.getNetworkCapabilities(active) ?: return cm.isActiveNetworkMetered
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return true
            !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (e: Exception) {
            // SecurityException without ACCESS_NETWORK_STATE, or anything else: unknown.
            null
        }
    }
}
