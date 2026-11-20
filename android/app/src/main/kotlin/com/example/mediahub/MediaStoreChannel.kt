package com.example.mediahub

import android.content.ContentUris
import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MediaStoreChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "mediahub/media_store")

    /** Dart listens here for "mediaChanged": songs or videos were added, changed or removed. */
    private val events = MethodChannel(messenger, "mediahub/media_store_events")
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private val artworkExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Posts one "mediaChanged" 2 s after the last MediaStore change (a copy of 300 songs is one event). */
    private val notifyChanged = Runnable {
        try {
            events.invokeMethod("mediaChanged", null)
        } catch (_: Exception) {
        }
    }

    private val observer = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            mainHandler.removeCallbacks(notifyChanged)
            mainHandler.postDelayed(notifyChanged, CHANGE_DEBOUNCE_MS)
        }
    }
    private var observing = false

    init {
        channel.setMethodCallHandler(this)
        startObserving()
    }

    /** Called only when the Flutter engine itself goes away (see MainActivity.EngineChannels). */
    fun cleanup() {
        channel.setMethodCallHandler(null)
        stopObserving()
        scanExecutor.shutdown()
        artworkExecutor.shutdown()
    }

    private fun startObserving() {
        if (observing) return
        try {
            val resolver = context.contentResolver
            resolver.registerContentObserver(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, observer)
            resolver.registerContentObserver(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true, observer)
            observing = true
        } catch (_: Exception) {
            // No observer (e.g. a locked-down profile): the app still rescans on start and resume.
        }
    }

    private fun stopObserving() {
        mainHandler.removeCallbacks(notifyChanged)
        if (!observing) return
        try {
            context.contentResolver.unregisterContentObserver(observer)
        } catch (_: Exception) {
        }
        observing = false
    }

    /**
     * Changes whenever any media file changes (Android 11+): the generation of every external
     * volume, e.g. "external_primary:1234". Null on older phones, which cannot tell.
     */
    private fun mediaGeneration(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val volumes = MediaStore.getExternalVolumeNames(context).sorted()
        return volumes.joinToString(";") { volume -> "$volume:${MediaStore.getGeneration(context, volume)}" }
    }

    override fun onMethodCall(call: MethodCall, rawResult: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        val safeResult = object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { rawResult.success(result) }
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { rawResult.error(errorCode, errorMessage, errorDetails) }
                }
            }

            override fun notImplemented() {
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { rawResult.notImplemented() }
                }
            }
        }

        when (call.method) {
            "queryAudio" -> {
                scanExecutor.execute {
                    try {
                        val audioList = fetchAudio()
                        safeResult.success(audioList)
                    } catch (e: Exception) {
                        safeResult.error("AUDIO_QUERY_FAILED", e.localizedMessage ?: "Unknown error querying audio", null)
                    }
                }
            }
            "queryVideo" -> {
                scanExecutor.execute {
                    try {
                        val videoList = fetchVideo()
                        safeResult.success(videoList)
                    } catch (e: Exception) {
                        safeResult.error("VIDEO_QUERY_FAILED", e.localizedMessage ?: "Unknown error querying video", null)
                    }
                }
            }
            "getArtwork" -> {
                val uriString = call.argument<String>("uri")
                val width = call.argument<Int>("width") ?: 256
                val height = call.argument<Int>("height") ?: 256

                if (uriString == null) {
                    safeResult.success(null)
                    return
                }

                artworkExecutor.execute {
                    try {
                        val bytes = loadArtworkBytes(uriString, width, height)
                        safeResult.success(bytes)
                    } catch (e: Exception) {
                        safeResult.success(null)
                    }
                }
            }
            "mediaGeneration" -> {
                scanExecutor.execute {
                    try {
                        safeResult.success(mediaGeneration())
                    } catch (e: Exception) {
                        safeResult.success(null)
                    }
                }
            }
            "freeSpaceBytes" -> {
                scanExecutor.execute {
                    try {
                        val filesDir = context.filesDir
                        val stat = StatFs(filesDir.path)
                        val availableBytes = stat.availableBytes
                        safeResult.success(availableBytes)
                    } catch (e: Exception) {
                        safeResult.error("STATFS_FAILED", e.localizedMessage ?: "Failed to get free space", null)
                    }
                }
            }
            else -> safeResult.notImplemented()
        }
    }

    private fun fetchAudio(): List<Map<String, Any?>> {
        val audioList = mutableListOf<Map<String, Any?>>()
        val baseProjection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.MIME_TYPE
        )
        // Album identity, track order and year (album / track / year columns exist on every
        // supported Android version; "album_artist" is a long-standing column only named in the
        // SDK since 11), the folder (10+) and the genre (11+).
        val extra = mutableListOf(
            MediaStore.Audio.Media.ALBUM_ID,
            ALBUM_ARTIST_COLUMN,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) extra.add(MediaStore.MediaColumns.RELATIVE_PATH)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) extra.add(MediaStore.Audio.AudioColumns.GENRE)
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        val uri: Uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        // A phone whose MediaStore lacks one of the extra columns throws on the query: scan
        // with the basic columns then, as before.
        val cursor: Cursor? = try {
            context.contentResolver.query(uri, baseProjection + extra, selection, null, sortOrder)
        } catch (_: IllegalArgumentException) {
            context.contentResolver.query(uri, baseProjection, selection, null, sortOrder)
        }
        cursor?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val mimeTypeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val albumIdCol = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
            val albumArtistCol = cursor.getColumnIndex(ALBUM_ARTIST_COLUMN)
            val trackCol = cursor.getColumnIndex(MediaStore.Audio.Media.TRACK)
            val yearCol = cursor.getColumnIndex(MediaStore.Audio.Media.YEAR)
            val relativePathCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            val genreCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                cursor.getColumnIndex(MediaStore.Audio.AudioColumns.GENRE)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id).toString()
                val title = cursor.getString(titleCol) ?: "Unknown Title"
                val artist = cursor.getString(artistCol)
                val album = cursor.getString(albumCol)
                val duration = cursor.getLong(durationCol)
                val size = cursor.getLong(sizeCol)
                val dateAdded = cursor.getLong(dateAddedCol)
                val mimeType = cursor.getString(mimeTypeCol)

                val itemMap = hashMapOf<String, Any?>(
                    "id" to id.toString(),
                    "uri" to contentUri,
                    "title" to title,
                    "artist" to artist,
                    "album" to album,
                    "durationMs" to duration,
                    "sizeBytes" to size,
                    "dateAdded" to dateAdded,
                    "mimeType" to mimeType,
                    "albumId" to cursor.longOrNull(albumIdCol)?.toString(),
                    "albumArtist" to cursor.stringOrNull(albumArtistCol),
                    "track" to cursor.longOrNull(trackCol),
                    "year" to cursor.longOrNull(yearCol),
                    "relativePath" to cursor.stringOrNull(relativePathCol),
                    "genre" to cursor.stringOrNull(genreCol)
                )
                audioList.add(itemMap)
            }
        }
        return audioList
    }

    private fun fetchVideo(): List<Map<String, Any?>> {
        val videoList = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.TITLE,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.MIME_TYPE,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT
        )
        val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

        val uri: Uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        context.contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val titleCol = cursor.getColumnIndex(MediaStore.Video.Media.TITLE)
            val displayNameCol = cursor.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
            val mimeTypeCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)
            val widthCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
            val heightCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val contentUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id).toString()
                val displayName = if (displayNameCol != -1) cursor.getString(displayNameCol) else null
                val titleName = if (titleCol != -1) cursor.getString(titleCol) else null
                val title = titleName?.takeIf { it.isNotBlank() } ?: displayName?.takeIf { it.isNotBlank() } ?: "Unknown Video"

                val duration = cursor.getLong(durationCol)
                val size = cursor.getLong(sizeCol)
                val dateAdded = cursor.getLong(dateAddedCol)
                val mimeType = cursor.getString(mimeTypeCol)
                val width = cursor.getInt(widthCol)
                val height = cursor.getInt(heightCol)

                val itemMap = hashMapOf<String, Any?>(
                    "id" to id.toString(),
                    "uri" to contentUri,
                    "title" to title,
                    "durationMs" to duration,
                    "sizeBytes" to size,
                    "dateAdded" to dateAdded,
                    "mimeType" to mimeType,
                    "width" to width,
                    "height" to height
                )
                videoList.add(itemMap)
            }
        }
        return videoList
    }

    /**
     * Artwork for either a MediaStore content:// URI or a plain file path / file:// URI
     * (downloaded files live in app-private storage and have no MediaStore entry).
     */
    private fun loadArtworkBytes(uriString: String, width: Int, height: Int): ByteArray? {
        return try {
            val isFile = uriString.startsWith("/") || uriString.startsWith("file://")
            val bitmap: Bitmap? = if (isFile) {
                loadFileBitmap(uriString.removePrefix("file://"), width, height)
            } else {
                loadContentBitmap(Uri.parse(uriString), width, height)
            }
            if (bitmap != null) {
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                stream.toByteArray()
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun loadContentBitmap(uri: Uri, width: Int, height: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return context.contentResolver.loadThumbnail(uri, Size(width, height), null)
        }
        // API 26-28: no loadThumbnail. Use the retriever (embedded picture / video frame).
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            bitmapFromRetriever(retriever, width, height)
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    private fun loadFileBitmap(path: String, width: Int, height: Int): Bitmap? {
        val file = File(path)
        if (!file.isFile) return null
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            bitmapFromRetriever(retriever, width, height)
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    private fun bitmapFromRetriever(retriever: MediaMetadataRetriever, width: Int, height: Int): Bitmap? {
        val picture = retriever.embeddedPicture
        if (picture != null) {
            return decodeScaled(picture, width, height)
        }
        val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
        if (!hasVideo) return null
        val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        val timeUs = minOf(1_000_000L, (durationMs * 1000L) / 2L)
        val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, width, height)
        } else {
            retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }
        return frame
    }

    private fun Cursor.stringOrNull(index: Int): String? =
        if (index < 0 || isNull(index)) null else getString(index)

    private fun Cursor.longOrNull(index: Int): Long? =
        if (index < 0 || isNull(index)) null else getLong(index)

    private fun decodeScaled(bytes: ByteArray, reqWidth: Int, reqHeight: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= reqWidth && bounds.outHeight / (sample * 2) >= reqHeight) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }

    private companion object {
        const val CHANGE_DEBOUNCE_MS = 2000L

        /** MediaStore.Audio.AudioColumns.ALBUM_ARTIST, named in the SDK only from Android 11. */
        const val ALBUM_ARTIST_COLUMN = "album_artist"
    }
}
