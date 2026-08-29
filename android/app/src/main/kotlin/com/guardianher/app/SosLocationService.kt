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
 * Holds the foreground location context for an active SOS session.
 *
 * Android 10+ blocks location access while the screen is off, the device is
 * locked, or the app is backgrounded — unless the app either holds
 * `ACCESS_BACKGROUND_LOCATION` or runs a foreground service with the `location`
 * foreground-service type. GuardianHer deliberately does NOT request the
 * background-location permission (nothing tracks the user continuously); this
 * service is the documented alternative: it is started only for the duration of
 * an SOS session and lets the existing one-shot Flutter location capture run
 * even when the SOS was triggered by a shake with the phone locked/screen-off.
 *
 * The service does NOT obtain a fix itself — the Flutter capture flow
 * (LocationManagerLocationService over the guardianher/location_engine
 * channel) does.
 * It only keeps the app in the location foreground, then is stopped when the
 * session ends (`guardianher/sos_location` channel `stop`).
 */
class SosLocationService : Service() {

  companion object {
    private const val TAG = "SosLocationService"
    private const val CHANNEL_ID = "sos_location"
    private const val NOTIFICATION_ID = 3200

    /** Foreground-service type for location access (Android 10+). */
    private const val FGS_TYPE_LOCATION = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION

    fun start(context: Context) {
      val intent = Intent(context, SosLocationService::class.java)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, SosLocationService::class.java))
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
    // Not sticky: if the OS recycles the process the location context ends with
    // the session; the Flutter side re-starts it on a fresh SOS activation.
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
      // Android 14+ refuses a location FGS without the location runtime
      // permission. Location is best-effort for SOS: swallow it and let the
      // Flutter capture surface the truthful "location unavailable" state.
      Log.w(TAG, "cannot start location FGS (location permission missing): $error")
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
        .setContentTitle("SOS location active")
        .setContentText("Getting your location for the SOS session.")
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
                "SOS location",
                NotificationManager.IMPORTANCE_LOW,
            )
            .apply {
              description = "Keeps the app able to capture location during an SOS session"
              setShowBadge(false)
            }
    manager.createNotificationChannel(channel)
  }
}
