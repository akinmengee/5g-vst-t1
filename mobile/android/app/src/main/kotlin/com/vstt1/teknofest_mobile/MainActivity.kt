package com.vstt1.teknofest_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Number Verification, Turkcell'in cihazın o an bağlı olduğu HÜCRESEL (SIM)
 * bağlantıdan geldiğini görmek zorunda — istek Wi-Fi üzerinden giderse
 * doğrulama başarısız olur (bkz. mobile-final-sprint memory notu).
 *
 * Bu kanal, Dart tarafının tek bir HTTP isteği süresince process'i cellular
 * network'e bind etmesini sağlıyor. Wi-Fi kapalıysa zaten gerek yok ama final
 * günü sahada Wi-Fi'nin açık kalma ihtimaline karşı bir güvenlik katmanı.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.vstt1.teknofest_mobile/cellular_network"
    private var cellularNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "bindCellular" -> bindCellular(result)
                "unbind" -> unbind(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun bindCellular(result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .build()

        var resultSent = false
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                cellularNetwork = network
                cm.bindProcessToNetwork(network)
                if (!resultSent) {
                    resultSent = true
                    runOnUiThread { result.success(true) }
                }
            }

            override fun onUnavailable() {
                if (!resultSent) {
                    resultSent = true
                    runOnUiThread { result.success(false) }
                }
            }
        }
        networkCallback = callback

        try {
            cm.requestNetwork(request, callback, 5000)
        } catch (e: Exception) {
            result.error("CELLULAR_BIND_FAILED", e.message, null)
        }
    }

    private fun unbind(result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
        networkCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (e: IllegalArgumentException) {
                // zaten unregister edilmiş olabilir, yok say
            }
        }
        networkCallback = null
        cellularNetwork = null
        result.success(null)
    }
}
