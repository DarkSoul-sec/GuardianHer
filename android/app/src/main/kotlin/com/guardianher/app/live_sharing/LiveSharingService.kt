package com.guardianher.app.live_sharing;

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.*
import kotlinx.coroutines.*

/**
 * Foreground service that sends live location updates via SMS every 30 seconds.
 * Survives app backgrounding and screen-off.
 * Uses FOREGROUND_SERVICE_TYPE_LOCATION + DATA_SYNC on Android 14+.
 */
class LiveSharingService : Service() {

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

        // Update interval
        private const val DEFAULT_INTERVAL_MS = 30_000L // 30 seconds
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var updateJob: Job? = null
    private var contacts = mutableListOf<String>()
    private var intervalMs = DEFAULT_INTERVAL_MS
    private var updateCount = 0

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        when (intent.action) {
            ACTION_START -> {
                val contactsJson = intent.getStringExtra(EXTRA_CONTACTS_JSON) ?: "[]"
                val interval = intent.getIntExtra(EXTRA_INTERVAL_SECONDS, 30) * 1000L

                contacts = parseContacts(contactsJson)
                intervalMs = interval

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
                    startForegroundCompat()
                    // Don't stop self - keep running to show notification
                    return START_NOT_STICKY
                }

                Log.d(TAG, "Starting live sharing to ${contacts.size} contacts: ${contacts.joinToString(", ")} every ${intervalMs}ms")
                startForegroundCompat()
                startLocationUpdates()
                startPeriodicUpdates()
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping live sharing")
                stopLocationUpdates()
                updateJob?.cancel()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_UPDATE -> {
                scope.launch { sendLocationUpdate() }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "Service destroyed - updates sent: $updateCount")
        stopLocationUpdates()
        updateJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─── Location ────────────────────────────────────────────────────────

    private fun startLocationUpdates() {
        val request = LocationRequest.create().apply {
            priority = LocationRequest.PRIORITY_HIGH_ACCURACY
            interval = intervalMs
            fastestInterval = max(intervalMs / 2, 5000L)
            smallestDisplacement = 10f // meters
        }

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let { location ->
                    scope.launch { sendLocationUpdate(location) }
                }
            }
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                fusedLocationClient?.requestLocationUpdates(request, locationCallback!!, Looper.getMainLooper())
            } else {
                @Suppress("DEPRECATION")
                fusedLocationClient?.requestLocationUpdates(request, locationCallback!!, Looper.getMainLooper())
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission missing: ${e.message}")
        }
    }

    private fun stopLocationUpdates() {
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
        }
        locationCallback = null
    }

    // ─── Periodic SMS ────────────────────────────────────────────────────

    private fun startPeriodicUpdates() {
        updateJob = scope.launch {
            while (isActive) {
                delay(intervalMs)
                if (isActive) sendLocationUpdate()
            }
        }
    }

    private suspend fun sendLocationUpdate(location: Location? = null) {
        val loc = location ?: getLastKnownLocationSync()
            ?: return

        updateCount++
        val message = buildMessage(loc)
        val sentCount = sendSmsToAll(message)

        Log.d(TAG, "Live update #$updateCount sent to $sentCount/${contacts.size} contacts")
        updateNotification(message)
    }

    private fun getLastKnownLocationSync(): Location? {
        return try {
            fusedLocationClient?.getLastLocation()?.await()
        } catch (e: Exception) {
            null
        }
    }

    private fun buildMessage(loc: Location): String {
        val mapLink = "https://maps.google.com/?q=${loc.latitude},${loc.longitude}"
        val accuracy = loc.accuracy.roundToInt()
        val now = java.util.Date()
        val hh = android.text.format.DateFormat.format("HH", now)
        val mm = android.text.format.DateFormat.format("mm", now)

        return StringBuilder()
            .append("🚨 GuardianHer LIVE #$updateCount\n")
            .append("📍 $mapLink\n")
            .append("±${accuracy}m | $hh:$mm")
            .toString()
    }

    private fun sendSmsToAll(message: String): Int {
        var sent = 0
        // Check SMS permission before sending
        if (checkSelfPermission(android.Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "SEND_SMS permission not granted")
            updateNotification("SMS permission denied")
            return 0
        }
        for (number in contacts) {
            try {
                val smsManager = android.telephony.SmsManager.getDefault()
                // Ensure E.164 format with + prefix
                val destination = if (number.startsWith("+")) number else "+$number"
                smsManager.sendTextMessage(destination, null, message, null, null)
                sent++
                delay(200) // throttle - use coroutine delay, not Thread.sleep
            } catch (e: Exception) {
                Log.w(TAG, "SMS failed for $number: ${e.message}")
            }
        }
        return sent
    }

    // ─── Foreground Notification ─────────────────────────────────────────

    private fun startForegroundCompat() {
        val notification = buildNotification("Starting live sharing…")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+: location + dataSync
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10-13: location type
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "Foreground service started successfully")
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
            setContentTitle("Live Location Sharing")
            setContentText(text)
            setSmallIcon(android.R.drawable.ic_dialog_map)
            setContentIntent(pendingIntent)
            setOngoing(true)
            setPriority(Notification.PRIORITY_HIGH)
            setCategory(Notification.CATEGORY_SERVICE)
        }.build()
    }

    private fun updateNotification(lastMessage: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = buildNotification("Update #$updateCount sent to ${contacts.size} contacts")
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Live Location Sharing",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Shows while live location is being shared via SMS"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private fun parseContacts(json: String): MutableList<String> {
        val result = mutableListOf<String>()
        val trimmed = json.trim()
        if (!trimmed.startsWith("[")) return result

        // Simple JSON array parsing: ["+91...", "+91..."]
        val content = trimmed.removeSurrounding("[", "]")
        if (content.isBlank()) return result

        content.split(",\\s*").forEach { item ->
            val clean = item.trim().removeSurrounding("\"", "\"")
            if (clean.isNotBlank()) result.add(clean)
        }
        return result
    }
}