// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.videoplayer.AudioSessions
import java.lang.ref.WeakReference
import kotlin.math.log10
import kotlin.math.roundToInt

/**
 * Volume, screen brightness, picture-in-picture, the headphone-unplug signal and the video
 * volume boost for the video player. Brightness only changes this app's window (it never
 * touches the system setting).
 *
 * The channel lives as long as the Flutter engine; the Activity it acts on is attached
 * and detached as Activities come and go (see MainActivity.EngineChannels).
 */
class DeviceControlsChannel(
    context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "DeviceControls"

        /** Hidden framework action; sent by the system whenever a stream's volume changes. */
        private const val ACTION_VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"
        private const val EXTRA_VOLUME_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE"

        /** The picture-in-picture window's buttons; app-private (explicit package, not exported). */
        private const val ACTION_PIP = "com.example.mediahub.action.PIP_CONTROL"
        private const val EXTRA_PIP = "pip_control"

        /** +6 dB is twice the amplitude: 200 % of full volume. */
        private const val MAX_BOOST_MB = 600

        /**
         * Whether FLAG_SECURE stays on in picture-in-picture. Checked on the API 37 emulator
         * (2026-11-25): see docs/DECISIONS.md #20.
         */
        private const val SECURE_IN_PIP = true
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "mediahub/device_controls")
    private val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var activityRef: WeakReference<Activity>? = null
    private val activity: Activity? get() = activityRef?.get()

    // --- picture in picture -------------------------------------------------
    private var pipEligible = false
    private var pipAspect = Rational(16, 9)

    /** Null: no buttons. Otherwise whether the middle button shows pause (playing) or play. */
    private var pipActionsPlaying: Boolean? = null

    // --- App lock: keep the app out of screenshots and the Recents thumbnail ---
    /** Dart's AppLockNotifier asks for it while App lock is on ("setSecure"). */
    private var secureWanted = false

    /**
     * FLAG_SECURE (and on API 33+ setRecentsScreenshotEnabled(false)) while [secureWanted].
     * Never while the Activity is in picture-in-picture when [SECURE_IN_PIP] is false: see
     * its note. Called on every change, on attach and when picture-in-picture changes.
     */
    fun applySecure(a: Activity? = activity) {
        val act = a ?: return
        val inPip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && act.isInPictureInPictureMode
        val on = secureWanted && (SECURE_IN_PIP || !inPip)
        act.runOnUiThread {
            if (on) {
                act.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                act.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            if (Build.VERSION.SDK_INT >= 33) act.setRecentsScreenshotEnabled(!secureWanted)
        }
    }

    fun attach(activity: Activity) {
        activityRef = WeakReference(activity)
        applySecure(activity)
        // A re-created Activity must learn the current PiP setup again (Android 12+ auto-enter).
        applyPipParams()
    }

    /**
     * Diagnostic for "the YouTube page covers the app": walks the Activity's views and
     * reports what could draw over the Flutter UI.
     *
     * - orphanWrappers: Flutter's texture-layer platform-view wrappers that are attached
     *   and visible but have no render target. Such a wrapper draws its WebView straight
     *   onto the window, over the Flutter surface (PlatformViewWrapper.draw falls back to
     *   FrameLayout.draw), so only the page shows and the app looks frozen.
     * - strayViews: anything in the window's content besides the FlutterView (a WebView
     *   fullscreen "custom view" left behind).
     * - flutterViews: FlutterViews in this window (exactly 1 when healthy).
     * - a visible WebView outside a wrapper is listed in strayViews as "webview:...".
     */
    fun uiCoverCheck(a: Activity): Map<String, Any> {
        var orphans = 0
        var wrappers = 0
        var flutterViews = 0
        val stray = mutableListOf<String>()
        fun wrapped(v: android.view.View): Boolean {
            var p = v.parent
            while (p is android.view.View) {
                if (p is io.flutter.plugin.platform.PlatformViewWrapper) return true
                p = p.parent
            }
            return false
        }
        fun walk(v: android.view.View) {
            if (v is io.flutter.embedding.android.FlutterView) flutterViews++
            // A visible WebView outside a texture wrapper is drawn as a plain view over
            // the Flutter surface (a headless page made visible, hybrid composition).
            if (v is android.webkit.WebView && v.isShown && v.width > 0 && v.height > 0 && !wrapped(v)) {
                stray.add("webview:" + v.javaClass.name)
            }
            if (v is io.flutter.plugin.platform.PlatformViewWrapper) {
                wrappers++
            }
            if (v is android.view.ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        val decor = a.window.decorView
        walk(decor)
        val content = a.findViewById<android.view.ViewGroup>(android.R.id.content)
        if (content != null) {
            for (i in 0 until content.childCount) {
                val c = content.getChildAt(i)
                if (c !is io.flutter.embedding.android.FlutterView && c.visibility == android.view.View.VISIBLE) {
                    stray.add(c.javaClass.name)
                }
            }
        }
        if (decor is android.view.ViewGroup) {
            for (i in 0 until decor.childCount) {
                val c = decor.getChildAt(i)
                // The decor's own children are the LinearLayout and the bar backgrounds;
                // a full-size FrameLayout added there is a fullscreen custom view.
                if (c.visibility == android.view.View.VISIBLE && c.id == android.view.View.NO_ID &&
                    c.width >= decor.width && c.height >= decor.height / 2 && c !is android.widget.LinearLayout
                ) stray.add("decor:" + c.javaClass.name)
            }
        }
        return mapOf(
            "orphanWrappers" to orphans,
            "wrappers" to wrappers,
            "flutterViews" to flutterViews,
            "strayViews" to stray,
        )
    }

    fun detach(activity: Activity) {
        if (this.activity === activity) activityRef = null
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        activityRef = null
        unregister(pipReceiver)
        setVolumeWatch(false)
        setNoisyWatch(false)
        releaseBoost()
        releaseMusicEq()
    }

    private fun register(receiver: BroadcastReceiver, filter: IntentFilter) {
        // System broadcasts still reach a not-exported receiver; other apps cannot.
        ContextCompat.registerReceiver(appContext, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    private fun unregister(receiver: BroadcastReceiver) {
        try {
            appContext.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Was not registered.
        }
    }

    private fun pipSupported(): Boolean {
        val a = activity ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            a.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun pipIntent(control: String, requestCode: Int): PendingIntent {
        val intent = Intent(ACTION_PIP).setPackage(appContext.packageName).putExtra(EXTRA_PIP, control)
        return PendingIntent.getBroadcast(
            appContext,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun pipActions(playing: Boolean): List<RemoteAction> {
        fun action(icon: Int, title: String, control: String, code: Int) = RemoteAction(
            Icon.createWithResource(appContext, icon), title, title, pipIntent(control, code)
        )
        return listOf(
            action(android.R.drawable.ic_media_rew, "Rewind 10 seconds", "rewind", 31),
            if (playing) {
                action(android.R.drawable.ic_media_pause, "Pause", "playPause", 32)
            } else {
                action(android.R.drawable.ic_media_play, "Play", "playPause", 32)
            },
            action(android.R.drawable.ic_media_ff, "Forward 10 seconds", "forward", 33)
        )
    }

    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
        val playing = pipActionsPlaying
        builder.setActions(if (playing == null) emptyList() else pipActions(playing))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: the system enters picture-in-picture by itself when the user leaves.
            builder.setAutoEnterEnabled(pipEligible)
        }
        return builder.build()
    }

    private fun applyPipParams() {
        val a = activity ?: return
        if (!pipSupported()) return
        // Android 12+ needs the params ahead of time for auto-enter; on any version an open
        // window picks up new buttons (the play / pause glyph) this way.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S || a.isInPictureInPictureMode) {
            try {
                a.setPictureInPictureParams(pipParams())
            } catch (e: IllegalStateException) {
                // Activity not in a state that accepts PiP params; the next call will retry.
            } catch (e: IllegalArgumentException) {
                // Rejected params (e.g. more actions than the device allows): keep the old ones.
                Log.w(TAG, "PiP params rejected: ${e.message}")
            }
        }
    }

    private fun enterPip(): Boolean {
        val a = activity ?: return false
        if (!pipSupported()) return false
        return try {
            a.enterPictureInPictureMode(pipParams())
        } catch (e: IllegalStateException) {
            false
        } catch (e: IllegalArgumentException) {
            false
        }
    }

    /** Called from MainActivity.onUserLeaveHint (Android 8-11 need us to enter PiP ourselves). */
    fun onUserLeaveHint() {
        if (pipEligible && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    fun notifyPipChanged(inPip: Boolean) {
        applySecure()
        channel.invokeMethod("pipChanged", inPip)
    }

    /** The user closed the picture-in-picture window instead of expanding it. */
    fun notifyPipDismissed() {
        channel.invokeMethod("pipDismissed", null)
    }

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val control = intent.getStringExtra(EXTRA_PIP) ?: return
            if (control == "rewind" || control == "playPause" || control == "forward") {
                channel.invokeMethod("pipAction", control)
            }
        }
    }

    // --- volume changes (the volume keys, the system slider, other apps) -------------
    private var volumeWatching = false

    private val volumeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val stream = intent.getIntExtra(EXTRA_VOLUME_STREAM_TYPE, -1)
            if (stream != -1 && stream != AudioManager.STREAM_MUSIC) return
            channel.invokeMethod("volumeChanged", musicVolume())
        }
    }

    private fun setVolumeWatch(on: Boolean) {
        if (on == volumeWatching) return
        volumeWatching = on
        if (on) register(volumeReceiver, IntentFilter(ACTION_VOLUME_CHANGED)) else unregister(volumeReceiver)
    }

    private fun musicVolume(): Double {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val cur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        return if (max > 0) cur.toDouble() / max else 0.0
    }

    // --- headphones unplugged / Bluetooth headset gone ---------------------------------
    private var noisyWatching = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                channel.invokeMethod("becomingNoisy", null)
            }
        }
    }

    private fun setNoisyWatch(on: Boolean) {
        if (on == noisyWatching) return
        noisyWatching = on
        if (on) {
            register(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        } else {
            unregister(noisyReceiver)
        }
    }

    // --- video volume boost ----------------------------------------------------------
    // A LoudnessEnhancer on the VIDEO player's own audio session (never session 0, the
    // global mix, and never the music player's session). Released when the video closes.
    private var enhancer: LoudnessEnhancer? = null
    private var enhancerSession = 0
    private var musicEq: android.media.audiofx.Equalizer? = null
    private var musicLoudness: LoudnessEnhancer? = null
    private var musicEqSession = 0

    private fun ensureMusicEq(sessionId: Int): android.media.audiofx.Equalizer? {
        if (sessionId <= 0) return null
        if (musicEq != null && musicEqSession == sessionId) return musicEq
        releaseMusicEq()
        return try {
            val eq = android.media.audiofx.Equalizer(0, sessionId)
            musicEq = eq
            musicEqSession = sessionId
            eq
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun getMusicEqParams(sessionId: Int): Map<String, Any>? {
        val eq = ensureMusicEq(sessionId) ?: return null
        return try {
            val range = eq.bandLevelRange
            val n = eq.numberOfBands.toInt()
            val bands = ArrayList<Map<String, Any>>(n)
            for (i in 0 until n) {
                val idx = i.toShort()
                val freqRange = eq.getBandFreqRange(idx)
                bands.add(
                    mapOf(
                        "index" to i,
                        "lowerFrequency" to (freqRange[0].toDouble() / 1000.0),
                        "upperFrequency" to (freqRange[1].toDouble() / 1000.0),
                        "centerFrequency" to (eq.getCenterFreq(idx).toDouble() / 1000.0),
                        "gain" to (eq.getBandLevel(idx).toDouble() / 100.0),
                    )
                )
            }
            mapOf(
                "minDecibels" to (range[0].toDouble() / 100.0),
                "maxDecibels" to (range[1].toDouble() / 100.0),
                "bands" to bands,
            )
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun applyMusicEq(
        sessionId: Int,
        enabled: Boolean,
        gains: List<Double>?,
        loudnessDb: Double,
    ): Boolean {
        val eq = ensureMusicEq(sessionId) ?: return false
        return try {
            eq.enabled = enabled
            if (enabled && gains != null) {
                val range = eq.bandLevelRange
                val minMb = range[0].toInt()
                val maxMb = range[1].toInt()
                val n = minOf(gains.size, eq.numberOfBands.toInt())
                for (i in 0 until n) {
                    val mb = (gains[i] * 100.0).roundToInt().coerceIn(minMb, maxMb)
                    eq.setBandLevel(i.toShort(), mb.toShort())
                }
            }
            val loudOn = enabled && loudnessDb > 0.0
            if (loudOn) {
                if (musicLoudness == null || musicEqSession != sessionId) {
                    try {
                        musicLoudness?.release()
                    } catch (_: RuntimeException) {}
                    musicLoudness = try {
                        LoudnessEnhancer(sessionId)
                    } catch (_: RuntimeException) {
                        null
                    }
                }
                musicLoudness?.setTargetGain((loudnessDb * 100.0).roundToInt().coerceIn(0, 1500))
                musicLoudness?.enabled = true
            } else {
                musicLoudness?.enabled = false
            }
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun releaseMusicEq() {
        try {
            musicEq?.enabled = false
        } catch (_: RuntimeException) {}
        try {
            musicEq?.release()
        } catch (_: RuntimeException) {}
        try {
            musicLoudness?.enabled = false
        } catch (_: RuntimeException) {}
        try {
            musicLoudness?.release()
        } catch (_: RuntimeException) {}
        musicEq = null
        musicLoudness = null
        musicEqSession = 0
    }

    /** Returns false when the boost cannot be applied (no session, no effect on this phone). */
    private fun setVideoBoost(playerId: Long, percent: Int): Boolean {
        if (percent <= 100) {
            // Back to normal: keep the effect but neutral, so raising again is instant.
            enhancer?.let {
                try {
                    it.setTargetGain(0)
                    it.setEnabled(false)
                } catch (e: RuntimeException) {
                    releaseBoost()
                }
            }
            return true
        }
        val session = AudioSessions.sessionIdFor(playerId)
        if (session <= 0) return false
        return try {
            var e = enhancer
            if (e == null || enhancerSession != session) {
                releaseBoost()
                e = LoudnessEnhancer(session)
                enhancer = e
                enhancerSession = session
            }
            val gainMb = (2000.0 * log10(percent / 100.0)).roundToInt().coerceIn(0, MAX_BOOST_MB)
            e.setTargetGain(gainMb)
            e.setEnabled(true)
            true
        } catch (e: RuntimeException) {
            // UnsupportedOperationException / IllegalStateException / IllegalArgumentException:
            // the effect is missing or refused on this phone.
            Log.w(TAG, "Volume boost unavailable: ${e.message}")
            releaseBoost()
            false
        }
    }

    private fun releaseBoost() {
        val e = enhancer ?: return
        enhancer = null
        enhancerSession = 0
        try {
            e.setEnabled(false)
        } catch (ignored: RuntimeException) {
            // Already broken; release below.
        }
        try {
            e.release()
        } catch (ignored: RuntimeException) {
            // Nothing more to free.
        }
    }

    // Runs after every property above is initialised (Kotlin runs initialisers in order).
    init {
        channel.setMethodCallHandler(this)
        // Always on (cheap): only our own PendingIntents can reach it.
        register(pipReceiver, IntentFilter(ACTION_PIP))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getVolume" -> result.success(musicVolume())
                "setVolume" -> {
                    val v = (call.argument<Double>("value") ?: 0.0).coerceIn(0.0, 1.0)
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, (v * max).roundToInt(), 0)
                    result.success(true)
                }
                "watchVolume" -> {
                    setVolumeWatch(call.argument<Boolean>("on") ?: false)
                    result.success(true)
                }
                "watchNoisy" -> {
                    setNoisyWatch(call.argument<Boolean>("on") ?: false)
                    result.success(true)
                }
                "setVideoBoost" -> {
                    val playerId = (call.argument<Number>("playerId") ?: -1).toLong()
                    val percent = (call.argument<Number>("percent") ?: 100).toInt().coerceIn(100, 200)
                    result.success(setVideoBoost(playerId, percent))
                }
                "releaseVideoBoost" -> {
                    releaseBoost()
                    result.success(true)
                }
                "getMusicEqParams" -> {
                    val sessionId = (call.argument<Number>("sessionId") ?: 0).toInt()
                    result.success(getMusicEqParams(sessionId))
                }
                "applyMusicEq" -> {
                    val sessionId = (call.argument<Number>("sessionId") ?: 0).toInt()
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val gains = (call.argument<List<*>>("gains"))?.mapNotNull { (it as? Number)?.toDouble() }
                    val loudnessDb = (call.argument<Number>("loudnessDb") ?: 0.0).toDouble()
                    result.success(applyMusicEq(sessionId, enabled, gains, loudnessDb))
                }
                "getBrightness" -> {
                    val window = activity?.window?.attributes?.screenBrightness ?: -1f
                    if (window >= 0f) {
                        result.success(window.toDouble())
                    } else {
                        val system = Settings.System.getInt(
                            appContext.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128
                        )
                        result.success((system / 255.0).coerceIn(0.05, 1.0))
                    }
                }
                "setBrightness" -> {
                    val v = (call.argument<Double>("value") ?: 0.5).coerceIn(0.02, 1.0)
                    val a = activity
                    if (a == null) {
                        result.success(false)
                        return
                    }
                    a.runOnUiThread {
                        val lp = a.window.attributes
                        lp.screenBrightness = v.toFloat()
                        a.window.attributes = lp
                    }
                    result.success(true)
                }
                "isPipSupported" -> result.success(pipSupported())
                "setPipEligible" -> {
                    pipEligible = call.argument<Boolean>("eligible") ?: false
                    pipActionsPlaying = call.argument<Boolean>("actionsPlaying")
                    val w = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
                    val h = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
                    // The system only accepts ratios between 1:2.39 and 2.39:1.
                    val ratio = w.toDouble() / h.toDouble()
                    pipAspect = when {
                        ratio > 2.39 -> Rational(239, 100)
                        ratio < 0.42 -> Rational(42, 100)
                        else -> Rational(w, h)
                    }
                    applyPipParams()
                    result.success(true)
                }
                "enterPip" -> result.success(enterPip())
                "setSecure" -> {
                    secureWanted = call.argument<Boolean>("on") ?: false
                    applySecure()
                    result.success(true)
                }
                "uiCoverCheck" -> {
                    val a = activity
                    if (a == null) {
                        result.success(null)
                    } else {
                        a.runOnUiThread { result.success(uiCoverCheck(a)) }
                    }
                }
                "resetBrightness" -> {
                    val a = activity
                    if (a != null) {
                        a.runOnUiThread {
                            val lp = a.window.attributes
                            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            a.window.attributes = lp
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("DEVICE_CONTROL_FAILED", e.localizedMessage, null)
        }
    }
}
