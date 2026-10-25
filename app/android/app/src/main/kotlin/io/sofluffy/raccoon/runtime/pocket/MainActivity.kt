package io.sofluffy.raccoon.runtime.pocket

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A fragment activity, because local_auth shows its prompt as a fragment.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val pairing = Pocket.start(this)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rr_pocket/pairing")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(
                    mapOf(
                        "address" to pairing.address(),
                        "port" to Pocket.CONTROL_PORT,
                        "code" to pairing.code,
                        "name" to Build.MODEL,
                        "fingerprint" to Pocket.fingerprint(),
                    ),
                )
                "scan" -> CodeScanner.scan(this, result)
                "takeLink" -> result.success(Pocket.takeLink())
                "offerPairing" -> when (val token = call.argument<String>("token")) {
                    null, "" -> result.error("bad_token", "no token", null)
                    else -> result.success(Pocket.offerPairing(token))
                }
                else -> result.notImplemented()
            }
        }
        this.channel = channel
        Pocket.prompt.attach(channel)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.let { Pocket.prompt.detach(it) }
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // From PairLinkActivity. While a project runs nothing answers; the
        // link waits for RR Pocket's own screen, which takes it when it starts.
        if (Pocket.hasLink()) channel?.invokeMethod("linkArrived", null)
    }

    override fun onResume() {
        super.onResume()
        Pocket.prompt.setShowing(true)
    }

    override fun onPause() {
        Pocket.prompt.setShowing(false)
        super.onPause()
    }
}
