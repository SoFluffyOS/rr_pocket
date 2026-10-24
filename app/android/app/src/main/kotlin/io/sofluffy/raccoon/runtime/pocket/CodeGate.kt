package io.sofluffy.raccoon.runtime.pocket

import java.security.MessageDigest

/**
 * Lets a request through when it shows [code], compared in constant time;
 * [maxFailures] wrong codes in a row shut it for [lockoutMs], right codes
 * included, so guessing 40 bits over the network goes nowhere.
 */
class CodeGate(
    private val code: String,
    private val maxFailures: Int = 10,
    private val lockoutMs: Long = 5 * 60 * 1000L,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var failures = 0
    private var lockedUntil = 0L

    @Synchronized
    fun accepts(offered: String?): Boolean {
        val time = now()
        if (time < lockedUntil) return false
        val matches = offered != null &&
            MessageDigest.isEqual(offered.uppercase().toByteArray(), code.toByteArray())
        if (matches) {
            failures = 0
            return true
        }
        failures++
        if (failures >= maxFailures) {
            failures = 0
            lockedUntil = time + lockoutMs
        }
        return false
    }
}
