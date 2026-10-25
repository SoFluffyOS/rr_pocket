package io.sofluffy.raccoon.runtime.pocket

import java.io.ByteArrayInputStream
import java.io.File
import java.net.Socket
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket

/**
 * The phone's TLS key and self-signed certificate. A computer pins the
 * certificate's [fingerprint] when it pairs (docs/pairing.md), so nobody
 * else on the Wi-Fi can read the code, the project, or the VM service's
 * address, nor pass for this phone. Made once and kept with the app's data,
 * like the pairing code.
 */
class TlsIdentity(private val key: PrivateKey, val certificate: X509Certificate) {
    /** SHA-256 of the certificate, lowercase hex: what computers pin. */
    val fingerprint: String = MessageDigest.getInstance("SHA-256")
        .digest(certificate.encoded).joinToString("") { "%02x".format(it) }

    private val context: SSLContext = run {
        val password = CharArray(0)
        val store = KeyStore.getInstance("PKCS12").apply {
            load(null, null)
            setKeyEntry("rr-pocket", key, password, arrayOf(certificate))
        }
        val managers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            .apply { init(store, password) }
            .keyManagers
        SSLContext.getInstance("TLS").apply { init(managers, null, null) }
    }

    /**
     * [socket], accepted by a plain server socket, as the server's end of a
     * TLS connection. The handshake happens on the first read or write, in
     * the connection's own thread, under its read timeout.
     */
    fun serve(socket: Socket): SSLSocket {
        val secured = context.socketFactory.createSocket(
            socket,
            socket.inetAddress?.hostAddress,
            socket.port,
            true,
        ) as SSLSocket
        secured.useClientMode = false
        return secured
    }

    private fun save(directory: File) {
        directory.mkdirs()
        write(File(directory, KEY_FILE), key.encoded)
        write(File(directory, CERTIFICATE_FILE), certificate.encoded)
    }

    /** Written beside, then moved: a crash mid-write leaves the old file. */
    private fun write(file: File, bytes: ByteArray) {
        val draft = File(file.path + ".tmp")
        draft.writeBytes(bytes)
        if (!draft.renameTo(file)) error("could not save ${file.name}")
    }

    companion object {
        private const val KEY_FILE = "key.pk8"
        private const val CERTIFICATE_FILE = "certificate.der"

        /**
         * The identity kept in [directory], or a new one when there is none
         * or it can't be read. A new one breaks every pairing: computers
         * pinned the old certificate.
         */
        fun loadOrCreate(directory: File): TlsIdentity {
            load(directory)?.let { return it }
            return create().also { it.save(directory) }
        }

        private fun load(directory: File): TlsIdentity? = try {
            val key = KeyFactory.getInstance("EC")
                .generatePrivate(PKCS8EncodedKeySpec(File(directory, KEY_FILE).readBytes()))
            val certificate = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(File(directory, CERTIFICATE_FILE).readBytes()))
                as X509Certificate
            TlsIdentity(key, certificate)
        } catch (_: Exception) {
            null
        }

        /** A P-256 key and a certificate for it, signed by itself. */
        fun create(): TlsIdentity {
            val pair = KeyPairGenerator.getInstance("EC").apply {
                initialize(ECGenParameterSpec("secp256r1"))
            }.generateKeyPair()
            val serial = ByteArray(16).also { SecureRandom().nextBytes(it) }
            serial[0] = (serial[0].toInt() and 0x7f or 0x01).toByte() // positive, not zero
            val name = Der.sequence(
                Der.set(Der.sequence(Der.COMMON_NAME, Der.utf8("RR Pocket"))),
            )
            val algorithm = Der.sequence(Der.ECDSA_WITH_SHA256)
            val tbs = Der.sequence(
                Der.explicit0(Der.integer(byteArrayOf(2))), // v3
                Der.integer(serial),
                algorithm,
                name,
                // No expiry that matters: computers trust the pinned
                // certificate itself, not its dates.
                Der.sequence(Der.utcTime("200101000000Z"), Der.utcTime("491231235959Z")),
                name,
                pair.public.encoded, // SubjectPublicKeyInfo, DER already
            )
            val signature = Signature.getInstance("SHA256withECDSA").run {
                initSign(pair.private)
                update(tbs)
                sign()
            }
            val der = Der.sequence(tbs, algorithm, Der.bitString(signature))
            val certificate = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(der)) as X509Certificate
            return TlsIdentity(pair.private, certificate)
        }
    }
}

/** Just enough DER to write a self-signed certificate. */
private object Der {
    /** 1.2.840.10045.4.3.2 */
    val ECDSA_WITH_SHA256 = byteArrayOf(0x06, 0x08, 0x2a, 0x86.toByte(), 0x48, 0xce.toByte(), 0x3d, 0x04, 0x03, 0x02)

    /** 2.5.4.3 */
    val COMMON_NAME = byteArrayOf(0x06, 0x03, 0x55, 0x04, 0x03)

    fun sequence(vararg parts: ByteArray) = tagged(0x30, concat(parts))

    fun set(vararg parts: ByteArray) = tagged(0x31, concat(parts))

    fun explicit0(content: ByteArray) = tagged(0xa0, content)

    /** [value] is big-endian and non-negative. */
    fun integer(value: ByteArray) = tagged(0x02, value)

    fun utf8(text: String) = tagged(0x0c, text.toByteArray())

    fun utcTime(text: String) = tagged(0x17, text.toByteArray())

    fun bitString(bytes: ByteArray) = tagged(0x03, byteArrayOf(0) + bytes)

    private fun concat(parts: Array<out ByteArray>) =
        parts.fold(ByteArray(0)) { all, part -> all + part }

    private fun tagged(tag: Int, content: ByteArray): ByteArray {
        val size = content.size
        val length = when {
            size < 0x80 -> byteArrayOf(size.toByte())
            size < 0x100 -> byteArrayOf(0x81.toByte(), size.toByte())
            else -> byteArrayOf(0x82.toByte(), (size shr 8).toByte(), size.toByte())
        }
        return byteArrayOf(tag.toByte()) + length + content
    }
}
