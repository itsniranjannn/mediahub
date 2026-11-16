package com.example.mediahub.personal

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.ffmpeg.FFmpeg
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
    private val cancelledTasks: MutableSet<String> = ConcurrentHashMap.newKeySet()
    // Link lookups the user cancelled: stop probing further YouTube clients for them.
    private val cancelledInfo: MutableSet<String> = ConcurrentHashMap.newKeySet()

    private fun infoProcessId(requestId: String) = "info-$requestId"

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

        // The task id becomes part of the output file name: keep it boring.
        private val TASK_ID_REGEX = Regex("^[A-Za-z0-9_-]{1,64}$")

        // yt-dlp format selectors only ever need this small alphabet. Never starts with '-'.
        private val FORMAT_SELECTOR_REGEX = Regex("^[A-Za-z0-9_\\[\\]<>=!*+/,.()^$~:?][A-Za-z0-9_\\[\\]<>=!*+/,.()^$~:?-]{0,299}$")

        // Only extractor-args we generate ourselves are accepted (YouTube player clients).
        private val EXTRACTOR_ARGS_REGEX = Regex("^youtube:player_client=[a-z0-9_,]{1,80}$")

        private val AUDIO_FORMATS = setOf("mp3", "m4a", "opus", "aac", "flac", "wav")

        private val FINAL_EXTS = setOf(
            "mp4", "m4a", "webm", "mkv", "mp3", "opus", "ogg", "aac", "flac", "wav", "mov", "m4v"
        )

        // YouTube hides its high-resolution formats from some clients. We try the default
        // client first and only fall back when it only exposes low qualities.
        private val YOUTUBE_CLIENT_VARIANTS = listOf(
            null,
            "youtube:player_client=android_vr",
            "youtube:player_client=web_safari",
            "youtube:player_client=mweb"
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

        fun isYoutubeHost(url: String): Boolean {
            return try {
                val host = URI(url).host?.lowercase() ?: return false
                host == "youtube.com" || host.endsWith(".youtube.com") || host == "youtu.be"
            } catch (e: Exception) {
                false
            }
        }

        /**
         * YouTube links that point at many videos (playlists, channels, feeds, search) instead
         * of one. yt-dlp would read every entry, which takes minutes and can't be downloaded
         * as a single file anyway, so they are refused up front.
         */
        fun isYoutubeCollectionUrl(url: String): Boolean {
            return try {
                val uri = URI(url)
                val host = uri.host?.lowercase() ?: return false
                if (host == "youtu.be") return false
                val path = (uri.path ?: "").lowercase().trimEnd('/')
                val query = uri.rawQuery ?: ""
                val hasVideoId = query.split('&').any { it.startsWith("v=") && it.length > 2 }
                val singleVideo = (path == "/watch" && hasVideoId) ||
                    SINGLE_VIDEO_PREFIXES.any { path.startsWith(it) }
                !singleVideo
            } catch (e: Exception) {
                true
            }
        }

        private val SINGLE_VIDEO_PREFIXES = listOf("/shorts/", "/live/", "/embed/", "/v/", "/clip/")

        /** Whole budget for reading one link's info (all YouTube client variants together). */
        private const val INFO_BUDGET_MS = 85_000L
        private const val INFO_MIN_RUN_MS = 20_000L
    }

    private val watchdog = Executors.newSingleThreadScheduledExecutor()

    init {
        channel.setMethodCallHandler(this)
    }

    /** Called only when the Flutter engine itself goes away (see MainActivity.EngineChannels). */
    fun cleanup() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        watchdog.shutdownNow()
    }

    /**
     * The download folder must be inside this app's private data directory and must not
     * contain '%' (yt-dlp would read it as an output-template field).
     */
    private fun safeOutputDir(outDir: String): File? {
        if (outDir.contains('%')) return null
        return try {
            val dir = File(outDir).canonicalFile
            val root = context.applicationContext.filesDir.parentFile?.canonicalFile ?: return null
            if (dir.path.startsWith(root.path + File.separator)) dir else null
        } catch (e: Exception) {
            null
        }
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
            "resetToBundled" -> handleResetToBundled(result)
            "getInfo" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("INVALID_ARGUMENT", "Missing url", null)
                    return
                }
                // Optional id chosen by Dart so the lookup can be cancelled ("cancelInfo").
                val requestId = call.argument<String>("requestId")?.takeIf { TASK_ID_REGEX.matches(it) }
                handleGetInfo(url, requestId, result)
            }
            "cancelInfo" -> {
                val requestId = call.argument<String>("requestId")
                if (requestId == null || !TASK_ID_REGEX.matches(requestId)) {
                    result.error("INVALID_ARGUMENT", "Missing requestId", null)
                    return
                }
                cancelledInfo.add(requestId)
                val killed = runCatching {
                    YoutubeDL.getInstance().destroyProcessById(infoProcessId(requestId))
                }.getOrDefault(false)
                result.success(killed)
            }
            "download" -> {
                val taskId = call.argument<String>("taskId")
                val url = call.argument<String>("url")
                val formatSelector = call.argument<String>("formatSelector")
                val outDir = call.argument<String>("outDir")
                val extractorArgs = call.argument<String>("extractorArgs")
                val audioFormat = call.argument<String>("audioFormat")
                if (taskId == null || url == null || outDir == null) {
                    result.error("INVALID_ARGUMENT", "Missing required arguments", null)
                    return
                }
                handleDownload(taskId, url, formatSelector, outDir, extractorArgs, audioFormat, result)
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
                ensureInitialized()
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

    /**
     * Undo a yt-dlp self-update: delete the downloaded copy so the version shipped inside the
     * app is unpacked again. This is the way back if an update breaks downloads, without
     * clearing app storage (which would delete every download).
     */
    private fun handleResetToBundled(result: MethodChannel.Result) {
        if (activeTasks.isNotEmpty()) {
            result.error("BUSY", "Wait for the current downloads to finish first", null)
            return
        }
        executor.execute {
            try {
                val app = context.applicationContext
                val ytdlpDir = File(File(app.noBackupFilesDir, "youtubedl-android"), "yt-dlp")
                if (ytdlpDir.exists()) ytdlpDir.deleteRecursively()
                app.getSharedPreferences("youtubedl-android", Context.MODE_PRIVATE)
                    .edit()
                    .remove("dlpVersion")
                    .remove("dlpVersionName")
                    .apply()
                // Unpacks the bundled copy again (it only does so when the file is missing).
                YoutubeDL.getInstance().init_ytdlp(app, ytdlpDir)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("RESET_FAILED", e.localizedMessage ?: "Could not reset yt-dlp", null)
                }
            }
        }
    }

    /**
     * Runs `yt-dlp --dump-json` once, optionally with a YouTube player-client override.
     * A watchdog kills the run after [timeoutMs] so a slow site can never hang the app.
     */
    private fun fetchInfoJson(url: String, extractorArgs: String?, timeoutMs: Long, requestId: String?): JSONObject {
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            // Links to a collection on other sites (e.g. an Instagram carousel): first item only.
            addOption("--playlist-items", "1")
            addOption("--ignore-config")
            addOption("--dump-json")
            addOption("--no-warnings")
            addOption("--socket-timeout", "20")
            if (extractorArgs != null) {
                addOption("--extractor-args", extractorArgs)
            }
        }
        val processId = if (requestId != null) infoProcessId(requestId) else "info-" + java.util.UUID.randomUUID().toString()
        val timedOut = java.util.concurrent.atomic.AtomicBoolean(false)
        val kill = watchdog.schedule({
            timedOut.set(true)
            runCatching { YoutubeDL.getInstance().destroyProcessById(processId) }
        }, timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
        val response = try {
            YoutubeDL.getInstance().execute(request, processId)
        } catch (e: Exception) {
            if (timedOut.get()) throw YoutubeDLException("INFO_TIMEOUT: reading the link took too long")
            throw e
        } finally {
            kill.cancel(false)
        }
        // One JSON object per line; we asked for a single item, take the first.
        val outJson = response.out?.lineSequence()?.map { it.trim() }?.firstOrNull { it.startsWith("{") }
        if (outJson.isNullOrEmpty()) {
            throw YoutubeDLException("Empty response from extractor")
        }
        return JSONObject(outJson)
    }

    private fun maxVideoHeight(json: JSONObject): Int {
        val formats = json.optJSONArray("formats") ?: return 0
        var best = 0
        for (i in 0 until formats.length()) {
            val fmt = formats.optJSONObject(i) ?: continue
            val vcodec = fmt.optString("vcodec", "none")
            if (vcodec.isEmpty() || vcodec == "none") continue
            val h = fmt.optInt("height", 0)
            if (h > best) best = h
        }
        return best
    }

    private fun handleGetInfo(url: String, requestId: String?, result: MethodChannel.Result) {
        if (!isHostAllowed(url)) {
            result.error("HOST_NOT_ALLOWED", "This platform is not in the allowed extractor list", null)
            return
        }
        if (isYoutubeHost(url) && isYoutubeCollectionUrl(url)) {
            result.error(
                "PLAYLIST_NOT_SUPPORTED",
                "Playlists and channels can't be downloaded. Open a single video link instead.",
                null
            )
            return
        }

        executor.execute {
            try {
                ensureInitialized()

                var bestJson: JSONObject? = null
                var bestHeight = -1
                var bestArgs: String? = null
                var lastError: Exception? = null
                val started = System.currentTimeMillis()

                val variants = if (isYoutubeHost(url)) YOUTUBE_CLIENT_VARIANTS else listOf(null)
                for ((index, variant) in variants.withIndex()) {
                    if (requestId != null && cancelledInfo.contains(requestId)) {
                        throw YoutubeDLException("Interrupted: lookup cancelled")
                    }
                    val left = INFO_BUDGET_MS - (System.currentTimeMillis() - started)
                    // Out of time for another client: use what we have (or report the error).
                    if (index > 0 && left < INFO_MIN_RUN_MS) break
                    try {
                        val json = fetchInfoJson(url, variant, maxOf(left, INFO_MIN_RUN_MS), requestId)
                        val h = maxVideoHeight(json)
                        if (h > bestHeight) {
                            bestHeight = h
                            bestJson = json
                            bestArgs = variant
                        }
                        // Good enough: stop probing other clients.
                        if (h >= 1080) break
                    } catch (e: Exception) {
                        lastError = e
                        if ((e.message ?: "").startsWith("INFO_TIMEOUT")) break
                    }
                }

                val json = bestJson ?: throw (lastError ?: YoutubeDLException("No info returned"))

                if (json.optString("_type", "video") == "playlist") {
                    throw YoutubeDLException("PLAYLIST_NOT_SUPPORTED: link points at a playlist")
                }
                val liveStatus = json.optString("live_status", "")
                if (json.optBoolean("is_live", false) || liveStatus == "is_live" || liveStatus == "is_upcoming") {
                    throw YoutubeDLException("LIVE_NOT_SUPPORTED: live or upcoming stream")
                }

                val id = json.optString("id", "")
                val title = json.optString("title", "Video")
                val uploader = json.optString("uploader", json.optString("channel", ""))
                val duration = json.optInt("duration", 0)
                val thumbnail = pickThumbnail(json)

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
                        // Skip storyboards / images (no audio, no video stream).
                        if (!hasVideo && !hasAudio) continue

                        formatsList.add(
                            mapOf(
                                "formatId" to formatId,
                                "ext" to ext,
                                "formatNote" to note,
                                "hasVideo" to hasVideo,
                                "hasAudio" to hasAudio,
                                "height" to height,
                                "width" to width,
                                "filesize" to filesize,
                                "tbr" to fmt.optDouble("tbr", 0.0),
                                "abr" to fmt.optDouble("abr", 0.0),
                                "fps" to fmt.optDouble("fps", 0.0),
                                "vcodec" to vcodec,
                                "acodec" to acodec
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
                    "extractorArgs" to bestArgs,
                    "formats" to formatsList
                )

                mainHandler.post { result.success(resultMap) }
            } catch (e: Exception) {
                val (code, msg) = mapException(e)
                val detail = errorDetail(e)
                mainHandler.post { result.error(code, msg, detail) }
            } finally {
                if (requestId != null) cancelledInfo.remove(requestId)
            }
        }
    }

    private fun pickThumbnail(json: JSONObject): String {
        val direct = json.optString("thumbnail", "")
        if (direct.startsWith("https://")) return direct
        val list = json.optJSONArray("thumbnails") ?: return ""
        var bestUrl = ""
        var bestArea = -1
        for (i in 0 until list.length()) {
            val t = list.optJSONObject(i) ?: continue
            val u = t.optString("url", "")
            if (!u.startsWith("https://")) continue
            val area = t.optInt("width", 0) * t.optInt("height", 0)
            if (area >= bestArea) {
                bestArea = area
                bestUrl = u
            }
        }
        return bestUrl
    }

    private fun handleDownload(
        taskId: String,
        url: String,
        formatSelector: String?,
        outDir: String,
        extractorArgs: String?,
        audioFormat: String?,
        result: MethodChannel.Result
    ) {
        if (!isHostAllowed(url)) {
            result.error("HOST_NOT_ALLOWED", "This platform is not in the allowed extractor list", null)
            return
        }
        if (!TASK_ID_REGEX.matches(taskId)) {
            result.error("INVALID_ARGUMENT", "Invalid task id", null)
            return
        }
        if (!formatSelector.isNullOrEmpty() && !FORMAT_SELECTOR_REGEX.matches(formatSelector)) {
            result.error("INVALID_ARGUMENT", "Invalid format selector", null)
            return
        }
        val outputDir = safeOutputDir(outDir)
        if (outputDir == null) {
            result.error("INVALID_ARGUMENT", "Invalid output folder", null)
            return
        }

        executor.execute {
            try {
                ensureInitialized()
                activeTasks[taskId] = taskId

                cancelledTasks.remove(taskId)
                if (!outputDir.exists()) outputDir.mkdirs()

                // First the client the quality list came from, then (YouTube only) the other
                // clients: some of them hand out stream URLs that fail with HTTP 403.
                val variants = mutableListOf<String?>()
                if (extractorArgs != null && EXTRACTOR_ARGS_REGEX.matches(extractorArgs)) variants.add(extractorArgs)
                if (isYoutubeHost(url)) {
                    for (v in YOUTUBE_CLIENT_VARIANTS) if (v !in variants) variants.add(v)
                }
                if (variants.isEmpty()) variants.add(null)

                var lastError: Exception? = null
                var done = false
                for (variant in variants.take(3)) {
                    if (cancelledTasks.contains(taskId)) throw YoutubeDLException("Interrupted")
                    val request = YoutubeDLRequest(url).apply {
                        addOption("--no-playlist")
                        // Same single item the quality list was read from.
                        addOption("--playlist-items", "1")
                        // Never record a live stream (it has no end).
                        addOption("--match-filters", "!is_live")
                        addOption("--ignore-config")
                        addOption("--max-filesize", "2G")
                        addOption("--no-mtime")
                        addOption("--socket-timeout", "30")
                        addOption("--retries", "5")
                        addOption("--fragment-retries", "5")
                        addOption("--concurrent-fragments", "4")
                        addOption("-o", "${outputDir.absolutePath}/$taskId.%(ext)s")
                        if (!formatSelector.isNullOrEmpty()) {
                            addOption("-f", formatSelector)
                        }
                        if (variant != null) {
                            addOption("--extractor-args", variant)
                        }
                        if (audioFormat != null && audioFormat in AUDIO_FORMATS) {
                            addOption("-x")
                            addOption("--audio-format", audioFormat)
                            addOption("--audio-quality", "0")
                        } else {
                            // mp4 when the codecs fit it, otherwise mkv (VP9/AV1 + Opus for 1440p/4K).
                            addOption("--merge-output-format", "mp4/mkv")
                        }
                    }

                    var lastPercent = -1
                    var lastPostTime = 0L
                    try {
                        val response = YoutubeDL.getInstance().execute(request, taskId) { progress, etaInSeconds, line ->
                            val now = System.currentTimeMillis()
                            val p = progress.toInt()
                            val isPostProcess = line != null && (line.contains("[Merger]") ||
                                line.contains("[ExtractAudio]") || line.contains("[VideoConvertor]"))
                            // Throttle progress events to ~4 Hz (250 ms) or completion
                            if (isPostProcess || (p != lastPercent && (now - lastPostTime >= 250 || p == 100))) {
                                lastPercent = p
                                lastPostTime = now
                                mainHandler.post {
                                    channel.invokeMethod("onProgress", mapOf(
                                        "taskId" to taskId,
                                        "progress" to progress,
                                        "eta" to etaInSeconds,
                                        "line" to (line ?: "")
                                    ))
                                }
                            }
                        }
                        // yt-dlp skips (exit 0, no file) items rejected by --match-filters.
                        if ((response.out ?: "").contains("does not pass filter")) {
                            throw YoutubeDLException("LIVE_NOT_SUPPORTED: live stream")
                        }
                        done = true
                        break
                    } catch (e: Exception) {
                        lastError = e
                        if (isCancelled(taskId, e)) throw e
                        // Wrong credentials / private / DRM / not found / too large: another client cannot help.
                        val code = mapException(e).first
                        if (code != "EXTRACTION_FAILED" && code != "NETWORK_ERROR") throw e
                    }
                }
                if (!done) throw (lastError ?: YoutubeDLException("Download failed"))

                activeTasks.remove(taskId)

                // Final file is "<taskId>.<ext>" (exactly one dot after the id). Intermediate
                // streams ("<taskId>.f137.mp4"), ".part", ".ytdl" and ".temp" files are ignored.
                val files = outputDir.listFiles { _, name -> name.startsWith("$taskId.") } ?: emptyArray()
                val targetFile = files
                    .filter { f ->
                        val rest = f.name.removePrefix("$taskId.")
                        !rest.contains('.') && rest.lowercase() in FINAL_EXTS
                    }
                    .maxByOrNull { it.length() }

                if (targetFile == null) {
                    throw YoutubeDLException("Download finished but no output file was produced")
                }

                mainHandler.post {
                    result.success(mapOf(
                        "taskId" to taskId,
                        "filePath" to targetFile.absolutePath,
                        "ext" to targetFile.extension.lowercase(),
                        "fileSize" to targetFile.length()
                    ))
                }
            } catch (e: Exception) {
                activeTasks.remove(taskId)
                val (code, msg) = mapException(e)
                val detail = errorDetail(e)
                mainHandler.post { result.error(code, msg, detail) }
            }
        }
    }

    private fun handleCancel(taskId: String, result: MethodChannel.Result) {
        try {
            cancelledTasks.add(taskId)
            YoutubeDL.getInstance().destroyProcessById(taskId)
            activeTasks.remove(taskId)
            result.success(true)
        } catch (e: Exception) {
            result.error("CANCEL_FAILED", e.localizedMessage ?: "Could not cancel task", null)
        }
    }

    @Synchronized
    private fun ensureInitialized() {
        if (!isInitialized) {
            YoutubeDL.getInstance().init(context.applicationContext)
            // Without this yt-dlp cannot find ffmpeg: every "video + audio" merge and
            // every MP3 conversion fails with a generic extraction error.
            FFmpeg.getInstance().init(context.applicationContext)
            isInitialized = true
        }
    }

    /** Last meaningful line of yt-dlp's error output, without URLs / paths, for display and logs. */
    private fun errorDetail(e: Exception): String {
        val raw = e.message ?: e.javaClass.simpleName
        val line = raw.lines().map { it.trim() }.lastOrNull { it.startsWith("ERROR:") }
            ?: raw.lines().map { it.trim() }.lastOrNull { it.isNotEmpty() }
            ?: return ""
        return line
            .replace(Regex("https?://\\S+"), "<url>")
            .replace(Regex("/(data|storage|sdcard)/\\S+"), "<path>")
            .removePrefix("ERROR:")
            .trim()
            .take(220)
    }

    private fun isCancelled(taskId: String, e: Exception): Boolean {
        val msg = e.message ?: ""
        return cancelledTasks.contains(taskId) ||
            msg.contains("Interrupted", ignoreCase = true) ||
            msg.contains("destroy", ignoreCase = true)
    }

    private fun mapException(e: Exception): Pair<String, String> {
        val msg = e.localizedMessage ?: ""
        return when {
            msg.startsWith("PLAYLIST_NOT_SUPPORTED") ->
                Pair("PLAYLIST_NOT_SUPPORTED", "Playlists and channels can't be downloaded. Open a single video link instead.")
            msg.startsWith("LIVE_NOT_SUPPORTED") || msg.contains("does not pass filter") ->
                Pair("LIVE_NOT_SUPPORTED", "Live streams can't be downloaded.")
            msg.startsWith("INFO_TIMEOUT") ->
                Pair("INFO_TIMEOUT", "This link is taking too long. Try again later.")
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
            msg.contains("Unable to resolve host", ignoreCase = true) ||
                msg.contains("timed out", ignoreCase = true) ||
                msg.contains("Network is unreachable", ignoreCase = true) ||
                msg.contains("Connection reset", ignoreCase = true) ->
                Pair("NETWORK_ERROR", "Network problem while downloading. Check your connection and try again")
            else ->
                Pair("EXTRACTION_FAILED", "Could not extract or download media")
        }
    }
}
