package com.example.mediahub

import android.content.res.Configuration
import androidx.lifecycle.Lifecycle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.mediahub.personal.ExtractorChannel
import java.lang.ref.WeakReference

class MainActivity : AudioServiceActivity() {

    /**
     * audio_service keeps one Flutter engine alive for the whole process, longer than any
     * single Activity (e.g. Back on Android 8-12 finishes the Activity while music and
     * downloads keep running). The platform channels therefore belong to the ENGINE: they
     * are created once per engine and are never torn down when an Activity is destroyed,
     * so a running yt-dlp download or the download notification's "Pause all" keep working.
     * Only the device-controls channel needs an Activity (brightness, picture-in-picture);
     * it is re-attached to whichever Activity is currently showing the engine.
     */
    private object EngineChannels {
        var engine: WeakReference<FlutterEngine>? = null
        var mediaStore: MediaStoreChannel? = null
        var downloadService: DownloadServiceChannel? = null
        var extractor: ExtractorChannel? = null
        var deviceControls: DeviceControlsChannel? = null

        fun bind(activity: MainActivity, flutterEngine: FlutterEngine) {
            if (engine?.get() !== flutterEngine) {
                // First launch, or the previous engine was destroyed: drop the old channels.
                release()
                val app = activity.applicationContext
                val messenger = flutterEngine.dartExecutor.binaryMessenger
                mediaStore = MediaStoreChannel(app, messenger)
                downloadService = DownloadServiceChannel(app, messenger)
                deviceControls = DeviceControlsChannel(app, messenger)
                if (ExtractorChannel.PERSONAL_TOOLS) extractor = ExtractorChannel(app, messenger)
                engine = WeakReference(flutterEngine)
            }
            deviceControls?.attach(activity)
        }

        private fun release() {
            runCatching { mediaStore?.cleanup() }
            runCatching { downloadService?.cleanup() }
            runCatching { extractor?.cleanup() }
            runCatching { deviceControls?.cleanup() }
            mediaStore = null
            downloadService = null
            extractor = null
            deviceControls = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EngineChannels.bind(this, flutterEngine)
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

    override fun onDestroy() {
        // Only the Activity reference is released; the engine (and its channels) live on.
        EngineChannels.deviceControls?.detach(this)
        super.onDestroy()
    }
}
