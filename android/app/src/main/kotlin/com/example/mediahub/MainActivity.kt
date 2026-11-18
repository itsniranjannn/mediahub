package com.example.mediahub

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.lifecycle.Lifecycle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.example.mediahub.personal.ExtractorChannel
import java.io.File
import java.io.FileNotFoundException
import java.lang.ref.WeakReference

class MainActivity : AudioServiceActivity() {

    companion object {
        /** The download notification's tap: open the Downloads tab (explicit, app-internal). */
        const val ACTION_OPEN_DOWNLOADS = "com.example.mediahub.action.OPEN_DOWNLOADS"
    }

    /**
     * audio_service keeps one Flutter engine alive for the whole process, longer than any
     * single Activity (e.g. Back on Android 8-12 finishes the Activity while music and
     * downloads keep running). The platform channels therefore belong to the ENGINE: they
     * are created once per engine and are never torn down when an Activity is destroyed,
     * so a running yt-dlp download or the download notification's "Pause all" keep working.
     * Only the device-controls and share channels need an Activity (brightness,
     * picture-in-picture, the share sheet); they are re-attached to whichever Activity is
     * currently showing the engine.
     */
    private object EngineChannels {
        var engine: WeakReference<FlutterEngine>? = null
        var mediaStore: MediaStoreChannel? = null
        var downloadService: DownloadServiceChannel? = null
        var extractor: ExtractorChannel? = null
        var deviceControls: DeviceControlsChannel? = null
        var share: ShareChannel? = null

        fun bind(activity: MainActivity, flutterEngine: FlutterEngine) {
            if (engine?.get() !== flutterEngine) {
                // First launch, or the previous engine was destroyed: drop the old channels.
                release()
                val app = activity.applicationContext
                val messenger = flutterEngine.dartExecutor.binaryMessenger
                mediaStore = MediaStoreChannel(app, messenger)
                downloadService = DownloadServiceChannel(app, messenger)
                deviceControls = DeviceControlsChannel(app, messenger)
                share = ShareChannel(app, messenger)
                if (ExtractorChannel.PERSONAL_TOOLS) extractor = ExtractorChannel(app, messenger)
                engine = WeakReference(flutterEngine)
            }
            deviceControls?.attach(activity)
            share?.attach(activity)
        }

        private fun release() {
            runCatching { mediaStore?.cleanup() }
            runCatching { downloadService?.cleanup() }
            runCatching { extractor?.cleanup() }
            runCatching { deviceControls?.cleanup() }
            runCatching { share?.cleanup() }
            mediaStore = null
            downloadService = null
            extractor = null
            deviceControls = null
            share = null
        }
    }

    /**
     * No route from outside: FlutterActivity would otherwise take the launching intent's
     * "route" extra as the first screen, letting any app open any screen on a cold start
     * (the Dart router ignores the platform's route as well). The download notification
     * uses [ACTION_OPEN_DOWNLOADS] instead.
     */
    override fun getInitialRoute(): String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EngineChannels.bind(this, flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A fresh Activity started from the download notification (not a re-creation).
        if (savedInstanceState == null) handleAppIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAppIntent(intent)
    }

    private fun handleAppIntent(intent: Intent?) {
        if (intent == null) return
        // Reopened from Recents: the old notification tap must not jump to Downloads again.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        if (intent.action == ACTION_OPEN_DOWNLOADS) {
            EngineChannels.downloadService?.openDownloads()
        }
    }

    // Leaving the app while a video plays: switch to a floating picture-in-picture window.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        EngineChannels.deviceControls?.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val controls = EngineChannels.deviceControls
        controls?.notifyPipChanged(isInPictureInPictureMode)
        // Leaving picture-in-picture while the Activity is no longer started means the user
        // closed the floating window (X or swipe away) instead of expanding it: Android
        // expects playback in it to stop. Expanding it back resumes the Activity instead.
        if (!isInPictureInPictureMode && !lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            controls?.notifyPipDismissed()
        }
    }

    // Android pauses an Activity in picture-in-picture, so a resumed one is not in it. Say so
    // again in case the "left picture-in-picture" callback never reached Dart: seen once on the
    // emulator, where the Online tab kept its PiP layout (no toolbar) until the app restarted.
    // Dart ignores a repeat of the state it already has.
    override fun onResume() {
        super.onResume()
        if (!isInPictureInPictureMode) EngineChannels.deviceControls?.notifyPipChanged(false)
    }

    override fun onDestroy() {
        // Only the Activity reference is released; the engine (and its channels) live on.
        EngineChannels.deviceControls?.detach(this)
        EngineChannels.share?.detach(this)
        super.onDestroy()
    }
}

/**
 * The system share sheet ("mediahub/share"): an ACTION_SEND chooser.
 *
 * - shareFile: a MediaStore content:// URI is shared as is (the app holds read access and
 *   grants it for this one share); a file path or file:// URI must lie inside the app's
 *   downloads folder and goes out through [DownloadShareProvider]; anything else is refused.
 * - shareText: plain text (links).
 */
class ShareChannel(
    context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "mediahub/share")
    private var activityRef: WeakReference<Activity>? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun attach(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    fun detach(activity: Activity) {
        if (activityRef?.get() === activity) activityRef = null
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        activityRef = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "shareFile" -> {
                    val raw = call.argument<String>("uriOrPath")
                    val mime = call.argument<String>("mimeType") ?: "*/*"
                    val title = call.argument<String>("title")
                    val uri = raw?.let { shareableUri(it) }
                    if (uri == null) {
                        result.success(false)
                        return
                    }
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = mime
                        putExtra(Intent.EXTRA_STREAM, uri)
                        if (!title.isNullOrBlank()) putExtra(Intent.EXTRA_TITLE, title)
                        // The chooser passes the grant on only through ClipData.
                        clipData = ClipData.newRawUri(title ?: "", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    result.success(startChooser(send))
                }
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.success(false)
                        return
                    }
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                        call.argument<String>("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                    }
                    result.success(startChooser(send))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.localizedMessage, null)
        }
    }

    /** MediaStore URIs as they are; downloads through our provider; null for anything else. */
    private fun shareableUri(raw: String): Uri? {
        if (raw.startsWith("content://")) {
            val uri = Uri.parse(raw)
            // Only the phone's media library, never another provider's content.
            return if (uri.authority == "media") uri else null
        }
        val path = if (raw.startsWith("file://")) Uri.parse(raw).path else raw
        if (path.isNullOrEmpty() || path.contains("://")) return null
        return DownloadShareProvider.uriFor(appContext, File(path))
    }

    private fun startChooser(send: Intent): Boolean {
        val chooser = Intent.createChooser(send, null)
        val a = activityRef?.get()
        return try {
            if (a != null) {
                a.startActivity(chooser)
            } else {
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appContext.startActivity(chooser)
            }
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}

/**
 * Read-only access to the app's downloads (app_flutter/downloads, where the Dart side keeps
 * them) for the share sheet. Not exported: another app can only open a URI it was granted
 * for one share. Paths outside the downloads folder (including "..") are refused.
 */
class DownloadShareProvider : ContentProvider() {

    companion object {
        private fun authority(context: Context) = "${context.packageName}.downloadshare"

        /** Media extensions older MimeTypeMap tables do not know. */
        private val MEDIA_TYPES = mapOf(
            "m4a" to "audio/mp4",
            "aac" to "audio/aac",
            "opus" to "audio/ogg",
            "flac" to "audio/flac",
            "webm" to "video/webm",
            "mkv" to "video/x-matroska",
        )

        /** path_provider's getApplicationDocumentsDirectory() + "/downloads". */
        private fun downloadsRoot(context: Context): File =
            File(context.getDir("flutter", Context.MODE_PRIVATE), "downloads").canonicalFile

        /** A content:// URI for [file], or null when it is not a file inside the downloads folder. */
        fun uriFor(context: Context, file: File): Uri? {
            val root = downloadsRoot(context)
            val f = try {
                file.canonicalFile
            } catch (e: java.io.IOException) {
                return null
            }
            if (!f.isFile || !f.path.startsWith(root.path + File.separator)) return null
            val builder = Uri.Builder().scheme("content").authority(authority(context))
            f.path.substring(root.path.length + 1).split(File.separatorChar).forEach { builder.appendPath(it) }
            return builder.build()
        }
    }

    override fun onCreate(): Boolean = true

    private fun fileFor(uri: Uri): File {
        val ctx = context ?: throw FileNotFoundException("No context")
        val root = downloadsRoot(ctx)
        val segments = uri.pathSegments
        if (uri.authority != authority(ctx) || segments.isEmpty()) throw FileNotFoundException("Unknown URI")
        val f = File(root, segments.joinToString(File.separator)).canonicalFile
        if (!f.path.startsWith(root.path + File.separator) || !f.isFile) throw FileNotFoundException("Not shared")
        return f
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Read-only")
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String {
        // From the decoded file name: MimeTypeMap.getFileExtensionFromUrl returns "" for any
        // name with spaces or non-ASCII letters ("My Song.mp3", Devanagari titles), which is
        // nearly every download, and receivers would then see an unknown file.
        val ext = (uri.lastPathSegment ?: "").substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: MEDIA_TYPES[ext]
            ?: "application/octet-stream"
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val f = fileFor(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns, 1)
        cursor.addRow(columns.map { col ->
            when (col) {
                OpenableColumns.DISPLAY_NAME -> f.name
                OpenableColumns.SIZE -> f.length()
                else -> null
            }
        })
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException("Read-only")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("Read-only")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = throw UnsupportedOperationException("Read-only")
}
