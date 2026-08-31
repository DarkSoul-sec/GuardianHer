package com.guardianher.app.live_sharing;

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.guardianher.app.FixFreshness
import com.guardianher.app.LocationEngine
import kotlinx.coroutines.*

/**
 * Foreground service that sends live location updates via SMS to emergency contacts.
 *
 * Uses the shared [LocationEngine] for all location operations — no duplicate
 * LocationManager listeners. Applies the single authoritative freshness policy
 * so SMS is only sent for LIVE or STALE fixes (never UNAVAILABLE).
 *
 * Lifecycle:
 * - START: registers with LocationEngine, starts foreground service, begins periodic SMS
 * - STOP: unregisters from LocationEngine, cancels periodic job, stops foreground service
 * - FORCE_UPDATE: requests immediate fix from LocationEngine
 *
 * Invariants:
 * - Exactly one LocationEngine registration per service instance.
 * - SMS only sent when fix freshness is LIVE or STALE (with label).
 * - Permission/location-services changes handled via LocationEngine callbacks.
 * - No coordinates, phone numbers, or SMS bodies logged.
 */
class LiveSharingService : Service(), LocationEngine.ServiceCallback {

    companion object {
        private const val TAG = "LiveSharingService"
        private const val CHANNEL_ID = "live_sharing"
        private const val NOTIFICATION_ID = 4400

        // Intent extras
        const val EXTRA_CONTACTS_JSON = "contacts_json"
        const val EXTRA_INTERVAL_SECONDS = "interval_seconds"
        const val ACTION_START = "START_LIVE_SHARING"
        const val ACTION_STOP = "STOP_LIVE_SHARING"
        const val ACTION_UPDATE = "FORCE_UPDATE"

        // Default update interval
        private const val DEFAULT_INTERVAL_MS = 30_000L // 30 seconds

        // Minimum interval between SMS sends (carrier throttle protection)
        private const val MIN_SMS_INTERVAL_MS = 1_000L
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var engine: LocationEngine
    private var contacts = mutableListOf<String>()
    private var intervalMs = DEFAULT_INTERVAL_MS
    private var updateCount = 0
    private var lastSmsSentMs = 0L
    private var updateJob: Job? = null
    private var hasSentFirstFix = false
    private var locationServicesEnabled = true
    private var locationPermissionGranted = false

    override fun onCreate() {
        super.onCreate()
        engine = LocationEngine(this)
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        when (intent.action) {
            ACTION_START -> {
                val contactsJson = intent.getStringExtra(EXTRA_CONTACTS_JSON) ?: "[]"
                val interval = intent.getIntExtra(EXTRA_INTERVAL_SECONDS, 30) * 1000L

                contacts = parseContacts(contactsJson)
                intervalMs = interval.coerceIn(10_000L, 300_000L) // 10s..5min bounds

                if (contacts.isEmpty()) {
                    Log.w(TAG, "No contacts provided, stopping")
                    stopSelf()
                    return START_NOT_STICKY
                }

                // Verify SMS permission
                val smsPerm = checkSelfPermission(android.Manifest.permission.SEND_SMS)
                if (smsPerm != PackageManager.PERMISSION_GRANTED) {
                    Log.e(TAG, "SEND_SMS permission NOT granted - cannot send SMS")
                    val notification = buildNotification("SMS permission denied - cannot share location")
                    startForegroundCompat(notification)
                    stopSelf()
                    return START_NOT_STICKY
                }

                // Verify location permission
                locationPermissionGranted = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    || checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                if (!locationPermissionGranted) {
                    Log.e(TAG, "Location permission NOT granted - cannot start live updates")
                    val notification = buildNotification("Location permission denied - cannot share location")
                    startForegroundCompat(notification)
                    stopSelf()
                    return START_NOT_STICKY
                }

                Log.d(TAG, "Starting live sharing to ${contacts.size} contacts every ${intervalMs}ms")
                startForegroundCompat(buildNotification("Starting live sharing…"))

                // Register with shared LocationEngine
                engine.registerServiceCallback(this)

                // Immediately try to send a fresh fix if available
                val cached = engine.getFreshestFixForRelay()
                cached?.let { fix ->
                    if (engine.classifyFreshness(fix["ageMs"] as Long) != FixFreshness.UNAVAILABLE) {
                        sendLocationUpdateFromFix(fix)
                    }
                }

                startPeriodicUpdates()
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping live sharing")
                engine.unregisterServiceCallback(this)
                updateJob?.cancel()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_UPDATE -> {
                // Force update: request immediate fix from engine
                engine.requestForceUpdate()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "Service destroyed - updates sent: $updateCount")
        engine.unregisterServiceCallback(this)
        updateJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─── LocationEngine.ServiceCallback ────────────────────────────────

    override fun onLiveFix(fixMap: Map<String, Any>) {
        // Called by LocationEngine on every live fix from GPS/NETWORK
        // Apply freshness policy before sending SMS
        val freshness = FixFreshness.valueOf(fixMap["freshness"] as String)
        when (freshness) {
            FixFreshness.LIVE,
            FixFreshness.STALE -> {
                // Valid for SMS relay
                sendLocationUpdateFromFix(fixMap)
            }
            FixFreshness.UNAVAILABLE -> {
                Log.d(TAG, "Received UNAVAILABLE fix (ageMs=${fixMap["ageMs"]}), not sending SMS")
            }
        }
    }

    override fun onServicesChanged(enabled: Boolean) {
        locationServicesEnabled = enabled
        if (!enabled) {
            Log.w(TAG, "Location services disabled - stopping periodic updates")
            updateNotification("Location services disabled - sharing paused")
            updateJob?.cancel()
        } else {
            val jobActive = updateJob?.isActive == true
            if (!jobActive) {
                Log.d(TAG, "Location services re-enabled - resuming periodic updates")
                startPeriodicUpdates()
            }
        }
    }

    // ─── Periodic SMS ────────────────────────────────────────────────

    private fun startPeriodicUpdates() {
        updateJob?.cancel()
        updateJob = scope.launch {
            while (isActive) {
                delay(intervalMs)
                if (!isActive) break
                if (!locationServicesEnabled || !locationPermissionGranted) continue

                // Check SMS permission at each tick (can be revoked at runtime)
                if (checkSelfPermission(android.Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                    Log.w(TAG, "SMS permission revoked at runtime")
                    updateNotification("SMS permission revoked - sharing paused")
                    continue
                }

                // Request a fresh fix from the engine
                engine.requestForceUpdate()
            }
        }
    }

    private fun sendLocationUpdateFromFix(fix: Map<String, Any>) {
        val freshness = FixFreshness.valueOf(fix["freshness"] as String)
        val accuracy = (fix["accuracyMeters"] as Double).toInt()
        val provider = fix["provider"] as String

        updateCount++
        val message = buildMessage(fix, freshness, accuracy, updateCount)

        val freshnessLabel = when (freshness) {
            FixFreshness.LIVE -> "LIVE"
            FixFreshness.STALE -> "STALE"
            else -> "UNAVAILABLE"
        }
        Log.d(TAG, "Live update #$updateCount [$freshnessLabel] queued for ${contacts.size} contacts (provider: $provider, accuracy: ${accuracy}m)")
        updateNotification("Update #$updateCount [$freshnessLabel] queued for ${contacts.size} contacts")

        // Send SMS in a coroutine since sendSmsToAll is suspend
        scope.launch { sendSmsToAll(message) }
    }

    private fun buildMessage(fix: Map<String, Any>, freshness: FixFreshness, accuracy: Int, count: Int): String {
        val latitude = fix["latitude"] as Double
        val longitude = fix["longitude"] as Double
        val mapLink = "https://maps.google.com/?q=$latitude,$longitude"
        val now = java.util.Date()
        val hh = android.text.format.DateFormat.format("HH", now)
        val mm = android.text.format.DateFormat.format("mm", now)

        val freshnessLabel = when (freshness) {
            FixFreshness.LIVE -> "LIVE"
            FixFreshness.STALE -> "STALE (last known)"
            else -> "UNAVAILABLE"
        }

        return StringBuilder()
            .append("🚨 GuardianHer $freshnessLabel #$count\n")
            .append("📍 $mapLink\n")
            .append("±${accuracy}m | $hh:$mm")
            .toString()
    }

    private suspend fun sendSmsToAll(message: String): Int {
        var sent = 0
        for (number in contacts) {
            // Throttle SMS sends to avoid carrier limits
            val now = System.currentTimeMillis()
            val sinceLast = now - lastSmsSentMs
            if (sinceLast < MIN_SMS_INTERVAL_MS) {
                delay(MIN_SMS_INTERVAL_MS - sinceLast)
            }

            try {
                val smsManager = android.telephony.SmsManager.getDefault()
                val destination = if (number.startsWith("+")) number else "+$number"
                smsManager.sendTextMessage(destination, null, message, null, null)
                sent++
                lastSmsSentMs = System.currentTimeMillis()
            } catch (e: Exception) {
                Log.w(TAG, "SMS failed for $number: ${e.message}")
            }
        }
        return sent
    }

    // ─── Foreground Notification ────────────────────────────────────

    private fun startForegroundCompat(initialNotification: Notification? = null) {
        val notification = initialNotification ?: buildNotification("Live sharing active")
        try {
            // Use LOCATION type only — dataSync has 6-hour limit on Android 14+
            // LOCATION type is the documented alternative to ACCESS_BACKGROUND_LOCATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "Foreground service started successfully (type=location)")
        } catch (e: SecurityException) {
            // Android 14+ refuses location FGS without runtime permission
            Log.w(TAG, "Cannot start location FGS (permission missing): $e")
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}")
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, com.guardianher.app.MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }.apply {
            setContentTitle("Live Location Sharing (SMS)")
            setContentText(text)
            setSmallIcon(android.R.drawable.ic_dialog_map)
            setContentIntent(pendingIntent)
            setOngoing(true)
            setPriority(Notification.PRIORITY_HIGH)
            setCategory(Notification.CATEGORY_SERVICE)
        }.build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = buildNotification(text)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Live Location Sharing (SMS)",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Shows while live location is being shared via SMS to emergency contacts"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private fun parseContacts(json: String): MutableList<String> {
        val result = mutableListOf<String>()
        val trimmed = json.trim()
        if (!trimmed.startsWith("[")) return result

        val content = trimmed.removeSurrounding("[", "]")
        if (content.isBlank()) return result

        content.split(",\\s*").forEach { item ->
            val clean = item.trim().removeSurrounding("\"", "\"")
            if (clean.isNotBlank()) result.add(clean)
        }
        return result
    }
}