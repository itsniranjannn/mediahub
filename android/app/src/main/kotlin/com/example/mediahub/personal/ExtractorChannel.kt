package com.example.mediahub.personal

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class ExtractorChannel(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "mediahub/extractor")
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isInitialized = false

    private val activeTasks = ConcurrentHashMap<String, String>() // taskId -> processId or status

    companion object {
        const val PERSONAL_TOOLS = true

        private val ALLOWED_HOSTS = listOf(
            "youtube.com",
            "youtu.be",
            "music.youtube.com",
            "instagram.com",
            "facebook.com",
            "fb.watch",
            "tiktok.com",
            "x.com",
            "twitter.com",
            "spotify.com",
            "soundcloud.com",
            "vimeo.com"
        )

        fun isHostAllowed(url: String): Boolean {
            return try {
                val uri = URI(url)
                if (uri.scheme?.lowercase() != "https") return false
                val host = uri.host?.lowercase() ?: return false
                ALLOWED_HOSTS.any { allowed ->
                    host == allowed || host.endsWith(".$allowed")
                }
            } catch (e: Exception) {
                false
            }
        }

        fun sanitizeFilename(raw: String): String {
            // Replace invalid characters /: *?"<>| and control characters with '_'
            val cleaned = raw.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_").trim()
            val result = if (cleaned.isEmpty()) "media" else cleaned
            return if (result.length > 100) result.substring(0, 100) else result
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!PERSONAL_TOOLS) {
            result.error("FEATURE_DISABLED", "Personal extractor tools are disabled", null)
            return
        }

        when (call.method) {
            "init" -> handleInit(result)
            "version" -> handleVersion(result)
            "update" -> handleUpdate(result)
            "getInfo" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("INVALID_ARGUMENT", "Missing url", null)
                    return
                }
                handleGetInfo(url, result)
            }
            "download" -> {
                val taskId = call.argument<String>("taskId")
                val url = call.argument<String>("url")
                val formatSelector = call.argument<String>("formatSelector")
                val outDir = call.argument<String>("outDir")
                if (taskId == null || url == null || outDir == null) {
                    result.error("INVALID_ARGUMENT", "Missing required arguments", null)
                    return
                }
                handleDownload(taskId, url, formatSelector, outDir, result)
            }
            "cancel" -> {
                val taskId = call.argument<String>("taskId")
                if (taskId == null) {
                    result.error("INVALID_ARGUMENT", "Missing taskId", null)
                    return
                }
                handleCancel(taskId, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleInit(result: MethodChannel.Result) {
        executor.execute {
            try {
                if (!isInitialized) {
                    YoutubeDL.getInstance().init(context.applicationContext)
                    isInitialized = true
                }
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("INIT_FAILED", e.localizedMessage ?: "Failed to initialize extractor", null)
                }
            }
        }
    }

    private fun handleVersion(result: MethodChannel.Result) {
        executor.execute {
            try {
                ensureInitialized()
                val ver = YoutubeDL.getInstance().version(context.applicationContext)
                mainHandler.post { result.success(ver) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("VERSION_ERROR", e.localizedMessage ?: "Could not get version", null)
                }
            }
        }
    }

    private fun handleUpdate(result: MethodChannel.Result) {
        executor.execute {
            try {
                ensureInitialized()
                val status = YoutubeDL.getInstance().updateYoutubeDL(
                    context.applicationContext,
                    YoutubeDL.UpdateChannel._STABLE
                )
                val statusName = status?.name ?: "DONE"
                mainHandler.post { result.success(statusName) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("UPDATE_ERROR", e.localizedMessage ?: "Could not update", null)
                }
            }
        }
    }

    private fun handleGetInfo(url: String, result: MethodChannel.Result) {
        if (!isHostAllowed(url)) {
            result.error("HOST_NOT_ALLOWED", "This platform is not in the allowed extractor list", null)
            return
        }

        executor.execute {
            try {
                ensureInitialized()

                val request = YoutubeDLRequest(url).apply {
                    addOption("--no-playlist")
                    addOption("--ignore-config")
                    addOption("--dump-json")
                    addOption("--no-warnings")
                }

                val response = YoutubeDL.getInstance().execute(request)
                val outJson = response.out
                if (outJson.isNullOrEmpty()) {
                    throw YoutubeDLException("Empty response from extractor")
                }

                val json = JSONObject(outJson)
                val id = json.optString("id", "")
                val title = json.optString("title", "Video")
                val uploader = json.optString("uploader", "")
                val duration = json.optInt("duration", 0)
                val thumbnail = json.optString("thumbnail", "")

                val formatsArray = json.optJSONArray("formats")
                val formatsList = mutableListOf<Map<String, Any?>>()
                if (formatsArray != null) {
                    for (i in 0 until formatsArray.length()) {
                        val fmt = formatsArray.optJSONObject(i) ?: continue
                        val formatId = fmt.optString("format_id", "")
                        val ext = fmt.optString("ext", "")
                        val note = fmt.optString("format_note", "")
                        val vcodec = fmt.optString("vcodec", "none")
                        val acodec = fmt.optString("acodec", "none")
                        val height = fmt.optInt("height", 0)
                        val width = fmt.optInt("width", 0)
                        val filesize = fmt.optLong("filesize", 0L).let { if (it > 0) it else fmt.optLong("filesize_approx", 0L) }
                        val hasVideo = vcodec.isNotEmpty() && vcodec != "none"
                        val hasAudio = acodec.isNotEmpty() && acodec != "none"

                        formatsList.add(
                            mapOf(
                                "formatId" to formatId,
                                "ext" to ext,
                                "formatNote" to note,
                                "hasVideo" to hasVideo,
                                "hasAudio" to hasAudio,
                                "height" to height,
                                "width" to width,
                                "filesize" to filesize
                            )
                        )
                    }
                }

                val resultMap = mapOf(
                    "id" to id,
                    "title" to title,
                    "uploader" to uploader,
                    "duration" to duration,
                    "thumbnail" to thumbnail,
                    "formats" to formatsList
                )

                mainHandler.post { result.success(resultMap) }
            } catch (e: Exception) {
                val (code, msg) = mapException(e)
                mainHandler.post { result.error(code, msg, null) }
            }
        }
    }

    private fun handleDownload(
        taskId: String,
        url: String,
        formatSelector: String?,
        outDir: String,
        result: MethodChannel.Result
    ) {
        if (!isHostAllowed(url)) {
            result.error("HOST_NOT_ALLOWED", "This platform is not in the allowed extractor list", null)
            return
        }

        executor.execute {
            try {
                ensureInitialized()
                activeTasks[taskId] = taskId

                val outputDir = File(outDir)
                if (!outputDir.exists()) outputDir.mkdirs()

                val request = YoutubeDLRequest(url).apply {
                    addOption("--no-playlist")
                    addOption("--ignore-config")
                    addOption("--max-filesize", "2G")
                    addOption("-o", "${outputDir.absolutePath}/$taskId.%(ext)s")
                    if (!formatSelector.isNullOrEmpty()) {
                        addOption("-f", formatSelector)
                    }
                }

                var lastPercent = -1
                var lastPostTime = 0L

                YoutubeDL.getInstance().execute(request, taskId) { progress, etaInSeconds, line ->
                    val now = System.currentTimeMillis()
                    val p = progress.toInt()
                    // Throttle progress events to ~4 Hz (250 ms) or completion
                    if (p != lastPercent && (now - lastPostTime >= 250 || p == 100)) {
                        lastPercent = p
                        lastPostTime = now
                        mainHandler.post {
                            channel.invokeMethod("onProgress", mapOf(
                                "taskId" to taskId,
                                "progress" to progress,
                                "eta" to etaInSeconds
                            ))
                        }
                    }
                }

                activeTasks.remove(taskId)

                // Locate the downloaded file
                val candidates = outputDir.listFiles { _, name -> name.startsWith(taskId) }
                val targetFile = candidates?.firstOrNull { !it.name.endsWith(".part") && !it.name.endsWith(".ytdl") }

                mainHandler.post {
                    result.success(mapOf(
                        "taskId" to taskId,
                        "filePath" to (targetFile?.absolutePath ?: "")
                    ))
                }
            } catch (e: Exception) {
                activeTasks.remove(taskId)
                val (code, msg) = mapException(e)
                mainHandler.post { result.error(code, msg, null) }
            }
        }
    }

    private fun handleCancel(taskId: String, result: MethodChannel.Result) {
        try {
            YoutubeDL.getInstance().destroyProcessById(taskId)
            activeTasks.remove(taskId)
            result.success(true)
        } catch (e: Exception) {
            result.error("CANCEL_FAILED", e.localizedMessage ?: "Could not cancel task", null)
        }
    }

    private fun ensureInitialized() {
        if (!isInitialized) {
            YoutubeDL.getInstance().init(context.applicationContext)
            isInitialized = true
        }
    }

    private fun mapException(e: Exception): Pair<String, String> {
        val msg = e.localizedMessage ?: ""
        return when {
            msg.contains("Private video", ignoreCase = true) ->
                Pair("PRIVATE_CONTENT", "This content is private and cannot be downloaded")
            msg.contains("Sign in", ignoreCase = true) || msg.contains("login", ignoreCase = true) ->
                Pair("LOGIN_REQUIRED", "This video requires login or authentication")
            msg.contains("DRM", ignoreCase = true) ->
                Pair("DRM_PROTECTED", "This content is protected by DRM")
            msg.contains("404", ignoreCase = true) || msg.contains("Not Found", ignoreCase = true) ->
                Pair("NOT_FOUND", "The requested media was not found")
            msg.contains("max-filesize", ignoreCase = true) || msg.contains("File is larger than", ignoreCase = true) ->
                Pair("FILE_TOO_LARGE", "The media exceeds the 2 GB download limit")
            msg.contains("Interrupted", ignoreCase = true) || msg.contains("destroy", ignoreCase = true) ->
                Pair("CANCELLED", "The download was cancelled")
            else ->
                Pair("EXTRACTION_FAILED", "Could not extract or download media")
        }
    }
}

