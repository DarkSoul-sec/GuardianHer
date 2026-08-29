package com.guardianher.app

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
import android.util.Log

/**
 * Holds the foreground location context for an ACTIVE LIVE-LOCATION sharing
 * session (Phase 3J §6).
 *
 * Deliberately a separate, minimal service rather than a generalization of
 * [SosLocationService]: that class sits on the safety-critical SOS path and
 * must not be perturbed; both services are thin (~100 lines), and Android
 * happily runs two location-type foreground services concurrently (SOS +
 * live share can legitimately be active at once).
 *
 * Same contract as the SOS service:
 *  - `location` foreground-service type — the documented alternative to
 *    ACCESS_BACKGROUND_LOCATION, which GuardianHer does NOT request.
 *  - The service obtains NO fix itself; the Flutter live flow registers
 *    continuous engine updates (`guardianher/location_engine`
 *    startLiveUpdates) while this service keeps the app in the location
 *    foreground across screen-off/lock.
 *  - START_NOT_STICKY: if the OS kills the process, tracking ends with it.
 *    There is deliberately NO boot restore for live sessions — a session
 *    cannot silently resume after process death or reboot (§23).
 */
class LiveLocationService : Service() {

  companion object {
    private const val TAG = "LiveLocationService"
    private const val CHANNEL_ID = "live_location"
    private const val NOTIFICATION_ID = 3400

    /** Foreground-service type for location access (Android 10+). */
    private const val FGS_TYPE_LOCATION = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION

    fun start(context: Context) {
      val intent = Intent(context, LiveLocationService::class.java)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, LiveLocationService::class.java))
    }
  }

  override fun onCreate() {
    super.onCreate()
    Log.d(TAG, "service created")
    createChannel()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.d(TAG, "onStartCommand startId=$startId")
    startForegroundCompat()
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    Log.d(TAG, "service destroyed")
    super.onDestroy()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  private fun startForegroundCompat() {
    try {
      val notification = buildNotification()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(NOTIFICATION_ID, notification, FGS_TYPE_LOCATION)
      } else {
        startForeground(NOTIFICATION_ID, notification)
      }
    } catch (error: SecurityException) {
      // Android 14+ refuses a location FGS without the runtime permission;
      // without it live sharing cannot continue in the background. Surface a
      // stopped state on the Dart side instead of crashing.
      Log.w(TAG, "cannot start location FGS (permission missing): $error")
      stopSelf()
    }
  }

  private fun buildNotification(): Notification {
    val openIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    val builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          Notification.Builder(this, CHANNEL_ID)
        } else {
          @Suppress("DEPRECATION") Notification.Builder(this)
        }
    return builder
        .setContentTitle("Sharing live location")
        .setContentText("GuardianHer is sharing your live location.")
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentIntent(openIntent)
        .setOngoing(true)
        .build()
  }

  private fun createChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val channel =
        NotificationChannel(
                CHANNEL_ID,
                "Live location",
                NotificationManager.IMPORTANCE_LOW,
            )
            .apply {
              description = "Shown while GuardianHer shares your live location"
              setShowBadge(false)
            }
    manager.createNotificationChannel(channel)
  }
}
