package io.sofluffy.raccoon.runtime.pocket

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The QR code the user last allowed pairing with (docs/pairing.md, "A QR
 * code on the computer"). The phone never sends its code to the computer
 * in the clear: it sends where it is and its certificate's fingerprint,
 * signed with the QR code's token; the computer then asks for the code
 * over TLS pinned to that certificate, showing the token once.
 */
class PairOffers(
    private val lifetimeMs: Long = 120_000L,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var token: String? = null
    private var expires = 0L

    /**
     * Keeps [token] for one [redeem], replacing any earlier one, and returns
     * the proof the computer checks: HMAC-SHA256 of [fingerprint] keyed
     * with [token], lowercase hex.
     */
    @Synchronized
    fun offer(token: String, fingerprint: String): String {
        this.token = token
        expires = now() + lifetimeMs
        return proof(token, fingerprint)
    }

    /** Whether [offered] is the token kept, still in time; it works once. */
    @Synchronized
    fun redeem(offered: String): Boolean {
        val kept = token ?: return false
        if (now() >= expires) {
            token = null
            return false
        }
        if (!MessageDigest.isEqual(offered.toByteArray(), kept.toByteArray())) return false
        token = null
        return true
    }

    companion object {
        fun proof(token: String, fingerprint: String): String {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(token.toByteArray(), "HmacSHA256"))
            return mac.doFinal(fingerprint.toByteArray()).joinToString("") { "%02x".format(it) }
        }
    }
}
