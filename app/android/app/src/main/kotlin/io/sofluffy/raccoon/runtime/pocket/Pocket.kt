package io.sofluffy.raccoon.runtime.pocket

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterJNI
import java.util.Date
import kotlin.concurrent.thread
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
    private var link: String? = null

    private var relay: VmRelay? = null

    /** Set by [start]: the phone's TLS key and certificate. */
    private var identity: TlsIdentity? = null

    /** The QR code the user last allowed pairing with. */
    private val offers = PairOffers()

    /** The running project's first seconds, watched for a startup error. */
    private var watch: StartupErrorWatch? = null

    /** Where /pair asks the user. */
    val prompt = ScreenPrompt()

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
        val identity = TlsIdentity.loadOrCreate(File(context.filesDir, "tls")).also { identity = it }
        relay = VmRelay(VM_RELAY_PORT, secure = identity::serve, vmServiceUri = ::vmServiceUri)
            .also { it.start() }
        // Learn the engine's VM service address now, before anything
        // attaches: a tool attached with DDS (run_probe.sh's driver does)
        // makes FlutterJNI report the computer's address instead.
        thread(isDaemon = true, name = "rr-pocket-vm-service") {
            repeat(100) {
                if (vmServiceUri() != null) return@thread
                Thread.sleep(100)
            }
        }
        PocketServer(
            port = CONTROL_PORT,
            code = pairing.code,
            accepts = pairing::accepts,
            root = File(context.filesDir, "pocket"),
            hello = { hello(context) },
            actions = object : PocketServer.Actions {
                override fun run(bundle: File) = runInView(bundle)

                override fun stop() = stopProject()
            },
            prompt = prompt,
            secure = identity::serve,
            offers = offers,
        ).start()
        Advertiser(context).start(CONTROL_PORT, Build.MODEL, context.getString(R.string.rr_flutter_version))
        Log.i("RRPocket", "pair with: ${pairing.address() ?: "(offline)"} ${pairing.code}")
        return pairing
    }

    private fun activity() = activity.get()

    /** Replaces the watch on the project's first seconds; null ends it. */
    @Synchronized
    private fun swapWatch(next: StartupErrorWatch?) {
        watch?.stop()
        watch = next
        next?.start()
    }

    /** Back to RR Pocket's own screen: a new engine, without the project. */
    private fun stopProject() {
        swapWatch(null)
        relay?.closeAll()
        activity()?.let {
            it.runOnUiThread {
                StartupErrorPanel.dismiss()
                it.recreate()
            }
        }
    }

    /** Shows a startup error over the frozen screen; the panel can go back. */
    private fun showStartupError(message: String) {
        activity()?.let {
            it.runOnUiThread { StartupErrorPanel.show(it, message, ::stopProject) }
        }
    }

    /**
     * Keeps [token], from a QR code the user allowed, for the computer to
     * redeem, and returns what the phone posts to it instead of the code:
     * the certificate's fingerprint and the proof it came from this phone.
     */
    @Synchronized
    fun offerPairing(token: String): Map<String, String>? {
        val identity = identity ?: return null
        val proof = offers.offer(token, identity.fingerprint)
        return mapOf("fingerprint" to identity.fingerprint, "proof" to proof)
    }

    /** An rrpocket://pair link for RR Pocket's own screen to take. */
    @Synchronized
    fun keepLink(link: String) {
        this.link = link
    }

    @Synchronized
    fun takeLink(): String? = link.also { link = null }

    @Synchronized
    fun hasLink() = link != null

    private fun hello(context: Context) = JSONObject()
        .put("name", "RR Pocket")
        .put("flutterVersion", context.getString(R.string.rr_flutter_version))
        .put("engineRevision", context.getString(R.string.rr_engine_revision))
        .put("vmRelayPort", VM_RELAY_PORT)
        .put("plugins", plugins(context))
        .toString()

    /** The Android plugin packages and versions built in, by tool/build_apk.sh. */
    private fun plugins(context: Context) = try {
        JSONObject(context.assets.open("rr_plugins.json").use { it.readBytes().decodeToString() })
    } catch (_: Exception) {
        JSONObject()
    }

    /**
     * Restarts the running engine into [bundle], the way hot restart does:
     * the engine's `_flutter.runInView` takes a kernel and an assets folder
     * from the filesystem, which a fresh launch on Android does not.
     * From the first call on, RR Pocket's own screen may be gone.
     */
    private fun runInView(bundle: File): String {
        prompt.projectRunning = true
        // A new session: whatever the last one left attached goes.
        relay?.closeAll()
        // Before the restart: an error in the project's first milliseconds
        // is logged before the watch could start.
        val since = Date()
        val path = try {
            restartInto(bundle)
        } catch (e: Exception) {
            prompt.projectRunning = false
            throw e
        }
        swapWatch(StartupErrorWatch(since, onError = ::showStartupError))
        return path
    }

    private fun restartInto(bundle: File): String {
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
