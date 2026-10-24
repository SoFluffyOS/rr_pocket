package io.sofluffy.raccoon.runtime.pocket

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Takes an rrpocket://pair link (from the camera app or a browser), keeps it
 * for RR Pocket's screen and brings that screen up. A link is never
 * MainActivity's own intent: Android starts a task again with its first
 * intent (after an update, or once the process has died), which would ask
 * about an old link again. Seen on a Pixel 7, 2026-10-24.
 */
class PairLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val link = intent?.data?.takeIf { it.scheme == "rrpocket" }
        if (savedInstanceState == null && link != null) Pocket.keepLink(link.toString())
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }
}
