package kr.medit.medinote

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * MediNote (메디노트) — Android 셸 (2026-09-25 · 대표님 결정 C-18 · #14 MN-14-2 · #20)
 *
 * 화면은 assets/index.html 에 든 웹앱 그대로입니다. 손으로 만든 파일이 아니라
 * 저장소 맨 위의 MediNote_app.html 에서 tools/build-packaged-app.py 가 만듭니다.
 *
 * 전과 다른 점
 *  - file:// 대신 WebViewAssetLoader 로 https://appassets.androidplatform.net/assets/index.html 을 띄웁니다.
 *    file:// 에서는 서비스워커·푸시·Web Bluetooth 가 돌지 않아 「웹에서 열어 주세요」로 돌려보냈습니다 (#20).
 *  - window.Native 다리로 HealthConnectManager 를 웹 화면에 잇습니다 (MN-14-2). 값은 기기 안에서만 씁니다.
 *
 * window.Native
 *  platform()         "android"
 *  healthAvailable()  Health Connect 가 이 폰에 있는지
 *  requestHealth()    걸음·심박·수면 읽기 권한을 OS 화면으로 묻고, 허락되면 읽어 window.onNativeHealth(json)
 *  readHealth()       이미 권한이 있으면 읽어서 같은 콜백으로
 *
 * 남은 것: Google 로그인(OAuth)은 WebView 안에서 완결되지 않습니다 — 폰 브라우저로 넘겨 돌아오게 하는 것은 #20 MN-20-2.
 */
class MainActivity : ComponentActivity() {

    companion object { const val APP_HOST = "appassets.androidplatform.net" }

    private lateinit var web: WebView
    private lateinit var health: HealthConnectManager

    private val askHealth = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        if (granted.containsAll(health.permissions)) pushHealth()
        else callback("""{"error":"denied"}""")
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        health = HealthConnectManager(this)

        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                    loader.shouldInterceptRequest(request.url)

                /* window.Native 가 건강 데이터를 돌려주므로 이 WebView 안에서는 우리 화면만 엽니다.
                   바깥 링크(질병관리청 · tel: 등)는 폰의 브라우저·전화 앱으로 넘깁니다. */
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val url = request.url
                    if (url.host == APP_HOST) return false
                    try { startActivity(Intent(Intent.ACTION_VIEW, url)) } catch (_: Exception) {}
                    return true
                }
            }
            addJavascriptInterface(Bridge(), "Native")
            loadUrl("https://$APP_HOST/assets/index.html")
        }
        setContentView(web)
    }

    override fun onDestroy() {
        if (this::web.isInitialized) {
            (web.parent as? ViewGroup)?.removeView(web)
            web.stopLoading()
            web.removeJavascriptInterface("Native")
            web.destroy()
        }
        super.onDestroy()
    }

    private fun pushHealth() {
        lifecycleScope.launch {
            val json = try { health.readSummary().toString() } catch (e: Exception) { JSONObject().put("error", e.message ?: "read").toString() }
            callback(json)
        }
    }

    private fun callback(json: String) {
        runOnUiThread { web.evaluateJavascript("window.onNativeHealth && window.onNativeHealth($json)", null) }
    }

    inner class Bridge {
        @JavascriptInterface fun platform(): String = "android"
        @JavascriptInterface fun healthAvailable(): Boolean = health.isAvailable()
        @JavascriptInterface fun requestHealth() {
            if (!health.isAvailable()) { callback("""{"error":"unavailable"}"""); return }
            lifecycleScope.launch {
                if (health.hasAllPermissions()) pushHealth()
                else askHealth.launch(health.permissions)
            }
        }
        @JavascriptInterface fun readHealth() {
            lifecycleScope.launch {
                if (health.isAvailable() && health.hasAllPermissions()) pushHealth()
                else callback("""{"error":"no-permission"}""")
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (this::web.isInitialized && web.canGoBack()) web.goBack() else super.onBackPressed()
    }
}
