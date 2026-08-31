package com.guardianher.app.emergency

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receives the SENT-result broadcast from [android.telephony.SmsManager.sendTextMessage].
 *
 * Each guardian SMS gets its own [PendingIntent] whose action encodes the
 * guardian id and attempt number. When the modem confirms or rejects the
 * send, Android fires this receiver with the matching intent.
 *
 * The [onResult] callback carries the parsed [EmergencySmsResult] together
 * with the guardian id and attempt so the service can update per-guardian
 * status and schedule retries.
 */
class EmergencySmsResultReceiver(
    private val onResult: (guardianId: String, attempt: Int, result: EmergencySmsResult) -> Unit,
) : BroadcastReceiver() {

    companion object {
        const val ACTION_SMS_SENT = "com.guardianher.app.emergency.SMS_SENT"
        const val EXTRA_GUARDIAN_ID = "guardian_id"
        const val EXTRA_ATTEMPT = "attempt"
        const val EXTRA_PART_INDEX = "part_index"
        private const val TAG = "EmergencySmsResult"

        /**
         * Creates a [PendingIntent] that will fire this receiver with the
         * correct extras for a specific guardian and attempt.
         */
        fun createSentIntent(
            context: Context,
            guardianId: String,
            attempt: Int,
            partIndex: Int,
        ): android.app.PendingIntent {
            val intent = Intent(ACTION_SMS_SENT).apply {
                putExtra(EXTRA_GUARDIAN_ID, guardianId)
                putExtra(EXTRA_ATTEMPT, attempt)
                putExtra(EXTRA_PART_INDEX, partIndex)
                setPackage(context.packageName)
            }
            // Unique request code for every part of an attempted guardian SMS.
            val requestCode = 31 * (31 * guardianId.hashCode() + attempt) + partIndex
            return android.app.PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        val guardianId = intent?.getStringExtra(EXTRA_GUARDIAN_ID) ?: return
        val attempt = intent.getIntExtra(EXTRA_ATTEMPT, 0)
        val resultCode = resultCode
        val result = EmergencySmsResult.fromResultCode(resultCode)

        Log.d(TAG, "SMS result: guardian=$guardianId attempt=$attempt code=$resultCode -> $result")
        onResult(guardianId, attempt, result)
    }
}
