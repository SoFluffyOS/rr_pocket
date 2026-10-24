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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.GZIPOutputStream
import io.sofluffy.raccoon.runtime.pocket.PocketServer.PairAnswer
import kotlin.concurrent.thread

class PocketServerTest {
    // The server's root sits one level down, so a file that escapes it
    // still lands somewhere this test cleans up.
    private val base: File = Files.createTempDirectory("pocket").toFile()
    private val root = File(base, "root").apply { mkdirs() }
    private var ran: File? = null
    private var stopped = false
    private val prompt = FakePrompt()
    @Volatile private var clock = 0L
    private val port = PocketServer(
        port = 0,
        code = "CODE",
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
        prompt = prompt,
        pairTimeoutMs = 1000,
        now = { clock },
    ).start()

    /** Answers with [answer] after [delayMs]; null leaves the question open. */
    private class FakePrompt : PocketServer.PairPrompt {
        @Volatile var answer: PairAnswer? = PairAnswer.ALLOWED
        @Volatile var delayMs = 0L
        @Volatile var asked: String? = null
        @Volatile var askedFrom: String? = null
        val asks = AtomicInteger()
        val withdrawn = AtomicInteger()
        val waiting = CountDownLatch(1)

        override fun ask(computer: String, from: String, answer: (PairAnswer) -> Unit) {
            asked = computer
            askedFrom = from
            asks.incrementAndGet()
            waiting.countDown()
            val given = this.answer ?: return
            thread {
                Thread.sleep(delayMs)
                answer(given)
            }
        }

        override fun withdraw() {
            withdrawn.incrementAndGet()
        }
    }

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

    @Test
    fun pairsWhenTheUserAllowsWithoutACode() {
        val response = request("POST", "/pair", code = null, body = """{"computer":"Simon's Mac"}""".toByteArray())

        assertEquals(200, response.status)
        assertEquals("""{"code":"CODE"}""", response.body)
        assertEquals("Simon's Mac", prompt.asked)
        assertEquals("127.0.0.1", prompt.askedFrom)
    }

    @Test
    fun aWrongCodeDoesNotStopPairing() {
        val response = request("POST", "/pair", code = "NOPE", body = """{"computer":"Mac"}""".toByteArray())

        assertEquals(200, response.status)
    }

    @Test
    fun refusesWhenTheUserRefuses() {
        prompt.answer = PairAnswer.REFUSED

        val response = request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray())

        assertEquals(403, response.status)
        assertEquals("""{"error":"pairing refused on the phone"}""", response.body)
        assertEquals(0, prompt.withdrawn.get())
    }

    @Test
    fun givesUpWhenNobodyAnswers() {
        prompt.answer = null

        val response = request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray())

        assertEquals(408, response.status)
        assertEquals("""{"error":"no answer on the phone"}""", response.body)
        assertEquals(1, prompt.withdrawn.get())
    }

    @Test
    fun aLateAnswerCountsAsNone() {
        prompt.delayMs = 1500

        assertEquals(408, request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray()).status)
    }

    @Test
    fun asksForOneComputerAtATime() {
        prompt.answer = null
        var first: Response? = null
        val waiting = thread { first = request("POST", "/pair", code = null, body = """{"computer":"A"}""".toByteArray()) }
        assertTrue(prompt.waiting.await(2, TimeUnit.SECONDS))

        val second = request("POST", "/pair", code = null, body = """{"computer":"B"}""".toByteArray())

        assertEquals(409, second.status)
        assertEquals(1, prompt.asks.get())
        waiting.join()
        assertEquals(408, first?.status)
        prompt.answer = PairAnswer.ALLOWED
        clock += 30_000
        assertEquals(200, request("POST", "/pair", code = null, body = """{"computer":"C"}""".toByteArray()).status)
    }

    @Test
    fun staysQuietAfterANo() {
        prompt.answer = PairAnswer.REFUSED
        assertEquals(403, request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray()).status)

        prompt.answer = PairAnswer.ALLOWED
        clock += 29_000
        assertEquals(429, request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray()).status)
        assertEquals(1, prompt.asks.get())

        clock += 1_000
        assertEquals(200, request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray()).status)
    }

    @Test
    fun aConnectionResetMidRequestLeavesTheServerUp() {
        Socket("127.0.0.1", port).use { socket ->
            socket.setSoLinger(true, 0) // close sends a reset
            socket.getOutputStream().write("POST /pair HTTP/1.1\r\nContent-Le".toByteArray())
        }
        Thread.sleep(200)

        assertEquals(200, request("GET", "/hello").status)
    }

    @Test
    fun anEndlessLineEndsOnlyItsConnection() {
        Socket("127.0.0.1", port).use { socket ->
            // Closed after 8 KB: an end, or a reset if more was still coming.
            val ended = try {
                socket.getOutputStream().write(("GET /" + "x".repeat(20_000)).toByteArray())
                socket.getInputStream().read() == -1
            } catch (_: java.net.SocketException) {
                true
            }
            assertTrue(ended)
        }

        assertEquals(200, request("GET", "/hello").status)
    }

    @Test
    fun saysWhenNobodyCanAnswer() {
        prompt.answer = PairAnswer.UNAVAILABLE

        val response = request("POST", "/pair", code = null, body = """{"computer":"Mac"}""".toByteArray())

        assertEquals(409, response.status)
        assertTrue(response.body.contains("open RR Pocket"))
    }

    @Test
    fun cutsTheNameTo64Characters() {
        val name = "M".repeat(63) + "\uD83D\uDE00" + "tail"

        request("POST", "/pair", code = null, body = """{"computer":"$name"}""".toByteArray())

        assertEquals("M".repeat(63) + "\uD83D\uDE00", prompt.asked)
    }

    @Test
    fun needsAComputerName() {
        assertEquals(400, request("POST", "/pair", code = null, body = "{}".toByteArray()).status)
        assertEquals(400, request("POST", "/pair", code = null, body = "not json".toByteArray()).status)
        assertEquals(400, request("POST", "/pair", code = null, body = """{"computer":"  "}""".toByteArray()).status)
        assertEquals(0, prompt.asks.get())
    }

    @Test
    fun everyOtherEndpointStillNeedsTheCode() {
        val endpoints = listOf(
            "GET" to "/hello",
            "POST" to "/bundle/begin",
            "PUT" to "/bundle/kernel_blob.bin",
            "POST" to "/bundle/commit",
            "POST" to "/run",
            "POST" to "/stop",
            "GET" to "/logs",
            "GET" to "/pair",
            "POST" to "/nothing",
        )
        for ((method, path) in endpoints) {
            assertEquals("$method $path", 401, request(method, path, code = null).status)
        }
        assertEquals(null, ran)
        assertFalse(stopped)
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
