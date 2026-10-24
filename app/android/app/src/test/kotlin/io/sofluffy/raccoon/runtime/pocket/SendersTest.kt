package io.sofluffy.raccoon.runtime.pocket

import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SendersTest {
    @Test
    fun countsIpv4ByAddressAndIpv6ByItsSlash64() {
        assertEquals("192.168.0.12", senderOf(InetAddress.getByName("192.168.0.12")))
        assertEquals(
            senderOf(InetAddress.getByName("2001:db8:1:2::1")),
            senderOf(InetAddress.getByName("2001:db8:1:2:ffff::9")),
        )
        assertEquals("20010db800010002::/64", senderOf(InetAddress.getByName("2001:db8:1:2::1")))
    }

    @Test
    fun limitsPerSenderAndInAll() {
        val limit = ConnectionLimit(total = 3, perSender = 2)
        assertTrue(limit.take("a"))
        assertTrue(limit.take("a"))
        assertFalse(limit.take("a"))
        assertTrue(limit.take("b"))
        assertFalse(limit.take("c"))

        limit.release("a")
        assertTrue(limit.take("c"))
        assertFalse(limit.take("a"))
    }
}
