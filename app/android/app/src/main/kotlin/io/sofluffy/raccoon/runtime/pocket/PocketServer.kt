package io.sofluffy.raccoon.runtime.pocket

import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.GZIPInputStream
import kotlin.concurrent.thread
import org.json.JSONException
import org.json.JSONObject

/**
 * What a paired computer drives, over HTTPS on the LAN ([secure]: TLS with
 * the phone's own certificate, which the computer pinned when it paired):
 *
 *  GET  /hello            who this is: versions, plugins, the VM relay's port
 *  POST /bundle/begin     start a new bundle
 *  PUT  /bundle/<path>    one file of it (gzip allowed)
 *  POST /bundle/commit    make it the one /run starts
 *  POST /run              restart the engine into the bundle
 *  POST /stop             back to RR Pocket's own screen
 *  GET  /logs             the running app's `print` output, as it comes
 *  POST /pair             ask the user to give a computer the code, or
 *                         redeem a QR code the user allowed
 *
 * Every request carries `Authorization: Bearer <pairing code>`, except
 * `/pair`: a computer that has no code yet asks for it there, and gets it
 * only when the user taps Allow on the phone, or shows the token of a QR
 * code they allowed (docs/pairing.md).
 */
class PocketServer(
    private val port: Int,
    private val code: String,
    /** Whether a code offered by a sender ([senderOf]) is right. */
    private val accepts: (String?, String) -> Boolean,
    /** Whether a sender is shut out for guessing ([CodeGate]). */
    private val lockedOut: (String) -> Boolean = { false },
    private val root: File,
    private val hello: () -> String,
    private val actions: Actions,
    private val prompt: PairPrompt,
    /** Wraps each accepted connection: TLS, or nothing in some tests. */
    private val secure: (Socket) -> Socket,
    private val offers: PairOffers = PairOffers(),
    private val pairTimeoutMs: Long = 60_000L,
    private val quietMs: Long = 30_000L,
    private val readTimeoutMs: Int = 30_000,
    private val limit: ConnectionLimit = ConnectionLimit(total = 32, perSender = 16),
    private val now: () -> Long = System::currentTimeMillis,
    /** The running app's log, from now on; logcat on a phone. */
    private val openLog: () -> Process = ::logcat,
) {
    @Volatile
    private var quietUntil = 0L

    interface Actions {
        /** Starts [bundle]; returns the VM service's path, `/<auth>/`. */
        fun run(bundle: File): String

        fun stop()
    }

    /** RR Pocket's own screen asking "Pair with <computer>?". */
    interface PairPrompt {
        /**
         * Shows the question, with the address it came [from], and calls
         * [answer] once, from any thread: right away with
         * [PairAnswer.UNAVAILABLE] when nobody could answer.
         */
        fun ask(computer: String, from: String, answer: (PairAnswer) -> Unit)

        /** Takes the question down: nobody answered in time. */
        fun withdraw()
    }

    enum class PairAnswer { ALLOWED, REFUSED, UNAVAILABLE }

    /** Set while a /pair request waits for the user; one at a time. */
    private val asking = AtomicBoolean(false)

    /** The /logs streams open: a session's ends when the next starts. */
    private val logs = ConcurrentHashMap.newKeySet<Process>()

    private val staging = File(root, "staging")
    private val bundle = File(root, "bundle")

    /** Listens on [port] (0 for any) and returns the port it got. */
    fun start(): Int {
        val server = ServerSocket()
        server.reuseAddress = true
        server.bind(InetSocketAddress(port))
        thread(isDaemon = true, name = "rr-pocket-control") {
            server.use {
                while (true) {
                    val client = server.accept()
                    val sender = senderOf(client.inetAddress)
                    if (!limit.take(sender)) {
                        client.close()
                        continue
                    }
                    thread(isDaemon = true) {
                        try {
                            serve(client, sender)
                        } finally {
                            limit.release(sender)
                        }
                    }
                }
            }
        }
        return server.localPort
    }

    /**
     * One connection, until it ends. Anything that goes wrong with it, a
     * reset mid-request included, ends it and only it: an exception out of
     * this thread would end RR Pocket, and anyone on the Wi-Fi can connect.
     * A connection that sends nothing for [readTimeoutMs] ends too.
     */
    private fun serve(socket: Socket, sender: String) {
        try {
            socket.soTimeout = readTimeoutMs
            secure(socket).use {
                val input = BufferedInputStream(it.getInputStream())
                val output = it.getOutputStream()
                val from = socket.inetAddress?.hostAddress ?: "an unknown address"
                while (true) {
                    val request = Request.read(input) ?: return
                    if (request.method == "GET" && request.path == "/logs") {
                        refusal(request, sender)?.let { refused -> return refused.write(output, close = true) }
                        return streamLogs(output)
                    }
                    val response = try {
                        respond(request, from, sender)
                    } catch (e: Exception) {
                        Response(500, error(e.message ?: e.toString()))
                    }
                    // Reading the rest of a refused request, or of one too
                    // large to read, would let anyone keep this thread busy.
                    val close = request.header("connection") == "close" ||
                        response.status == 401 || response.status == 429 ||
                        request.unread > MAX_DRAIN
                    if (!close) request.drain()
                    response.write(output, close)
                    if (close) return
                }
            }
        } catch (_: Exception) {
        } finally {
            // A failed handshake never reached use().
            socket.close()
        }
    }

    /** Null when [request] shows the code; otherwise what to answer. */
    private fun refusal(request: Request, sender: String): Response? {
        if (accepts(request.header("authorization")?.removePrefix("Bearer "), sender)) return null
        if (lockedOut(sender)) {
            return Response(429, error("too many wrong pairing codes from this computer; wait 5 minutes, then pair again"))
        }
        return Response(401, error("wrong pairing code"))
    }

    /** Ends every /logs stream: the session they belong to is over. */
    private fun endLogs() {
        for (log in logs.toList()) log.destroy()
    }

    /**
     * The running app's `print` output for as long as the computer listens,
     * or until the next /run or /stop. A computer that went away (asleep, off
     * the Wi-Fi) is noticed only on a write, and a quiet app writes nothing:
     * without the end at the next session, each such stream would keep a
     * thread, a logcat and one of the sender's connections for good.
     */
    private fun streamLogs(output: OutputStream) {
        output.write(
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n"
                .toByteArray(),
        )
        output.flush()
        val log = openLog()
        logs += log
        try {
            val reader = log.inputStream.bufferedReader()
            reader.readLine() // logged before this stream began
            while (true) {
                val line = reader.readLine() ?: break
                output.write((line + "\n").toByteArray())
                // One TLS record per burst, not per line, for chatty apps.
                if (!reader.ready()) output.flush()
            }
        } catch (_: Exception) {
        } finally {
            logs -= log
            log.destroy()
        }
    }

    private fun respond(request: Request, from: String, sender: String): Response {
        if (request.method == "POST" && request.path == "/pair") return pair(request, from)
        refusal(request, sender)?.let { return it }
        val path = request.path
        return when {
            request.method == "GET" && path == "/hello" -> Response(200, hello())
            request.method == "POST" && path == "/bundle/begin" -> {
                staging.deleteRecursively()
                staging.mkdirs()
                Response(200, ok())
            }
            request.method == "PUT" && path.startsWith("/bundle/") -> receive(request)
            request.method == "POST" && path == "/bundle/commit" -> {
                if (!File(staging, "kernel_blob.bin").exists()) {
                    return Response(400, error("the bundle has no kernel_blob.bin"))
                }
                bundle.deleteRecursively()
                if (!staging.renameTo(bundle)) return Response(500, error("could not keep the bundle"))
                Response(200, ok())
            }
            request.method == "POST" && path == "/run" -> {
                if (!File(bundle, "kernel_blob.bin").exists()) {
                    return Response(409, error("no bundle installed"))
                }
                endLogs()
                val vmPath = actions.run(bundle)
                Response(200, """{"vmPath":${quote(vmPath)}}""")
            }
            request.method == "POST" && path == "/stop" -> {
                endLogs()
                actions.stop()
                Response(200, ok())
            }
            else -> Response(404, error("no ${request.method} $path"))
        }
    }

    /**
     * Holds the request until the user answers, or [pairTimeoutMs] passes.
     * After a no, or no answer, the phone stays quiet for [quietMs]: someone
     * on the Wi-Fi asking again and again can't keep the question on screen
     * until a tired tap allows it.
     */
    private fun pair(request: Request, from: String): Response {
        val body = pairBody(request)
        val token = body?.optString("token").orEmpty()
        if (token.isNotEmpty()) {
            if (!offers.redeem(token)) {
                return Response(403, error("this pairing QR code has expired or was used; show a new one and scan it again"))
            }
            return Response(200, """{"code":${quote(code)}}""")
        }
        val computer = body?.let(::computerName)
            ?: return Response(400, error("send {\"computer\": \"<this computer's name>\"}"))
        if (now() < quietUntil) {
            return Response(429, error("the phone said no a moment ago; try again in a little while"))
        }
        if (!asking.compareAndSet(false, true)) {
            return Response(409, error("another computer is waiting for an answer on the phone; try again in a minute"))
        }
        try {
            val answers = ArrayBlockingQueue<PairAnswer>(1)
            prompt.ask(computer, from) { answers.offer(it) }
            return when (answers.poll(pairTimeoutMs, TimeUnit.MILLISECONDS)) {
                PairAnswer.ALLOWED -> Response(200, """{"code":${quote(code)}}""")
                PairAnswer.REFUSED -> {
                    quietUntil = now() + quietMs
                    Response(403, error("pairing refused on the phone"))
                }
                PairAnswer.UNAVAILABLE -> Response(
                    409,
                    error("RR Pocket's screen is not showing on the phone (a project may be running); open RR Pocket, then try again"),
                )
                null -> {
                    prompt.withdraw()
                    quietUntil = now() + quietMs
                    Response(408, error("no answer on the phone"))
                }
            }
        } finally {
            asking.set(false)
        }
    }

    /** /pair's JSON body; null when it is too large or not an object. */
    private fun pairBody(request: Request): JSONObject? {
        val length = request.header("content-length")?.toLongOrNull() ?: 0L
        // Anyone on the network may call /pair, so it reads no large bodies.
        if (length > MAX_PAIR_BODY) return null
        return try {
            JSONObject(request.input.readBytes().decodeToString())
        } catch (_: JSONException) {
            null
        }
    }

    /** The `computer` field, trimmed and cut to [MAX_NAME] characters. */
    private fun computerName(body: JSONObject): String? {
        val name = body.optString("computer").trim()
        if (name.isEmpty()) return null
        if (name.codePointCount(0, name.length) <= MAX_NAME) return name
        return name.substring(0, name.offsetByCodePoints(0, MAX_NAME))
    }

    private fun receive(request: Request): Response {
        val relative = URLDecoder.decode(request.path.removePrefix("/bundle/"), "UTF-8")
        val target = File(staging, relative).canonicalFile
        if (!target.path.startsWith(staging.canonicalPath + File.separator)) {
            return Response(400, error("bad path $relative"))
        }
        target.parentFile?.mkdirs()
        val body = when (request.header("content-encoding")) {
            "gzip" -> GZIPInputStream(request.input)
            else -> request.input
        }
        target.outputStream().use { body.copyTo(it) }
        return Response(200, ok())
    }

    private fun ok() = """{"ok":true}"""

    private fun error(message: String) = """{"error":${quote(message)}}"""

    private class Request(
        val method: String,
        val path: String,
        private val headers: Map<String, String>,
        private val body: Bounded,
    ) {
        fun header(name: String) = headers[name]

        /** The body: at most its Content-Length, read from the connection. */
        val input: InputStream get() = body

        /** How much of the body is still unread. */
        val unread: Long get() = body.remaining

        fun drain() {
            body.skip(Long.MAX_VALUE)
        }

        companion object {
            /** Null at the end of the connection, or for what no client sends. */
            fun read(input: InputStream): Request? {
                val line = readLine(input) ?: return null
                val parts = line.split(" ")
                if (parts.size < 2) return null
                val headers = mutableMapOf<String, String>()
                while (true) {
                    val header = readLine(input) ?: return null
                    if (header.isEmpty()) break
                    if (headers.size >= MAX_HEADERS) return null
                    val colon = header.indexOf(':')
                    if (colon > 0) {
                        headers[header.substring(0, colon).trim().lowercase()] =
                            header.substring(colon + 1).trim()
                    }
                }
                val length = headers["content-length"]?.toLongOrNull() ?: 0L
                return Request(parts[0], parts[1].substringBefore('?'), headers, Bounded(input, length))
            }

            /** A line of at most [MAX_LINE] bytes; null for a longer one. */
            private fun readLine(input: InputStream): String? {
                val line = StringBuilder()
                while (true) {
                    val byte = input.read()
                    if (byte == -1) return if (line.isEmpty()) null else line.toString()
                    if (byte == '\n'.code) return line.toString().trimEnd('\r')
                    if (line.length >= MAX_LINE) return null
                    line.append(byte.toChar())
                }
            }
        }
    }

    /** At most [remaining] bytes of [input], for one request's body. */
    private class Bounded(private val input: InputStream, var remaining: Long) : InputStream() {
        override fun read(): Int {
            if (remaining <= 0) return -1
            val byte = input.read()
            if (byte >= 0) remaining--
            return byte
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (remaining <= 0) return -1
            val count = input.read(buffer, offset, minOf(length.toLong(), remaining).toInt())
            if (count > 0) remaining -= count
            return count
        }
    }

    private class Response(val status: Int, private val json: String) {
        /** With [close], says so: the server ends the connection after it. */
        fun write(output: OutputStream, close: Boolean = false) {
            val body = json.toByteArray()
            val reason = when (status) {
                200 -> "OK"
                400 -> "Bad Request"
                401 -> "Unauthorized"
                403 -> "Forbidden"
                404 -> "Not Found"
                408 -> "Request Timeout"
                409 -> "Conflict"
                429 -> "Too Many Requests"
                else -> "Error"
            }
            output.write(
                ("HTTP/1.1 $status $reason\r\nContent-Type: application/json\r\n" +
                    "Content-Length: ${body.size}\r\n" +
                    (if (close) "Connection: close\r\n" else "") + "\r\n").toByteArray(),
            )
            output.write(body)
            output.flush()
        }
    }

    companion object {
        const val MAX_NAME = 64
        private const val MAX_PAIR_BODY = 4096L
        private const val MAX_LINE = 8192
        private const val MAX_HEADERS = 64

        /** The most of an unwanted body read to keep the connection. */
        private const val MAX_DRAIN = 64 * 1024L

        /**
         * Dart's `print` lands in this process's log under the `flutter`
         * tag, and an app may read its own log. `-T 1` starts with the
         * newest line already logged, which [streamLogs] skips.
         */
        private fun logcat(): Process = ProcessBuilder(
            "logcat", "-v", "raw", "-T", "1", "--pid=${android.os.Process.myPid()}",
            "flutter:V", "*:S",
        ).redirectErrorStream(true).start()

        fun quote(text: String) =
            "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
    }
}
