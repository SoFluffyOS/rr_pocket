package io.sofluffy.raccoon.runtime.pocket

import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import kotlin.concurrent.thread

/**
 * Makes the engine's VM service, which listens on 127.0.0.1 only, reachable
 * from the LAN, byte for byte (HTTP, WebSockets, DDS). Its auth code in the
 * URL still guards it; the computer learns it only through the paired
 * control server. Every engine in the process shares the one VM service.
 */
class VmRelay(private val port: Int, private val vmServiceUri: () -> String?) {
    fun start() {
        thread(isDaemon = true, name = "rr-pocket-vm-relay") {
            ServerSocket().use { server ->
                server.reuseAddress = true
                server.bind(InetSocketAddress(port))
                while (true) {
                    val client = server.accept()
                    thread(isDaemon = true) { relay(client) }
                }
            }
        }
    }

    private fun relay(client: Socket) {
        val vmPort = vmServiceUri()?.let { URI(it).port }
        if (vmPort == null || vmPort <= 0) {
            client.close()
            return
        }
        val engine = try {
            Socket("127.0.0.1", vmPort)
        } catch (e: Exception) {
            client.close()
            return
        }
        thread(isDaemon = true) { pump(client.getInputStream(), engine.getOutputStream(), client, engine) }
        pump(engine.getInputStream(), client.getOutputStream(), client, engine)
    }

    private fun pump(from: InputStream, to: OutputStream, a: Socket, b: Socket) {
        try {
            from.copyTo(to)
        } catch (_: Exception) {
        } finally {
            a.close()
            b.close()
        }
    }
}
