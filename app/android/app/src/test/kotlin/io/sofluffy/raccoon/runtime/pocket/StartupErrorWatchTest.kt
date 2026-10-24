package io.sofluffy.raccoon.runtime.pocket

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StartupErrorWatchTest {
    private fun error(vararg lines: String) = StartupErrorWatch.startupError(lines.asSequence())

    @Test
    fun takesTheExceptionAndItsCauseUpToTheStack() {
        assertEquals(
            "IsarError: Could not initialize IsarCore library.\n" +
                "IsarError: Incorrect Isar Core version: Required 3.3.2 found 3.4.1.",
            error(
                "[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: " +
                    "IsarError: Could not initialize IsarCore library.",
                "IsarError: Incorrect Isar Core version: Required 3.3.2 found 3.4.1.",
                "#0      initializeCoreBinary (package:isar_community/src/native/isar_core.dart:78:7)",
                "#1      openIsar (package:isar_community/src/native/open.dart:81:3)",
            ),
        )
    }

    @Test
    fun ignoresWhatComesBefore() {
        assertEquals(
            "StateError: Bad state: no element",
            error("some other error", "Unhandled Exception: StateError: Bad state: no element", ""),
        )
    }

    @Test
    fun keepsAtMostThreeLines() {
        assertEquals(
            "A\nB\nC",
            error("Unhandled Exception: A", "B", "C", "D", "E"),
        )
    }

    @Test
    fun nothingWithoutAnUnhandledException() {
        assertNull(error("flutter: hello", "Another exception was thrown: x"))
    }

    @Test
    fun cutsAVeryLongMessage() {
        val message = error("Unhandled Exception: " + "x".repeat(2000)) ?: ""
        assertEquals(601, message.length)
        assertEquals('…', message.last())
    }
}
