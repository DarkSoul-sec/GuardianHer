package com.guardianher.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives the [Activity.RESULT_OK] or error broadcast from
 * [android.telephony.SmsManager.sendTextMessage].
 *
 * The Dart side waits for this result before marking the SMS as
 * "sent" or "failed" in the emergency orchestrator.
 */
class SmsSentReceiver(
  private val onResult: (success: Boolean, errorCode: Int?) -> Unit,
) : BroadcastReceiver() {

  companion object {
    const val ACTION_SMS_SENT = "com.guardianher.app.SMS_SENT"
  }

  override fun onReceive(context: Context?, intent: Intent?) {
    val result = resultCode
    when (result) {
      Activity.RESULT_OK -> {
        onResult(true, null)
      }
      else -> {
        onResult(false, result)
      }
    }
  }
}
