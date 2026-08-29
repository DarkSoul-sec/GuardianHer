package com.guardianher.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restores the Shake SOS detector after a reboot, an OEM "quick boot" or an
 * app update (Phase 3F).
 *
 * The detector is the app's background safety agent: without this receiver it
 * would stay dead after every restart until the user happened to open the app,
 * which is exactly when a safety feature must not depend on user action.
 *
 * Policy notes:
 *  - It only reacts to protected system broadcasts (BOOT_COMPLETED,
 *    QUICKBOOT_POWERON variants, MY_PACKAGE_REPLACED), so nothing third-party
 *    can wake GuardianHer through it.
 *  - It starts ONLY the accelerometer detector, and only when the user enabled
 *    Shake SOS (native flag written from MainActivity's channel handlers).
 *    No SOS session exists across restarts, so SosLocationService is never
 *    started here.
 *  - The start is wrapped in try/catch on purpose: some Android 16 builds
 *    refuse specialUse foreground-service launches from BOOT_COMPLETED and
 *    aggressive OEM battery managers kill them outright. A refusal must never
 *    crash the receiver; when the user next opens the app, the Dart side
 *    (`ShakeSosSettingsController._restore`) re-anchors the service anyway.
 */
class BootReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG = "GuardianHerBoot"
  }

  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    if (!ShakeSosService.isUserEnabled(context)) {
      Log.d(TAG, "$action ignored: Shake SOS disabled")
      return
    }
    try {
      Log.d(TAG, "$action -> restarting shake detector")
      ShakeSosService.start(context)
    } catch (error: Exception) {
      // ForegroundServiceStartNotAllowedException / SecurityException /
      // OEM-specific refusals. Logged and swallowed; the Dart-side restore is
      // the fallback path.
      Log.w(TAG, "could not restore shake detector on $action: $error")
    }
  }
}
