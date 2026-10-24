package io.sofluffy.raccoon.runtime.pocket

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

/**
 * Tells computers on the Wi-Fi that RR Pocket is here, as the DNS-SD service
 * `_rrpocket._tcp` (docs/pairing.md), for as long as the process runs. The
 * system drops the registration when the process dies. Registering needs no
 * permission beyond INTERNET (NsdManager in API 35-37 asks for none).
 */
class Advertiser(context: Context) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager

    fun start(port: Int, model: String, flutterVersion: String) {
        val service = NsdServiceInfo().apply {
            serviceName = model
            serviceType = TYPE
            setPort(port)
            setAttribute("v", "1")
            setAttribute("model", model)
            setAttribute("flutter", flutterVersion)
        }
        nsd.registerService(service, NsdManager.PROTOCOL_DNS_SD, Listener)
    }

    private object Listener : NsdManager.RegistrationListener {
        override fun onServiceRegistered(service: NsdServiceInfo) {
            // The system may rename it, "Pixel 7 (2)", when the name is taken.
            Log.i(TAG, "advertising ${service.serviceName} as $TYPE")
        }

        override fun onRegistrationFailed(service: NsdServiceInfo, error: Int) {
            Log.w(TAG, "could not advertise $TYPE (error $error); pair by QR code or by typing")
        }

        override fun onServiceUnregistered(service: NsdServiceInfo) {}

        override fun onUnregistrationFailed(service: NsdServiceInfo, error: Int) {}
    }

    companion object {
        const val TYPE = "_rrpocket._tcp"
        private const val TAG = "RRPocket"
    }
}
