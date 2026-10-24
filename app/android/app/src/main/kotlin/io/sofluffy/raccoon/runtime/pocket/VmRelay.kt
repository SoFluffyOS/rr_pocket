package io.sofluffy.raccoon.runtime.pocket

import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * Makes the engine's VM service, which listens on 127.0.0.1 only, reachable
 * from the LAN, byte for byte (HTTP, WebSockets, DDS). Its auth code in the
 * URL still guards it; the computer learns it only through the paired
 * control server. Every engine in the process shares the one VM service.
 */
class VmRelay(private val port: Int, private val vmServiceUri: () -> String?) {
    /** Every relayed connection's two ends, while it lasts. */
    private val open = ConcurrentHashMap.newKeySet<Socket>()

    /** Listens on [port] (0 for any) and returns the port it got. */
    fun start(): Int {
        val server = ServerSocket()
        server.reuseAddress = true
        server.bind(InetSocketAddress(port))
        thread(isDaemon = true, name = "rr-pocket-vm-relay") {
            server.use {
                while (true) {
                    val client = server.accept()
                    thread(isDaemon = true) { relay(client) }
                }
            }
        }
        return server.localPort
    }

    /**
     * Ends every relayed connection. The VM outlives sessions, and a
     * computer's DDS that outlived its own (a killed `flutter run`) would
     * keep the VM to itself: the next session's DDS can't start, and its
     * hot restart fails. A new run, or a stop, frees it.
     */
    fun closeAll() {
        for (socket in open.toList()) {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
        open.clear()
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
        open += client
        open += engine
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
            open -= a
            open -= b
        }
    }
}
