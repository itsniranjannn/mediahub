package com.example.mediahub

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

/**
 * Volume, screen brightness and picture-in-picture for the video player.
 * Brightness only changes this app's window (it never touches the system setting).
 *
 * The channel lives as long as the Flutter engine; the Activity it acts on is attached
 * and detached as Activities come and go (see MainActivity.EngineChannels).
 */
class DeviceControlsChannel(
    context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "mediahub/device_controls")
    private val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var activityRef: WeakReference<Activity>? = null
    private val activity: Activity? get() = activityRef?.get()

    // --- picture in picture -------------------------------------------------
    private var pipEligible = false
    private var pipAspect = Rational(16, 9)

    init {
        channel.setMethodCallHandler(this)
    }

    fun attach(activity: Activity) {
        activityRef = WeakReference(activity)
        // A re-created Activity must learn the current PiP setup again (Android 12+ auto-enter).
        applyPipParams()
    }

    fun detach(activity: Activity) {
        if (this.activity === activity) activityRef = null
    }

    fun cleanup() {
        channel.setMethodCallHandler(null)
        activityRef = null
    }

    private fun pipSupported(): Boolean {
        val a = activity ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            a.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: the system enters picture-in-picture by itself when the user leaves.
            builder.setAutoEnterEnabled(pipEligible)
        }
        return builder.build()
    }

    private fun applyPipParams() {
        val a = activity ?: return
        if (pipSupported() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                a.setPictureInPictureParams(pipParams())
            } catch (e: IllegalStateException) {
                // Activity not in a state that accepts PiP params; the next call will retry.
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
        }
    }

    /** Called from MainActivity.onUserLeaveHint (Android 8-11 need us to enter PiP ourselves). */
    fun onUserLeaveHint() {
        if (pipEligible && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    fun notifyPipChanged(inPip: Boolean) {
        channel.invokeMethod("pipChanged", inPip)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getVolume" -> {
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val cur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(if (max > 0) cur.toDouble() / max else 0.0)
                }
                "setVolume" -> {
                    val v = (call.argument<Double>("value") ?: 0.0).coerceIn(0.0, 1.0)
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, (v * max).roundToInt(), 0)
                    result.success(true)
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
