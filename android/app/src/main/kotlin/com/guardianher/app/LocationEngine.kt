package com.guardianher.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager

/**
 * Single authoritative GMS-free location engine (Phase 3J / Serverless SMS Relay).
 *
 * Consolidates all LocationManager interactions behind one class so that:
 * - Flutter (via LocationEngineHandler/EventChannel) and
 * - Android services (LiveSharingService, future consumers)
 * share the SAME GPS/NETWORK listeners, freshness policy, and lifecycle.
 *
 * Invariants:
 * - Exactly ONE LocationManager registration per provider at any time.
 * - Listeners are ref-counted: added on first subscriber, removed on last.
 * - Every fix carries boot-scoped monotonic ageMs for correct freshness across
 *   wall-clock changes and reboots.
 * - Freshness policy is the single source of truth for ALL consumers.
 * - Never logs coordinates, contact data, or message content.
 */

/** Freshness thresholds (single policy for all consumers). */
const val FRESH_THRESHOLD_MS = 30_000L        // 30s → "LIVE"
const val STALE_THRESHOLD_MS = 5 * 60 * 1000L // 5m  → "STALE but usable"
const val MAX_AGE_MS = 30 * 60 * 1000L        // 30m → "UNAVAILABLE"

/** Fix freshness classification. */
enum class FixFreshness {
    LIVE,       // ageMs <= FRESH_THRESHOLD_MS
    STALE,      // FRESH_THRESHOLD_MS < ageMs <= STALE_THRESHOLD_MS
    UNAVAILABLE // ageMs > STALE_THRESHOLD_MS or no fix
}

/** Intent action for live fix broadcasts to Android service consumers. */
const val ACTION_LIVE_FIX = "com.guardianher.LIVE_FIX"
const val EXTRA_FIX = "fix_map"

/** Broadcast when location services state changes. */
const val ACTION_SERVICES_CHANGED = "com.guardianher.LOCATION_SERVICES_CHANGED"
const val EXTRA_ENABLED = "enabled"

/** Providers used for LIVE continuous updates. */
private val LIVE_PROVIDERS = listOf(
    LocationManager.GPS_PROVIDER,
    LocationManager.NETWORK_PROVIDER
)

/** Providers probed for cached last-known fixes (fallback only). */
private val LAST_KNOWN_PROVIDERS = listOf(
    LocationManager.GPS_PROVIDER,
    LocationManager.NETWORK_PROVIDER,
    LocationManager.PASSIVE_PROVIDER
)

class LocationEngine(private val context: Context) {

    companion object {
        private const val TAG = "GuardianHerLocationEngine"
    }

    internal val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Ref-counted live listeners per provider. */
    private val liveListenerRefs = mutableMapOf<String, Int>()
    private val liveListeners = mutableMapOf<String, LocationListener>()

    /** Subscribers: Flutter EventChannel sink + Android service callbacks. */
    private var flutterSink: ((Map<String, Any>) -> Unit)? = null
    private val serviceCallbacks = mutableSetOf<ServiceCallback>()

    interface ServiceCallback {
        fun onLiveFix(fixMap: Map<String, Any>)
        fun onServicesChanged(enabled: Boolean)
    }

    /** Current provider enabled state (cached to avoid repeated probes). */
    private var cachedGpsEnabled: Boolean? = null
    private var cachedNetworkEnabled: Boolean? = null

    init {
        // Probe initial state
        updateProviderCache()
    }

    // ─── Public API for Flutter (via LocationEngineHandler) ────────────────

    fun setFlutterSink(sink: ((Map<String, Any>) -> Unit)?) {
        flutterSink = sink
    }

    fun hasFlutterSink(): Boolean = flutterSink != null

    /** Returns true if master location switch is ON. */
    fun isServiceEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            locationManager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    /** Checks location permission state. */
    fun hasAnyLocationPermission(): Boolean {
        return context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            || context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    /** Gets cached fixes from all providers with monotonic ageMs. */
    @SuppressLint("MissingPermission")
    fun getLastKnownLocations(): List<Map<String, Any>> {
        if (!hasAnyLocationPermission()) return emptyList()
        val fixes = mutableListOf<Map<String, Any>>()
        for (provider in LAST_KNOWN_PROVIDERS) {
            val location = try {
                locationManager.getLastKnownLocation(provider)
            } catch (e: SecurityException) {
                Log.w(TAG, "last-known probe refused for $provider")
                null
            } ?: continue
            fixes.add(fixMap(provider, location))
        }
        return fixes
    }

    /**
     * Registers a service consumer (e.g., LiveSharingService) for live fixes.
     * Starts provider listeners if this is the first subscriber.
     */
    fun registerServiceCallback(callback: ServiceCallback) {
        val wasEmpty = serviceCallbacks.isEmpty() && flutterSink == null
        serviceCallbacks.add(callback)
        if (wasEmpty) {
            startLiveListeners()
        }
        // Immediately notify of current services state
        callback.onServicesChanged(isServiceEnabled())
    }

    /** Unregisters a service consumer. Stops listeners if no subscribers remain. */
    fun unregisterServiceCallback(callback: ServiceCallback) {
        serviceCallbacks.remove(callback)
        if (serviceCallbacks.isEmpty() && flutterSink == null) {
            stopLiveListeners()
        }
    }

    // ─── Public API for LiveSharingService (SMS Relay) ────────────────────

    /**
     * Gets the freshest available fix for immediate SMS relay use.
     * Applies freshness policy: returns null if UNAVAILABLE.
     */
    @SuppressLint("MissingPermission")
    fun getFreshestFixForRelay(): Map<String, Any>? {
        if (!hasAnyLocationPermission()) return null
        updateProviderCache()

        var bestFix: Map<String, Any>? = null
        var bestFreshness = FixFreshness.UNAVAILABLE
        var bestAgeMs = Long.MAX_VALUE

        for (provider in LAST_KNOWN_PROVIDERS) {
            val location = try {
                locationManager.getLastKnownLocation(provider)
            } catch (e: SecurityException) {
                continue
            } ?: continue

            val fix = fixMap(provider, location)
            val ageMs = fix["ageMs"] as Long
            val freshness = classifyFreshness(ageMs)

            // Prefer fresher fixes; within same freshness, prefer lower age
            if (freshness.ordinal > bestFreshness.ordinal ||
                (freshness == bestFreshness && ageMs < bestAgeMs)) {
                bestFix = fix
                bestFreshness = freshness
                bestAgeMs = ageMs
            }
        }

        return if (bestFreshness == FixFreshness.UNAVAILABLE) null else bestFix
    }

    /** Forces an immediate live update attempt (used by forceUpdate). */
    fun requestForceUpdate() {
        // The live listeners are already running; they'll deliver the next fix.
        // For immediate satisfaction, we also broadcast the freshest cached fix.
        val cached = getFreshestFixForRelay()
        cached?.let { broadcastToServices(it) }
    }

    // ─── Internal: Live Listener Management ────────────────────────────────

    private fun startLiveListeners() {
        if (!hasAnyLocationPermission()) {
            Log.w(TAG, "Cannot start live listeners: no location permission")
            return
        }
        updateProviderCache()

        var registered = false
        for (providerName in LIVE_PROVIDERS) {
            val enabled = try {
                locationManager.isProviderEnabled(providerName)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Provider probe failed for $providerName")
                false
            }
            if (!enabled) continue

            val refCount = liveListenerRefs.getOrDefault(providerName, 0)
            if (refCount > 0) {
                liveListenerRefs[providerName] = refCount + 1
                registered = true
                continue
            }

            val listener = LocationListener { location ->
                onLocationFix(providerName, location)
            }
            try {
                // minTime=0, minDistance=0 → all updates; minTime controlled by caller's interval
                locationManager.requestLocationUpdates(
                    providerName, 0, 0f, listener, mainHandler.looper
                )
                liveListeners[providerName] = listener
                liveListenerRefs[providerName] = 1
                registered = true
                Log.d(TAG, "Live listener registered on $providerName")
            } catch (e: SecurityException) {
                Log.w(TAG, "Live registration refused on $providerName (permission): ${e.message}")
            } catch (e: Exception) {
                Log.w(TAG, "Live registration failed on $providerName: ${e.message}")
            }
        }

        if (!registered) {
            Log.w(TAG, "No enabled location provider available for live updates")
            notifyServicesChanged(false)
        }
    }

    private fun stopLiveListeners() {
        for ((providerName, listener) in liveListeners) {
            try {
                locationManager.removeUpdates(listener)
                Log.d(TAG, "Live listener removed from $providerName")
            } catch (e: Exception) {
                Log.w(TAG, "removeUpdates failed for $providerName: ${e.message}")
            }
        }
        liveListeners.clear()
        liveListenerRefs.clear()
    }

    /** Called by LocationEngineHandler when Flutter requests interval-based updates. */
    @SuppressLint("MissingPermission")
    fun startLiveUpdatesForFlutter(intervalMs: Long): Boolean {
        if (!hasAnyLocationPermission()) return false
        updateProviderCache()

        var registered = false
        for (providerName in LIVE_PROVIDERS) {
            val enabled = try {
                locationManager.isProviderEnabled(providerName)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Provider probe failed for $providerName")
                false
            }
            if (!enabled) continue

            val refCount = liveListenerRefs.getOrDefault(providerName, 0)
            if (refCount > 0) {
                liveListenerRefs[providerName] = refCount + 1
                registered = true
                continue
            }

            val listener = LocationListener { location ->
                onLocationFix(providerName, location)
            }
            try {
                locationManager.requestLocationUpdates(
                    providerName, intervalMs, 0f, listener, mainHandler.looper
                )
                liveListeners[providerName] = listener
                liveListenerRefs[providerName] = 1
                registered = true
                Log.d(TAG, "Flutter live listener registered on $providerName interval=${intervalMs}ms")
            } catch (e: SecurityException) {
                Log.w(TAG, "Flutter live registration refused on $providerName (permission): ${e.message}")
            } catch (e: Exception) {
                Log.w(TAG, "Flutter live registration failed on $providerName: ${e.message}")
            }
        }

        if (!registered) {
            Log.w(TAG, "No enabled location provider for Flutter live updates")
        }
        return registered
    }

    /** Called by LocationEngineHandler when Flutter stops updates. */
    fun stopLiveUpdatesForFlutter() {
        for (providerName in LIVE_PROVIDERS) {
            val refCount = liveListenerRefs.getOrDefault(providerName, 0)
            if (refCount <= 1) {
                // Last Flutter reference; remove if no service callbacks
                if (serviceCallbacks.isEmpty()) {
                    liveListeners[providerName]?.let { listener ->
                        try {
                            locationManager.removeUpdates(listener)
                        } catch (e: Exception) {
                            Log.w(TAG, "removeUpdates failed for $providerName: ${e.message}")
                        }
                    }
                    liveListeners.remove(providerName)
                    liveListenerRefs.remove(providerName)
                } else {
                    // Service callbacks still need it; just decrement
                    liveListenerRefs[providerName] = 0
                }
            } else {
                liveListenerRefs[providerName] = refCount - 1
            }
        }
    }

    // ─── Fix Processing & Distribution ─────────────────────────────────────

    private fun onLocationFix(provider: String, location: Location) {
        val fix = fixMap(provider, location)
        // Deliver to Flutter EventChannel
        flutterSink?.invoke(fix)
        // Deliver to Android service callbacks
        broadcastToServices(fix)
    }

    private fun broadcastToServices(fix: Map<String, Any>) {
        for (callback in serviceCallbacks) {
            try {
                callback.onLiveFix(fix)
            } catch (e: Exception) {
                Log.w(TAG, "Service callback error: ${e.message}")
            }
        }
        // Also broadcast via LocalBroadcastManager for any other components
        val intent = Intent(ACTION_LIVE_FIX)
        val bundle = Bundle()
        fix.forEach { (key, value) ->
            when (value) {
                is String -> bundle.putString(key, value)
                is Int -> bundle.putInt(key, value)
                is Long -> bundle.putLong(key, value)
                is Double -> bundle.putDouble(key, value)
                is Boolean -> bundle.putBoolean(key, value)
                is Float -> bundle.putFloat(key, value)
                else -> bundle.putString(key, value.toString())
            }
        }
        intent.putExtra(EXTRA_FIX, bundle)
        LocalBroadcastManager.getInstance(context).sendBroadcast(intent)
    }

    private fun notifyServicesChanged(enabled: Boolean) {
        for (callback in serviceCallbacks) {
            try {
                callback.onServicesChanged(enabled)
            } catch (e: Exception) {
                Log.w(TAG, "Service callback error (servicesChanged): ${e.message}")
            }
        }
    }

    private fun updateProviderCache() {
        cachedGpsEnabled = try {
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        } catch (e: Exception) { false }
        cachedNetworkEnabled = try {
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        } catch (e: Exception) { false }
    }

    /** Classifies fix freshness using the single authoritative policy. */
    fun classifyFreshness(ageMs: Long): FixFreshness {
        return when {
            ageMs <= FRESH_THRESHOLD_MS -> FixFreshness.LIVE
            ageMs <= STALE_THRESHOLD_MS -> FixFreshness.STALE
            else -> FixFreshness.UNAVAILABLE
        }
    }

    /**
     * Serializes a fix WITHOUT ever persisting or logging its coordinates.
     * ageMs uses boot-scoped monotonic time so it survives clock changes and reboots.
     */
    @SuppressLint("MissingPermission")
    internal fun fixMap(provider: String, location: Location): Map<String, Any> {
        val ageMs =
            ((SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000L)
                .coerceAtLeast(0L)
        return mapOf(
            "provider" to provider,
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracyMeters" to location.accuracy.toDouble(),
            "epochMs" to location.time,
            "ageMs" to ageMs,
            "freshness" to classifyFreshness(ageMs).name
        )
    }
}