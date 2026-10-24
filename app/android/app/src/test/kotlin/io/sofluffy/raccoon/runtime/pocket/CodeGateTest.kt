package io.sofluffy.raccoon.runtime.pocket

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CodeGateTest {
    private var time = 0L
    private val gate = CodeGate("K729VVAN", maxFailures = 3, lockoutMs = 1000, maxSenders = 2, now = { time })

    @Test
    fun acceptsTheCodeInAnyCase() {
        assertTrue(gate.accepts("K729VVAN", "10.0.0.2"))
        assertTrue(gate.accepts("k729vvan", "10.0.0.2"))
    }

    @Test
    fun refusesOtherCodesAndNone() {
        assertFalse(gate.accepts("K729VVAM", "10.0.0.2"))
        assertFalse(gate.accepts("K729VVA", "10.0.0.2"))
        assertFalse(gate.accepts(null, "10.0.0.2"))
    }

    @Test
    fun locksAfterTooManyWrongCodesEvenForTheRightOne() {
        repeat(3) { gate.accepts("WRONGCOD", "10.0.0.2") }
        assertFalse(gate.accepts("K729VVAN", "10.0.0.2"))
        time += 999
        assertFalse(gate.accepts("K729VVAN", "10.0.0.2"))
        time += 1
        assertTrue(gate.accepts("K729VVAN", "10.0.0.2"))
    }

    @Test
    fun aRightCodeResetsTheCount() {
        repeat(2) { gate.accepts("WRONGCOD", "10.0.0.2") }
        assertTrue(gate.accepts("K729VVAN", "10.0.0.2"))
        repeat(2) { gate.accepts("WRONGCOD", "10.0.0.2") }
        assertTrue(gate.accepts("K729VVAN", "10.0.0.2"))
    }

    @Test
    fun locksOutOnlyTheSenderGuessing() {
        repeat(3) { gate.accepts("WRONGCOD", "10.0.0.66") }
        assertFalse(gate.accepts("K729VVAN", "10.0.0.66"))
        assertTrue(gate.accepts("K729VVAN", "10.0.0.2"))
    }

    @Test
    fun whileTooManySendersAreLockedOutNobodyNewTries() {
        repeat(3) { gate.accepts("WRONGCOD", "10.0.0.66") }
        repeat(3) { gate.accepts("WRONGCOD", "10.0.0.67") }

        assertFalse(gate.accepts("K729VVAN", "10.0.0.68"))
        time += 1000
        assertTrue(gate.accepts("K729VVAN", "10.0.0.68"))
    }
}
