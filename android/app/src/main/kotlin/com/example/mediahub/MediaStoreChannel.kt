package com.example.mediahub

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MediaStoreChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "mediahub/media_store")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
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
                executor.execute {
                    try {
                        val audioList = fetchAudio()
                        safeResult.success(audioList)
                    } catch (e: Exception) {
                        safeResult.error("AUDIO_QUERY_FAILED", e.localizedMessage ?: "Unknown error querying audio", null)
                    }
                }
            }
            "queryVideo" -> {
                executor.execute {
                    try {
                        val videoList = fetchVideo()
                        safeResult.success(videoList)
                    } catch (e: Exception) {
                        safeResult.error("VIDEO_QUERY_FAILED", e.localizedMessage ?: "Unknown error querying video", null)
                    }
                }
            }
            else -> safeResult.notImplemented()
        }
    }

    private fun fetchAudio(): List<Map<String, Any?>> {
        val audioList = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.MIME_TYPE
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        val uri: Uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        context.contentResolver.query(uri, projection, selection, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val mimeTypeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)

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
                    "mimeType" to mimeType
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
                val title = displayName?.takeIf { it.isNotBlank() } ?: titleName?.takeIf { it.isNotBlank() } ?: "Unknown Video"

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
}

