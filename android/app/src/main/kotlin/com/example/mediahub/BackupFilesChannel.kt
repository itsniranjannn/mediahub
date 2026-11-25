// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/**
 * Library backup files ("mediahub/backup_files") through the Storage Access Framework:
 * - save: ACTION_CREATE_DOCUMENT, then writes the bytes to the file the user picked;
 * - open: ACTION_OPEN_DOCUMENT, then reads that file (refused past maxBytes).
 * The system picker grants access to that one file only, so no storage permission is used.
 * Needs the current Activity (re-attached like the share channel).
 */
class BackupFilesChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object {
        const val REQUEST_SAVE = 0x4d48
        const val REQUEST_OPEN = 0x4d49
    }

    private val channel = MethodChannel(messenger, "mediahub/backup_files")
    private val io = Executors.newSingleThreadExecutor()
    private var activity: WeakReference<Activity>? = null
    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var pendingMax: Int = 0

    init {
        channel.setMethodCallHandler(this)
    }

    fun attach(a: Activity) {
        activity = WeakReference(a)
    }

    fun detach(a: Activity) {
        if (activity?.get() === a) activity = null
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        pending?.success(null)
        pending = null
        pendingBytes = null
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save" && call.method != "open") {
            result.notImplemented()
            return
        }
        val a = activity?.get()
        if (a == null) {
            result.error("NO_ACTIVITY", "MediaHub is not on screen", null)
            return
        }
        if (pending != null) {
            result.error("BUSY", "A file picker is already open", null)
            return
        }
        val intent: Intent
        val code: Int
        if (call.method == "save") {
            val bytes = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("fileName") ?: "mediahub-backup.json"
            if (bytes == null) {
                result.error("BAD_ARGS", "Nothing to save", null)
                return
            }
            pendingBytes = bytes
            intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, name)
            }
            code = REQUEST_SAVE
        } else {
            pendingMax = call.argument<Int>("maxBytes") ?: (5 * 1024 * 1024)
            intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
            }
            code = REQUEST_OPEN
        }
        pending = result
        try {
            a.startActivityForResult(intent, code)
        } catch (e: ActivityNotFoundException) {
            pending = null
            pendingBytes = null
            result.error("NO_PICKER", "This phone has no file picker", null)
        }
    }

    /** Called from MainActivity.onActivityResult. True when the request was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_OPEN) return false
        val result = pending ?: return true
        val bytes = pendingBytes
        val max = pendingMax
        pending = null
        pendingBytes = null
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        val a = activity?.get()
        if (uri == null || a == null) {
            result.success(if (requestCode == REQUEST_SAVE) false else null)
            return true
        }
        val resolver = a.applicationContext.contentResolver
        io.execute {
            try {
                if (requestCode == REQUEST_SAVE) {
                    val out = resolver.openOutputStream(uri, "wt") ?: throw IllegalStateException("Could not open the file")
                    out.use { it.write(bytes ?: ByteArray(0)) }
                    a.runOnUiThread { result.success(true) }
                } else {
                    val input = resolver.openInputStream(uri) ?: throw IllegalStateException("Could not open the file")
                    val out = ByteArrayOutputStream()
                    var tooLarge = false
                    input.use {
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = it.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            if (out.size() > max) {
                                tooLarge = true
                                break
                            }
                        }
                    }
                    a.runOnUiThread {
                        if (tooLarge) result.error("TOO_LARGE", "The file is too large", null)
                        else result.success(out.toByteArray())
                    }
                }
            } catch (e: Exception) {
                a.runOnUiThread { result.error("IO", e.message ?: "Could not read or write the file", null) }
            }
        }
        return true
    }
}
