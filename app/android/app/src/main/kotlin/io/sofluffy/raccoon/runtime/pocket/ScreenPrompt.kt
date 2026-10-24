package io.sofluffy.raccoon.runtime.pocket

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import io.sofluffy.raccoon.runtime.pocket.PocketServer.PairAnswer

/**
 * Asks "Pair with <computer>?" on RR Pocket's own screen, through the Dart
 * side's `askPair`. Only while that screen shows: not while a project runs in
 * the engine (its Dart code has replaced RR Pocket's) and not while the app is
 * in the background, since nobody could answer then. Its state lives on the
 * main thread; the server's thread only posts to it.
 */
class ScreenPrompt : PocketServer.PairPrompt {
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var showing = false
    private var asked = 0

    /** Set by `runInView`; a new engine (after /stop) clears it. */
    @Volatile
    var projectRunning = false

    /** A new engine runs RR Pocket's own Dart code. Main thread. */
    fun attach(channel: MethodChannel) {
        this.channel = channel
        projectRunning = false
    }

    /** Main thread. */
    fun detach(channel: MethodChannel) {
        if (this.channel === channel) this.channel = null
    }

    /** Whether the activity is in front. Main thread. */
    fun setShowing(showing: Boolean) {
        this.showing = showing
    }

    override fun ask(computer: String, answer: (PairAnswer) -> Unit) {
        main.post {
            val channel = channel
            if (channel == null || !showing || projectRunning) {
                answer(PairAnswer.UNAVAILABLE)
                return@post
            }
            asked++
            channel.invokeMethod(
                "askPair",
                mapOf("id" to asked, "computer" to computer),
                object : MethodChannel.Result {
                    override fun success(result: Any?) =
                        answer(if (result == true) PairAnswer.ALLOWED else PairAnswer.REFUSED)

                    override fun error(code: String, message: String?, details: Any?) =
                        answer(PairAnswer.UNAVAILABLE)

                    // A project's Dart code, which has no such handler.
                    override fun notImplemented() = answer(PairAnswer.UNAVAILABLE)
                },
            )
        }
    }

    override fun withdraw() {
        main.post { channel?.invokeMethod("withdrawPair", mapOf("id" to asked)) }
    }
}
