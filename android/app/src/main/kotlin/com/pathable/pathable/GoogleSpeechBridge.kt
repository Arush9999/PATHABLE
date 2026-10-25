package com.pathable.pathable

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Binds Android speech recognition to a Google RecognitionService.
 *
 * [SpeechRecognizer.createSpeechRecognizer] with no component uses
 * Settings.Secure.VOICE_RECOGNITION_SERVICE, which on a Galaxy is often Samsung.
 * This bridge passes a Google [ComponentName] and never falls back to Samsung.
 * The legacy Google app class is used only when the system lists it. Android 16
 * does not, so the bind target is Speech Services by Google.
 */
class GoogleSpeechBridge(
    private val activity: Activity,
    private val requestRecordAudio: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var partialSink: EventChannel.EventSink? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingStart: (() -> Unit)? = null
    private var latestTranscript = ""
    private var boundComponent: ComponentName? = null
    private var timeoutRunnable: Runnable? = null
    private var endFallback: Runnable? = null
    private var ending = false
    private var startedAt = 0L

    fun attach(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        val methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel.setMethodCallHandler(::onMethodCall)
        channel = methodChannel
        EventChannel(messenger, PARTIALS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    partialSink = events
                }

                override fun onCancel(arguments: Any?) {
                    partialSink = null
                }
            },
        )
        val component = findGoogleComponent()
        if (component == null) {
            Log.i(TAG, "Google recognizer is not installed")
        } else {
            Log.i(TAG, "Google recognizer component: ${component.flattenToString()}")
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        partialSink = null
        if (pendingResult != null) {
            deliver(
                engineAvailable = false,
                message = "Speech recognition stopped.",
            )
        } else {
            releaseRecognizer()
        }
    }

    fun onRecordAudioPermission(granted: Boolean) {
        val start = pendingStart
        pendingStart = null
        if (pendingResult == null) return
        if (!granted || start == null) {
            deliver(engineAvailable = false, message = MIC_DENIED)
            return
        }
        start()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> {
                val timeoutMs = (call.argument<Number>("timeoutMs") ?: DEFAULT_TIMEOUT_MS)
                    .toLong()
                    .coerceIn(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
                if (pendingResult != null) {
                    deliver(engineAvailable = true, message = NO_SPEECH)
                }
                pendingResult = result
                latestTranscript = ""
                boundComponent = null
                ending = false
                startListen(timeoutMs)
            }
            "stop" -> {
                pendingStart = null
                if (pendingResult != null) {
                    deliverHeardOrEmpty()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startListen(timeoutMs: Long) {
        val component = findGoogleComponent()
        if (component == null) {
            Log.i(TAG, "Google recognizer is not installed")
            deliver(engineAvailable = false, message = GOOGLE_MISSING)
            return
        }
        boundComponent = component
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            pendingStart = { begin(component, timeoutMs) }
            requestRecordAudio()
            return
        }
        begin(component, timeoutMs)
    }

    private fun begin(component: ComponentName, timeoutMs: Long) {
        if (pendingResult == null) return
        try {
            releaseRecognizer()
            Log.i(TAG, "Binding speech recognizer to ${component.flattenToString()}")
            val recognizer = SpeechRecognizer.createSpeechRecognizer(activity, component)
            speechRecognizer = recognizer
            recognizer.setRecognitionListener(listener)
            recognizer.startListening(recognitionIntent())
            startedAt = SystemClock.elapsedRealtime()
            val timeout = Runnable { requestEnd() }
            timeoutRunnable = timeout
            handler.postDelayed(timeout, timeoutMs)
        } catch (error: Exception) {
            Log.e(TAG, "Unable to bind ${component.flattenToString()}", error)
            deliver(engineAvailable = false, message = GOOGLE_MISSING)
        }
    }

    private fun recognitionIntent(): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
            // Ask Google to prefer the product name over “hey possible”.
            putStringArrayListExtra(
                "android.speech.extra.BIASING_STRINGS",
                arrayListOf("PathAble", "Hey PathAble"),
            )
            // End after a short pause, while the caller timeout remains the cap.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3_000)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                3_000,
            )
        }
    }

    private fun requestEnd() {
        if (pendingResult == null || ending) return
        ending = true
        try {
            speechRecognizer?.stopListening()
        } catch (_: Exception) {
            deliverHeardOrEmpty()
            return
        }
        scheduleEndFallback(800)
    }

    private fun scheduleEndFallback(delayMs: Long) {
        endFallback?.let { handler.removeCallbacks(it) }
        val fallback = Runnable {
            if (pendingResult != null) deliverHeardOrEmpty()
        }
        endFallback = fallback
        handler.postDelayed(fallback, delayMs)
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}

        override fun onBeginningOfSpeech() {}

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            if (pendingResult == null) return
            scheduleEndFallback(1200)
        }

        override fun onError(error: Int) {
            if (pendingResult == null) return
            Log.i(TAG, "Google recognizer error $error")
            if (latestTranscript.isNotBlank()) {
                deliver(engineAvailable = true, message = null)
                return
            }
            when (error) {
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    deliver(engineAvailable = false, message = MIC_DENIED)
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER,
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
                -> deliver(engineAvailable = false, message = NETWORK)
                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                SpeechRecognizer.ERROR_TOO_MANY_REQUESTS,
                -> {
                    // A failure in the first moment means the bind was rejected.
                    // Retrying immediately makes Android return error 10 in a loop.
                    val elapsed = if (startedAt == 0L) {
                        Long.MAX_VALUE
                    } else {
                        SystemClock.elapsedRealtime() - startedAt
                    }
                    if (elapsed < 800 || error == SpeechRecognizer.ERROR_TOO_MANY_REQUESTS) {
                        val message = if (error == SpeechRecognizer.ERROR_TOO_MANY_REQUESTS) {
                            BUSY
                        } else {
                            GOOGLE_MISSING
                        }
                        deliver(engineAvailable = false, message = message)
                    } else {
                        deliverHeardOrEmpty()
                    }
                }
                else -> deliverHeardOrEmpty()
            }
        }

        override fun onResults(results: Bundle?) {
            readResults(results, predicting = false)
            if (pendingResult != null) deliverHeardOrEmpty()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            readResults(partialResults, predicting = true)
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun readResults(bundle: Bundle?, predicting: Boolean) {
        val phrases = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val stable = phrases?.firstOrNull { it.isNotBlank() }?.trim().orEmpty()
        val unstable = if (predicting) {
            bundle?.getString(UNSTABLE_TEXT)?.trim().orEmpty()
        } else {
            ""
        }
        if (stable.isNotBlank()) {
            latestTranscript = stable
        }
        val shown = listOf(stable, unstable).filter { it.isNotEmpty() }.joinToString(" ").trim()
        if (shown.isNotEmpty()) {
            emitPartial(shown)
        }
    }

    private fun emitPartial(text: String) {
        val sink = partialSink ?: return
        try {
            sink.success(text)
        } catch (error: Exception) {
            Log.w(TAG, "Could not send speech prediction", error)
        }
    }

    private fun deliverHeardOrEmpty() {
        if (latestTranscript.isNotBlank()) {
            deliver(engineAvailable = true, message = null)
        } else {
            deliver(engineAvailable = true, message = NO_SPEECH)
        }
    }

    private fun deliver(engineAvailable: Boolean, message: String?) {
        val result = pendingResult ?: return
        pendingResult = null
        pendingStart = null
        ending = false
        val transcript = latestTranscript.trim().ifEmpty { null }
        val payload = hashMapOf<String, Any?>(
            "engineAvailable" to engineAvailable,
            "transcript" to transcript,
            "message" to if (transcript == null) message else null,
            "component" to boundComponent?.flattenToString(),
        )
        latestTranscript = ""
        releaseRecognizer()
        try {
            result.success(payload)
        } catch (error: Exception) {
            Log.w(TAG, "Could not deliver speech result", error)
        }
    }

    private fun releaseRecognizer() {
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        timeoutRunnable = null
        endFallback?.let { handler.removeCallbacks(it) }
        endFallback = null
        val recognizer = speechRecognizer
        speechRecognizer = null
        if (recognizer == null) return
        try {
            recognizer.cancel()
        } catch (_: Exception) {
        }
        try {
            recognizer.destroy()
        } catch (_: Exception) {
        }
    }

    private fun findGoogleComponent(): ComponentName? {
        // The system server only accepts components returned by this query.
        // Binding anything else fails with "serviceComponent is not RecognitionService".
        val services = queryRecognitionServices().mapNotNull { it.serviceInfo }.filter { it.enabled }
        services.forEach { info ->
            Log.i(TAG, "RecognitionService candidate: ${info.packageName}/${info.name}")
        }
        val preferred = services.firstOrNull {
            it.packageName == GOOGLE_PACKAGE && it.name == GOOGLE_CLASS
        }
        if (preferred != null) {
            return ComponentName(preferred.packageName, preferred.name)
        }
        val googleApp = services.firstOrNull { it.packageName == GOOGLE_PACKAGE }
        if (googleApp != null) {
            return ComponentName(googleApp.packageName, googleApp.name)
        }
        // Android 16 still ships the legacy class inside the Google app, but the
        // speech manager does not treat it as a RecognitionService. Speech
        // Services by Google is the recognizer it will bind. Samsung is never used.
        val speechServices = services.firstOrNull {
            it.packageName == SPEECH_SERVICES_PACKAGE && it.name == SPEECH_SERVICES_CLASS
        } ?: services.firstOrNull { it.packageName == SPEECH_SERVICES_PACKAGE }
        if (speechServices != null) {
            Log.i(TAG, "Legacy GoogleRecognitionService is not a resolvable RecognitionService")
            return ComponentName(speechServices.packageName, speechServices.name)
        }
        return null
    }

    private fun queryRecognitionServices() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        activity.packageManager.queryIntentServices(
            Intent(RecognitionService.SERVICE_INTERFACE),
            PackageManager.ResolveInfoFlags.of(0),
        )
    } else {
        @Suppress("DEPRECATION")
        activity.packageManager.queryIntentServices(
            Intent(RecognitionService.SERVICE_INTERFACE),
            0,
        )
    }

    companion object {
        const val CHANNEL = "pathable/google_speech"
        const val PARTIALS = "pathable/google_speech/partials"
        private const val UNSTABLE_TEXT = "android.speech.extra.UNSTABLE_TEXT"
        const val GOOGLE_PACKAGE = "com.google.android.googlequicksearchbox"
        const val GOOGLE_CLASS =
            "com.google.android.voicesearch.serviceapi.GoogleRecognitionService"
        const val SPEECH_SERVICES_PACKAGE = "com.google.android.tts"
        const val SPEECH_SERVICES_CLASS =
            "com.google.android.apps.speech.tts.googletts.service.GoogleTTSRecognitionService"
        private const val TAG = "PathAbleSpeech"
        private const val DEFAULT_TIMEOUT_MS = 8_000L
        private const val MIN_TIMEOUT_MS = 1_000L
        private const val MAX_TIMEOUT_MS = 120_000L
        private const val GOOGLE_MISSING =
            "Install or enable the Google app, including Speech Services by Google, to use speech recognition. Type the report instead."
        private const val MIC_DENIED =
            "Allow microphone access so PathAble can hear you. Type the note if you prefer."
        private const val NO_SPEECH =
            "No speech was captured. Try again, or type the note."
        private const val NETWORK =
            "Google speech recognition could not reach Google. Check your connection, or type the note."
        private const val BUSY =
            "Google speech recognition is busy. Wait a moment, then say Hey Pathable again."
    }
}
