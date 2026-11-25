// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "mediahub/other_audio": other apps' playback, for Settings → "Resume after other apps".
 *
 * When another app takes the sound for good (it starts music or a video), the music pauses and
 * Android never gives the sound back. Dart then calls "start"; from then on every change in the
 * phone's playback (AudioManager's playback callback: API 26+, no permission; other apps'
 * players are anonymous but still say whether they play and what for) is reported with
 * "otherAudio" {playing, inCall}:
 * - playing = true at once when some app plays music, a video or a game;
 * - playing = false once nothing has played for [QUIET_DELAY_MS] (long enough for a buffering
 *   pause or YouTube's "Up next" countdown not to count as the other app stopping).
 * The list has no owners on it, so MediaHub's own player must have stopped before anything
 * counts: Dart starts watching only after its own pause, and nothing is reported for the first
 * [SETTLE_MS] after "start" either (the first report says how things are once that is over).
 * Dart calls "stop" when it no longer waits, and the callback is unregistered.
 */
class OtherAudioChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        private const val QUIET_DELAY_MS = 10_000L
        private const val SETTLE_MS = 500L
    }

    private val audio = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val channel = MethodChannel(messenger, "mediahub/other_audio")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var watching = false
    private var settling = false
    private var sentPlaying = false

    private val callback = object : AudioManager.AudioPlaybackCallback() {
        override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>?) {
            onPlayback(configs ?: emptyList())
        }
    }

    /** Nothing has played for [QUIET_DELAY_MS]: checked once more, then reported. */
    private val reportQuiet = Runnable {
        if (!watching) return@Runnable
        if (anyMediaPlaying(currentConfigs())) {
            report(true)
        } else {
            sentPlaying = false
            report(false)
        }
    }

    /** The first look, once MediaHub's own player has surely stopped. */
    private val settled = Runnable {
        if (!watching) return@Runnable
        settling = false
        onPlayback(currentConfigs())
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    start()
                    result.success(true)
                } catch (e: Exception) {
                    stop()
                    result.error("OTHER_AUDIO_FAILED", e.localizedMessage, null)
                }
            }
            "stop" -> {
                stop()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** Called only when the Flutter engine itself goes away (see MainActivity.EngineChannels). */
    fun cleanup() {
        channel.setMethodCallHandler(null)
        stop()
    }

    private fun start() {
        if (!watching) {
            audio.registerAudioPlaybackCallback(callback, mainHandler)
            watching = true
        }
        sentPlaying = false
        // How things are in a moment (the other app may already play by then).
        settling = true
        mainHandler.removeCallbacks(reportQuiet)
        mainHandler.removeCallbacks(settled)
        mainHandler.postDelayed(settled, SETTLE_MS)
    }

    private fun stop() {
        mainHandler.removeCallbacks(reportQuiet)
        mainHandler.removeCallbacks(settled)
        settling = false
        sentPlaying = false
        if (!watching) return
        watching = false
        runCatching { audio.unregisterAudioPlaybackCallback(callback) }
    }

    private fun onPlayback(configs: List<AudioPlaybackConfiguration>) {
        // While settling, the first look ([settled]) reads the list itself.
        if (!watching || settling) return
        mainHandler.removeCallbacks(reportQuiet)
        if (anyMediaPlaying(configs)) {
            if (!sentPlaying) report(true)
        } else {
            mainHandler.postDelayed(reportQuiet, QUIET_DELAY_MS)
        }
    }

    private fun currentConfigs(): List<AudioPlaybackConfiguration> =
        try {
            audio.activePlaybackConfigurations
        } catch (_: Exception) {
            emptyList()
        }

    /** An app plays music, a video or a game (not a notification, a call or navigation). */
    private fun anyMediaPlaying(configs: List<AudioPlaybackConfiguration>): Boolean =
        configs.any {
            val usage = it.audioAttributes.usage
            usage == AudioAttributes.USAGE_MEDIA || usage == AudioAttributes.USAGE_GAME
        }

    /** Ringing, in a call, or in a voice or video chat. */
    private fun inCall(): Boolean = audio.mode != AudioManager.MODE_NORMAL

    private fun report(playing: Boolean) {
        if (playing) sentPlaying = true
        try {
            channel.invokeMethod("otherAudio", mapOf("playing" to playing, "inCall" to inCall()))
        } catch (_: Exception) {
        }
    }
}
