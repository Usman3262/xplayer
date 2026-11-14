package com.player.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Foreground "media playback" service while a video plays (client 23 Oct #7).
 * Without it Android (XOS on Infinix in particular) kept the player running
 * but silenced it when the app went to the background or the phone was
 * locked. Holds a partial wake lock and a Wi-Fi lock so a locked phone keeps
 * streaming. Started / stopped from Dart over app/device.
 */
class PlaybackService : Service() {
  private var wake: PowerManager.WakeLock? = null
  private var wifi: WifiManager.WifiLock? = null

  override fun onBind(intent: Intent?): IBinder? = null

  /** Launcher name (from app.config via the manifest label). */
  private fun appLabel(): String = applicationInfo.loadLabel(packageManager).toString()

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() } ?: appLabel()
    val notification = buildNotification(title)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }
    acquireLocks()
    return START_NOT_STICKY
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
    // App swiped away: stop (the player is gone with it).
    stopSelf()
    super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy() {
    releaseLocks()
    super.onDestroy()
  }

  private fun acquireLocks() {
    if (wake == null) {
      val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
      wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "app:playback").apply {
        setReferenceCounted(false)
        acquire(6 * 60 * 60 * 1000L)
      }
    }
    if (wifi == null) {
      val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
      @Suppress("DEPRECATION")
      val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        WifiManager.WIFI_MODE_FULL_LOW_LATENCY
      } else {
        WifiManager.WIFI_MODE_FULL_HIGH_PERF
      }
      wifi = wm.createWifiLock(mode, "app:playback").apply {
        setReferenceCounted(false)
        acquire()
      }
    }
  }

  private fun releaseLocks() {
    try { wake?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
    try { wifi?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
    wake = null
    wifi = null
  }

  private fun buildNotification(title: String): Notification {
    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      nm.createNotificationChannel(
        NotificationChannel(CHANNEL_ID, "Playback", NotificationManager.IMPORTANCE_LOW).apply {
          setShowBadge(false)
          setSound(null, null)
        },
      )
    }
    val open = PendingIntent.getActivity(
      this,
      0,
      Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(this, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(this)
    }
    return builder
      .setSmallIcon(R.drawable.ic_stat_notification)
      .setContentTitle(title)
      .setContentText("Playing on ${appLabel()}")
      .setContentIntent(open)
      .setOngoing(true)
      .setCategory(Notification.CATEGORY_TRANSPORT)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .build()
  }

  companion object {
    private const val CHANNEL_ID = "app_playback"
    private const val NOTIFICATION_ID = 4401
    const val EXTRA_TITLE = "title"

    fun start(context: Context, title: String?) {
      val i = Intent(context, PlaybackService::class.java).putExtra(EXTRA_TITLE, title ?: "")
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i) else context.startService(i)
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, PlaybackService::class.java))
    }
  }
}
