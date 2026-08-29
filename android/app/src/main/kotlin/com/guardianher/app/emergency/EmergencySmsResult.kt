package com.guardianher.app.emergency

/**
 * Represents the result of a single SMS send attempt.
 *
 * Maps Android's SmsManager result codes to meaningful emergency outcomes.
 */
sealed class EmergencySmsResult {

    /** SMS was accepted by the modem for delivery. */
    data object Sent : EmergencySmsResult()

    /** SMS could not be sent. Contains the Android error code. */
    data class Failed(val errorCode: Int, val description: String) : EmergencySmsResult()

    companion object {
        /**
         * Maps [android.app.Activity.RESULT_OK] and related codes to a
         * human-readable description.
         */
        fun fromResultCode(resultCode: Int): EmergencySmsResult {
            return when (resultCode) {
                android.app.Activity.RESULT_OK -> Sent
                ERROR_GENERIC_FAILURE -> Failed(resultCode, "GENERIC_FAILURE")
                ERROR_RADIO_OFF -> Failed(resultCode, "RADIO_OFF")
                ERROR_NULL_PDU -> Failed(resultCode, "NULL_PDU")
                ERROR_NO_SERVICE -> Failed(resultCode, "NO_SERVICE")
                ERROR_LIMIT_EXCEEDED -> Failed(resultCode, "LIMIT_EXCEEDED")
                ERROR_SHORT_CODE_NEVER_ALLOWED -> Failed(resultCode, "SHORT_CODE_NEVER_ALLOWED")
                ERROR_SHORT_CODE_NOT_ALLOWED -> Failed(resultCode, "SHORT_CODE_NOT_ALLOWED")
                else -> Failed(resultCode, "UNKNOWN($resultCode)")
            }
        }

        // SmsManager error constants (available from API level 1).
        private const val ERROR_GENERIC_FAILURE = 1
        private const val ERROR_RADIO_OFF = 2
        private const val ERROR_NULL_PDU = 3
        private const val ERROR_NO_SERVICE = 4
        private const val ERROR_LIMIT_EXCEEDED = 5
        private const val ERROR_SHORT_CODE_NEVER_ALLOWED = 6
        private const val ERROR_SHORT_CODE_NOT_ALLOWED = 7
    }
}
