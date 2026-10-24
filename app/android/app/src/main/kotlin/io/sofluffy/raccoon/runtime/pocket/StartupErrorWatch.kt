package io.sofluffy.raccoon.runtime.pocket

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

/**
 * Watches a project's first seconds for an unhandled Dart exception. One
 * thrown before the project's first frame leaves RR Pocket's last frame on
 * screen with nothing behind it, so the phone looks frozen; [onError] gets
 * the error to show instead. Reads this process's own log, where Dart's
 * unhandled errors land under the `flutter` tag, from [since].
 */
class StartupErrorWatch(
    private val since: Date,
    private val windowMs: Long = 15_000L,
    private val onError: (String) -> Unit,
) {
    @Volatile
    private var process: Process? = null

    fun start() {
        thread(isDaemon = true, name = "rr-pocket-startup-errors") {
            val logcat = ProcessBuilder(
                "logcat", "-v", "raw", "-T",
                SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(since),
                "--pid=${android.os.Process.myPid()}", "flutter:E", "*:S",
            ).redirectErrorStream(true).start()
            process = logcat
            // The window closes the log, which ends the reading below.
            thread(isDaemon = true) {
                Thread.sleep(windowMs)
                stop()
            }
            try {
                logcat.inputStream.bufferedReader().useLines { lines ->
                    startupError(lines)?.let(onError)
                }
            } catch (_: Exception) {
            } finally {
                stop()
            }
        }
    }

    fun stop() {
        process?.destroy()
        process = null
    }

    companion object {
        private const val MARK = "Unhandled Exception: "
        private const val MAX_LENGTH = 600

        /**
         * The first unhandled exception in [lines]: its message and the lines
         * that follow it up to the stack trace, where the cause often is
         * (Isar's version mismatch comes second). Null when none comes.
         */
        fun startupError(lines: Sequence<String>): String? {
            val found = mutableListOf<String>()
            for (line in lines) {
                if (found.isEmpty()) {
                    val at = line.indexOf(MARK)
                    if (at >= 0) found += line.substring(at + MARK.length).trim()
                    continue
                }
                val text = line.trim()
                if (text.isEmpty() || text.startsWith("#") || found.size == 3) break
                found += text
            }
            if (found.isEmpty()) return null
            val message = found.joinToString("\n")
            if (message.length <= MAX_LENGTH) return message
            return message.substring(0, MAX_LENGTH).trimEnd() + "…"
        }
    }
}
