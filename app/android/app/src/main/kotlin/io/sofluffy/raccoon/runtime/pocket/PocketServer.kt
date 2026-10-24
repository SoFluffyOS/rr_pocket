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
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.GZIPInputStream
import kotlin.concurrent.thread
import org.json.JSONException
import org.json.JSONObject

/**
 * What a paired computer drives, over plain HTTP on the LAN:
 *
 *  GET  /hello            who this is: versions, plugins, the VM relay's port
 *  POST /bundle/begin     start a new bundle
 *  PUT  /bundle/<path>    one file of it (gzip allowed)
 *  POST /bundle/commit    make it the one /run starts
 *  POST /run              restart the engine into the bundle
 *  POST /stop             back to RR Pocket's own screen
 *  GET  /logs             the running app's `print` output, as it comes
 *  POST /pair             ask the user to give a computer the code
 *
 * Every request carries `Authorization: Bearer <pairing code>`, except
 * `/pair`: a computer that has no code yet asks for it there, and gets it
 * only when the user taps Allow on the phone (docs/pairing.md).
 */
class PocketServer(
    private val port: Int,
    private val code: String,
    /** Whether a code offered by a sender ([senderOf]) is right. */
    private val accepts: (String?, String) -> Boolean,
    private val root: File,
    private val hello: () -> String,
    private val actions: Actions,
    private val prompt: PairPrompt,
    private val pairTimeoutMs: Long = 60_000L,
    private val quietMs: Long = 30_000L,
    private val readTimeoutMs: Int = 30_000,
    private val limit: ConnectionLimit = ConnectionLimit(total = 32, perSender = 16),
    private val now: () -> Long = System::currentTimeMillis,
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
            socket.use {
                val input = BufferedInputStream(it.getInputStream())
                val output = it.getOutputStream()
                val from = it.inetAddress?.hostAddress ?: "an unknown address"
                while (true) {
                    val request = Request.read(input) ?: return
                    if (request.method == "GET" && request.path == "/logs") {
                        if (authorized(request, sender)) return streamLogs(output)
                        return Response(401, error("wrong pairing code")).write(output)
                    }
                    val response = try {
                        respond(request, from, sender)
                    } catch (e: Exception) {
                        Response(500, error(e.message ?: e.toString()))
                    }
                    request.drain()
                    response.write(output)
                    if (request.header("connection") == "close") return
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun authorized(request: Request, sender: String) =
        accepts(request.header("authorization")?.removePrefix("Bearer "), sender)

    /**
     * Dart's `print` lands in this process's log under the `flutter` tag; an
     * app may read its own log, so this tails it for as long as the computer
     * listens.
     */
    private fun streamLogs(output: OutputStream) {
        output.write(
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n"
                .toByteArray(),
        )
        output.flush()
        val logcat = ProcessBuilder(
            "logcat", "-v", "raw", "-T", "1", "--pid=${android.os.Process.myPid()}",
            "flutter:V", "*:S",
        ).redirectErrorStream(true).start()
        try {
            logcat.inputStream.bufferedReader().useLines { lines ->
                // -T 1 starts with the newest line already logged.
                for (line in lines.drop(1)) {
                    output.write((line + "\n").toByteArray())
                    output.flush()
                }
            }
        } catch (_: Exception) {
        } finally {
            logcat.destroy()
        }
    }

    private fun respond(request: Request, from: String, sender: String): Response {
        if (request.method == "POST" && request.path == "/pair") return pair(request, from)
        if (!authorized(request, sender)) {
            return Response(401, error("wrong pairing code"))
        }
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
                val vmPath = actions.run(bundle)
                Response(200, """{"vmPath":${quote(vmPath)}}""")
            }
            request.method == "POST" && path == "/stop" -> {
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
        val computer = computerName(request)
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

    /** The `computer` field, trimmed and cut to [MAX_NAME] characters. */
    private fun computerName(request: Request): String? {
        val length = request.header("content-length")?.toLongOrNull() ?: 0L
        // Anyone on the network may call /pair, so it reads no large bodies.
        if (length > MAX_PAIR_BODY) return null
        val name = try {
            JSONObject(request.body.readBytes().decodeToString()).optString("computer").trim()
        } catch (_: JSONException) {
            return null
        }
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
            "gzip" -> GZIPInputStream(request.body)
            else -> request.body
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
        val body: InputStream,
    ) {
        fun header(name: String) = headers[name]

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
    private class Bounded(private val input: InputStream, private var remaining: Long) : InputStream() {
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

    private class Response(private val status: Int, private val json: String) {
        fun write(output: OutputStream) {
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
                    "Content-Length: ${body.size}\r\n\r\n").toByteArray(),
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

        fun quote(text: String) =
            "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
    }
}
