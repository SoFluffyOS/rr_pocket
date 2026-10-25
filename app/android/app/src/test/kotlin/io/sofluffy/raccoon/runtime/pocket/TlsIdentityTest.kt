package io.sofluffy.raccoon.runtime.pocket

import java.io.File
import java.net.ServerSocket
import java.net.Socket
import java.nio.file.Files
import java.security.MessageDigest
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class TlsIdentityTest {
    private val directory: File = Files.createTempDirectory("tls").toFile()

    @After
    fun cleanUp() {
        directory.deleteRecursively()
    }

    @Test
    fun makesAValidSelfSignedCertificate() {
        val identity = TlsIdentity.create()
        val certificate = identity.certificate

        certificate.checkValidity()
        certificate.verify(certificate.publicKey)
        assertEquals(3, certificate.version)
        assertEquals("CN=RR Pocket", certificate.subjectX500Principal.name)
        assertEquals(64, identity.fingerprint.length)
        assertEquals(sha256(certificate.encoded), identity.fingerprint)
    }

    @Test
    fun keepsTheSameIdentityAcrossStarts() {
        val first = TlsIdentity.loadOrCreate(directory)
        val second = TlsIdentity.loadOrCreate(directory)

        assertEquals(first.fingerprint, second.fingerprint)
    }

    @Test
    fun makesANewOneWhenTheKeptOneCantBeRead() {
        val first = TlsIdentity.loadOrCreate(directory)
        File(directory, "key.pk8").writeText("cut short")

        assertNotEquals(first.fingerprint, TlsIdentity.loadOrCreate(directory).fingerprint)
    }

    @Test
    fun aClientPinnedToTheFingerprintTalksToTheServer() {
        val identity = TlsIdentity.create()
        val port = echoOnce(identity)

        pinnedTo(identity.fingerprint).socketFactory.createSocket("127.0.0.1", port).use { socket ->
            socket.getOutputStream().write("hello\n".toByteArray())
            assertEquals("hello", socket.getInputStream().bufferedReader().readLine())
        }
    }

    @Test
    fun aClientPinnedToAnotherPhoneRefusesIt() {
        val port = echoOnce(TlsIdentity.create())

        val socket = pinnedTo(TlsIdentity.create().fingerprint).socketFactory
            .createSocket("127.0.0.1", port) as SSLSocket
        try {
            socket.startHandshake()
            fail("the handshake should fail")
        } catch (_: SSLException) {
        } finally {
            socket.close()
        }
    }

    @Test
    fun theControlServerSpeaksOnlyTls() {
        val identity = TlsIdentity.create()
        val port = PocketServer(
            port = 0,
            code = "CODE",
            accepts = { offered, _ -> offered == "CODE" },
            root = directory,
            hello = { """{"name":"RR Pocket"}""" },
            actions = object : PocketServer.Actions {
                override fun run(bundle: File) = "/auth/"

                override fun stop() {}
            },
            prompt = object : PocketServer.PairPrompt {
                override fun ask(computer: String, from: String, answer: (PocketServer.PairAnswer) -> Unit) {}

                override fun withdraw() {}
            },
            secure = identity::serve,
        ).start()
        val request = "GET /hello HTTP/1.1\r\nAuthorization: Bearer CODE\r\nConnection: close\r\n\r\n"

        pinnedTo(identity.fingerprint).socketFactory.createSocket("127.0.0.1", port).use { socket ->
            socket.getOutputStream().write(request.toByteArray())
            val reply = socket.getInputStream().readBytes().decodeToString()
            assertTrue(reply, reply.startsWith("HTTP/1.1 200 OK"))
            assertTrue(reply.endsWith("""{"name":"RR Pocket"}"""))
        }
        Socket("127.0.0.1", port).use { socket ->
            socket.soTimeout = 5000
            socket.getOutputStream().write(request.toByteArray())
            val reply = try {
                socket.getInputStream().readBytes().decodeToString()
            } catch (_: java.net.SocketException) {
                ""
            }
            assertTrue(reply, !reply.contains("RR Pocket"))
        }
    }

    @Test
    fun theVmRelayCarriesTheVmServiceInsideTls() {
        val identity = TlsIdentity.create()
        val vm = ServerSocket(0)
        thread(isDaemon = true) {
            vm.accept().use { it.getInputStream().copyTo(it.getOutputStream()) }
        }
        val relay = VmRelay(0, secure = identity::serve) { "http://127.0.0.1:${vm.localPort}/abc=/" }

        pinnedTo(identity.fingerprint).socketFactory.createSocket("127.0.0.1", relay.start()).use { socket ->
            socket.getOutputStream().write("ws\n".toByteArray())
            assertEquals("ws", socket.getInputStream().bufferedReader().readLine())
        }
        vm.close()
    }

    /** A TLS server for one connection, echoing it. */
    private fun echoOnce(identity: TlsIdentity): Int {
        val server = ServerSocket(0)
        thread(isDaemon = true) {
            server.use {
                try {
                    identity.serve(it.accept()).use { socket ->
                        socket.getInputStream().copyTo(socket.getOutputStream())
                    }
                } catch (_: Exception) {
                }
            }
        }
        return server.localPort
    }

    /** What the computer does: trust one certificate, by its fingerprint. */
    private fun pinnedTo(fingerprint: String): SSLContext {
        val trust = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
                throw UnsupportedOperationException()

            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                if (sha256(chain[0].encoded) != fingerprint) {
                    throw java.security.cert.CertificateException("not the paired phone")
                }
            }

            override fun getAcceptedIssuers() = arrayOf<X509Certificate>()
        }
        return SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
    }

    private fun sha256(bytes: ByteArray) =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
