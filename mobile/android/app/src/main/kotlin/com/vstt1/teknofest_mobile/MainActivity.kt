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
 * doğrulama başarısız olur.
 *
 * Bu kanal, Dart tarafının NV akışı süresince process'i cellular network'e
 * bind etmesini sağlıyor.
 *
 * DİKKAT — `bindProcessToNetwork` TÜM UYGULAMAYI o ağa bağlar (tek bir isteği
 * değil). Bağlanılan [Network] geçersizleşirse (hücre değişimi, 5G↔LTE geçişi,
 * `requestNetwork` ile açılan geçici ağın serbest bırakılması) uygulamanın
 * HİÇBİR isteği çıkamaz: her soket anında "connection failed" ile patlar,
 * sunucu tarafında isteğin izi bile olmaz.
 *
 * 7 Ağustos gecesi tam olarak bu yaşandı: backend sağlamdı (tarayıcıdan
 * `/health` açılıyordu) ama uygulama login isteğini bile gönderemiyordu.
 * Aşağıdaki üç koruma bunun için var:
 *   1. [releaseBinding] her yeni bind'den ÖNCE çağrılır — eskiden her deneme
 *      bir NetworkCallback daha sızdırıyordu ve sızan callback'ler unbind'den
 *      SONRA bile `bindProcessToNetwork` çağırıp bağlamayı geri getiriyordu.
 *   2. [ConnectivityManager.NetworkCallback.onLost] override edilir — bağlı
 *      olduğumuz ağ düşerse bağlama anında bırakılır (kendi kendini onarır).
 *   3. [onDestroy] son çare temizlik.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.vstt1.teknofest_mobile/cellular_network"
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val connectivityManager: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindCellular" -> bindCellular(result)
                    "unbind" -> {
                        releaseBinding()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Process bağlamasını bırakır ve kayıtlı callback'i iptal eder.
     * Idempotent: bağlama/callback yoksa sessizce hiçbir şey yapmaz, bu yüzden
     * Dart tarafı "bind başarılı mıydı" diye düşünmeden her zaman çağırabilir.
     */
    private fun releaseBinding() {
        val cm = connectivityManager
        cm.bindProcessToNetwork(null)
        networkCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (e: IllegalArgumentException) {
                // Zaten unregister edilmiş olabilir — yok say.
            }
        }
        networkCallback = null
    }

    private fun bindCellular(result: MethodChannel.Result) {
        // Sızıntı koruması: önceki denemeden kalan callback varsa ÖNCE temizle.
        releaseBinding()

        val cm = connectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            // Yalnızca gerçekten internete çıkabilen bir hücresel ağ isteniyor;
            // aksi halde bağlanılan ağdan hiçbir istek geçmeyebilir.
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        var resultSent = false
        fun sendOnce(value: Boolean) {
            if (resultSent) return
            resultSent = true
            runOnUiThread { result.success(value) }
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                cm.bindProcessToNetwork(network)
                sendOnce(true)
            }

            override fun onUnavailable() {
                // requestNetwork zaman aşımı da buraya düşer — Dart tarafı
                // sonsuza dek beklemez.
                sendOnce(false)
            }

            override fun onLost(network: Network) {
                // Bağlandığımız ağ düştü: bağlamayı BIRAK, yoksa uygulamanın
                // tamamı ölü bir Network'e bağlı kalır (yukarıdaki nota bak).
                cm.bindProcessToNetwork(null)
            }
        }
        networkCallback = callback

        try {
            cm.requestNetwork(request, callback, CELLULAR_REQUEST_TIMEOUT_MS)
        } catch (e: Exception) {
            // Kayıt edilemedi: yarım kalmış durum bırakma.
            releaseBinding()
            sendOnce(false)
        }
    }

    override fun onDestroy() {
        releaseBinding()
        super.onDestroy()
    }

    companion object {
        /**
         * Native taraf bu süre içinde kesin bir cevap üretir (onAvailable ya da
         * onUnavailable). Dart tarafındaki bekleme payı bundan UZUN olmalı —
         * kısa olursa Dart "başarısız" sanıp unbind'i atlar, native taraf ise
         * saniyeler sonra bağlamayı yapar ve bağlama kalıcı olarak asılı kalır.
         */
        const val CELLULAR_REQUEST_TIMEOUT_MS = 5000
    }
}
