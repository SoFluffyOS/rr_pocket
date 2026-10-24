package io.sofluffy.raccoon.runtime.pocket

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A fragment activity, because local_auth shows its prompt as a fragment.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val pairing = Pocket.start(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rr_pocket/pairing")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(
                        mapOf(
                            "address" to pairing.address(),
                            "port" to Pocket.CONTROL_PORT,
                            "code" to pairing.code,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
