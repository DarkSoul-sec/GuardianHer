package com.guardianher.app

import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/// Log tag for tile diagnostics (non-sensitive: no location, contacts, ids).
const val SOS_TILE_LOG_TAG = "SosTileService"

/**
 * Quick Settings SOS tile (Phase B).
 *
 * Pure trigger with NO business logic: a tap launches GuardianHer with the
 * `guardianher://tilesos` URI. The Flutter side routes that launch to /sos AND
 * arms SOS through the SAME [SosController.startSos] seam used by the in-app
 * button and the shake detector — there is exactly one SOS implementation.
 *
 * Duplicate taps are absorbed downstream by the SosController state machine
 * (a second start while countdown/active/cancelling is ignored), so this class
 * never needs to know whether SOS is running.
 *
 * Tile state mirrors the authoritative Dart-side SOS state through the
 * `guardianher/sos_tile` channel in MainActivity; it is written to prefs so a
 * freshly bound tile shows an honest state even after process death.
 */
class SosTileService : TileService() {

  override fun onStartListening() {
    qsTile?.let { tile ->
      tile.state =
          if (isSosEngaged(this)) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
      tile.updateTile()
    }
  }

  override fun onClick() {
    super.onClick()
    Log.d(TAG, "TILE_CLICKED")
    // While the secure keyguard is up, Android silently refuses a COLD
    // activity start (app process fully dead) — observed on Android 14:
    // TILE_TRIGGER_DISPATCHED logs but no ActivityTaskManager START record
    // ever appears. unlockAndRun is the documented TileService API for this
    // exact case: it raises the unlock prompt and dispatches right after the
    // user unlocks. When the app process is alive, the plain launch already
    // works behind the keyguard (Dart runs invisibly and arms SOS).
    val keyguard = getSystemService(KeyguardManager::class.java)
    val dispatch = {
      Log.d(TAG, "TILE_TRIGGER_DISPATCHED uri=$SOS_TILE_URI")
      // Explicit intent to MainActivity with the home_widget launch action —
      // exactly how ShakeSosService launches the app. Two reasons this must
      // NOT be an implicit ACTION_VIEW: (1) MainActivity declares no
      // guardianher:// intent-filter, so implicit resolution throws
      // ActivityNotFoundException; (2) the home_widget plugin only captures
      // cold-start URIs carried by its own HOME_WIDGET_LAUNCH_ACTION.
      val intent =
          Intent(this, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = Uri.parse(SOS_TILE_URI)
            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
          }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        // API 34+ requires the PendingIntent overload. Dedicated request
        // code: PendingIntent matching ignores data URIs, so sharing request
        // code 0 with the widget's PendingIntent could return a record whose
        // stored intent carries guardianher://sos instead of tilesos
        // (navigation-only).
        val pi =
            PendingIntent.getActivity(
                this,
                SOS_TILE_PI_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_IMMUTABLE,
            )
        startActivityAndCollapse(pi)
      } else {
        @Suppress("DEPRECATION")
        startActivityAndCollapse(intent)
      }
    }
    if (keyguard?.isKeyguardLocked == true) {
      Log.d(TAG, "keyguard locked -> deferring dispatch behind unlock prompt")
      unlockAndRun(dispatch)
    } else {
      dispatch()
    }
  }

  companion object {
    private val TAG = SOS_TILE_LOG_TAG
    const val SOS_TILE_URI = "guardianher://tilesos"
    const val SOS_TILE_PI_REQUEST_CODE = 4242
    private const val PREFS = "guardianher_background"
    private const val KEY_ENGAGED = "sos_tile_engaged"

    /** Mirrored SOS state; prefs-backed so it survives process death. */
    fun isSosEngaged(context: Context): Boolean =
        context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENGAGED, false)

    /** Called from Dart via the `guardianher/sos_tile` channel only. */
    fun setSosEngaged(context: Context, engaged: Boolean) {
      context
          .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
          .edit()
          .putBoolean(KEY_ENGAGED, engaged)
          .apply()
    }
  }
}
