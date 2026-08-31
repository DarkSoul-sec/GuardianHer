package com.guardianher.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.os.UserHandle
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * GMS-free one-shot location engine behind the `guardianher/location_engine`
 * MethodChannel (F-Droid-first Phase 3H-1).
 *
 * Delegates all LocationManager interactions to the shared [LocationEngine].
 * This handler only manages:
 *  - MethodChannel / EventChannel plumbing
 *  - Permission request/state logic (shared-prefs heuristic)
 *  - One-shot capture timeouts (Tier 1/2 logic lives on Dart side)
 *  - Silent location-services enable (owner/adb only)
 *
 * PRIVACY: never log coordinates, contact data or message content. Diagnostics
 * carry only provider names, permission states, status codes and durations.
 *
 * Timestamps: every fix carries both an epoch wall-clock time (`epochMs`,
 * from [Location.getTime]) for display, and `ageMs` derived from
 * [SystemClock.elapsedRealtimeNanos] minus the fix's elapsed-realtime stamp.
 * Because both counters are boot-scoped and sampled together, `ageMs` stays
 * correct across wall-clock changes AND device reboots — freshness decisions
 * never compare timestamps recorded before a reboot.
 */
class LocationEngineHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val engine = LocationEngine(activity.applicationContext)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val prefs: SharedPreferences =
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Result of the in-flight runtime permission request, if any. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    /** Tracks whether we have an active Flutter live session. */
    private var flutterSessionActive = false

    private var liveEvents: EventChannel.EventSink? = null

    init {
        // Wire the shared engine's Flutter sink
        engine.setFlutterSink { fixMap ->
            liveEvents?.success(fixMap)
        }

        EventChannel(messenger, LIVE_UPDATES_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    liveEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    liveEvents = null
                }
            })

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (error: Exception) {
                Log.w(TAG, "engine error in ${call.method}", error)
                result.error(CODE_UNAVAILABLE, error.message, null)
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isServiceEnabled" -> result.success(engine.isServiceEnabled())
            "checkPermission" -> result.success(checkPermission())
            "requestPermission" -> requestPermission(result)
            "openLocationSettings" -> result.success(openLocationSettings())
            "enableSilently" -> result.success(enableSilently())
            "getLastKnownLocations" -> result.success(engine.getLastKnownLocations())
            "requestSingleUpdate" -> requestSingleUpdate(call, result)
            "startLiveUpdates" -> startLiveUpdates(call, result)
            "stopLiveUpdates" -> stopLiveUpdates(result)
            else -> result.notImplemented()
        }
    }

    /** Master location switch. Pre-P devices fall back to provider probes. */
    private fun isServiceEnabled(): Boolean {
        return engine.isServiceEnabled()
    }

    private fun hasAnyLocationPermission(): Boolean {
        return engine.hasAnyLocationPermission()
    }

    private fun granted(permission: String): Boolean {
        return activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Maps the OS permission state onto the three states the app understands.
     *
     * The permanently-denied heuristic needs evidence of an earlier request:
     * before the first request Android always reports "no rationale needed",
     * which would misclassify a first-time denial as permanent. A shared-prefs
     * flag records our first request so later classifications are honest.
     */
    private fun checkPermission(): String {
        if (hasAnyLocationPermission()) return STATE_GRANTED
        val askedBefore = prefs.getBoolean(KEY_ASKED_ONCE, false)
        val noRationale =
            !activity.shouldShowRequestPermissionRationale(
                Manifest.permission.ACCESS_FINE_LOCATION)
        return if (askedBefore && noRationale) STATE_PERMANENTLY_DENIED else STATE_DENIED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasAnyLocationPermission()) {
            result.success(STATE_GRANTED)
            return
        }
        val askedBefore = prefs.getBoolean(KEY_ASKED_ONCE, false)
        if (askedBefore && !activity.shouldShowRequestPermissionRationale(
                Manifest.permission.ACCESS_FINE_LOCATION)
        ) {
            Log.d(TAG, "request short-circuited: permanently denied")
            result.success(STATE_PERMANENTLY_DENIED)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(CODE_BUSY, "permission request already in flight", null)
            return
        }
        prefs.edit().putBoolean(KEY_ASKED_ONCE, true).apply()
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            PERMISSION_REQUEST_CODE,
        )
    }

    /** Called from MainActivity when the runtime permission dialog resolves. */
    fun onRequestPermissionsResult(grantResults: IntArray) {
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        val fineIndex = 0
        val fineGranted =
            grantResults.getOrNull(fineIndex) == PackageManager.PERMISSION_GRANTED
        val state = when {
            hasAnyLocationPermission() -> STATE_GRANTED
            !fineGranted &&
                !activity.shouldShowRequestPermissionRationale(
                    Manifest.permission.ACCESS_FINE_LOCATION) -> STATE_PERMANENTLY_DENIED
            else -> STATE_DENIED
        }
        Log.d(TAG, "permission request resolved: $state")
        pending.success(state)
    }

    private fun openLocationSettings(): Boolean {
        return try {
            activity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            true
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "no activity handles location source settings")
            false
        }
    }

    /**
     * Silent master-switch enable. Only works for the device/profile owner or an
     * install holding WRITE_SECURE_SETTINGS (granted via adb); normal installs
     * throw inside the hidden-API reflection and get false, whereupon the Dart
     * side opens the settings screen instead.
     */
    private fun enableSilently(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val enable = LocationManager::class.java.getMethod(
                    "setLocationEnabledForUser",
                    Boolean::class.javaPrimitiveType,
                    UserHandle::class.java,
                )
                enable.invoke(engine.locationManager, true, Process.myUserHandle())
            } else {
                @Suppress("DEPRECATION")
                Settings.Secure.putInt(
                    activity.contentResolver,
                    Settings.Secure.LOCATION_MODE,
                    Settings.Secure.LOCATION_MODE_HIGH_ACCURACY,
                )
            }
            Log.d(TAG, "location services enabled silently")
            engine.isServiceEnabled()
        } catch (error: Exception) {
            Log.w(TAG, "cannot enable location services silently: $error")
            false
        }
    }

    /**
     * One live fix from [LocationManager] within [MethodCall]-supplied bounds.
     *
     * Errors (as platform exception codes):
     *  - `servicesDisabled`  — the requested provider is switched off.
     *  - `timeout`           — no fix arrived within the budget.
     *  - `providerFailed`    — the registration itself failed.
     */
    @SuppressLint("MissingPermission")
    private fun requestSingleUpdate(call: MethodCall, result: MethodChannel.Result) {
        val provider = when (call.argument<String>("provider")) {
            PROVIDER_GPS -> LocationManager.GPS_PROVIDER
            PROVIDER_NETWORK -> LocationManager.NETWORK_PROVIDER
            else -> {
                result.error(CODE_INVALID_ARGUMENTS, "unknown provider", null)
                return
            }
        }
        val timeoutMs = (call.argument<Number>("timeoutMs") ?: 20000L).toLong()
            .coerceIn(1_000, 120_000)

        if (!try { engine.locationManager.isProviderEnabled(provider) } catch (e: Exception) { false }) {
            result.error(CODE_SERVICES_DISABLED, provider, null)
            return
        }
        if (!hasAnyLocationPermission()) {
            result.error(CODE_PERMISSION_DENIED, provider, null)
            return
        }

        var done = false
        var timeoutRunnable: Runnable? = null
        var listener: LocationListener? = null
        listener = LocationListener { location ->
            if (done) return@LocationListener
            done = true
            timeoutRunnable?.let(mainHandler::removeCallbacks)
            listener?.let(engine.locationManager::removeUpdates)
            result.success(engine.fixMap(provider, location))
        }
        timeoutRunnable = Runnable {
            if (done) return@Runnable
            done = true
            listener?.let(engine.locationManager::removeUpdates)
            Log.d(TAG, "single update timed out on $provider after ${timeoutMs}ms")
            result.error(CODE_TIMEOUT, provider, null)
        }

        mainHandler.postDelayed(timeoutRunnable!!, timeoutMs)
        try {
            engine.locationManager.requestSingleUpdate(provider, listener, mainHandler.looper)
        } catch (error: Exception) {
            if (done) return
            done = true
            timeoutRunnable?.let(mainHandler::removeCallbacks)
            Log.w(TAG, "single update failed to register on $provider", error)
            result.error(CODE_PROVIDER_FAILED, provider, null)
        }
    }

    /**
     * Continuous updates for an active live-location session (Phase 3J §5).
     *
     * Delegates to the shared [LocationEngine] which manages listener ref-counting
     * across Flutter and Android service consumers.
     */
    @SuppressLint("MissingPermission")
    private fun startLiveUpdates(call: MethodCall, result: MethodChannel.Result) {
        val intervalMs = (call.argument<Number>("intervalMs") ?: 30_000L)
            .toLong()
            .coerceIn(1_000, 300_000)

        if (!hasAnyLocationPermission()) {
            result.error(CODE_PERMISSION_DENIED, "live updates", null)
            return
        }

        val registered = engine.startLiveUpdatesForFlutter(intervalMs)
        flutterSessionActive = registered

        if (registered) {
            Log.d(TAG, "live updates started interval=${intervalMs}ms")
            result.success(null)
        } else {
            result.error(CODE_SERVICES_DISABLED, "no enabled location provider", null)
        }
    }

    /** Stops Flutter's live updates; safe to call repeatedly. */
    private fun stopLiveUpdates(result: MethodChannel.Result) {
        engine.stopLiveUpdatesForFlutter()
        flutterSessionActive = false
        Log.d(TAG, "live updates stopped")
        result.success(null)
    }

    companion object {
        private const val TAG = "GuardianHerLocationEngine"
        const val CHANNEL = "guardianher/location_engine"
        private const val PREFS_NAME = "guardianher_location_engine"
        private const val KEY_ASKED_ONCE = "asked_once"
        private const val PERMISSION_REQUEST_CODE = 4711

        const val PROVIDER_GPS = "gps"
        const val PROVIDER_NETWORK = "network"

        const val STATE_GRANTED = "granted"
        const val STATE_DENIED = "denied"
        const val STATE_PERMANENTLY_DENIED = "permanentlyDenied"

        const val CODE_SERVICES_DISABLED = "servicesDisabled"
        const val CODE_PERMISSION_DENIED = "permissionDenied"
        const val CODE_TIMEOUT = "timeout"
        const val CODE_PROVIDER_FAILED = "providerFailed"
        const val CODE_UNAVAILABLE = "unavailable"
        const val CODE_BUSY = "busy"
        const val CODE_INVALID_ARGUMENTS = "invalidArguments"

        /** Fix stream for active live-location sessions. */
        const val LIVE_UPDATES_CHANNEL = "guardianher/location_updates"
    }
}