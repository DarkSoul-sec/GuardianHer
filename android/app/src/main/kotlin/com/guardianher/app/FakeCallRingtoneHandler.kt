package com.guardianher.app

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Simulated incoming-call alert for the Fake Call feature — and nothing else.
 *
 * Loops the system default ringtone ([RingtoneManager]) and, optionally, a
 * repeating vibration waveform. Stopped idempotently; never outlives the
 * feature because every controller transition calls `stopAlert`, and the
 * ringing state self-times-out after 30 s on the Dart side.
 *
 * No telephony, no SMS, no microphone, no overlay, no service, no new
 * permissions. SOS services ([EmergencySmsService], [SosLocationService],
 * [ShakeSosService]) are untouched.
 */
class FakeCallRingtoneHandler(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var loopRunnable: Runnable? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlert" -> {
                    val vibrate = call.argument<Boolean>("vibrate") ?: true
                    startAlert(vibrate)
                    result.success(null)
                }
                "stopAlert" -> {
                    stopAlert()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Synchronized
    private fun startAlert(vibrate: Boolean) {
        stopAlertLocked()
        try {
            val uri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ringtone = RingtoneManager.getRingtone(context, uri)?.apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                } else {
                    @Suppress("DEPRECATION")
                    streamType = android.media.AudioManager.STREAM_RING
                }
                play()
            }
        } catch (error: Exception) {
            Log.w(TAG, "ringtone unavailable: ${error.message}")
            ringtone = null
        }
        if (vibrate) {
            try {
                vibrator = vibrator()
                val pattern = longArrayOf(0, 1000, 1000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createWaveform(pattern, 0),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(pattern, 0)
                }
            } catch (error: Exception) {
                Log.w(TAG, "vibration unavailable: ${error.message}")
            }
        }
        // Re-play the ringtone when each pass ends (Ringtone.play is one-shot).
        val loop = object : Runnable {
            override fun run() {
                val current = ringtone ?: return
                try {
                    if (!current.isPlaying) {
                        current.play()
                    }
                } catch (error: Exception) {
                    Log.w(TAG, "ringtone replay failed: ${error.message}")
                    return
                }
                mainHandler.postDelayed(this, 2500)
            }
        }
        loopRunnable = loop
        mainHandler.postDelayed(loop, 2500)
        Log.d(TAG, "fake-call alert started (vibrate=$vibrate)")
    }

    @Synchronized
    private fun stopAlert() {
        stopAlertLocked()
        Log.d(TAG, "fake-call alert stopped")
    }

    private fun stopAlertLocked() {
        loopRunnable?.let(mainHandler::removeCallbacks)
        loopRunnable = null
        try {
            ringtone?.takeIf { it.isPlaying }?.stop()
        } catch (error: Exception) {
            Log.w(TAG, "ringtone stop failed: ${error.message}")
        }
        ringtone = null
        try {
            vibrator?.cancel()
        } catch (error: Exception) {
            Log.w(TAG, "vibrator cancel failed: ${error.message}")
        }
        vibrator = null
    }

    @Suppress("DEPRECATION")
    private fun vibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as? VibratorManager
            manager?.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    companion object {
        private const val TAG = "FakeCallRingtone"
        const val CHANNEL = "guardianher/fake_call"
    }
}
