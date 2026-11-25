// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "Share to MediaHub" ("mediahub/shared_link"): the text of an ACTION_SEND text/plain
 * intent, passed to Dart as plain text and nothing else. Dart picks the first https link
 * out of it, checks it with UrlPolicy and hands it to the Downloads tab. No extra other
 * than EXTRA_TEXT is read, so a sharing app cannot pick a screen, a route or a file.
 *
 * A share that arrives before Dart listens (cold start) waits here until Dart asks with
 * takePending; a newer share replaces an older one nobody took.
 */
class SharedLinkChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        /** Longer text is cut: a caption with a link fits, a whole document does not. */
        const val MAX_TEXT = 4096

        /** The shared text of [intent], or null when it is not a plain-text share. */
        fun sharedText(intent: Intent?): String? {
            if (intent?.action != Intent.ACTION_SEND) return null
            val type = intent.type ?: return null
            if (!type.startsWith("text/plain")) return null
            val text = runCatching { intent.getCharSequenceExtra(Intent.EXTRA_TEXT) }.getOrNull()
                ?.toString()?.trim()
            if (text.isNullOrEmpty()) return null
            return if (text.length > MAX_TEXT) text.substring(0, MAX_TEXT) else text
        }

        /**
         * The share nobody took yet. Process-wide, not per channel: on a cold start the
         * Activity can see the share before the engine's channels exist.
         */
        @Volatile
        var pending: String? = null

        /** Keeps [text] for Dart and sends it at once when [channel] is there. */
        fun receive(text: String, channel: SharedLinkChannel?) {
            pending = text
            channel?.deliver(text)
        }
    }

    private val channel = MethodChannel(messenger, "mediahub/shared_link")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePending" -> {
                val text = pending
                pending = null
                result.success(text)
            }
            else -> result.notImplemented()
        }
    }

    /** Sends [text] to Dart now; it stays in [pending] for takePending until Dart answers. */
    fun deliver(text: String) {
        channel.invokeMethod("sharedText", text, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pending == text) pending = null
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

            override fun notImplemented() {}
        })
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
    }
}
