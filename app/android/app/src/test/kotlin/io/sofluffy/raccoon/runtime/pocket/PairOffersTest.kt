package io.sofluffy.raccoon.runtime.pocket

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PairOffersTest {
    private var time = 0L
    private val offers = PairOffers(lifetimeMs = 1000, now = { time })

    @Test
    fun theProofIsAnHmacOfTheFingerprintKeyedWithTheToken() {
        // RFC 4231, test case 2.
        assertEquals(
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
            PairOffers.proof("Jefe", "what do ya want for nothing?"),
        )
        assertEquals(PairOffers.proof("t", "f"), offers.offer("t", "f"))
    }

    @Test
    fun aTokenWorksOnceAndInTime() {
        offers.offer("token", "f")
        assertFalse(offers.redeem("other"))
        assertTrue(offers.redeem("token"))
        assertFalse(offers.redeem("token"))

        offers.offer("late", "f")
        time += 1000
        assertFalse(offers.redeem("late"))
    }

    @Test
    fun aNewOfferReplacesTheLast() {
        offers.offer("first", "f")
        offers.offer("second", "f")
        assertFalse(offers.redeem("first"))
        assertTrue(offers.redeem("second"))
    }

    @Test
    fun nothingOfferedRedeemsNothing() {
        assertFalse(offers.redeem(""))
    }
}
