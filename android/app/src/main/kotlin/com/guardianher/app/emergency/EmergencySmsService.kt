package com.guardianher.app.emergency

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
import android.util.Log
import com.guardianher.app.MainActivity
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Short-lived foreground service that sends emergency SMS to all guardians.
 *
 * CORE SAFETY FUNCTION: SEND_SMS exists solely for this service. Automatic
 * dispatch on a validly armed SOS (button/shake/tile/widget) to the user's
 * own selected emergency contacts is the app's primary purpose — it must
 * never be replaced with a manual composer or gated behind extra taps.
 *
 * Lifecycle:
 *   1. Flutter calls `startEmergency` via MethodChannel.
 *   2. MainActivity creates an Intent and calls [startForegroundService].
 *   3. Service starts as foreground, processes guardians concurrently.
 *   4. Each SMS gets a PendingIntent-backed SENT result.
 *   5. Failed SMS are retried once (after 5 s).
 *   6. When all guardians are resolved, the service stops itself.
 *   7. Results are pushed back to Flutter via MethodChannel.
 *
 * The service does NOT depend on MainActivity remaining alive. Once started,
 * it processes the full SMS workflow in its own foreground context.
 *
 * Uses FOREGROUND_SERVICE_TYPE_DATA_SYNC (Android 14+) for a 6-hour limit,
 * sufficient for the SMS burst with retries.
 *
 * Duplicate protection: the service tracks the current [sosEventId]. A second
 * start with the same id is silently ignored.
 */
/**
 * Callback interface for pushing results back to Flutter.
 * Set by MainActivity when the MethodChannel is available.
 */
interface FlutterCallback {
    fun onGuardianStatusChanged(guardianId: String, status: String, error: String?)
    fun onEmergencyComplete(sosEventId: String, sent: Int, failed: Int)
}

class EmergencySmsService : Service() {

    companion object {
        private const val TAG = "EmergencySmsService"
        private const val CHANNEL_ID = "emergency_sms"
        private const val NOTIFICATION_ID = 3300

        // Intent extras
        const val EXTRA_SOS_EVENT_ID = "sos_event_id"
        const val EXTRA_GUARDIANS_JSON = "guardians_json"
        const val EXTRA_SMS_BODY = "sms_body"
        const val EXTRA_LOCATION_URL = "location_url"
        const val EXTRA_BATTERY_PERCENTAGE = "battery_percentage"

        // Retry
        private const val RETRY_DELAY_MS = 5000L
        private const val MAX_ATTEMPTS = 2

        /** Singleton reference so the result receiver can push updates. */
        @Volatile
        private var currentInstance: EmergencySmsService? = null

        @Volatile
        var flutterCallback: FlutterCallback? = null
    }

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var smsManager: EmergencySmsManager
    private var wakeLock: PowerManager.WakeLock? = null

    // Per-guardian tracking
    private data class GuardianAttempt(
        val id: String,
        val name: String,
        val phoneNumber: String,
        var attempt: Int = 0,
        var completed: Boolean = false,
        var sent: Boolean = false,
    )

    private val guardians = ConcurrentHashMap<String, GuardianAttempt>()
    private var sosEventId = ""
    private var smsBody = ""
    private var totalSent = 0
    private var totalFailed = 0
    private var allResolved = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "[EmergencySMS] Service created")
        smsManager = EmergencySmsManager(this)
        currentInstance = this
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val eventId = intent?.getStringExtra(EXTRA_SOS_EVENT_ID)
        val body = intent?.getStringExtra(EXTRA_SMS_BODY)

        if (eventId == null || body == null) {
            Log.w(TAG, "[EmergencySMS] Missing required extras, stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        // Duplicate protection: ignore a second start only if the same
        // event is already in-flight AND all guardians haven't resolved yet.
        // After resolution (allResolved=true), a new start with the same id
        // is allowed — this handles the GPS-retry location-update SMS.
        if (eventId == sosEventId && !allResolved) {
            Log.d(TAG, "[EmergencySMS] Duplicate SOS event $eventId (in-flight) — ignoring")
            return START_NOT_STICKY
        }

        Log.d(TAG, "[EmergencySMS] SOS received: $eventId")
        sosEventId = eventId
        totalSent = 0
        totalFailed = 0
        allResolved = false
        guardians.clear()

        // Start foreground IMMEDIATELY (Android requirement).
        startForegroundCompat()

        // Acquire a partial wake lock so SMS processing survives screen-off.
        acquireWakeLock()

        // Parse guardians from JSON.
        val guardiansJson = intent.getStringExtra(EXTRA_GUARDIANS_JSON)
        if (guardiansJson.isNullOrBlank()) {
            Log.w(TAG, "[EmergencySMS] No guardians — completing")
            notifyComplete()
            stopSelf()
            return START_NOT_STICKY
        }

        val parsed = parseGuardians(guardiansJson)
        if (parsed.isEmpty()) {
            Log.w(TAG, "[EmergencySMS] Parsed 0 guardians — completing")
            notifyComplete()
            stopSelf()
            return START_NOT_STICKY
        }

        // Check prerequisites.
        if (!smsManager.hasSmsPermission()) {
            Log.w(TAG, "[EmergencySMS] SEND_SMS not granted")
            flutterCallback?.onGuardianStatusChanged("_system", "permission_denied", null)
            notifyComplete()
            stopSelf()
            return START_NOT_STICKY
        }

        if (!smsManager.hasUsableSim()) {
            Log.w(TAG, "[EmergencySMS] No usable SIM")
            flutterCallback?.onGuardianStatusChanged("_system", "no_sim", null)
            notifyComplete()
            stopSelf()
            return START_NOT_STICKY
        }

        Log.d(TAG, "[EmergencySMS] Guardian count: ${parsed.size}, SIM count: ${smsManager.activeSimCount()}, SIM ready: ${smsManager.isSimReady()}")

        // Build the final SMS body BEFORE launching coroutines to avoid race
        // condition where the coroutine reads a stale value.
        val locationUrl = intent.getStringExtra(EXTRA_LOCATION_URL)
        val finalBody = if (!locationUrl.isNullOrBlank() && !body.contains("maps.google.com")) {
            body.replace(
                "Please contact me immediately.",
                "Location: $locationUrl\n\nPlease contact me immediately.",
            )
        } else {
            body
        }
        smsBody = finalBody

        // Diagnostic: log SMS body length and first guardian's destination (masked)
        if (parsed.isNotEmpty()) {
            val firstDest = smsManager.formatDestination(parsed[0].phoneNumber)
            Log.d(TAG, "[EmergencySMS] SMS body length: ${smsBody.length}, first dest suffix: ${firstDest.takeLast(4)}")
        }

        // Start processing all guardians concurrently.
        for (g in parsed) {
            guardians[g.id] = GuardianAttempt(id = g.id, name = g.name, phoneNumber = g.phoneNumber)
            flutterCallback?.onGuardianStatusChanged(g.id, "sending", null)
        }

        serviceScope.launch {
            // Safety timeout: if guardians don't resolve within 3 minutes
            // (e.g., modem hangs, receiver never fires), force-complete.
            launch {
                delay(180_000L)
                if (!allResolved) {
                    Log.w(TAG, "[EmergencySMS] Safety timeout — force-completing")
                    onAllGuardiansResolved()
                }
            }
            val deferreds = guardians.values.map { guardian ->
                async { processGuardian(guardian) }
            }
            deferreds.awaitAll()
            if (!allResolved) {
                onAllGuardiansResolved()
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "[EmergencySMS] Service destroyed — sent=$totalSent failed=$totalFailed allResolved=$allResolved")
        // If the service was killed before all guardians resolved (e.g., OS
        // memory reclaim, SHORT_SERVICE timeout), notify Flutter so the
        // orchestrator doesn't stay stuck in _processing forever.
        if (!allResolved && sosEventId.isNotEmpty()) {
            notifyComplete()
        }
        currentInstance = null
        serviceScope.cancel()
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Guardian processing ─────────────────────────────────────────────

    private suspend fun processGuardian(guardian: GuardianAttempt) {
        val destination = smsManager.formatDestination(guardian.phoneNumber)

        if (!smsManager.isValidPhoneNumber(guardian.phoneNumber)) {
            Log.w(TAG, "[EmergencySMS] Invalid phone for ${maskId(guardian.id)}")
            guardians[guardian.id]?.completed = true
            flutterCallback?.onGuardianStatusChanged(guardian.id, "failed", "Invalid phone number")
            return
        }

        // Verify SIM is ready before each send attempt
        if (!smsManager.isSimReady()) {
            Log.w(TAG, "[EmergencySMS] SIM not ready for ${maskId(guardian.id)}")
            guardians[guardian.id]?.completed = true
            flutterCallback?.onGuardianStatusChanged(guardian.id, "failed", "SIM not ready")
            return
        }

        for (attempt in 0 until MAX_ATTEMPTS) {
            if (guardians[guardian.id]?.completed == true) break

            guardian.attempt = attempt + 1
            Log.d(TAG, "[EmergencySMS] SMS attempt ${attempt + 1}/$MAX_ATTEMPTS for ${maskId(guardian.id)}")

            val result = sendWithResult(guardian.id, destination, smsBody, attempt + 1)

            when (result) {
                is EmergencySmsResult.Sent -> {
                    Log.d(TAG, "[EmergencySMS] SMS sent for ${maskId(guardian.id)}")
                    guardians[guardian.id]?.completed = true
                    guardians[guardian.id]?.sent = true
                    flutterCallback?.onGuardianStatusChanged(guardian.id, "sent", null)
                    return
                }
                is EmergencySmsResult.Failed -> {
                    Log.w(TAG, "[EmergencySMS] SMS failed for ${maskId(guardian.id)}: ${result.description}")
                    // Only retry on transient failures
                    if (attempt < MAX_ATTEMPTS - 1 && isTransientFailure(result.description)) {
                        flutterCallback?.onGuardianStatusChanged(guardian.id, "retrying", result.description)
                        delay(RETRY_DELAY_MS)
                    } else {
                        guardians[guardian.id]?.completed = true
                        flutterCallback?.onGuardianStatusChanged(guardian.id, "failed", result.description)
                    }
                }
            }
        }
    }

    /**
     * Determines if a failure is transient and worth retrying.
     * GENERIC_FAILURE, NO_SERVICE, RADIO_OFF may be transient.
     * NULL_PDU, LIMIT_EXCEEDED, SHORT_CODE_NEVER_ALLOWED, SHORT_CODE_NOT_ALLOWED are permanent.
     */
    private fun isTransientFailure(description: String): Boolean {
        return when (description) {
            "GENERIC_FAILURE", "NO_SERVICE", "RADIO_OFF" -> true
            else -> false
        }
    }

    /**
     * Sends an SMS and waits for the SENT-result broadcast.
     *
     * Uses a [CompletableDeferred] that is resolved by the one-shot
     * [EmergencySmsResultReceiver] when the modem delivers the result.
     */
    private suspend fun sendWithResult(
        guardianId: String,
        destination: String,
        body: String,
        attempt: Int,
    ): EmergencySmsResult {
        val deferred = CompletableDeferred<EmergencySmsResult>()
        val parts = smsManager.divideMessage(body)
        var successfulParts = 0
        var completed = false

        // Register one receiver for every SENT result. Multipart SMS must not
        // report success until Android has accepted every encoded part.
        val receiver = EmergencySmsResultReceiver { id, _, result ->
            if (id != guardianId || completed) return@EmergencySmsResultReceiver
            when (result) {
                is EmergencySmsResult.Failed -> {
                    completed = true
                    deferred.complete(result)
                }
                is EmergencySmsResult.Sent -> {
                    successfulParts++
                    if (successfulParts == parts.size) {
                        completed = true
                        deferred.complete(result)
                    }
                }
            }
        }
        val filter = android.content.IntentFilter(EmergencySmsResultReceiver.ACTION_SMS_SENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }

        try {
            val sentIntents = parts.indices.map { partIndex ->
                EmergencySmsResultReceiver.createSentIntent(
                    this,
                    guardianId,
                    attempt,
                    partIndex,
                )
            }
            smsManager.sendSms(destination, body, sentIntents)

            // Wait for modem result (max 30 s).
            return withTimeoutOrNull(30_000L) {
                deferred.await()
            } ?: EmergencySmsResult.Failed(-1, "TIMEOUT")
        } catch (e: Exception) {
            Log.e(TAG, "[EmergencySMS] sendSms exception: ${e.message}")
            return EmergencySmsResult.Failed(-1, e.message ?: "EXCEPTION")
        } finally {
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
                // Receiver was never registered or already unregistered.
            }
        }
    }

    private fun onAllGuardiansResolved() {
        allResolved = true
        totalSent = guardians.values.count { it.sent }
        totalFailed = guardians.values.count { !it.sent }
        Log.d(TAG, "[EmergencySMS] All guardians resolved: sent=$totalSent failed=$totalFailed")
        releaseWakeLock()
        notifyComplete()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun notifyComplete() {
        flutterCallback?.onEmergencyComplete(sosEventId, totalSent, totalFailed)
    }

    // ── Foreground service ──────────────────────────────────────────────

    private fun startForegroundCompat() {
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+: use dataSync type (6-hour limit, requires
                // FOREGROUND_SERVICE_DATA_SYNC permission). More appropriate for
                // SMS transmission than shortService (3-min limit).
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[EmergencySMS] Failed to start foreground: ${e.message}")
            // Notify Flutter of failure so it doesn't wait indefinitely.
            flutterCallback?.onEmergencyComplete(sosEventId, 0, 0)
            stopSelf()
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle("Emergency SMS active")
            .setContentText("Sending emergency messages to your guardians.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_HIGH)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Emergency SMS",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Shows while emergency SMS messages are being sent"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    // ── Wake lock ───────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "GuardianHer:EmergencySms",
        ).apply {
            acquire(120_000L) // 2-minute safety timeout.
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    /**
     * Parses a simple JSON array of guardian objects.
     * Format: [{"id":"...","name":"...","phoneNumber":"..."}]
     *
     * Uses basic string parsing to avoid adding a JSON dependency.
     */
    private fun parseGuardians(json: String): List<GuardianData> {
        val result = mutableListOf<GuardianData>()
        val trimmed = json.trim()
        if (!trimmed.startsWith("[")) return result

        // Split by guardian objects.
        val objects = trimmed.removeSurrounding("[", "]").split("},{")
        for (obj in objects) {
            val clean = obj.removeSurrounding("{", "}")
            val id = extractJsonValue(clean, "id")
            val name = extractJsonValue(clean, "name")
            val phone = extractJsonValue(clean, "phoneNumber")
            if (id != null && name != null && phone != null) {
                result.add(GuardianData(id, name, phone))
            }
        }
        return result
    }

    private fun extractJsonValue(json: String, key: String): String? {
        val pattern = "\"$key\":"
        val idx = json.indexOf(pattern)
        if (idx < 0) return null
        val start = idx + pattern.length
        // Find the opening quote.
        var i = start
        while (i < json.length && json[i] != '"') i++
        if (i >= json.length) return null
        i++ // skip opening quote
        val sb = StringBuilder()
        while (i < json.length && json[i] != '"') {
            if (json[i] == '\\' && i + 1 < json.length) {
                i++ // skip escape char
            }
            sb.append(json[i])
            i++
        }
        return sb.toString()
    }

    private fun maskId(id: String): String {
        if (id.length <= 8) return "****"
        return id.take(4) + "\u2026" + id.takeLast(4)
    }

    private data class GuardianData(
        val id: String,
        val name: String,
        val phoneNumber: String,
    )
}
