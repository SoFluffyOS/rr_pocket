package io.sofluffy.raccoon.runtime.pocket

import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLSocket
import kotlin.concurrent.thread

/**
 * Makes the engine's VM service, which listens on 127.0.0.1 only, reachable
 * from the LAN, byte for byte (HTTP, WebSockets, DDS) inside TLS ([secure]),
 * which the computer's `pocket run` unwraps. Its auth code in the URL still
 * guards it; the computer learns it only through the paired control server.
 * Every engine in the process shares the one VM service.
 */
class VmRelay(
    private val port: Int,
    private val limit: ConnectionLimit = ConnectionLimit(total = 32, perSender = 16),
    /** Wraps each accepted connection: TLS, or nothing in some tests. */
    private val secure: (Socket) -> Socket,
    private val vmServiceUri: () -> String?,
) {
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
                    // Each connection holds two threads; anyone on the
                    // Wi-Fi can open them.
                    val sender = senderOf(client.inetAddress)
                    if (!limit.take(sender)) {
                        client.close()
                        continue
                    }
                    thread(isDaemon = true) {
                        try {
                            relay(client)
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
        try {
            relayOrThrow(client)
        } catch (_: Exception) {
            // A failed handshake, or closeAll() or the client ended it
            // first: an exception out of this thread would end RR Pocket.
            client.close()
        }
    }

    private fun relayOrThrow(raw: Socket) {
        val vmPort = vmServiceUri()?.let { URI(it).port }
        if (vmPort == null || vmPort <= 0) {
            raw.close()
            return
        }
        // Long enough for a handshake; then none, since a VM service
        // connection may sit quiet for as long as the session lasts.
        raw.soTimeout = HANDSHAKE_TIMEOUT_MS
        val client = secure(raw)
        (client as? SSLSocket)?.startHandshake()
        raw.soTimeout = 0
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

    private companion object {
        const val HANDSHAKE_TIMEOUT_MS = 10_000
    }
}
