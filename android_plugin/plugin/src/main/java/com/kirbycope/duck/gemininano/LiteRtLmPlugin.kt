package com.kirbycope.duck.gemininano

import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.ThinkingConfig
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Google's LiteRT-LM for the duck: a .litertlm model, such as Gemma 4 E2B, run on the phone's CPU
 * or GPU. GDScript (local_brain.gd) downloads the model, calls load(), then ask() for each turn,
 * and hears back through signals:
 *
 *   litert_status(load, state, detail)  for load() number `load`: "ready" (the seconds the engine
 *                                 took to start) or "failed" (why)
 *   litert_chunk(request, text)   a piece of the answer as it is written
 *   litert_done(request, text, benchmark)  the whole answer, and LiteRT-LM's own timings as JSON
 *   litert_failed(request, why)
 */
class LiteRtLmPlugin(godot: Godot) : GodotPlugin(godot) {

    // One thread for the engine: loading, answering and closing never overlap.
    private val worker = Executors.newSingleThreadExecutor()
    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var system: String = ""

    override fun getPluginName() = "LiteRtLm"

    override fun getPluginSignals() = setOf(
        SignalInfo("litert_status", Integer::class.java, String::class.java, String::class.java),
        SignalInfo("litert_chunk", Integer::class.java, String::class.java),
        SignalInfo("litert_done", Integer::class.java, String::class.java, String::class.java),
        SignalInfo("litert_failed", Integer::class.java, String::class.java),
    )

    /**
     * Starts the engine on `modelPath` with `backend` ("CPU" or "GPU"), and a conversation with
     * `systemPrompt` and `historyJson` ([{role, content}]). `cacheDir` keeps what the GPU compiles,
     * which makes the next start quicker. `load` comes back with the result, so a late answer to a
     * load since stopped can be told apart.
     */
    @OptIn(ExperimentalApi::class)
    @UsedByGodot
    fun load(load: Int, modelPath: String, backend: String, cacheDir: String, systemPrompt: String, historyJson: String) {
        worker.execute {
            try {
                closeEngine()
                ExperimentalFlags.enableBenchmark = true
                val started = System.nanoTime()
                val config = EngineConfig(
                    modelPath = modelPath,
                    backend = if (backend == "GPU") Backend.GPU() else Backend.CPU(),
                    cacheDir = cacheDir.ifEmpty { null },
                )
                val created = Engine(config)
                created.initialize()
                engine = created
                system = systemPrompt
                conversation = created.createConversation(conversationConfig(historyJson))
                emitSignal("litert_status", load, "ready", String.format(java.util.Locale.US, "%.3f", (System.nanoTime() - started) / 1e9))
            } catch (e: Throwable) {
                Log.e(pluginName, "LiteRT-LM did not start", e)
                closeEngine()
                emitSignal("litert_status", load, "failed", e.message ?: e.javaClass.simpleName)
            }
        }
    }

    /** Starts the conversation again from `historyJson`, with the same model. */
    @UsedByGodot
    fun reset(systemPrompt: String, historyJson: String) {
        worker.execute {
            val loaded = engine ?: return@execute
            try {
                conversation?.close()
                system = systemPrompt
                conversation = loaded.createConversation(conversationConfig(historyJson))
            } catch (e: Throwable) {
                Log.e(pluginName, "LiteRT-LM could not start the conversation again", e)
            }
        }
    }

    /** Answers `line` as request `request`, a piece at a time. */
    @OptIn(ExperimentalApi::class)
    @UsedByGodot
    fun ask(request: Int, line: String) {
        worker.execute {
            val talking = conversation
            if (talking == null) {
                emitSignal("litert_failed", request, "LiteRT-LM is not ready")
                return@execute
            }
            val answer = StringBuilder()
            try {
                talking.sendMessageAsync(Message.user(line), object : MessageCallback {
                    override fun onMessage(message: Message) {
                        val text = message.toString()
                        if (text.isNotEmpty()) {
                            answer.append(text)
                            emitSignal("litert_chunk", request, text)
                        }
                    }

                    override fun onDone() {
                        emitSignal("litert_done", request, answer.toString(), benchmark(talking))
                    }

                    override fun onError(throwable: Throwable) {
                        emitSignal("litert_failed", request, throwable.message ?: throwable.javaClass.simpleName)
                    }
                })
            } catch (e: Throwable) {
                Log.e(pluginName, "LiteRT-LM did not answer", e)
                emitSignal("litert_failed", request, e.message ?: e.javaClass.simpleName)
            }
        }
    }

    /** Stops the answer being written. */
    @UsedByGodot
    fun stop_answer() {
        try {
            conversation?.cancelProcess()
        } catch (e: Throwable) {
            Log.w(pluginName, "Nothing to stop", e)
        }
    }

    /** Lets go of the model and its memory. load() starts it again. */
    @UsedByGodot
    fun release() {
        stop_answer()
        worker.execute { closeEngine() }
    }

    override fun onMainDestroy() {
        release()
        worker.shutdown()
        super.onMainDestroy()
    }

    private fun conversationConfig(historyJson: String): ConversationConfig {
        val history = mutableListOf<Message>()
        val messages = JSONArray(historyJson.ifEmpty { "[]" })
        for (i in 0 until messages.length()) {
            val message = messages.getJSONObject(i)
            val text = message.optString("content")
            when (message.optString("role")) {
                "user" -> history.add(Message.user(text))
                "assistant" -> history.add(Message.model(text))
            }
        }
        return ConversationConfig(
            systemInstruction = Contents.of(system),
            initialMessages = history,
            // Gemma 4 can think aloud first, which reads badly when spoken.
            thinkingConfig = ThinkingConfig(enableThinking = false),
            maxOutputToken = 512,
        )
    }

    /** LiteRT-LM's own timings for the last answer, as JSON; "{}" when it has none. */
    @OptIn(ExperimentalApi::class)
    private fun benchmark(talking: Conversation): String = try {
        val info = talking.getBenchmarkInfo()
        JSONObject()
            .put("init_s", info.initTimeInSecond)
            .put("native_ttft_s", info.timeToFirstTokenInSecond)
            .put("prefill_tokens", info.lastPrefillTokenCount)
            .put("decode_tokens", info.lastDecodeTokenCount)
            .put("prefill_tps", info.lastPrefillTokensPerSecond)
            .put("decode_tps", info.lastDecodeTokensPerSecond)
            .toString()
    } catch (e: Throwable) {
        Log.w(pluginName, "No benchmark info", e)
        "{}"
    }

    private fun closeEngine() {
        try {
            conversation?.close()
        } catch (e: Throwable) {
            Log.w(pluginName, "Conversation did not close", e)
        }
        conversation = null
        try {
            engine?.close()
        } catch (e: Throwable) {
            Log.w(pluginName, "Engine did not close", e)
        }
        engine = null
    }
}
