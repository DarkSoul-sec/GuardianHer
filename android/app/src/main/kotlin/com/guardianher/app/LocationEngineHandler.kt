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
 * Replaces the Geolocator plugin (whose Android implementation bundles the
 * proprietary Google Play Services location library) with plain
 * [LocationManager] primitives. All capture strategy — freshness windows,
 * provider tiers and stale fallbacks — lives on the Dart side; this handler
 * only exposes small deterministic operations:
 *
 *  - `isServiceEnabled`      → whether the master location switch is on.
 *  - `checkPermission`       → "granted" | "denied" | "permanentlyDenied".
 *  - `requestPermission`     → runtime request for FINE + COARSE together.
 *  - `openLocationSettings`  → system location settings; true when launched.
 *  - `enableSilently`        → best-effort owner/adb-only silent enable.
 *  - `getLastKnownLocations` → cached fixes from GPS / NETWORK / PASSIVE,
 *                              each with a monotonic `ageMs`.
 *  - `requestSingleUpdate`   → one live fix from "gps" or "network" within a
 *                              timeout, or an error code.
 *  - `startLiveUpdates`      → continuous requestLocationUpdates on GPS +
 *                              NETWORK for an active live session; fixes are
 *                              pushed over `guardianher/location_updates`.
 *  - `stopLiveUpdates`       → removes every live listener.
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
  private val locationManager =
      activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager

  private val mainHandler = Handler(Looper.getMainLooper())

  private val prefs: SharedPreferences =
      activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  /** Result of the in-flight runtime permission request, if any. */
  private var pendingPermissionResult: MethodChannel.Result? = null

  /**
   * Live-update listeners for the Phase 3J continuous capture. Registered on
   * BOTH gps and network providers; fixes flow to Dart over the
   * `guardianher/location_updates` EventChannel while a live session is on.
   * Empty when no session is active — the engine NEVER keeps listeners
   * registered outside an explicit start..stop window.
   */
  private val liveListeners = mutableListOf<LocationListener>()

  private var liveEvents: EventChannel.EventSink? = null

  init {
    EventChannel(messenger, LIVE_UPDATES_CHANNEL).setStreamHandler(
        object : EventChannel.StreamHandler {
          override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            // A fresh sink replaces any stale one (hot restart safety).
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
        // Never crash the app over a location hiccup (brief §7).
        Log.w(TAG, "engine error in ${call.method}", error)
        result.error(CODE_UNAVAILABLE, error.message, null)
      }
    }
  }

  private fun handle(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isServiceEnabled" -> result.success(isServiceEnabled())
      "checkPermission" -> result.success(checkPermission())
      "requestPermission" -> requestPermission(result)
      "openLocationSettings" -> result.success(openLocationSettings())
      "enableSilently" -> result.success(enableSilently())
      "getLastKnownLocations" -> result.success(getLastKnownLocations())
      "requestSingleUpdate" -> requestSingleUpdate(call, result)
      "startLiveUpdates" -> startLiveUpdates(call, result)
      "stopLiveUpdates" -> stopLiveUpdates(result)
      else -> result.notImplemented()
    }
  }

  /** Master location switch. Pre-P devices fall back to provider probes. */
  private fun isServiceEnabled(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      locationManager.isLocationEnabled
    } else {
      @Suppress("DEPRECATION")
      locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
          locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }
  }

  private fun hasAnyLocationPermission(): Boolean {
    return granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
        granted(Manifest.permission.ACCESS_COARSE_LOCATION)
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
    // A prior request plus no OS rationale means Android will never show
    // this dialog again on its own terms — re-prompting would only flash a
    // dialog that auto-dismisses. Route straight to the permanent state so
    // the UI sends the user to Settings instead.
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
        enable.invoke(locationManager, true, Process.myUserHandle())
      } else {
        @Suppress("DEPRECATION")
        Settings.Secure.putInt(
            activity.contentResolver,
            Settings.Secure.LOCATION_MODE,
            Settings.Secure.LOCATION_MODE_HIGH_ACCURACY,
        )
      }
      Log.d(TAG, "location services enabled silently")
      isServiceEnabled()
    } catch (error: Exception) {
      Log.w(TAG, "cannot enable location services silently: $error")
      false
    }
  }

  /** Cached fixes per provider; empty list when none exist. */
  @SuppressLint("MissingPermission")
  private fun getLastKnownLocations(): List<Map<String, Any>> {
    if (!hasAnyLocationPermission()) return emptyList()
    val fixes = mutableListOf<Map<String, Any>>()
    for (provider in LAST_KNOWN_PROVIDERS) {
      val location = try {
        locationManager.getLastKnownLocation(provider)
      } catch (error: SecurityException) {
        Log.w(TAG, "last-known probe refused for $provider")
        null
      } ?: continue
      fixes.add(fixMap(provider, location))
    }
    return fixes
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

    if (!locationManager.isProviderEnabled(provider)) {
      result.error(CODE_SERVICES_DISABLED, provider, null)
      return
    }
    if (!hasAnyLocationPermission()) {
      result.error(CODE_PERMISSION_DENIED, provider, null)
      return
    }

    var done = false
    // Nullable holders break the listener <-> timeout forward-reference cycle;
    // both are assigned before any callback can fire.
    var timeoutRunnable: Runnable? = null
    var listener: LocationListener? = null
    listener = LocationListener { location ->
      if (done) return@LocationListener
      done = true
      timeoutRunnable?.let(mainHandler::removeCallbacks)
      listener?.let(locationManager::removeUpdates)
      result.success(fixMap(provider, location))
    }
    timeoutRunnable = Runnable {
      if (done) return@Runnable
      done = true
      listener?.let(locationManager::removeUpdates)
      Log.d(TAG, "single update timed out on $provider after ${timeoutMs}ms")
      result.error(CODE_TIMEOUT, provider, null)
    }

    mainHandler.postDelayed(timeoutRunnable!!, timeoutMs)
    try {
      locationManager.requestSingleUpdate(provider, listener, mainHandler.looper)
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
   * Uses [LocationManager.requestLocationUpdates] on GPS and NETWORK with the
   * caller's interval as minTime — deliberately NOT a Dart loop of one-shot
   * requests, which would churn provider wake-ups. The foreground service is
   * managed by the Flutter flow (`guardianher/live_location`); this method
   * only owns listener registration.
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
    stopLiveListeners()

    var registered = false
    for (providerName in LIVE_PROVIDERS) {
      val enabled = try {
        locationManager.isProviderEnabled(providerName)
      } catch (error: IllegalArgumentException) {
        Log.w(TAG, "provider probe failed for $providerName")
        false
      }
      if (!enabled) continue
      val listener = LocationListener { location ->
        liveEvents?.success(fixMap(providerName, location))
      }
      try {
        locationManager.requestLocationUpdates(
            providerName, intervalMs, 0f /* minDistance */, listener,
            mainHandler.looper)
        liveListeners.add(listener)
        registered = true
      } catch (error: Exception) {
        Log.w(TAG, "live registration failed on $providerName", error)
      }
    }

    if (registered) {
      Log.d(TAG, "live updates started interval=${intervalMs}ms")
      result.success(null)
    } else {
      result.error(CODE_SERVICES_DISABLED, "no enabled location provider", null)
    }
  }

  /** Stops listener registration; safe to call repeatedly. */
  private fun stopLiveListeners() {
    for (listener in liveListeners) {
      try {
        locationManager.removeUpdates(listener)
      } catch (error: Exception) {
        Log.w(TAG, "removeUpdates failed", error)
      }
    }
    liveListeners.clear()
  }

  private fun stopLiveUpdates(result: MethodChannel.Result) {
    stopLiveListeners()
    Log.d(TAG, "live updates stopped")
    result.success(null)
  }

  /**
   * Serializes a fix WITHOUT ever persisting or logging its coordinates.
   * `ageMs` uses boot-scoped monotonic time so it survives clock changes and
   * reboots; negative values (possible clock skew) are clamped to zero.
   */
  private fun fixMap(provider: String, location: Location): Map<String, Any> {
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
    )
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

    private val LAST_KNOWN_PROVIDERS = listOf(
        LocationManager.GPS_PROVIDER,
        LocationManager.NETWORK_PROVIDER,
        LocationManager.PASSIVE_PROVIDER,
    )

    /** Providers polled for live-session updates (Phase 3J §5). */
    private val LIVE_PROVIDERS = listOf(
        LocationManager.GPS_PROVIDER,
        LocationManager.NETWORK_PROVIDER,
    )

    /** Fix stream for active live-location sessions. */
    const val LIVE_UPDATES_CHANNEL = "guardianher/location_updates"
  }
}
