package io.sofluffy.raccoon.runtime.pocket

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CodeGateTest {
    private var time = 0L
    private val gate = CodeGate("K729VVAN", maxFailures = 3, lockoutMs = 1000, now = { time })

    @Test
    fun acceptsTheCodeInAnyCase() {
        assertTrue(gate.accepts("K729VVAN"))
        assertTrue(gate.accepts("k729vvan"))
    }

    @Test
    fun refusesOtherCodesAndNone() {
        assertFalse(gate.accepts("K729VVAM"))
        assertFalse(gate.accepts("K729VVA"))
        assertFalse(gate.accepts(null))
    }

    @Test
    fun locksAfterTooManyWrongCodesEvenForTheRightOne() {
        repeat(3) { gate.accepts("WRONGCOD") }
        assertFalse(gate.accepts("K729VVAN"))
        time += 999
        assertFalse(gate.accepts("K729VVAN"))
        time += 1
        assertTrue(gate.accepts("K729VVAN"))
    }

    @Test
    fun aRightCodeResetsTheCount() {
        repeat(2) { gate.accepts("WRONGCOD") }
        assertTrue(gate.accepts("K729VVAN"))
        repeat(2) { gate.accepts("WRONGCOD") }
        assertTrue(gate.accepts("K729VVAN"))
    }
}
