// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/**
 * The phone's shared media folders ("mediahub/phone_media").
 *
 * - capabilities -> {sdk, canSaveToPhone (Android 10+), systemAsksBeforeDelete (Android 11+)}
 * - saveToPhone {path, kind: audio|video, displayName, mimeType?} -> the new MediaStore URI.
 *   Copies a file from MediaHub's own downloads folder into Music/MediaHub or
 *   Movies/MediaHub through MediaStore with IS_PENDING, so no storage permission is
 *   needed (Android 10+). Nothing outside the downloads folder is ever read. Returns the
 *   URI in the same form the library scan uses (EXTERNAL_CONTENT_URI + id), so the scan
 *   can recognise the copy and never show it twice.
 * - deleteFromPhone {uris} -> true when the files are gone. Only content://media URIs.
 *   Android 11+: MediaStore.createDeleteRequest (the system's own consent dialog).
 *   Android 10: delete, and on RecoverableSecurityException the system's dialog, then again.
 *   Android 8-9: a plain delete, which only works for files MediaHub itself added.
 * - readLyricsSidecar {uri} -> {path, lrc}: the file path of a phone song when it can be
 *   read directly (Android 11+ with the read-audio permission) and the text of a .lrc file
 *   next to it, when the app may read one. Either can be null.
 */
class PhoneMediaChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object {
        const val REQUEST_DELETE = 0x4d50
        private const val MAX_LRC_BYTES = 512 * 1024
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "mediahub/phone_media")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var activity: WeakReference<Activity>? = null

    /** The delete waiting for the system dialog's answer. */
    private var pendingDelete: MethodChannel.Result? = null
    /** Android 10: the URIs still to delete once the user allowed the current one. */
    private var pendingQueue: ArrayDeque<Uri>? = null

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
        pendingDelete?.success(false)
        pendingDelete = null
        pendingQueue = null
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(
                mapOf(
                    "sdk" to Build.VERSION.SDK_INT,
                    "canSaveToPhone" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
                    "systemAsksBeforeDelete" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R),
                )
            )
            "saveToPhone" -> {
                val path = call.argument<String>("path")
                val kind = call.argument<String>("kind")
                val name = call.argument<String>("displayName")
                val mime = call.argument<String>("mimeType")
                if (path == null || (kind != "audio" && kind != "video")) {
                    result.error("BAD_ARGS", "path and kind are needed", null)
                    return
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("UNSUPPORTED", "Needs Android 10 or newer", null)
                    return
                }
                io.execute {
                    try {
                        val uri = saveToPhone(File(path), kind, name, mime)
                        main.post { result.success(uri) }
                    } catch (e: SecurityException) {
                        main.post { result.error("NOT_ALLOWED", e.localizedMessage, null) }
                    } catch (e: Exception) {
                        main.post { result.error("SAVE_FAILED", e.localizedMessage, null) }
                    }
                }
            }
            "deleteFromPhone" -> {
                val raw = call.argument<List<String>>("uris") ?: emptyList()
                val uris = raw.mapNotNull { mediaUri(it) }
                if (uris.isEmpty() || uris.size != raw.size) {
                    result.error("BAD_ARGS", "Only the phone's media library can be deleted", null)
                    return
                }
                if (pendingDelete != null) {
                    result.error("BUSY", "A delete is already waiting", null)
                    return
                }
                deleteFromPhone(uris, result)
            }
            "readLyricsSidecar" -> {
                val raw = call.argument<String>("uri")
                val uri = raw?.let { mediaUri(it) }
                if (uri == null) {
                    result.success(null)
                    return
                }
                io.execute {
                    val found = try {
                        lyricsSidecar(uri)
                    } catch (_: Exception) {
                        null
                    }
                    main.post { result.success(found) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** A content://media URI, or null for anything else. */
    private fun mediaUri(raw: String): Uri? {
        if (!raw.startsWith("content://")) return null
        val uri = Uri.parse(raw)
        return if (uri.authority == MediaStore.AUTHORITY) uri else null
    }

    /** path_provider's getApplicationDocumentsDirectory() + "/downloads". */
    private fun downloadsRoot(): File =
        File(appContext.getDir("flutter", Context.MODE_PRIVATE), "downloads").canonicalFile

    private fun saveToPhone(source: File, kind: String, displayName: String?, mimeType: String?): String {
        val file = source.canonicalFile
        val root = downloadsRoot()
        if (!file.isFile || !file.path.startsWith(root.path + File.separator)) {
            throw SecurityException("Only MediaHub's own downloads can be saved to the phone")
        }
        val ext = file.name.substringAfterLast('.', "").lowercase()
        val mime = (mimeType?.takeIf { it.startsWith("$kind/") })
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)?.takeIf { it.startsWith("$kind/") }
            ?: when (ext) {
                "m4a" -> "audio/mp4"
                "opus", "ogg" -> "audio/ogg"
                "webm" -> if (kind == "audio") "audio/webm" else "video/webm"
                "mkv" -> "video/x-matroska"
                else -> if (kind == "audio") "audio/mpeg" else "video/mp4"
            }
        val name = (displayName?.trim()?.takeIf { it.isNotEmpty() } ?: file.name).replace('/', '_')
        val resolver = appContext.contentResolver
        val collection: Uri
        val folder: String
        val external: Uri
        if (kind == "audio") {
            collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            folder = Environment.DIRECTORY_MUSIC + "/MediaHub"
            external = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        } else {
            collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            folder = Environment.DIRECTORY_MOVIES + "/MediaHub"
            external = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val item = resolver.insert(collection, values) ?: throw IllegalStateException("MediaStore refused the file")
        try {
            resolver.openOutputStream(item, "w").use { out ->
                if (out == null) throw IllegalStateException("No output stream")
                file.inputStream().use { it.copyTo(out, 256 * 1024) }
            }
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(item, done, null, null)
        } catch (e: Exception) {
            runCatching { resolver.delete(item, null, null) }
            throw e
        }
        return ContentUris.withAppendedId(external, ContentUris.parseId(item)).toString()
    }

    private fun deleteFromPhone(uris: List<Uri>, result: MethodChannel.Result) {
        val resolver = appContext.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val a = activity?.get()
            if (a == null) {
                result.error("NO_ACTIVITY", "MediaHub is not on screen", null)
                return
            }
            try {
                val pi = MediaStore.createDeleteRequest(resolver, uris)
                pendingDelete = result
                a.startIntentSenderForResult(pi.intentSender, REQUEST_DELETE, null, 0, 0, 0)
            } catch (e: Exception) {
                pendingDelete = null
                result.error("DELETE_FAILED", e.localizedMessage, null)
            }
            return
        }
        pendingDelete = result
        pendingQueue = ArrayDeque(uris)
        continueLegacyDelete()
    }

    /** Android 8-10: deletes the queued URIs one by one, asking where Android 10 lets us. */
    private fun continueLegacyDelete() {
        val queue = pendingQueue ?: return
        val resolver = appContext.contentResolver
        while (queue.isNotEmpty()) {
            val uri = queue.first()
            try {
                resolver.delete(uri, null, null)
                queue.removeFirst()
            } catch (e: SecurityException) {
                val sender: IntentSender? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                        e.userAction.actionIntent.intentSender
                    } else {
                        null
                    }
                val a = activity?.get()
                if (sender == null || a == null) {
                    finishDelete(false)
                    return
                }
                try {
                    a.startIntentSenderForResult(sender, REQUEST_DELETE, null, 0, 0, 0)
                } catch (_: Exception) {
                    finishDelete(false)
                }
                return
            } catch (_: Exception) {
                finishDelete(false)
                return
            }
        }
        finishDelete(true)
    }

    /** MainActivity.onActivityResult hands the system dialog's answer here. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_DELETE) return false
        val ok = resultCode == Activity.RESULT_OK
        if (pendingQueue != null && ok) {
            // Android 10: the user allowed this file; delete it and go on.
            continueLegacyDelete()
        } else {
            finishDelete(ok)
        }
        return true
    }

    private fun finishDelete(ok: Boolean) {
        val r = pendingDelete
        pendingDelete = null
        pendingQueue = null
        r?.success(ok)
    }

    private fun lyricsSidecar(uri: Uri): Map<String, String?>? {
        @Suppress("DEPRECATION")
        val column = MediaStore.MediaColumns.DATA
        val path = appContext.contentResolver.query(uri, arrayOf(column), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: return null
        val file = File(path)
        val readable = runCatching { file.canRead() }.getOrDefault(false)
        val base = path.substringBeforeLast('.', path)
        var lrc: String? = null
        for (candidate in listOf("$base.lrc", "$base.LRC")) {
            val f = File(candidate)
            val text = runCatching {
                if (f.isFile && f.length() in 1..MAX_LRC_BYTES) f.readText(Charsets.UTF_8) else null
            }.getOrNull()
            if (text != null) {
                lrc = text
                break
            }
        }
        return mapOf("path" to if (readable) path else null, "lrc" to lrc)
    }
}
