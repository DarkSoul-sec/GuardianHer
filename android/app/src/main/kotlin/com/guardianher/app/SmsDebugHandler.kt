package com.guardianher.app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Minimal diagnostic: can this phone send an SMS via SmsManager?
 *
 * One method. One SMS. One result. Nothing else.
 */
class SmsDebugHandler(
    private val activity: Activity,
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
) {

    companion object {
        private const val TAG = "SMS-DEBUG"
        private const val CHANNEL = "guardianher/sms_debug"
        private const val ACTION_SMS_SENT = "com.guardianher.app.sms_debug.SENT"
        private const val REQUEST_CODE = 9999
    }

    private var pendingResult: MethodChannel.Result? = null

    fun attach() {
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] MethodChannel initialized")
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendTestSms" -> handleSendTestSms(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSendTestSms(call: MethodCall, result: MethodChannel.Result) {
        val phoneNumber = call.argument<String>("phoneNumber") ?: ""
        val message = call.argument<String>("message") ?: ""

        Log.d(TAG, "[GuardianHer][SMS-DEBUG] sendTestSms called")
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] Raw phoneNumber: '$phoneNumber', message length: ${message.length}")

        if (phoneNumber.isBlank() || message.isBlank()) {
            Log.e(TAG, "[GuardianHer][SMS-DEBUG] phoneNumber or message is blank")
            result.success(mapOf(
                "success" to false,
                "error" to "phoneNumber or message is blank",
            ))
            return
        }

        // 1. Check SEND_SMS permission.
        val permissionStatus = activity.checkSelfPermission(android.Manifest.permission.SEND_SMS)
        val permissionGranted = permissionStatus == PackageManager.PERMISSION_GRANTED
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] SEND_SMS permission = ${if (permissionGranted) "GRANTED" else "DENIED ($permissionStatus)"}")

        if (!permissionGranted) {
            result.success(mapOf(
                "success" to false,
                "error" to "SEND_SMS permission not granted",
                "permissionGranted" to false,
            ))
            return
        }

        // 2. Check SIM - try multiple approaches.
        val simInfo = getSimInfo()
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] SIM count = ${simInfo.simCount}, selected subscription = ${if (simInfo.hasUsable) "available" else "NOT available"}")

        // Also try EmergencySmsManager approach as fallback
        val emergencySmsManager = com.guardianher.app.emergency.EmergencySmsManager(activity)
        val hasSmsPerm = emergencySmsManager.hasSmsPermission()
        val hasSim = emergencySmsManager.hasUsableSim()
        val simCount = emergencySmsManager.activeSimCount()
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] EmergencySmsManager: hasSmsPerm=$hasSmsPerm, hasSim=$hasSim, simCount=$simCount")

        if (!simInfo.hasUsable && !hasSim) {
            result.success(mapOf(
                "success" to false,
                "error" to "No usable SIM subscription (both checks failed)",
                "simCount" to simInfo.simCount,
                "emergencySimCount" to simCount,
            ))
            return
        }

        // 3. Obtain SmsManager - use fallback if primary fails.
        var smsManager = simInfo.smsManager
        if (smsManager == null && hasSim) {
            Log.d(TAG, "[GuardianHer][SMS-DEBUG] Primary SmsManager null, trying EmergencySmsManager.obtainSmsManager()")
            smsManager = emergencySmsManager.obtainSmsManager()
        }
        if (smsManager == null) {
            Log.e(TAG, "[GuardianHer][SMS-DEBUG] SmsManager is null (both paths)")
            result.success(mapOf(
                "success" to false,
                "error" to "SmsManager is null (both paths)",
            ))
            return
        }
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] SmsManager obtained: ${smsManager.javaClass.simpleName}")

        // 4. Register a one-shot BroadcastReceiver for the SENT result.
        val deferredResult = CompletableResult()
        pendingResult = result

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val resultCode = resultCode
                Log.d(TAG, "[GuardianHer][SMS-DEBUG] SENT RESULT = $resultCode")

                val resultMap = when (resultCode) {
                    Activity.RESULT_OK -> {
                        Log.d(TAG, "[GuardianHer][SMS-DEBUG] RESULT_OK — SMS submitted to carrier")
                        mapOf("success" to true, "resultCode" to resultCode, "resultDescription" to "RESULT_OK")
                    }
                    SmsManager.RESULT_ERROR_NO_SERVICE -> {
                        Log.e(TAG, "[GuardianHer][SMS-DEBUG] RESULT_ERROR_NO_SERVICE")
                        mapOf("success" to false, "resultCode" to resultCode, "resultDescription" to "RESULT_ERROR_NO_SERVICE")
                    }
                    SmsManager.RESULT_ERROR_RADIO_OFF -> {
                        Log.e(TAG, "[GuardianHer][SMS-DEBUG] RESULT_ERROR_RADIO_OFF")
                        mapOf("success" to false, "resultCode" to resultCode, "resultDescription" to "RESULT_ERROR_RADIO_OFF")
                    }
                    SmsManager.RESULT_ERROR_NULL_PDU -> {
                        Log.e(TAG, "[GuardianHer][SMS-DEBUG] RESULT_ERROR_NULL_PDU")
                        mapOf("success" to false, "resultCode" to resultCode, "resultDescription" to "RESULT_ERROR_NULL_PDU")
                    }
                    SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                        Log.e(TAG, "[GuardianHer][SMS-DEBUG] RESULT_ERROR_GENERIC_FAILURE")
                        mapOf("success" to false, "resultCode" to resultCode, "resultDescription" to "RESULT_ERROR_GENERIC_FAILURE")
                    }
                    else -> {
                        Log.e(TAG, "[GuardianHer][SMS-DEBUG] UNKNOWN result code: $resultCode")
                        mapOf("success" to false, "resultCode" to resultCode, "resultDescription" to "UNKNOWN_$resultCode")
                    }
                }

                try {
                    activity.unregisterReceiver(this)
                } catch (_: Exception) {}

                pendingResult?.success(resultMap)
                pendingResult = null
            }
        }

        val filter = IntentFilter(ACTION_SMS_SENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(receiver, filter)
        }

        // 5. Build unique PendingIntent.
        val sentIntent = PendingIntent.getBroadcast(
            activity,
            REQUEST_CODE,
            Intent(ACTION_SMS_SENT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // 6. Send - try both raw and formatted number.
        val formattedNumber = if (phoneNumber.startsWith("+")) phoneNumber else "+$phoneNumber"
        Log.d(TAG, "[GuardianHer][SMS-DEBUG] Trying with formatted number: $formattedNumber")

        try {
            Log.d(TAG, "[GuardianHer][SMS-DEBUG] Calling sendTextMessage to $formattedNumber")
            smsManager.sendTextMessage(formattedNumber, null, message, sentIntent, null)
            Log.d(TAG, "[GuardianHer][SMS-DEBUG] sendTextMessage returned (waiting for PendingIntent)")
        } catch (e: SecurityException) {
            Log.e(TAG, "[GuardianHer][SMS-DEBUG] SecurityException: ${e.message}")
            try { activity.unregisterReceiver(receiver) } catch (_: Exception) {}
            pendingResult = null
            result.success(mapOf("success" to false, "error" to "SecurityException: ${e.message}"))
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "[GuardianHer][SMS-DEBUG] IllegalArgumentException: ${e.message}")
            try { activity.unregisterReceiver(receiver) } catch (_: Exception) {}
            pendingResult = null
            result.success(mapOf("success" to false, "error" to "IllegalArgumentException: ${e.message}"))
        } catch (e: Exception) {
            Log.e(TAG, "[GuardianHer][SMS-DEBUG] Exception: ${e.javaClass.simpleName}: ${e.message}")
            try { activity.unregisterReceiver(receiver) } catch (_: Exception) {}
            pendingResult = null
            result.success(mapOf("success" to false, "error" to "${e.javaClass.simpleName}: ${e.message}"))
        }
    }

    private fun getSimInfo(): SimInfo {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val subMgr = activity.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                if (subMgr != null) {
                    val activeList = subMgr.activeSubscriptionInfoList
                    val count = activeList?.size ?: 0
                    if (count > 0) {
                        val defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                        val sub = activeList?.find { it.subscriptionId == defaultSubId }
                            ?: activeList?.first()
                        if (sub != null) {
                            SimInfo(
                                simCount = count,
                                hasUsable = true,
                                smsManager = SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId),
                            )
                        } else {
                            SimInfo(simCount = count, hasUsable = false, smsManager = null)
                        }
                    } else {
                        SimInfo(simCount = 0, hasUsable = false, smsManager = null)
                    }
                } else {
                    SimInfo(simCount = 0, hasUsable = false, smsManager = null)
                }
            } else {
                @Suppress("DEPRECATION")
                val mgr = SmsManager.getDefault()
                val hasSim = mgr != null
                SimInfo(simCount = if (hasSim) 1 else 0, hasUsable = hasSim, smsManager = mgr)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "[GuardianHer][SMS-DEBUG] SIM check SecurityException: ${e.message}")
            SimInfo(simCount = 0, hasUsable = false, smsManager = null)
        }
    }

    private data class SimInfo(
        val simCount: Int,
        val hasUsable: Boolean,
        val smsManager: SmsManager?,
    )

    private class CompletableResult
}
