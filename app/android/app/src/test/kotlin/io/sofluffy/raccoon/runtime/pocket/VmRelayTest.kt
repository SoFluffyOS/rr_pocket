package io.sofluffy.raccoon.runtime.pocket

import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VmRelayTest {
    /** A stand-in VM service: echoes what it gets. */
    private fun echoServer(): ServerSocket {
        val server = ServerSocket(0)
        thread(isDaemon = true) {
            while (true) {
                val socket = try {
                    server.accept()
                } catch (_: Exception) {
                    return@thread
                }
                thread(isDaemon = true) {
                    socket.use { it.getInputStream().copyTo(it.getOutputStream()) }
                }
            }
        }
        return server
    }

    @Test
    fun relaysBothWays() {
        val vm = echoServer()
        val relay = VmRelay(0) { "http://127.0.0.1:${vm.localPort}/abc=/" }
        Socket("127.0.0.1", relay.start()).use { socket ->
            socket.getOutputStream().write("hello".toByteArray())
            val read = ByteArray(5)
            var got = 0
            while (got < 5) got += socket.getInputStream().read(read, got, 5 - got)
            assertEquals("hello", String(read))
        }
        vm.close()
    }

    @Test
    fun closeAllEndsWhatALastSessionLeft() {
        val vm = echoServer()
        val relay = VmRelay(0) { "http://127.0.0.1:${vm.localPort}/abc=/" }
        val leftover = Socket("127.0.0.1", relay.start())
        leftover.getOutputStream().write("x".toByteArray())
        assertEquals('x'.code, leftover.getInputStream().read())

        val ended = CountDownLatch(1)
        thread(isDaemon = true) {
            if (leftover.getInputStream().read() == -1) ended.countDown()
        }
        relay.closeAll()

        assertTrue(ended.await(5, TimeUnit.SECONDS))
        vm.close()
    }
}
