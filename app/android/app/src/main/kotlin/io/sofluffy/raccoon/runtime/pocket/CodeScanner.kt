package io.sofluffy.raccoon.runtime.pocket

import android.app.Activity
import android.os.SystemClock
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.MethodChannel

/**
 * Google's code scanner, QR codes only. It runs in Play services, so it needs
 * no camera permission; where Play services or its scanner module is missing
 * it answers `unavailable` and the Dart side opens RR Pocket's own scanner.
 * Answers `{status: scanned, text}`, `{status: cancelled}` or
 * `{status: unavailable}`.
 */
object CodeScanner {
    fun scan(activity: Activity, result: MethodChannel.Result) {
        val playServices = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity)
        if (playServices != ConnectionResult.SUCCESS) return result.success(status("unavailable"))
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        val scanner = GmsBarcodeScanning.getClient(activity, options)
        val modules = ModuleInstall.getClient(activity)
        // Play services downloads the scanner on first use, which can take
        // minutes (seen on a Pixel 7, 2026-10-24); RR Pocket's own scanner
        // stands in meanwhile.
        val asked = SystemClock.elapsedRealtime()
        modules.areModulesAvailable(scanner)
            .addOnSuccessListener { availability ->
                val ms = SystemClock.elapsedRealtime() - asked
                Log.i("RRPocket", "Google's scanner installed: ${availability.areModulesAvailable()} ($ms ms to find out)")
                if (availability.areModulesAvailable()) return@addOnSuccessListener start(scanner, result)
                modules.installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
                result.success(status("unavailable"))
            }
            .addOnFailureListener { result.success(status("unavailable")) }
    }

    private fun start(scanner: GmsBarcodeScanner, result: MethodChannel.Result) {
        scanner.startScan()
            .addOnSuccessListener { result.success(status("scanned") + ("text" to it.rawValue)) }
            .addOnCanceledListener { result.success(status("cancelled")) }
            .addOnFailureListener { error ->
                Log.w("RRPocket", "Google's scanner failed: ${error.javaClass.name} ${(error as? MlKitException)?.errorCode}: ${error.message}")
                if (unavailable(error)) return@addOnFailureListener result.success(status("unavailable"))
                // Back in the scanner ends it as INTERNAL, "Failed to scan
                // code.", not as cancelled (Pixel 7, Play services 26.11,
                // 2026-10-24); the X button cancels. Back is no error to show.
                if (error is MlKitException && error.errorCode == MlKitException.INTERNAL) {
                    return@addOnFailureListener result.success(status("cancelled"))
                }
                result.error("scan_failed", error.message ?: error.toString(), null)
            }
    }

    // Play services or the scanner module went missing after the check.
    private fun unavailable(error: Exception) =
        (error is MlKitException && error.errorCode == MlKitException.UNAVAILABLE) || error is ApiException

    private fun status(name: String) = mapOf<String, Any?>("status" to name)
}
