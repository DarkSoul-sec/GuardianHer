package com.guardianher.app

import android.app.Activity
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import android.util.Log
import com.guardianher.app.emergency.EmergencySmsService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  companion object {
    private const val TAG = "MainActivity"
    private const val REQUEST_SMS_PERMISSION = 4712
  }

  private val deviceAdminComponent: ComponentName
    get() = ComponentName(this, DeviceAdminReceiver::class.java)

  /** GMS-free one-shot location engine (Phase 3H-1). */
  private lateinit var locationEngineHandler: LocationEngineHandler

  /** Channel for forwarding warm-start SOS intents to Flutter. */
  private var sosTriggerChannel: MethodChannel? = null
  /** Buffered URI waiting for Flutter to register its listener. */
  private var pendingSosUri: String? = null

  /** Pending result for SMS permission request (set from MethodChannel, resolved in onRequestPermissionsResult). */
  private var pendingSmsResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager

    // One-shot LocationManager-based capture engine (replaces Geolocator).
    locationEngineHandler = LocationEngineHandler(
        activity = this,
        messenger = flutterEngine.dartExecutor.binaryMessenger,
    )

    // TEMPORARY: minimal SMS diagnostic — prove SmsManager works on this device.
    SmsDebugHandler(this, flutterEngine.dartExecutor.binaryMessenger).attach()

    // Controls the Shake SOS foreground service from Dart.
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/shake_sos",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          ShakeSosService.start(this)
          // Recorded so BootReceiver restores the detector after reboot /
          // app update without spinning up Flutter (Phase 3F).
          ShakeSosService.setUserEnabled(this, true)
          result.success(null)
        }
        "stop" -> {
          ShakeSosService.setUserEnabled(this, false)
          ShakeSosService.stop(this)
          result.success(null)
        }
        "openBatteryOptimizationSettings" -> {
          startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
          result.success(null)
        }
        "isIgnoringBatteryOptimizations" -> {
          val powerManager = getSystemService(POWER_SERVICE) as android.os.PowerManager
          result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
        }
        "manufacturerToken" -> {
          result.success(oemToken(Build.MANUFACTURER))
        }
        "canDrawOverlays" -> {
          result.success(Settings.canDrawOverlays(this))
        }
        "openOverlaySettings" -> {
          val intent =
              Intent(
                  Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                  Uri.parse("package:$packageName"),
              )
          startActivity(intent)
          result.success(null)
        }
        "startSosAlert" -> {
          // Engages the repeating SOS alert loop on the shake foreground
          // service so it keeps vibrating with the app closed or the process
          // under memory pressure. Returns false when the detector service is
          // not running (Shake SOS disabled), in which case Flutter drives the
          // alert itself.
          result.success(ShakeSosService.startSosAlert(this))
        }
        "stopSosAlert" -> {
          ShakeSosService.stopSosAlert(this)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    // Device-administrator status/activation (user-opt-in from Settings).
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/device_admin",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "isActive" -> result.success(dpm.isAdminActive(deviceAdminComponent))
        "requestActivation" -> {
          if (dpm.isAdminActive(deviceAdminComponent)) {
            result.success(true)
          } else {
            val intent =
                Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                  putExtra(
                      DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                      deviceAdminComponent,
                  )
                  putExtra(
                      DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                      "Enabling device administrator lets GuardianHer keep the " +
                          "shake detector running and blocks uninstall until it " +
                          "is deactivated. GuardianHer never locks your screen " +
                          "or wipes your device.",
                  )
                }
            startActivity(intent)
            result.success(false)
          }
        }
        "deactivate" -> {
          dpm.removeActiveAdmin(deviceAdminComponent)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // Holds the foreground location context while SOS is active so a fix can be
    // captured with the phone locked / screen off / app backgrounded.
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/sos_location",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          SosLocationService.start(this)
          result.success(null)
        }
        "stop" -> {
          SosLocationService.stop(this)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    // Quick Settings SOS tile state mirror (Phase B). Dart stays authoritative;
    // this only persists a boolean the tile reads in onStartListening.
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/sos_tile",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "setSosEngaged" -> {
          SosTileService.setSosEngaged(this, call.arguments as? Boolean ?: false)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    // Direct SMS sending for the emergency orchestrator (SmsManager API).
    // Requires SEND_SMS runtime permission; the Dart side requests it via
    // PermissionService before calling sendSms.
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/send_sms",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "checkSimReady" -> {
          try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val simState = tm.simState
            val ready = simState == TelephonyManager.SIM_STATE_READY
            Log.d(TAG, "checkSimReady: simState=$simState, ready=$ready")
            result.success(ready)
          } catch (e: Exception) {
            Log.e(TAG, "checkSimReady failed: ${e.message}")
            result.success(false)
          }
        }
        "sendSms" -> {
          val phoneNumber = call.argument<String>("phoneNumber") ?: ""
          val body = call.argument<String>("body") ?: ""
          Log.d(TAG, "sendSms called: phone=$phoneNumber, bodyLength=${body.length}")
          if (phoneNumber.isEmpty() || body.isEmpty()) {
            Log.w(TAG, "sendSms: missing phone or body")
            result.success(mapOf("success" to false, "error" to "Missing phone number or body."))
            return@setMethodCallHandler
          }
          try {
            val smsManager = SmsManager.getDefault()
            val sentIntent = PendingIntent.getBroadcast(
              this,
              phoneNumber.hashCode(),
              Intent(SmsSentReceiver.ACTION_SMS_SENT),
              PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            smsManager.sendTextMessage(phoneNumber, null, body, sentIntent, null)
            Log.d(TAG, "sendSms: dispatched for $phoneNumber")
            result.success(mapOf("success" to true, "error" to null as String?))
          } catch (e: Exception) {
            Log.e(TAG, "sendSms failed: ${e.message}")
            result.success(mapOf("success" to false, "error" to e.message))
          }
        }
        "getBatteryPercentage" -> {
          try {
            val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level == -1 || scale == -1) {
              Log.d(TAG, "getBatteryPercentage: level=$level, scale=$scale (null)")
              result.success(null)
            } else {
              val pct = (level * 100 / scale.toFloat()).toInt()
              Log.d(TAG, "getBatteryPercentage: $pct%")
              result.success(pct)
            }
          } catch (e: Exception) {
            Log.e(TAG, "getBatteryPercentage failed: ${e.message}")
            result.success(null)
          }
        }
        else -> result.notImplemented()
      }
    }

    // Battery percentage for emergency SMS (used by telephony-based SMS data source).
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/battery",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "getBatteryPercentage" -> {
          try {
            val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level == -1 || scale == -1) {
              Log.d(TAG, "getBatteryPercentage: level=$level, scale=$scale (null)")
              result.success(null)
            } else {
              val pct = (level * 100 / scale.toFloat()).toInt()
              Log.d(TAG, "getBatteryPercentage: $pct%")
              result.success(pct)
            }
          } catch (e: Exception) {
            Log.e(TAG, "getBatteryPercentage failed: ${e.message}")
            result.success(null)
          }
        }
        else -> result.notImplemented()
      }
    }

    // Best-effort silent location-services enable during SOS lives in the
    // location engine channel (`enableSilently`); see LocationEngineHandler.

// ── Emergency SMS bridge ────────────────────────────────────────────
    // Flutter requests native emergency SMS; the foreground service executes
    // independently of this Activity.
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/emergency_sms",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "startEmergency" -> {
          val sosEventId = call.argument<String>("sosEventId") ?: ""
          val guardiansJson = call.argument<String>("guardiansJson") ?: ""
          val smsBody = call.argument<String>("smsBody") ?: ""
          val locationUrl = call.argument<String>("locationUrl")
          val batteryPercentage = call.argument<Int>("batteryPercentage")

          Log.d(TAG, "[EmergencySMS] startEmergency: event=$sosEventId, guardians_json_len=${guardiansJson.length}")

          // Set up the callback so the service can push status to Flutter.
          val callback: com.guardianher.app.emergency.FlutterCallback =
              object : com.guardianher.app.emergency.FlutterCallback {
            private fun dispatchToMain(action: () -> Unit) {
                if (Looper.myLooper() == Looper.getMainLooper()) {
                  action()
                } else {
                  Handler(Looper.getMainLooper()).post(action)
                }
            }

            override fun onGuardianStatusChanged(guardianId: String, status: String, error: String?) {
                val args = mutableMapOf<String, Any?>(
                    "guardianId" to guardianId,
                    "status" to status,
                )
                if (error != null) args["error"] = error
                dispatchToMain {
                  try {
                    MethodChannel(
                        flutterEngine.dartExecutor.binaryMessenger,
                        "guardianher/emergency_sms",
                    ).invokeMethod("onGuardianStatusChanged", args)
                  } catch (e: Exception) {
                    Log.w(TAG, "[EmergencySMS] Could not push status to Flutter: ${e.message}")
                  }
                }
            }

            override fun onEmergencyComplete(sosEventId: String, sent: Int, failed: Int) {
                dispatchToMain {
                  try {
                    MethodChannel(
                        flutterEngine.dartExecutor.binaryMessenger,
                        "guardianher/emergency_sms",
                    ).invokeMethod("onEmergencyComplete", mapOf(
                        "sosEventId" to sosEventId,
                        "sent" to sent,
                        "failed" to failed,
                    ))
                  } catch (e: Exception) {
                    Log.w(TAG, "[EmergencySMS] Could not push completion to Flutter: ${e.message}")
                  }
                }
            }
        }
        com.guardianher.app.emergency.EmergencySmsService.flutterCallback = callback

        // Start the foreground service with all data in the intent.
        val serviceIntent = Intent(this, com.guardianher.app.emergency.EmergencySmsService::class.java).apply {
        putExtra(com.guardianher.app.emergency.EmergencySmsService.EXTRA_SOS_EVENT_ID, sosEventId)
        putExtra(com.guardianher.app.emergency.EmergencySmsService.EXTRA_GUARDIANS_JSON, guardiansJson)
        putExtra(com.guardianher.app.emergency.EmergencySmsService.EXTRA_SMS_BODY, smsBody)
        if (locationUrl != null) putExtra(com.guardianher.app.emergency.EmergencySmsService.EXTRA_LOCATION_URL, locationUrl)
        if (batteryPercentage != null) putExtra(com.guardianher.app.emergency.EmergencySmsService.EXTRA_BATTERY_PERCENTAGE, batteryPercentage)
      }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          startForegroundService(serviceIntent)
        } else {
          startService(serviceIntent)
        }
        result.success(null)
        }
        "cancelEmergency" -> {
          stopService(Intent(this, com.guardianher.app.emergency.EmergencySmsService::class.java))
          result.success(null)
        }
        "getBatteryPercentage" -> {
          try {
            val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) {
              val pct = (level * 100) / scale
              result.success(pct)
            } else {
              result.success(null)
            }
          } catch (e: Exception) {
            result.success(null)
          }
        }
        "checkSmsPermission" -> {
          val granted = checkSelfPermission(android.Manifest.permission.SEND_SMS) ==
              PackageManager.PERMISSION_GRANTED
          Log.d(TAG, "[EmergencySMS] checkSmsPermission: granted=$granted")
          result.success(granted)
        }
        "requestSmsPermission" -> {
          if (checkSelfPermission(android.Manifest.permission.SEND_SMS) ==
              PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "[EmergencySMS] requestSmsPermission: already granted")
            result.success(true)
          } else {
            Log.d(TAG, "[EmergencySMS] requestSmsPermission: requesting via ActivityCompat")
            pendingSmsResult = result
            ActivityCompat.requestPermissions(
              this,
              arrayOf(android.Manifest.permission.SEND_SMS),
              REQUEST_SMS_PERMISSION,
            )
          }
        }
        else -> result.notImplemented()
      }
    }

    // Device Admin for onboarding (matches lib/features/onboarding/data/datasources/device_admin_datasource.dart).
    MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.guardianher/device_admin",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "isActive" -> result.success(dpm.isAdminActive(deviceAdminComponent))
        "requestActivation" -> {
          if (dpm.isAdminActive(deviceAdminComponent)) {
            result.success(true)
          } else {
            val intent =
                Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                  putExtra(
                      DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                      deviceAdminComponent,
                  )
                  putExtra(
                      DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                      "Enabling device administrator lets GuardianHer keep the " +
                          "shake detector running and blocks uninstall until it " +
                          "is deactivated. GuardianHer never locks your screen " +
                          "or wipes your device.",
                  )
                }
            startActivity(intent)
            result.success(false)
          }
        }
        "deactivate" -> {
          dpm.removeActiveAdmin(deviceAdminComponent)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // Warm-start SOS intent forwarding: ShakeSosService and SosTileService
    // launch MainActivity with HOME_WIDGET_LAUNCH_ACTION + data URI. When the
    // app is already running, onNewIntent delivers the URI here; this channel
    // forwards it to Flutter so routeLaunch() can arm the SOS workflow.
    sosTriggerChannel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "guardianher/sos_trigger",
    )
    // Flush any URI that arrived before the engine was ready.
    pendingSosUri?.let { uri ->
      sosTriggerChannel?.invokeMethod("onNewIntent", uri)
      pendingSosUri = null
    }
  }

  override fun onRequestPermissionsResult(
      requestCode: Int,
      permissions: Array<out String>,
      grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    when (requestCode) {
      4711 -> locationEngineHandler.onRequestPermissionsResult(grantResults)
      REQUEST_SMS_PERMISSION -> {
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        Log.d(TAG, "[EmergencySMS] onRequestPermissionsResult: granted=$granted")
        pendingSmsResult?.success(granted)
        pendingSmsResult = null
      }
    }
  }

  /**
   * Forwards warm-start intents (shake SOS, tile SOS) to Flutter.
   *
   * When the app is already running and ShakeSosService or SosTileService
   * launches MainActivity with HOME_WIDGET_LAUNCH_ACTION + data URI,
   * Android delivers it here instead of onCreate. Without this override
   * the URI is silently dropped and SOS never activates.
   */
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    val action = intent.action
    val uri = intent.data?.toString()
    Log.d(TAG, "onNewIntent: action=$action, uri=$uri")
    if (uri != null && uri.startsWith("guardianher://")) {
      Log.d(TAG, "onNewIntent: forwarding $uri to Flutter")
      val channel = sosTriggerChannel
      if (channel != null) {
        channel.invokeMethod("onNewIntent", uri)
      } else {
        Log.d(TAG, "onNewIntent: channel not ready, buffering URI")
        pendingSosUri = uri
      }
    }
  }

  /**
   * Normalizes [manufacturer] into a stable token the Dart side maps to
   * OEM-specific battery/Autostart guidance (Phase 3F). Returns null when the
   * maker needs no special wording. Redmi/POCO report Xiaomi; OnePlus and
   * realme are grouped with Oppo (same OPlus battery stack).
   */
  private fun oemToken(manufacturer: String): String? {
    val vendor = manufacturer.lowercase().trim()
    return when {
      vendor.isEmpty() -> null
      vendor == "xiaomi" || vendor == "redmi" || vendor == "poco" -> "miui"
      vendor == "oppo" || vendor == "oneplus" || vendor == "realme" -> "coloros"
      vendor == "vivo" || vendor == "iqoo" -> "funtouch"
      vendor == "huawei" -> "emui"
      vendor == "honor" -> "magicos"
      vendor == "samsung" -> "samsung"
      else -> null
    }
  }
}