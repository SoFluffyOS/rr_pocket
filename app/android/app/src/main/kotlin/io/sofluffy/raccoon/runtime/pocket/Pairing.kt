package io.sofluffy.raccoon.runtime.pocket

import android.content.Context
import java.net.Inet4Address
import java.net.NetworkInterface
import java.security.SecureRandom

/**
 * The code a computer must show to drive this phone, and the address it
 * reaches it at. The code is 8 characters from 32 (40 bits) and stays until
 * the app's data is cleared; [CodeGate] checks it.
 */
class Pairing(context: Context) {
    private val prefs = context.getSharedPreferences("rr_pocket", Context.MODE_PRIVATE)

    val code: String = prefs.getString(KEY, null) ?: newCode().also {
        prefs.edit().putString(KEY, it).apply()
    }

    private val gate = CodeGate(code)

    fun accepts(offered: String?) = gate.accepts(offered)

    /** The phone's IPv4 address on Wi-Fi (or any LAN), null when offline. */
    fun address(): String? {
        val candidates = NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
            .filter { it.isUp && !it.isLoopback }
            .sortedByDescending { it.name.startsWith("wlan") }
        for (network in candidates) {
            val ipv4 = network.inetAddresses.toList().firstOrNull {
                it is Inet4Address && it.isSiteLocalAddress
            }
            if (ipv4 != null) return ipv4.hostAddress
        }
        return null
    }

    private fun newCode(): String {
        val random = SecureRandom()
        return (1..8).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")
    }

    companion object {
        private const val KEY = "pairing_code"
        private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    }
}
