package com.guardianher.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device-admin receiver (user-opt-in from Settings > Device administrator).
 *
 * While active, the system blocks uninstall and disables the "Force stop"
 * button for GuardianHer (it must be deactivated first), which keeps the
 * Shake SOS detector alive and stops the app being casually removed or
 * killed. No policies are declared — the receiver exists only to hold admin
 * status; we never lock the screen or wipe the device.
 */
class DeviceAdminReceiver : DeviceAdminReceiver() {
  override fun onEnabled(context: Context, intent: Intent) {
    Log.d(TAG, "device admin enabled")
  }

  override fun onDisabled(context: Context, intent: Intent) {
    Log.d(TAG, "device admin disabled")
  }

  companion object {
    private const val TAG = "DeviceAdminReceiver"
  }
}