package io.sofluffy.raccoon.runtime.pocket

import android.app.Activity
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterJNI
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder

/**
 * The servers a computer drives RR Pocket through, started once per process
 * and kept across engine restarts, which only replace the Dart side.
 */
object Pocket {
    const val CONTROL_PORT = 8100
    const val VM_RELAY_PORT = 8101

    private var pairing: Pairing? = null
    private var activity = WeakReference<Activity>(null)

    @Volatile
    private var firstVmServiceUri: String? = null

    /**
     * The engine's own VM service. The Dart VM lives as long as the process,
     * so the first address it reports stays right; FlutterJNI's later ones
     * are wrong: once the tool attaches, it reports the tool's DDS, which
     * is on the computer.
     */
    fun vmServiceUri(): String? = firstVmServiceUri ?: synchronized(this) {
        firstVmServiceUri ?: FlutterJNI.getVMServiceUri()?.also { firstVmServiceUri = it }
    }

    @Synchronized
    fun start(activity: Activity): Pairing {
        this.activity = WeakReference(activity)
        pairing?.let { return it }
        val context = activity.applicationContext
        val pairing = Pairing(context).also { pairing = it }
        VmRelay(VM_RELAY_PORT, ::vmServiceUri).start()
        PocketServer(
            port = CONTROL_PORT,
            pairing = pairing,
            root = File(context.filesDir, "pocket"),
            hello = { hello(context) },
            actions = object : PocketServer.Actions {
                override fun run(bundle: File) = runInView(bundle)

                override fun stop() {
                    activity()?.let { it.runOnUiThread { it.recreate() } }
                }
            },
        ).start()
        Log.i("RRPocket", "pair with: ${pairing.address() ?: "(offline)"} ${pairing.code}")
        return pairing
    }

    private fun activity() = activity.get()

    private fun hello(context: Context) = JSONObject()
        .put("name", "RR Pocket")
        .put("flutterVersion", context.getString(R.string.rr_flutter_version))
        .put("engineRevision", context.getString(R.string.rr_engine_revision))
        .put("vmRelayPort", VM_RELAY_PORT)
        .toString()

    /**
     * Restarts the running engine into [bundle], the way hot restart does:
     * the engine's `_flutter.runInView` takes a kernel and an assets folder
     * from the filesystem, which a fresh launch on Android does not.
     */
    private fun runInView(bundle: File): String {
        val vm = vmServiceUri() ?: error("the engine has no VM service yet")
        val base = vm.trimEnd('/')
        val views = JSONObject(get("$base/_flutter.listViews"))
            .getJSONObject("result").getJSONArray("views")
        if (views.length() == 0) error("no Flutter view to run in")
        val view = views.getJSONObject(0).getString("id")
        val result = JSONObject(
            get(
                "$base/_flutter.runInView?" + query(
                    "viewId" to view,
                    "mainScript" to File(bundle, "kernel_blob.bin").path,
                    "assetDirectory" to bundle.path,
                ),
            ),
        )
        if (!result.has("result")) error("runInView failed: $result")
        return URI(vm).path
    }

    private fun query(vararg pairs: Pair<String, String>) =
        pairs.joinToString("&") { (key, value) -> "$key=${URLEncoder.encode(value, "UTF-8")}" }

    private fun get(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 5000
        connection.readTimeout = 30000
        return connection.inputStream.use { it.readBytes().decodeToString() }
    }
}
