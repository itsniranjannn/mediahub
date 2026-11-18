package com.example.mediahub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class DownloadService : Service() {

    companion object {
        const val CHANNEL_ID = "downloads"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.example.mediahub.action.START_DOWNLOAD_SERVICE"
        const val ACTION_UPDATE = "com.example.mediahub.action.UPDATE_DOWNLOAD_SERVICE"
        const val ACTION_STOP = "com.example.mediahub.action.STOP_DOWNLOAD_SERVICE"
        const val ACTION_PAUSE_ALL = "com.example.mediahub.action.PAUSE_ALL"

        const val EXTRA_COUNT = "extra_count"
        const val EXTRA_PERCENT = "extra_percent"
        const val EXTRA_FILE_NAME = "extra_file_name"

        // Callback handler invoked when notification action buttons are pressed, timeout occurs, or wake lock changes
        var eventListener: ((String) -> Unit)? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var lastNotificationUpdateTime: Long = 0L

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE_ALL -> {
                eventListener?.invoke("pauseAll")
            }
            ACTION_STOP -> {
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_UPDATE -> {
                val count = intent.getIntExtra(EXTRA_COUNT, 0)
                val percent = intent.getIntExtra(EXTRA_PERCENT, -1)
                val fileName = intent.getStringExtra(EXTRA_FILE_NAME)
                acquireOrRefreshWakeLock()
                updateNotificationThrottled(count, percent, fileName)
            }
            ACTION_START -> {
                val count = intent.getIntExtra(EXTRA_COUNT, 1)
                val percent = intent.getIntExtra(EXTRA_PERCENT, -1)
                val fileName = intent.getStringExtra(EXTRA_FILE_NAME)
                acquireOrRefreshWakeLock()
                val notification = buildNotification(count, percent, fileName)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceCompat.startForeground(
                        this,
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Downloads"
            val descriptionText = "MediaHub active download progress"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun updateNotificationThrottled(count: Int, percent: Int, fileName: String?) {
        val now = System.currentTimeMillis()
        // Strict 1-second throttle for EVERY value (including -1, 0, and 100)
        if (now - lastNotificationUpdateTime >= 1000L) {
            lastNotificationUpdateTime = now
            val notification = buildNotification(count, percent, fileName)
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(count: Int, percent: Int, fileName: String?): Notification {
        // Content intent: open the Downloads tab. An explicit app-internal action (the
        // Activity ignores "route" extras, which any app could send).
        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_DOWNLOADS
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // Action: Pause all (Cancel all removed for safety against pocket taps)
        val pauseIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_PAUSE_ALL
        }
        val pausePendingIntent = PendingIntent.getService(
            this,
            1,
            pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // Text representation: "N downloading - P%" or sanitised filename
        val text = if (!fileName.isNullOrBlank() && count == 1) {
            if (percent in 0..100) "$fileName - $percent%" else "$fileName - Downloading"
        } else {
            if (percent in 0..100) "$count downloading - $percent%" else "$count downloading"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MediaHub downloads")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .addAction(0, "Pause all", pausePendingIntent)

        if (percent in 0..100) {
            builder.setProgress(100, percent, false)
        } else {
            builder.setProgress(100, 0, true)
        }

        return builder.build()
    }

    private fun acquireOrRefreshWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MediaHub:DownloadWakeLock").apply {
                setReferenceCounted(false)
            }
        }
        wakeLock?.let {
            if (!it.isHeld) {
                // 10 minute timeout
                it.acquire(10 * 60 * 1000L)
                eventListener?.invoke("wake_lock_acquired")
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                try {
                    it.release()
                    eventListener?.invoke("wake_lock_released")
                } catch (e: Exception) {}
            }
        }
        wakeLock = null
    }

    /**
     * Android 15 (API 35+) Timeout handler for dataSync foreground service type.
     * Sends "timeout" event to Dart to pause all active downloads and stops the foreground service cleanly.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        eventListener?.invoke("timeout")
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
