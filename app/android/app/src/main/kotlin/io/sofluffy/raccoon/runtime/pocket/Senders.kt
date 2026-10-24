package io.sofluffy.raccoon.runtime.pocket

import java.net.Inet6Address
import java.net.InetAddress

/**
 * Who a connection came from, for counting: the IPv4 address, or an IPv6
 * address's /64, since one machine can take any address in its /64.
 */
fun senderOf(address: InetAddress?): String {
    if (address == null) return "unknown"
    if (address !is Inet6Address) return address.hostAddress ?: "unknown"
    return address.address.take(8).joinToString("") { "%02x".format(it) } + "::/64"
}

/**
 * How many connections a server holds at once, in all and per sender:
 * every connection takes a thread, and anyone on the Wi-Fi can open them.
 */
class ConnectionLimit(private val total: Int, private val perSender: Int) {
    private val held = HashMap<String, Int>()
    private var all = 0

    /** False when [sender], or everyone, already holds the most allowed. */
    @Synchronized
    fun take(sender: String): Boolean {
        val theirs = held[sender] ?: 0
        if (all >= total || theirs >= perSender) return false
        held[sender] = theirs + 1
        all++
        return true
    }

    @Synchronized
    fun release(sender: String) {
        val theirs = held[sender] ?: return
        if (theirs <= 1) held.remove(sender) else held[sender] = theirs - 1
        all--
    }
}
