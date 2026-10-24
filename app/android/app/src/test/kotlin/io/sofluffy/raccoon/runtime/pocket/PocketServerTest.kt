package io.sofluffy.raccoon.runtime.pocket

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.Socket
import java.nio.file.Files
import java.util.zip.GZIPOutputStream

class PocketServerTest {
    // The server's root sits one level down, so a file that escapes it
    // still lands somewhere this test cleans up.
    private val base: File = Files.createTempDirectory("pocket").toFile()
    private val root = File(base, "root").apply { mkdirs() }
    private var ran: File? = null
    private var stopped = false
    private val port = PocketServer(
        port = 0,
        accepts = { it == "CODE" },
        root = root,
        hello = { """{"name":"RR Pocket"}""" },
        actions = object : PocketServer.Actions {
            override fun run(bundle: File): String {
                ran = bundle
                return "/auth/"
            }

            override fun stop() {
                stopped = true
            }
        },
    ).start()

    @After
    fun cleanUp() {
        base.deleteRecursively()
    }

    @Test
    fun refusesAWrongCode() {
        assertEquals(401, request("GET", "/hello", code = "NOPE").status)
        assertEquals(401, request("POST", "/run", code = null).status)
    }

    @Test
    fun saysHello() {
        val response = request("GET", "/hello")
        assertEquals(200, response.status)
        assertEquals("""{"name":"RR Pocket"}""", response.body)
    }

    @Test
    fun installsABundleAndRunsIt() {
        assertEquals(200, request("POST", "/bundle/begin").status)
        assertEquals(200, request("PUT", "/bundle/kernel_blob.bin", body = gzip("kernel"), gzip = true).status)
        assertEquals(200, request("PUT", "/bundle/fonts%2FNunito.ttf", body = "font".toByteArray()).status)
        assertEquals(200, request("POST", "/bundle/commit").status)

        val response = request("POST", "/run")

        assertEquals(200, response.status)
        assertEquals("""{"vmPath":"/auth/"}""", response.body)
        val bundle = File(root, "bundle")
        assertEquals(bundle, ran)
        assertEquals("kernel", File(bundle, "kernel_blob.bin").readText())
        assertEquals("font", File(bundle, "fonts/Nunito.ttf").readText())
    }

    @Test
    fun keepsFilesInsideTheBundle() {
        request("POST", "/bundle/begin")

        val response = request("PUT", "/bundle/..%2F..%2Fescaped", body = "x".toByteArray())

        assertEquals(400, response.status)
        assertFalse(File(base, "escaped").exists())
        assertFalse(File(root, "escaped").exists())
    }

    @Test
    fun refusesABundleWithoutAKernel() {
        request("POST", "/bundle/begin")
        assertEquals(400, request("POST", "/bundle/commit").status)
        assertEquals(409, request("POST", "/run").status)
        assertEquals(null, ran)
    }

    @Test
    fun stops() {
        assertEquals(200, request("POST", "/stop").status)
        assertTrue(stopped)
    }

    @Test
    fun servesSeveralRequestsOnOneConnection() {
        Socket("127.0.0.1", port).use { socket ->
            repeat(3) {
                socket.getOutputStream().write(
                    "GET /hello HTTP/1.1\r\nAuthorization: Bearer CODE\r\n\r\n".toByteArray(),
                )
                assertEquals(200, readResponse(socket).status)
            }
        }
    }

    private class Response(val status: Int, val body: String)

    private fun request(
        method: String,
        path: String,
        code: String? = "CODE",
        body: ByteArray = ByteArray(0),
        gzip: Boolean = false,
    ): Response = Socket("127.0.0.1", port).use { socket ->
        val head = buildString {
            append("$method $path HTTP/1.1\r\n")
            if (code != null) append("Authorization: Bearer $code\r\n")
            if (gzip) append("Content-Encoding: gzip\r\n")
            append("Content-Length: ${body.size}\r\nConnection: close\r\n\r\n")
        }
        socket.getOutputStream().write(head.toByteArray() + body)
        readResponse(socket)
    }

    private fun readResponse(socket: Socket): Response {
        val input = socket.getInputStream()
        val head = StringBuilder()
        while (!head.endsWith("\r\n\r\n")) head.append(input.read().toChar())
        val status = head.split(" ")[1].toInt()
        val length = Regex("Content-Length: (\\d+)").find(head)?.groupValues?.get(1)?.toInt() ?: 0
        val body = ByteArray(length)
        var read = 0
        while (read < length) read += input.read(body, read, length - read)
        return Response(status, body.decodeToString())
    }

    private fun gzip(text: String): ByteArray {
        val bytes = ByteArrayOutputStream()
        GZIPOutputStream(bytes).use { it.write(text.toByteArray()) }
        return bytes.toByteArray()
    }
}
