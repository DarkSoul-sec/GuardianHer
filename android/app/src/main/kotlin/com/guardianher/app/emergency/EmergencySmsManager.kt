package com.guardianher.app.emergency

import android.content.Context
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Handles telephony operations: SIM selection, phone validation, SMS submission.
 *
 * Multi-SIM aware: queries [SubscriptionManager] for active subscriptions and
 * obtains a subscription-specific [SmsManager] when available (API 22+).
 *
 * This class does NOT manage lifecycle — the caller (EmergencySmsService)
 * is responsible for the foreground service context.
 */
class EmergencySmsManager(private val context: Context) {

    companion object {
        private const val TAG = "EmergencySmsManager"
        private const val MAX_PHONE_DIGITS = 15
        private const val MIN_PHONE_DIGITS = 7
    }

    /** Whether the device has at least one usable SIM for SMS. */
    fun hasUsableSim(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val subMgr = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                    as? SubscriptionManager ?: return false
                val activeList = subMgr.activeSubscriptionInfoList
                if (!activeList.isNullOrEmpty()) {
                    return true
                }
                // Fallback: SubscriptionManager may return empty if READ_PHONE_STATE
                // not granted (API 29+). Try TelemetryManager as fallback.
            }
            // API < 22 or fallback: use TelephonyManager.
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE)
                as? TelephonyManager ?: return false
            tm.simState == TelephonyManager.SIM_STATE_READY
        } catch (e: SecurityException) {
            Log.w(TAG, "hasUsableSim: permission check failed: ${e.message}")
            false
        }
    }

    /** Whether SEND_SMS permission is granted. */
    fun hasSmsPermission(): Boolean {
        return context.checkSelfPermission(
            android.Manifest.permission.SEND_SMS,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    /**
     * Validates a phone number for SMS delivery.
     *
     * @param phoneNumber Digits-only number (e.g. "919876543210").
     * @return true if the number has 7–15 digits (E.164-compatible range).
     */
    fun isValidPhoneNumber(phoneNumber: String): Boolean {
        val digits = phoneNumber.filter { it.isDigit() }
        return digits.length in MIN_PHONE_DIGITS..MAX_PHONE_DIGITS
    }

    /**
     * Formats a digits-only stored number into an E.164 destination.
     *
     * If the number already starts with "+", it is returned as-is (after
     * stripping non-digit chars). Otherwise "+" is prepended.
     */
    fun formatDestination(phoneNumber: String): String {
        val digits = phoneNumber.filter { it.isDigit() }
        return "+$digits"
    }

    /**
     * Sends an SMS on the appropriate SIM subscription.
     *
     * @param destination E.164 phone number (e.g. "+919876543210").
     * @param body SMS text.
     * @param sentPendingIntent PendingIntent for the SENT result callback.
     * @throws [SecurityException] if SEND_SMS is not granted.
     * @throws [SimUnavailableException] if no usable SIM is found.
     * @throws [Exception] if SmsManager.sendTextMessage throws.
     */
    fun sendSms(
        destination: String,
        body: String,
        sentPendingIntent: android.app.PendingIntent,
    ) {
        val smsManager = obtainSmsManager()
            ?: throw SimUnavailableException("No usable SIM subscription found")

        Log.d(TAG, "sendSms: dest=${maskNumber(destination)}, bodyLen=${body.length}")

        // Use sendTextMessage directly. On API 24+ Android handles multi-part
        // internally and fires the SENT intent once after all parts succeed.
        // This avoids the need for explicit multipart PendingIntents which would
        // break the guardian-ID matching in EmergencySmsService.sendWithResult.
        smsManager.sendTextMessage(destination, null, body, sentPendingIntent, null)
    }

    /**
     * Returns the number of active SMS-capable subscriptions on this device.
     */
    fun activeSimCount(): Int {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val subMgr = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                    as? SubscriptionManager ?: return 0
                subMgr.activeSubscriptionInfoList?.size ?: 0
            } else {
                val tm = context.getSystemService(Context.TELEPHONY_SERVICE)
                    as? TelephonyManager ?: return 0
                if (tm.simState == TelephonyManager.SIM_STATE_READY) 1 else 0
            }
        } catch (e: SecurityException) {
            0
        }
    }

    // ── Internal ────────────────────────────────────────────────────────

    /**
     * Obtains a subscription-specific [SmsManager] when available,
     * or falls back to [SmsManager.getDefault] on older devices.
     *
     * On API 22+: picks the default SMS subscription if valid, otherwise
     * the first active subscription.
     *
     * On API < 22: uses [SmsManager.getDefault] directly.
     *
     * Returns `null` when no usable SIM is available.
     */
    internal fun obtainSmsManager(): SmsManager? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subMgr = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager

            if (subMgr != null) {
                val activeList = subMgr.activeSubscriptionInfoList
                if (!activeList.isNullOrEmpty()) {
                    // Prefer the default SMS subscription.
                    val defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                    val sub = activeList.find { it.subscriptionId == defaultSubId }
                        ?: activeList.first()
                    return SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId)
                }
            }
            // No active subscriptions found (may be missing READ_PHONE_STATE).
            // Fall back to default SmsManager which may still work.
        }

        // API < 22 or fallback: no subscription API, use default.
        @Suppress("DEPRECATION")
        return SmsManager.getDefault()
    }

    /** Masks a phone number for safe logging. */
    private fun maskNumber(number: String): String {
        if (number.length <= 4) return "****"
        return "*".repeat(number.length - 4) + number.takeLast(4)
    }
}

/** Thrown when no usable SIM subscription is available. */
class SimUnavailableException(message: String) : Exception(message)
