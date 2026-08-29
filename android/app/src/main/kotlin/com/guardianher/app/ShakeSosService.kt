package com.guardianher.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import kotlin.math.sqrt

/**
 * Deliberate-shake SOS detector (Phase 3E).
 *
 * A foreground service that keeps listening to the accelerometer even while
 * the app is closed. When the user deliberately shakes the phone (three quick
 * shakes within the window), it launches the app with a `guardianher://shakesos`
 * URI; the Flutter side routes to SOS and arms the workflow.
 *
 * A foreground service is the only way to keep reading motion with the app
 * closed (background processes and sensor listeners die with the activity).
 * This is a deliberate, user-opt-in exception to the V1 "no foreground
 * service" rule — it shows a persistent notification and reacts only to the
 * deliberate shake pattern, never to location or other sensors.
 *
 * Real-device tuning: tweak the constants below (THRESHOLD_G, REQUIRED_COUNT,
 * WINDOW_MS, MIN_GAP_MS) after testing on the target device.
 */
class ShakeSosService : Service(), SensorEventListener {

  companion object {
    private const val TAG = "ShakeSosService"
    private const val CHANNEL_ID = "shake_sos"
    private const val NOTIFICATION_ID = 3100

    /**
     * App-private prefs recording the user's Shake SOS choice so [BootReceiver]
     * can restore the detector after reboot / app update without spinning up
     * Flutter. Written only from MainActivity's channel handlers (real user
     * actions), never from internal re-anchors.
     */
    private const val PREFS_NAME = "guardianher_background"
    private const val PREF_USER_ENABLED = "shake_sos_user_enabled"

    // --- Deliberate-shake tuning (real-device) ---
    /** High-pass-filtered acceleration magnitude (in g) that counts as one shake. */
    private const val SHAKE_THRESHOLD_G = 2.2f
    /** Minimum gap between two shakes so one continuous burst isn't double-counted. */
    private const val SHAKE_MIN_GAP_MS = 150L
    /** How many shakes are needed within the window to count as deliberate. */
    private const val SHAKE_REQUIRED_COUNT = 3
    /** Rolling window in which the shakes must occur (ms). */
    private const val SHAKE_WINDOW_MS = 2000L
    /**
     * After triggering SOS, ignore further shakes for this long (ms).
     * Kept short so a user testing the feature can trigger again quickly,
     * but long enough that a phone shaking in a bag doesn't re-launch SOS
     * in a tight loop.
     */
    private const val TRIGGER_COOLDOWN_MS = 10_000L
    /** High-pass filter strength (1.0 = no filtering). */
    private const val LOW_PASS_ALPHA = 0.15f

    /** Foreground-service type value for `specialUse` (Android 14+). */
    private const val FGS_TYPE_SPECIAL_USE = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE

    /**
     * Repeating SOS alert timings (ms): three 400 ms bursts with 200 ms pauses,
     * then a 4 s quiet gap. The OS loops this with repeat index 0 until
     * cancelled, so it keeps alerting even with the app closed (the foreground
     * service keeps the process alive). Mirrors the Flutter-side pattern in
     * `vibration_service_impl.dart`.
     */
    private val SOS_ALERT_PATTERN_MS = longArrayOf(0, 400, 200, 400, 200, 400, 4000)

    @Volatile
    private var instance: ShakeSosService? = null

    fun start(context: Context) {
      val intent = Intent(context, ShakeSosService::class.java)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, ShakeSosService::class.java))
    }

    /**
     * Engages a repeating SOS alert loop on the running detector service.
     * Returns true only when the service is actually up (Shake SOS enabled);
     * otherwise the Flutter side keeps vibrating on its own.
     */
    fun startSosAlert(context: Context): Boolean {
      val service = instance ?: return false
      service.startSosAlertLoop()
      return true
    }

    /** Stops the repeating SOS alert loop, if any. Idempotent. */
    fun stopSosAlert(context: Context) {
      instance?.stopSosAlertLoop()
    }

    /** Records whether the user wants the detector running (Phase 3F). */
    fun setUserEnabled(context: Context, enabled: Boolean) {
      context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
          .edit()
          .putBoolean(PREF_USER_ENABLED, enabled)
          .apply()
      Log.d(TAG, "user-enabled flag set to $enabled")
    }

    /** Whether the user has Shake SOS enabled (drives [BootReceiver]). */
    fun isUserEnabled(context: Context): Boolean {
      return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
          .getBoolean(PREF_USER_ENABLED, false)
    }
  }

  private lateinit var sensorManager: SensorManager
  private var accelerometer: Sensor? = null
  private val lowPass = FloatArray(3)
  private var lastShakeAt = 0L
  private val shakeTimes = ArrayDeque<Long>()
  private var lastTriggerAt = 0L

  private val sosAlertVibrator: Vibrator by lazy {
    getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
  }
  private var alertLoopRunning = false

  override fun onCreate() {
    super.onCreate()
    Log.d(TAG, "service created")
    createChannel()
    sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
    accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    instance = this
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.d(TAG, "onStartCommand startId=$startId")
    startForegroundCompat()
    accelerometer?.let {
      sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
    } ?: Log.e(TAG, "no accelerometer found; shake detection disabled")
    return START_STICKY
  }

  override fun onSensorChanged(event: SensorEvent) {
    if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
    val now = SystemClock.uptimeMillis()

    val x = event.values[0]
    val y = event.values[1]
    val z = event.values[2]

    // High-pass filter: remove gravity and slow motion so only sharp movement
    // (a deliberate shake) exceeds the threshold.
    lowPass[0] += LOW_PASS_ALPHA * (x - lowPass[0])
    lowPass[1] += LOW_PASS_ALPHA * (y - lowPass[1])
    lowPass[2] += LOW_PASS_ALPHA * (z - lowPass[2])
    val highX = x - lowPass[0]
    val highY = y - lowPass[1]
    val highZ = z - lowPass[2]
    val magnitude = sqrt(highX * highX + highY * highY + highZ * highZ)

    if (magnitude > SHAKE_THRESHOLD_G * SensorManager.GRAVITY_EARTH &&
        now - lastShakeAt >= SHAKE_MIN_GAP_MS) {
      lastShakeAt = now
      shakeTimes.addLast(now)
      Log.d(TAG, "shake detected (mag=${"%.1f".format(magnitude / SensorManager.GRAVITY_EARTH)}g), "
          + "count=${shakeTimes.size}")
    }

    while (shakeTimes.isNotEmpty() && now - shakeTimes.firstOrNull()!! > SHAKE_WINDOW_MS) {
      shakeTimes.removeFirstOrNull()
    }

    if (shakeTimes.size >= SHAKE_REQUIRED_COUNT) {
      val elapsedSinceTrigger = now - lastTriggerAt
      if (elapsedSinceTrigger >= TRIGGER_COOLDOWN_MS) {
        lastTriggerAt = now
        shakeTimes.clear()
        Log.d(TAG, "deliberate shake pattern -> launching SOS")
        triggerSos()
      } else {
        Log.d(TAG, "shake pattern suppressed by cooldown (${elapsedSinceTrigger}ms / "
            + "$TRIGGER_COOLDOWN_MS ms)")
      }
    }
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

  private fun triggerSos() {
    // Engage the SOS alert loop natively right away. The OS-level repeating
    // vibration starts alerting immediately even if the activity launch below
    // is blocked (fully closed app without the display-over-apps exemption),
    // and it keeps looping until the user stops SOS — the Dart side merely
    // confirms it later via startSosAlert() once the app is up.
    startSosAlertLoop()

    // Best-effort: bring the location foreground service up before launching the
    // activity, so a cold-start capture can run with the screen locked/off. This
    // may be refused while the app is still fully backgrounded (Android 12+);
    // the Dart side starts it again once the activity resumes.
    try {
      SosLocationService.start(this)
    } catch (error: Exception) {
      Log.w(TAG, "could not pre-start SOS location service: $error")
    }
    val intent =
        Intent(this, MainActivity::class.java).apply {
          action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
          data = Uri.parse("guardianher://shakesos")
          flags =
              Intent.FLAG_ACTIVITY_NEW_TASK or
                  Intent.FLAG_ACTIVITY_CLEAR_TOP or
                  Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
    startActivity(intent)
  }

  private fun startForegroundCompat() {
    val notification = buildNotification()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, FGS_TYPE_SPECIAL_USE)
    } else {
      startForeground(NOTIFICATION_ID, notification)
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
        .setContentTitle("GuardianHer is watching")
        .setContentText("Shake your phone three times to trigger SOS.")
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
                "Shake SOS",
                NotificationManager.IMPORTANCE_LOW,
            )
            .apply {
              description = "Watching for a deliberate shake to trigger SOS"
              setShowBadge(false)
            }
    manager.createNotificationChannel(channel)
  }

  /** Starts the repeating SOS alert bursts (no-op if already running). */
  fun startSosAlertLoop() {
    if (alertLoopRunning) return
    alertLoopRunning = true
    vibrateSosPattern()
    Log.d(TAG, "SOS alert loop started")
  }

  /** Stops the repeating SOS alert bursts and any in-flight vibration. */
  fun stopSosAlertLoop() {
    if (!alertLoopRunning) return
    alertLoopRunning = false
    sosAlertVibrator.cancel()
    Log.d(TAG, "SOS alert loop stopped")
  }

  private fun vibrateSosPattern() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      sosAlertVibrator.vibrate(
          VibrationEffect.createWaveform(SOS_ALERT_PATTERN_MS, /* repeat = */ 0))
    } else {
      @Suppress("DEPRECATION") sosAlertVibrator.vibrate(SOS_ALERT_PATTERN_MS, 0)
    }
  }

  override fun onDestroy() {
    Log.d(TAG, "service destroyed")
    stopSosAlertLoop()
    sensorManager.unregisterListener(this)
    instance = null
    super.onDestroy()
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
    // The app was swiped away from recents. Do NOT stop the detector — the
    // whole point of the feature is that it works while the app is closed.
    // Re-anchor the service in case the launcher tore down the process.
    Log.d(TAG, "task removed; keeping shake detection alive")
    ShakeSosService.start(this)
  }

  override fun onBind(intent: Intent?): IBinder? = null
}