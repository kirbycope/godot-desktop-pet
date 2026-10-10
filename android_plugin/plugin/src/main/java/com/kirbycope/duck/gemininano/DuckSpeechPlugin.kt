package com.kirbycope.duck.gemininano

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * The phone's own speech recognizer, for talking to the duck with no PC to write speech down.
 * Android's on-device recognizer where the phone has one, otherwise its default. GDScript calls
 * start() for each sentence and hears back through signals:
 *
 *   speech_state(state)  "listening", "hearing" once you start talking, "quiet" when nothing was
 *                        said, or "failed: <why>"
 *   speech_heard(text)   what you said, once you pause or stop() is called
 */
class DuckSpeechPlugin(godot: Godot) : GodotPlugin(godot) {

    private var recognizer: SpeechRecognizer? = null

    override fun getPluginName() = "DuckSpeech"

    override fun getPluginSignals() = setOf(
        SignalInfo("speech_state", String::class.java),
        SignalInfo("speech_heard", String::class.java),
    )

    /** Whether this phone can turn speech into text at all. */
    @UsedByGodot
    fun available(): Boolean {
        val context = activity ?: return false
        return SpeechRecognizer.isRecognitionAvailable(context) ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && SpeechRecognizer.isOnDeviceRecognitionAvailable(context))
    }

    /** Listens for one sentence in `language` (a BCP 47 tag such as "en-US"). */
    @UsedByGodot
    fun start(language: String) {
        val activity = activity ?: return
        activity.runOnUiThread {
            val recognizer = recognizer ?: create()?.also { recognizer = it }
            if (recognizer == null) {
                emitSignal("speech_state", "failed: this phone has no speech recognizer")
                return@runOnUiThread
            }
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            recognizer.startListening(intent)
        }
    }

    /** Stops listening; what was said so far still arrives through speech_heard. */
    @UsedByGodot
    fun stop() {
        activity?.runOnUiThread { recognizer?.stopListening() }
    }

    /** Stops listening and drops what was heard, and lets the recognizer go. */
    @UsedByGodot
    fun cancel() {
        activity?.runOnUiThread {
            recognizer?.destroy()
            recognizer = null
        }
    }

    private fun create(): SpeechRecognizer? {
        val context = activity ?: return null
        val made = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && SpeechRecognizer.isOnDeviceRecognitionAvailable(context) ->
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            SpeechRecognizer.isRecognitionAvailable(context) -> SpeechRecognizer.createSpeechRecognizer(context)
            else -> return null
        }
        made.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = emitSignal("speech_state", "listening")
            override fun onBeginningOfSpeech() = emitSignal("speech_state", "hearing")
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                if (text.isBlank()) emitSignal("speech_state", "quiet") else emitSignal("speech_heard", text)
            }
            override fun onError(error: Int) = emitSignal("speech_state", describe(error))
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        return made
    }

    private fun describe(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "quiet"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "failed: the microphone is not allowed for this app"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "failed: the recognizer is busy"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            "failed: this language is not downloaded for speech on this phone"
        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER ->
            "failed: the recognizer needed the network"
        else -> "failed: error $error"
    }
}
