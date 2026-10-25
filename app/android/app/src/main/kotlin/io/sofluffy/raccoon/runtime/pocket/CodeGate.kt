package io.sofluffy.raccoon.runtime.pocket

import java.security.MessageDigest

/**
 * Lets a request through when it shows [code], compared in constant time.
 * [maxFailures] wrong codes in a row from one sender ([senderOf]) shut it
 * out for [lockoutMs], right codes included, so guessing 40 bits over the
 * network goes nowhere; other senders, the paired computer among them,
 * keep working.
 */
class CodeGate(
    private val code: String,
    private val maxFailures: Int = 10,
    private val lockoutMs: Long = 5 * 60 * 1000L,
    private val maxSenders: Int = 1024,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private class Sender {
        var failures = 0
        var lockedUntil = 0L
    }

    private val senders = HashMap<String, Sender>()

    @Synchronized
    fun accepts(offered: String?, from: String): Boolean {
        val time = now()
        val known = senders[from]
        if (known != null && time < known.lockedUntil) return false
        if (known == null && !hasRoom(time)) return false
        val matches = offered != null &&
            MessageDigest.isEqual(offered.uppercase().toByteArray(), code.toByteArray())
        if (matches) {
            senders.remove(from)
            return true
        }
        val sender = known ?: Sender().also { senders[from] = it }
        sender.failures++
        if (sender.failures >= maxFailures) {
            sender.failures = 0
            sender.lockedUntil = time + lockoutMs
        }
        return false
    }

    /** Whether [from] is shut out for now, so a right code would fail too. */
    @Synchronized
    fun lockedOut(from: String): Boolean = senders[from]?.let { now() < it.lockedUntil } ?: false

    /**
     * Whether a sender not seen yet may try. Not while [maxSenders] are
     * locked out at once: their guesses would go uncounted.
     */
    private fun hasRoom(time: Long): Boolean {
        if (senders.size >= maxSenders) senders.values.removeAll { time >= it.lockedUntil }
        return senders.size < maxSenders
    }
}
