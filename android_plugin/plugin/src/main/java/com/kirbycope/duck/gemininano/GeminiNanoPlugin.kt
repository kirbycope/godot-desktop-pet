package com.kirbycope.duck.gemininano

import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Gemini Nano for the duck: Android's on-device model, run by AICore on the phone's NPU, through
 * ML Kit's GenAI Prompt API. GDScript (local_brain.gd) calls prepare(), then ask() for each turn,
 * and hears back through signals:
 *
 *   nano_status(state, detail)  "ready", "downloading" (bytes so far), "unavailable" or "failed"
 *   nano_chunk(request, text)   a piece of the answer as it is written
 *   nano_done(request, text)    the whole answer
 *   nano_failed(request, why)
 */
class GeminiNanoPlugin(godot: Godot) : GodotPlugin(godot) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var model: GenerativeModel? = null
    private var answering: Job? = null

    override fun getPluginName() = BuildConfig.GODOT_PLUGIN_NAME

    override fun getPluginSignals() = setOf(
        SignalInfo("nano_status", String::class.java, String::class.java),
        SignalInfo("nano_chunk", Integer::class.java, String::class.java),
        SignalInfo("nano_done", Integer::class.java, String::class.java),
        SignalInfo("nano_failed", Integer::class.java, String::class.java),
    )

    /** Finds out whether this phone has Gemini Nano, downloads it if it can, and warms it up. */
    @UsedByGodot
    fun prepare() {
        scope.launch {
            try {
                val client = model ?: Generation.getClient().also { model = it }
                when (client.checkStatus()) {
                    FeatureStatus.AVAILABLE -> ready(client)
                    FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> download(client)
                    else -> emitSignal("nano_status", "unavailable", "AICore says this phone has no Gemini Nano")
                }
            } catch (e: Exception) {
                Log.e(pluginName, "Gemini Nano did not start", e)
                emitSignal("nano_status", "failed", e.message ?: e.javaClass.simpleName)
            }
        }
    }

    private suspend fun download(client: GenerativeModel) {
        client.download().collect { status ->
            when (status) {
                is DownloadStatus.DownloadStarted -> emitSignal("nano_status", "downloading", "started")
                is DownloadStatus.DownloadProgress -> emitSignal("nano_status", "downloading", "%.0f MB".format(status.totalBytesDownloaded / 1e6))
                DownloadStatus.DownloadCompleted -> ready(client)
                is DownloadStatus.DownloadFailed -> emitSignal("nano_status", "failed", status.e.message ?: "the download failed")
            }
        }
    }

    private suspend fun ready(client: GenerativeModel) {
        client.warmup()
        emitSignal("nano_status", "ready", "")
    }

    /** Answers `prompt` as request `request`, a piece at a time. */
    @UsedByGodot
    fun ask(request: Int, prompt: String, temperature: Float) {
        val client = model
        if (client == null) {
            emitSignal("nano_failed", request, "Gemini Nano is not ready")
            return
        }
        answering?.cancel()
        answering = scope.launch {
            val answer = StringBuilder()
            try {
                val asked = generateContentRequest(TextPart(prompt)) {
                    this.temperature = temperature
                    topK = 16
                    maxOutputTokens = 256
                }
                client.generateContentStream(asked).collect { chunk ->
                    val text = chunk.candidates.firstOrNull()?.text ?: ""
                    if (text.isNotEmpty()) {
                        answer.append(text)
                        emitSignal("nano_chunk", request, text)
                    }
                }
                emitSignal("nano_done", request, answer.toString())
            } catch (e: Exception) {
                Log.e(pluginName, "Gemini Nano did not answer", e)
                emitSignal("nano_failed", request, e.message ?: e.javaClass.simpleName)
            }
        }
    }

    /** Lets go of the model. prepare() starts it again. */
    @UsedByGodot
    fun release() {
        answering?.cancel()
        model?.close()
        model = null
    }

    override fun onMainDestroy() {
        release()
        scope.cancel()
        super.onMainDestroy()
    }
}
