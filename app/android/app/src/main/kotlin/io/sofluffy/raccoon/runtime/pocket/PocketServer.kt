package io.sofluffy.raccoon.runtime.pocket

import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.util.zip.GZIPInputStream
import kotlin.concurrent.thread

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
 *
 * Every request carries `Authorization: Bearer <pairing code>`.
 */
class PocketServer(
    private val port: Int,
    private val accepts: (String?) -> Boolean,
    private val root: File,
    private val hello: () -> String,
    private val actions: Actions,
) {
    interface Actions {
        /** Starts [bundle]; returns the VM service's path, `/<auth>/`. */
        fun run(bundle: File): String

        fun stop()
    }

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
                    thread(isDaemon = true) { serve(client) }
                }
            }
        }
        return server.localPort
    }

    private fun serve(socket: Socket) {
        socket.use {
            val input = BufferedInputStream(it.getInputStream())
            val output = it.getOutputStream()
            while (true) {
                val request = Request.read(input) ?: return
                if (request.method == "GET" && request.path == "/logs") {
                    if (authorized(request)) return streamLogs(output)
                    return Response(401, error("wrong pairing code")).write(output)
                }
                val response = try {
                    respond(request)
                } catch (e: Exception) {
                    Response(500, error(e.message ?: e.toString()))
                }
                request.drain()
                response.write(output)
                if (request.header("connection") == "close") return
            }
        }
    }

    private fun authorized(request: Request) =
        accepts(request.header("authorization")?.removePrefix("Bearer "))

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

    private fun respond(request: Request): Response {
        if (!authorized(request)) {
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
            fun read(input: InputStream): Request? {
                val line = readLine(input) ?: return null
                val parts = line.split(" ")
                if (parts.size < 2) return null
                val headers = mutableMapOf<String, String>()
                while (true) {
                    val header = readLine(input) ?: return null
                    if (header.isEmpty()) break
                    val colon = header.indexOf(':')
                    if (colon > 0) {
                        headers[header.substring(0, colon).trim().lowercase()] =
                            header.substring(colon + 1).trim()
                    }
                }
                val length = headers["content-length"]?.toLongOrNull() ?: 0L
                return Request(parts[0], parts[1].substringBefore('?'), headers, Bounded(input, length))
            }

            private fun readLine(input: InputStream): String? {
                val line = StringBuilder()
                while (true) {
                    val byte = input.read()
                    if (byte == -1) return if (line.isEmpty()) null else line.toString()
                    if (byte == '\n'.code) return line.toString().trimEnd('\r')
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
                404 -> "Not Found"
                409 -> "Conflict"
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
        fun quote(text: String) =
            "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
    }
}
