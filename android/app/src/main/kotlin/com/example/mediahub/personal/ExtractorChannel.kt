package com.example.mediahub.personal

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.ConnectivityManager
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
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantReadWriteLock

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

    // Every yt-dlp run (lookup, download, version) holds the read lock; Update and Reset
    // take the write lock without waiting (BUSY otherwise). So yt-dlp's files are never
    // replaced under a running process, and a run that starts during an update waits for it.
    private val engineLock = ReentrantReadWriteLock()

    // Version of the yt-dlp copy shipped inside the app (read once with --version).
    @Volatile
    private var bundledVersion: String? = null

    private fun infoProcessId(requestId: String) = "info-$requestId"

    companion object {
        const val PERSONAL_TOOLS = true

        // Kept in step with lib/personal/extractor_hosts.dart (a Dart test compares the two).
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
            "vimeo.com",
            "dailymotion.com",
            "dai.ly",
            "reddit.com",
            "redd.it"
        )

        // The task id becomes part of the output file name: keep it boring.
        private val TASK_ID_REGEX = Regex("^[A-Za-z0-9_-]{1,64}$")

        // yt-dlp format selectors only ever need this small alphabet. Never starts with '-'.
        private val FORMAT_SELECTOR_REGEX = Regex("^[A-Za-z0-9_\\[\\]<>=!*+/,.()^$~:?][A-Za-z0-9_\\[\\]<>=!*+/,.()^$~:?-]{0,299}$")

        // yt-dlp format sort (-S), e.g. "height:1080,vcodec:h264,ext:mp4:m4a". Never starts with '-'.
        private val FORMAT_SORT_REGEX = Regex("^[a-z0-9]+(:[a-z0-9.]+)*(,[a-z0-9]+(:[a-z0-9.]+)*){0,5}$")

        // Only extractor-args we generate ourselves are accepted (YouTube player clients).
        private val EXTRACTOR_ARGS_REGEX = Regex("^youtube:player_client=[a-z0-9_,]{1,80}$")

        // Errors another YouTube client (or the catch-all format) may get past. Everything
        // else (private, age-restricted, unavailable, live, offline, cancelled ...) stops at once.
        private val RETRY_WITH_OTHER_CLIENT = setOf(
            "EXTRACTION_FAILED", "FORMAT_UNAVAILABLE", "BOT_CHECK", "NETWORK_ERROR"
        )

        // At most this many YouTube clients at the chosen quality, then the catch-all once:
        // each try is a full yt-dlp run, and many runs in a row make YouTube limit the phone.
        private const val MAX_CLIENT_TRIES = 3

        // The yt-dlp inside youtubedl-android 0.18.1 (used when no version was ever recorded).
        private const val LIBRARY_YTDLP_VERSION = "2025.11.12"
        private val YTDLP_VERSION_REGEX = Regex("^\\d{4}\\.\\d{1,2}\\.\\d{1,2}(\\.\\d+)?$")

        /** yt-dlp versions ("2026.10.26", "2026.10.26.1") compared part by part. */
        fun compareYtDlpVersions(a: String, b: String): Int {
            val pa = a.split('.').map { it.toIntOrNull() ?: 0 }
            val pb = b.split('.').map { it.toIntOrNull() ?: 0 }
            for (i in 0 until maxOf(pa.size, pb.size)) {
                val c = (pa.getOrElse(i) { 0 }).compareTo(pb.getOrElse(i) { 0 })
                if (c != 0) return c
            }
            return 0
        }

        // Address-family probe before a yt-dlp run (see addressFamilyOption).
        private const val FAMILY_PROBE_MS = 1500
        private const val FAMILY_CACHE_MS = 5 * 60 * 1000L

        private val AUDIO_FORMATS = setOf("mp3", "m4a", "opus", "aac", "flac", "wav")
        /** yt-dlp --audio-quality values the app may ask for ("0" = best VBR). Nothing else is passed. */
        private val AUDIO_QUALITIES = setOf("0", "320K", "256K", "192K", "128K")

        private val FINAL_EXTS = setOf(
            "mp4", "m4a", "webm", "mkv", "mp3", "opus", "ogg", "aac", "flac", "wav", "mov", "m4v"
        )

        // YouTube hides its high-resolution formats from some clients. We try the default
        // client first and only fall back when it only exposes low qualities.
        // A client a newer yt-dlp no longer knows is skipped with a warning (the default is used).
        private val YOUTUBE_CLIENT_VARIANTS = listOf(
            null,
            "youtube:player_client=android_vr",
            "youtube:player_client=web_safari",
            "youtube:player_client=mweb",
            "youtube:player_client=tv_simply"
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
            // null when the phone cannot tell (e.g. no network-state permission).
            "isMetered" -> result.success(isMeteredNetwork())
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
                val audioQuality = call.argument<String>("audioQuality")?.takeIf { it in AUDIO_QUALITIES } ?: "0"
                val formatSort = call.argument<String>("formatSort")
                if (taskId == null || url == null || outDir == null) {
                    result.error("INVALID_ARGUMENT", "Missing required arguments", null)
                    return
                }
                handleDownload(taskId, url, formatSelector, formatSort, outDir, extractorArgs, audioFormat, audioQuality, result)
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
            // Init unpacks yt-dlp when it is missing: never in the middle of an update.
            installShippedYtDlpOnce()
            val readLock = engineLock.readLock()
            readLock.lock()
            try {
                ensureInitialized()
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("INIT_FAILED", e.localizedMessage ?: "Failed to initialize extractor", null)
                }
            } finally {
                readLock.unlock()
            }
        }
    }

    private fun handleVersion(result: MethodChannel.Result) {
        executor.execute {
            installShippedYtDlpOnce()
            val readLock = engineLock.readLock()
            readLock.lock()
            try {
                ensureInitialized()
                // Only known after an update; the copy inside the app is asked directly.
                val ver = YoutubeDL.getInstance().version(context.applicationContext)
                    ?.takeIf { it.isNotBlank() } ?: readBundledVersion()
                mainHandler.post { result.success(ver) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("VERSION_ERROR", e.localizedMessage ?: "Could not get version", null)
                }
            } finally {
                readLock.unlock()
            }
        }
    }

    /** `yt-dlp --version` of the copy in use (only asked when the library does not know it). */
    private fun readBundledVersion(): String? {
        bundledVersion?.let { return it }
        return try {
            val request = YoutubeDLRequest(emptyList<String>()).apply {
                addOption("--ignore-config")
                addOption("--version")
            }
            val out = YoutubeDL.getInstance().execute(request).out ?: ""
            val ver = out.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() }?.take(40)
            bundledVersion = ver
            ver
        } catch (e: Exception) {
            null
        }
    }

    private fun isMeteredNetwork(): Boolean? {
        return try {
            val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            cm?.isActiveNetworkMetered
        } catch (e: Exception) {
            // SecurityException without ACCESS_NETWORK_STATE: unknown.
            null
        }
    }

    private fun handleUpdate(result: MethodChannel.Result) {
        // Replacing the yt-dlp files while a download runs them breaks that download.
        if (activeTasks.isNotEmpty()) {
            result.error("BUSY", "Wait for the current downloads to finish first", null)
            return
        }
        executor.execute {
            val writeLock = engineLock.writeLock()
            // A lookup or download is running yt-dlp right now.
            if (!writeLock.tryLock()) {
                mainHandler.post { result.error("BUSY", "Wait for the current downloads to finish first", null) }
                return@execute
            }
            try {
                ensureInitialized()
                installShippedYtDlpLocked()
                val status = YoutubeDL.getInstance().updateYoutubeDL(
                    context.applicationContext,
                    YoutubeDL.UpdateChannel._STABLE
                )
                bundledVersion = null
                val statusName = status?.name ?: "DONE"
                mainHandler.post { result.success(statusName) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("UPDATE_ERROR", e.localizedMessage ?: "Could not update", null)
                }
            } finally {
                writeLock.unlock()
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
            val writeLock = engineLock.writeLock()
            if (!writeLock.tryLock()) {
                mainHandler.post { result.error("BUSY", "Wait for the current downloads to finish first", null) }
                return@execute
            }
            try {
                val app = context.applicationContext
                val ytdlpDir = File(File(app.noBackupFilesDir, "youtubedl-android"), "yt-dlp")
                if (ytdlpDir.exists()) ytdlpDir.deleteRecursively()
                app.getSharedPreferences("youtubedl-android", Context.MODE_PRIVATE)
                    .edit()
                    .remove("dlpVersion")
                    .remove("dlpVersionName")
                    .apply()
                // Unpacks the library's copy again (it only does so when the file is missing),
                // then MediaHub's newer shipped copy replaces it.
                YoutubeDL.getInstance().init_ytdlp(app, ytdlpDir)
                bundledVersion = null
                installShippedYtDlpLocked()
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("RESET_FAILED", e.localizedMessage ?: "Could not reset yt-dlp", null)
                }
            } finally {
                writeLock.unlock()
            }
        }
    }

    /**
     * Runs `yt-dlp --dump-json` once, optionally with a YouTube player-client override.
     * A watchdog kills the run after [timeoutMs] so a slow site can never hang the app.
     */
    // yt-dlp (Python) connects to one address after the other, with a 20-30 s timeout each,
    // and has no IPv4/IPv6 race ("Happy Eyeballs") the way a browser does. On a network where
    // one family is advertised but broken (IPv6 on some Wi-Fi, or IPv4 towards some servers,
    // as on the emulator), every request then waits out timeouts: a YouTube lookup there
    // stalled for over four minutes, and took 8 s with the working family forced. So before a
    // run, one TCP connection per family is tried at once (FAMILY_PROBE_MS at most). When only
    // one family answers, yt-dlp is told to use it; both or neither: yt-dlp decides as before.
    // Only allowlisted hosts are ever probed (callers check isHostAllowed first), and the
    // answer is kept for a few minutes per host.
    private val familyCache = ConcurrentHashMap<String, Pair<String?, Long>>()

    /** The cache key: the phone's current network and the host (a new network probes again). */
    private fun familyKey(url: String): String? {
        val host = try {
            URI(url).host?.lowercase()
        } catch (e: Exception) {
            null
        } ?: return null
        val network = runCatching {
            (context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)
                ?.activeNetwork?.networkHandle
        }.getOrNull() ?: 0L
        return "$network|$host"
    }

    /** "--force-ipv4", "--force-ipv6" or null for the host of [url]. */
    private fun addressFamilyOption(url: String): String? {
        val key = familyKey(url) ?: return null
        val host = key.substringAfter('|')
        val now = System.currentTimeMillis()
        familyCache[key]?.let { (flag, at) -> if (now - at in 0 until FAMILY_CACHE_MS) return flag }
        val (flag, conclusive) = probeFamily(host)
        // Only a clear answer is kept: a failed lookup or two failed connects say nothing
        // about the families and are asked again next time.
        if (conclusive) familyCache[key] = Pair(flag, now) else familyCache.remove(key)
        return flag
    }

    /** A run with a forced family failed as if offline: ask again next time, without it now. */
    private fun forgetAddressFamily(url: String) {
        familyKey(url)?.let { familyCache.remove(it) }
    }

    /** The family to force (or null), and whether that answer is worth keeping. */
    private fun probeFamily(host: String): Pair<String?, Boolean> {
        val addresses = try {
            InetAddress.getAllByName(host).toList()
        } catch (e: Exception) {
            return Pair(null, false)
        }
        val v4 = addresses.firstOrNull { it is Inet4Address }
        val v6 = addresses.firstOrNull { it is Inet6Address }
        // One family only (the phone has no IPv6, or the site none): nothing to choose.
        if (v4 == null || v6 == null) return Pair(null, true)
        val f4 = executor.submit<Boolean> { canConnect(v4) }
        val f6 = executor.submit<Boolean> { canConnect(v6) }
        val wait = FAMILY_PROBE_MS + 500L
        val ok4 = runCatching { f4.get(wait, TimeUnit.MILLISECONDS) }.getOrDefault(false)
        val ok6 = runCatching { f6.get(wait, TimeUnit.MILLISECONDS) }.getOrDefault(false)
        f4.cancel(true)
        f6.cancel(true)
        return when {
            ok4 && !ok6 -> Pair("--force-ipv4", true)
            ok6 && !ok4 -> Pair("--force-ipv6", true)
            ok4 && ok6 -> Pair(null, true)
            else -> Pair(null, false)
        }
    }

    private fun canConnect(address: InetAddress): Boolean = try {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(address, 443), FAMILY_PROBE_MS)
            true
        }
    } catch (e: Exception) {
        false
    }

    private fun fetchInfoJson(
        url: String,
        extractorArgs: String?,
        timeoutMs: Long,
        requestId: String?,
        family: String?
    ): JSONObject {
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            // Links to a collection on other sites (e.g. an Instagram carousel): first item only.
            addOption("--playlist-items", "1")
            addOption("--ignore-config")
            addOption("--dump-json")
            addOption("--no-warnings")
            addOption("--socket-timeout", "20")
            family?.let { addOption(it) }
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
            installShippedYtDlpOnce()
            val readLock = engineLock.readLock()
            readLock.lock()
            try {
                ensureInitialized()

                var bestJson: JSONObject? = null
                var bestHeight = -1
                var bestArgs: String? = null
                var lastError: Exception? = null
                val started = System.currentTimeMillis()

                val variants = if (isYoutubeHost(url)) YOUTUBE_CLIENT_VARIANTS else listOf(null)
                for ((index, variant) in variants.withIndex()) {
                    // Before the cancel check, so a cancel during the probe is still seen.
                    val family = addressFamilyOption(url)
                    if (requestId != null && cancelledInfo.contains(requestId)) {
                        throw YoutubeDLException("Interrupted: lookup cancelled")
                    }
                    val left = INFO_BUDGET_MS - (System.currentTimeMillis() - started)
                    // Out of time for another client: use what we have (or report the error).
                    if (index > 0 && left < INFO_MIN_RUN_MS) break
                    try {
                        val json = fetchInfoJson(url, variant, maxOf(left, INFO_MIN_RUN_MS), requestId, family)
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
                        // "Offline" with a forced family: the network changed under the answer
                        // (say, to Wi-Fi without IPv6). Ask again and carry on.
                        if (family != null && isOffline(e)) {
                            forgetAddressFamily(url)
                            continue
                        }
                        // Private, age-restricted, removed, offline ...: no other client helps.
                        if (isOffline(e) || mapException(e).first !in RETRY_WITH_OTHER_CLIENT) break
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
                                "acodec" to acodec,
                                // The direct media link (https only): the Online tab's swipe-away
                                // hand-off plays an audio-only one natively. Never logged.
                                "url" to fmt.optString("url", "").takeIf { it.startsWith("https://") }
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
                readLock.unlock()
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

    /** One yt-dlp run of a download: which YouTube client and which format selector. */
    private data class Attempt(val extractorArgs: String?, val selector: String?)

    /**
     * [selector] without its trailing catch-all ("/bv*+ba/b" or "/ba/b"): what each YouTube
     * client is tried with first, so one client offering fewer formats cannot lower the
     * quality while another still has it. The catch-all is the very last try.
     */
    private fun withoutCatchAll(selector: String?): String? {
        if (selector.isNullOrEmpty()) return selector
        for (tail in listOf("/bv*+ba/b", "/ba/b")) {
            if (selector.length > tail.length && selector.endsWith(tail)) return selector.removeSuffix(tail)
        }
        return selector
    }

    /**
     * The last-chance selector: whatever yt-dlp can get ("ba/b" for audio, otherwise its own
     * default "bv*+ba/b"). Null when [selector] already ends with it (or is yt-dlp's default).
     */
    private fun catchAllSelector(selector: String?, audioFormat: String?): String? {
        if (selector.isNullOrEmpty()) return null
        val isAudio = (audioFormat != null && audioFormat in AUDIO_FORMATS) ||
            selector.startsWith("ba") || selector.startsWith("bestaudio")
        val catchAll = if (isAudio) "ba/b" else "bv*+ba/b"
        return if (selector == catchAll || selector.endsWith("/$catchAll")) null else catchAll
    }

    /** What the finished file holds: a video track or sound only, and the video's height. */
    private data class TrackInfo(val hasVideo: Boolean?, val height: Int?)

    /**
     * Whether the finished file holds a video track (false: audio only, null: unknown) and,
     * when it does, the video's height in pixels (null when the file does not say).
     */
    private fun trackInfo(file: File): TrackInfo {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            var video = false
            var height: Int? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    video = true
                    if (height == null && format.containsKey(MediaFormat.KEY_HEIGHT)) {
                        height = format.getInteger(MediaFormat.KEY_HEIGHT)
                    }
                }
            }
            if (extractor.trackCount == 0) TrackInfo(null, null) else TrackInfo(video, height)
        } catch (e: Exception) {
            TrackInfo(null, null)
        } finally {
            runCatching { extractor.release() }
        }
    }

    private fun handleDownload(
        taskId: String,
        url: String,
        formatSelector: String?,
        formatSort: String?,
        outDir: String,
        extractorArgs: String?,
        audioFormat: String?,
        audioQuality: String,
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
        if (!formatSort.isNullOrEmpty() && (formatSort.length > 80 || !FORMAT_SORT_REGEX.matches(formatSort))) {
            result.error("INVALID_ARGUMENT", "Invalid format sort", null)
            return
        }
        val outputDir = safeOutputDir(outDir)
        if (outputDir == null) {
            result.error("INVALID_ARGUMENT", "Invalid output folder", null)
            return
        }

        executor.execute {
            installShippedYtDlpOnce()
            val readLock = engineLock.readLock()
            readLock.lock()
            try {
                ensureInitialized()
                activeTasks[taskId] = taskId

                cancelledTasks.remove(taskId)
                if (!outputDir.exists()) outputDir.mkdirs()

                // First the client the quality list came from, then (YouTube only) every
                // other client: YouTube hands some clients fewer formats, or stream URLs that
                // fail with HTTP 403. Last, once, the catch-all format with the default client.
                val variants = mutableListOf<String?>()
                if (extractorArgs != null && EXTRACTOR_ARGS_REGEX.matches(extractorArgs)) variants.add(extractorArgs)
                if (isYoutubeHost(url)) {
                    for (v in YOUTUBE_CLIENT_VARIANTS) if (v !in variants) variants.add(v)
                }
                if (variants.isEmpty()) variants.add(null)
                val strict = withoutCatchAll(formatSelector)
                val attempts = variants.take(MAX_CLIENT_TRIES).map { Attempt(it, strict) }.toMutableList()
                // Last, once: the nearest quality there is (the format sort keeps the cap).
                val last = if (strict != formatSelector) formatSelector else catchAllSelector(formatSelector, audioFormat)
                if (last != null) attempts.add(Attempt(null, last))

                var lastError: Exception? = null
                var done = false
                for (attempt in attempts) {
                    // Before the cancel check, so a cancel during the probe is still seen.
                    val family = addressFamilyOption(url)
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
                        family?.let { addOption(it) }
                        addOption("--retries", "5")
                        addOption("--fragment-retries", "5")
                        addOption("--concurrent-fragments", "4")
                        addOption("-o", "${outputDir.absolutePath}/$taskId.%(ext)s")
                        if (!attempt.selector.isNullOrEmpty()) {
                            addOption("-f", attempt.selector)
                        }
                        // Which of the matching formats wins (e.g. at most 1080p, H.264 + AAC first).
                        if (!formatSort.isNullOrEmpty()) {
                            addOption("-S", formatSort)
                        }
                        if (attempt.extractorArgs != null) {
                            addOption("--extractor-args", attempt.extractorArgs)
                        }
                        if (audioFormat != null && audioFormat in AUDIO_FORMATS) {
                            addOption("-x")
                            addOption("--audio-format", audioFormat)
                            addOption("--audio-quality", if (audioQuality in AUDIO_QUALITIES) audioQuality else "0")
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
                        // "Offline" with a forced family: the network changed under the answer.
                        // Ask again for the next attempt.
                        if (family != null && isOffline(e)) {
                            forgetAddressFamily(url)
                            continue
                        }
                        // Offline, private, age-restricted, removed, DRM, too large ...:
                        // another client or format cannot help.
                        if (isOffline(e)) throw e
                        if (mapException(e).first !in RETRY_WITH_OTHER_CLIENT) throw e
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
                // Videos go to Videos, sound only to Music (a "video" link can turn out audio only).
                // The height tells Dart when the nearest quality was saved instead of the chosen one.
                val tracks = trackInfo(targetFile)

                mainHandler.post {
                    result.success(mapOf(
                        "taskId" to taskId,
                        "filePath" to targetFile.absolutePath,
                        "ext" to targetFile.extension.lowercase(),
                        "fileSize" to targetFile.length(),
                        "hasVideo" to tracks.hasVideo,
                        "height" to tracks.height
                    ))
                }
            } catch (e: Exception) {
                activeTasks.remove(taskId)
                val (code, msg) = mapException(e)
                val detail = errorDetail(e)
                mainHandler.post { result.error(code, msg, detail) }
            } finally {
                readLock.unlock()
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

    // --- yt-dlp shipped with MediaHub -----------------------------------------------------
    // youtubedl-android 0.18.1 carries yt-dlp 2025.11.12, which YouTube no longer serves well
    // (1080p files fail part-way with HTTP 403). MediaHub ships a newer one in assets/ytdlp
    // (made by tools/device/update_ytdlp_asset.py from yt-dlp's PyPI package) and puts it in
    // place of the phone's copy when it is newer (a self-update that is newer still is kept).
    // The file is only replaced under the engine write lock (Python reads modules from the zip
    // while it runs), through a temporary file and a rename, and the version is recorded where
    // the library's updater keeps it, so Update compares against it.
    @Volatile
    private var shippedYtDlpChecked = false

    /** Before a run takes the read lock: installs the shipped yt-dlp once per process if newer. */
    private fun installShippedYtDlpOnce() {
        if (shippedYtDlpChecked) return
        val writeLock = engineLock.writeLock()
        // yt-dlp runs right now: the next run tries again.
        if (!writeLock.tryLock()) return
        try {
            if (!shippedYtDlpChecked) {
                installShippedYtDlpLocked()
                shippedYtDlpChecked = true
            }
        } catch (e: Exception) {
            // Never in the way of a run: the copy already there still works.
            shippedYtDlpChecked = true
        } finally {
            writeLock.unlock()
        }
    }

    /** With the engine write lock held. True when the shipped copy was put in place. */
    private fun installShippedYtDlpLocked(): Boolean {
        val app = context.applicationContext
        val shipped = try {
            app.assets.open("ytdlp/version.txt").bufferedReader().use { it.readText().trim() }
        } catch (e: Exception) {
            return false
        }
        if (!YTDLP_VERSION_REGEX.matches(shipped)) return false
        ensureInitialized()
        val prefs = app.getSharedPreferences("youtubedl-android", Context.MODE_PRIVATE)
        val current = prefs.getString("dlpVersion", null)?.takeIf { YTDLP_VERSION_REGEX.matches(it) }
            ?: LIBRARY_YTDLP_VERSION
        if (compareYtDlpVersions(shipped, current) <= 0) return false
        val dir = File(File(app.noBackupFilesDir, "youtubedl-android"), "yt-dlp")
        dir.mkdirs()
        val target = File(dir, "yt-dlp")
        val tmp = File(dir, "yt-dlp.shipped.tmp")
        try {
            app.assets.open("ytdlp/yt-dlp").use { input -> tmp.outputStream().use { input.copyTo(it) } }
            if (!tmp.renameTo(target)) return false
        } finally {
            if (tmp.exists()) tmp.delete()
        }
        prefs.edit()
            .putString("dlpVersion", shipped)
            .putString("dlpVersionName", "yt-dlp $shipped (shipped with MediaHub)")
            .apply()
        bundledVersion = null
        return true
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

    /**
     * The text an error is judged by: yt-dlp's ERROR lines when there are any. Its WARNING
     * lines (one client asked to sign in, another worked ...) must not decide the outcome.
     */
    private fun errorText(e: Exception): String {
        val raw = e.localizedMessage ?: ""
        val errors = raw.lines().map { it.trim() }.filter { it.startsWith("ERROR:") }
        return if (errors.isEmpty()) raw else errors.joinToString("\n")
    }

    /** The phone has no connection at all: no other client or format can help. */
    private fun isOffline(e: Exception): Boolean {
        val msg = errorText(e)
        return OFFLINE_MARKERS.any { msg.contains(it, ignoreCase = true) }
    }

    private val OFFLINE_MARKERS = listOf(
        "Unable to resolve host",
        "No address associated with hostname",
        "Name or service not known",
        "Temporary failure in name resolution",
        "Failed to resolve",
        "getaddrinfo failed",
        "Network is unreachable"
    )

    private val HTTP_404 = Regex("(^|[^A-Za-z0-9_-])404([^A-Za-z0-9_-]|$)")

    private fun mapException(e: Exception): Pair<String, String> {
        val msg = errorText(e)
        fun has(text: String) = msg.contains(text, ignoreCase = true)
        return when {
            msg.startsWith("PLAYLIST_NOT_SUPPORTED") ->
                Pair("PLAYLIST_NOT_SUPPORTED", "Playlists and channels can't be downloaded. Open a single video link instead.")
            msg.startsWith("LIVE_NOT_SUPPORTED") || msg.contains("does not pass filter") ||
                has("This live event will begin") || has("Premieres in") ->
                Pair("LIVE_NOT_SUPPORTED", "Live streams can't be downloaded.")
            msg.startsWith("INFO_TIMEOUT") ->
                Pair("INFO_TIMEOUT", "This link is taking too long. Try again later.")
            // The network breaks the secure connection (a school, office or hotel Wi-Fi that
            // inspects HTTPS, or a captive portal): no other client, update or retry can help.
            has("CERTIFICATE_VERIFY_FAILED") || has("certificate verify failed") ||
                has("SSLCertVerificationError") || has("unable to get local issuer certificate") ->
                Pair("NETWORK_BLOCKED", "This network blocks a secure connection to the site")
            // "Video unavailable. This content isn't available, try again later." is YouTube
            // limiting this phone's address for a while, not a removed video. Checked before
            // UNAVAILABLE; no other client or update can help (more runs make it worse).
            has("try again later") || has("rate-limit") || has("rate limit") ||
                has("Too Many Requests") || has("HTTP Error 429") ->
                Pair("RATE_LIMITED", "YouTube is limiting downloads from this phone for now")
            has("Private video") ->
                Pair("PRIVATE_CONTENT", "This content is private and cannot be downloaded")
            has("confirm your age") || has("age-restricted") || has("inappropriate for some users") ->
                Pair("AGE_RESTRICTED", "This video is age-restricted")
            // "Sign in to confirm you're not a bot": YouTube checks this client or address.
            has("not a bot") ->
                Pair("BOT_CHECK", "YouTube asked to confirm this is not a bot")
            has("Sign in") || has("login") || has("log in") ->
                Pair("LOGIN_REQUIRED", "This video requires login or authentication")
            msg.contains("DRM") ->
                Pair("DRM_PROTECTED", "This content is protected by DRM")
            has("Video unavailable") || has("This video is unavailable") || has("This video is not available") ||
                has("video has been removed") || has("not available in your country") ||
                has("account associated with this video has been terminated") ->
                Pair("UNAVAILABLE", "This video is unavailable")
            has("Requested format is not available") || has("No video formats found") ->
                Pair("FORMAT_UNAVAILABLE", "The site offered no format that could be saved")
            has("Unsupported URL") || has("No video could be found") || has("There is no video") ->
                Pair("NO_MEDIA", "This link has no video or audio to save")
            HTTP_404.containsMatchIn(msg) || has("Not Found") ->
                Pair("NOT_FOUND", "The requested media was not found")
            has("max-filesize") || has("File is larger than") ->
                Pair("FILE_TOO_LARGE", "The media exceeds the 2 GB download limit")
            has("Interrupted") || has("destroy") ->
                Pair("CANCELLED", "The download was cancelled")
            OFFLINE_MARKERS.any { has(it) } ||
                has("timed out") ||
                has("Connection reset") ||
                has("Connection refused") ||
                has("Remote end closed connection") ->
                Pair("NETWORK_ERROR", "Network problem while downloading. Check your connection and try again")
            else ->
                Pair("EXTRACTION_FAILED", "Could not extract or download media")
        }
    }
}
