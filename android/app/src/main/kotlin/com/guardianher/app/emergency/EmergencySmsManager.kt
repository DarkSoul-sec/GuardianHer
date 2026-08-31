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

    /**
     * Verifies SIM is ready for SMS transmission.
     * Checks both TelephonyManager SIM state and SubscriptionManager.
     */
    fun isSimReady(): Boolean {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            val simState = tm?.simState ?: TelephonyManager.SIM_STATE_UNKNOWN
            if (simState != TelephonyManager.SIM_STATE_READY) {
                Log.w(TAG, "isSimReady: SIM not ready, state=$simState")
                return false
            }
            // Also verify we can get a valid SmsManager
            val smsManager = obtainSmsManager()
            smsManager != null
        } catch (e: Exception) {
            Log.w(TAG, "isSimReady: error checking SIM: ${e.message}")
            false
        }
    }

    /** Whether the device has at least one usable SIM for SMS. */
    fun hasUsableSim(): Boolean = isSimReady()

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
     * Input: digits-only number in E.164 format (country code + national number)
     * Examples: "919876543210" → "+919876543210"
     *           "15551234567" → "+15551234567"
     *           "+919876543210" → "+919876543210" (already has +)
     *
     * Output: E.164 format with leading +, suitable for SmsManager.
     */
    fun formatDestination(phoneNumber: String): String {
        val digits = phoneNumber.filter { it.isDigit() }
        val hasPlus = phoneNumber.trim().startsWith("+")

        // If input already had +, trust it's E.164
        // Otherwise prepend + to digits-only E.164
        return if (hasPlus) {
            "+$digits"
        } else {
            "+$digits"
        }
    }

    /**
     * Sends an SMS on the appropriate SIM subscription.
     *
     * @param destination E.164 phone number (e.g. "+919876543210").
     * @param body SMS text.
     * @param sentPendingIntents PendingIntents for the SENT result callbacks,
     * one for each encoded SMS part.
     * @throws [SecurityException] if SEND_SMS is not granted.
     * @throws [SimUnavailableException] if no usable SIM is found.
     * @throws [Exception] if SmsManager.sendTextMessage throws.
     */
    fun sendSms(
        destination: String,
        body: String,
        sentPendingIntents: List<android.app.PendingIntent>,
    ) {
        if (!isSimReady()) {
            throw SimUnavailableException("SIM not ready for SMS")
        }

        val smsManager = obtainSmsManager()
            ?: throw SimUnavailableException("No usable SIM subscription found")

        // Diagnostic: log SMS manager type and SIM state
        val managerClass = smsManager.javaClass.simpleName
        val simState = try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            when (tm?.simState) {
                TelephonyManager.SIM_STATE_READY -> "READY"
                TelephonyManager.SIM_STATE_ABSENT -> "ABSENT"
                TelephonyManager.SIM_STATE_PIN_REQUIRED -> "PIN_REQUIRED"
                TelephonyManager.SIM_STATE_PUK_REQUIRED -> "PUK_REQUIRED"
                TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "NETWORK_LOCKED"
                TelephonyManager.SIM_STATE_UNKNOWN -> "UNKNOWN"
                else -> "UNKNOWN"
            }
        } catch (e: Exception) {
            "ERROR"
        }

        Log.d(TAG, "sendSms: dest=${maskNumber(destination)}, bodyLen=${body.length}, manager=$managerClass, simState=$simState")

        val parts = smsManager.divideMessage(body)
        require(parts.isNotEmpty()) { "SMS body cannot be empty" }
        require(parts.size == sentPendingIntents.size) {
            "Expected one sent callback per SMS part"
        }
        if (parts.size == 1) {
            smsManager.sendTextMessage(
                destination,
                null,
                parts.first(),
                sentPendingIntents.first(),
                null,
            )
        } else {
            Log.d(TAG, "sendSms: multipart parts=${parts.size}")
            smsManager.sendMultipartTextMessage(
                destination,
                null,
                parts,
                ArrayList(sentPendingIntents),
                null,
            )
        }
    }

    /** Splits a body according to the active SMS manager's encoding rules. */
    fun divideMessage(body: String): ArrayList<String> {
        val smsManager = obtainSmsManager()
            ?: throw SimUnavailableException("No usable SIM subscription found")
        return smsManager.divideMessage(body)
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
     * PREFERRED: [SmsManager.getDefault()] works reliably on all API levels
     * and respects the system's default SMS subscription selection.
     *
     * Subscription-specific manager is used ONLY when we have a valid
     * default SMS subscription ID AND the active subscription list is
     * accessible (requires READ_PHONE_STATE at runtime on API 29+).
     *
     * Returns `null` when no usable SIM is available.
     */
    internal fun obtainSmsManager(): SmsManager? {
        // First, try the simplest and most reliable approach: default SmsManager.
        // This respects the system's default SMS app/subscription and works
        // without needing READ_PHONE_STATE.
        val defaultManager = try {
            SmsManager.getDefault()
        } catch (e: Exception) {
            Log.w(TAG, "getDefault() failed: ${e.message}")
            null
        }

        // Diagnostic: log default manager availability
        Log.d(TAG, "obtainSmsManager: defaultManager=${defaultManager != null}, api=${Build.VERSION.SDK_INT}")

        // If default works, use it. Only attempt subscription-specific on API 22+
        // when we can verify the subscription is valid.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subMgr = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager

            if (subMgr != null) {
                val activeList = try {
                    subMgr.activeSubscriptionInfoList
                } catch (e: SecurityException) {
                    Log.w(TAG, "activeSubscriptionInfoList requires READ_PHONE_STATE; using default manager")
                    return defaultManager
                }

                if (!activeList.isNullOrEmpty()) {
                    // Only use subscription-specific if we have a valid default SMS sub ID
                    // that matches an active subscription.
                    val defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                    val sub = activeList.find { it.subscriptionId == defaultSubId }
                    if (sub != null) {
                        Log.d(TAG, "Using subscription-specific SmsManager for subId=${sub.subscriptionId}, carrier=${sub.carrierName}, defaultSubId=$defaultSubId")
                        return SmsManager.getSmsManagerForSubscriptionId(sub.subscriptionId)
                    }
                    // Default SMS sub not in active list — stick with default manager.
                    Log.d(TAG, "Default SMS subscription not in active list (defaultSubId=$defaultSubId, activeCount=${activeList.size}); using default manager")
                    return defaultManager
                } else {
                    Log.d(TAG, "activeSubscriptionInfoList is empty; using default manager")
                }
            } else {
                Log.d(TAG, "SubscriptionManager is null; using default manager")
            }
            // No active subscriptions found or subMgr null — use default.
            Log.d(TAG, "No active subscriptions or subMgr null; using default manager")
            return defaultManager
        }

        // API < 22: no subscription API.
        Log.d(TAG, "API < 22; using default manager")
        return defaultManager
    }

    /** Masks a phone number for safe logging. */
    private fun maskNumber(number: String): String {
        if (number.length <= 4) return "****"
        return "*".repeat(number.length - 4) + number.takeLast(4)
    }
}

/** Thrown when no usable SIM subscription is available. */
class SimUnavailableException(message: String) : Exception(message)
