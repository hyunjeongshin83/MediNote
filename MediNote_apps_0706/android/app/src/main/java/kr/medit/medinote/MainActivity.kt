package kr.medit.medinote

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * MediNote (메디노트) — Android 셸 (2026-09-25 · 대표님 결정 C-18 · #14 MN-14-2 · #16 MN-16-6 · #20)
 *
 * 화면은 assets/index.html 에 든 웹앱 그대로입니다. 손으로 만든 파일이 아니라
 * 저장소 맨 위의 MediNote_app.html 에서 tools/build-packaged-app.py 가 만듭니다.
 *
 * 전과 다른 점
 *  - file:// 대신 WebViewAssetLoader 로 https://appassets.androidplatform.net/assets/index.html 을 띄웁니다.
 *    file:// 에서는 서비스워커·푸시·Web Bluetooth 가 돌지 않아 「웹에서 열어 주세요」로 돌려보냈습니다 (#20).
 *  - window.Native 다리로 HealthConnectManager 를 웹 화면에 잇습니다 (MN-14-2). 값은 기기 안에서만 씁니다.
 *  - 복약 알림을 AlarmManager 에 걸어 앱을 닫아도 울립니다 (MN-16-6 · MedScheduler.kt). 서버 없이 폰 안에서만.
 *
 * window.Native
 *  platform()          "android"
 *  healthAvailable()   Health Connect 가 이 폰에 있는지
 *  requestHealth()     걸음·심박·수면 읽기 권한을 OS 화면으로 묻고, 허락되면 읽어 window.onNativeHealth(json)
 *  readHealth()        이미 권한이 있으면 읽어서 같은 콜백으로
 *  medsNative()        true — 복약 알림을 폰이 맡는다는 표시. 웹은 자기 타이머를 끕니다
 *  scheduleMeds(json)  {on, quiet, items} 를 저장하고 알람을 다시 겁니다. 알림 권한이 없으면 먼저 묻습니다
 *  medsLogTake()       알림 단추로 남긴 기록(JSON 배열)을 돌려주고 비웁니다 — 웹이 자기 기록에 합칩니다
 *  exactAlarmAllowed() 정확한 시각 알람이 허용됐는지 (Android 12 이상)
 *  openExactAlarmSettings() 그 허용 화면 열기
 *
 * 남은 것: Google 로그인(OAuth)은 WebView 안에서 완결되지 않습니다 — 폰 브라우저로 넘겨 돌아오게 하는 것은 #20 MN-20-2.
 */
class MainActivity : ComponentActivity() {

    companion object { const val APP_HOST = "appassets.androidplatform.net" }

    private lateinit var web: WebView
    private lateinit var health: HealthConnectManager
    private var pageReady = false
    private var pendingJs: String? = null

    private val askHealth = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        if (granted.containsAll(health.permissions)) pushHealth()
        else callback("""{"error":"denied"}""")
    }

    private val askNotify = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        MedScheduler.reschedule(this)
        js("window.onNativeMeds && window.onNativeMeds(" + JSONObject().put("granted", granted) + ")")
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        health = HealthConnectManager(this)
        MedScheduler.ensureChannel(this)

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

                override fun onPageFinished(view: WebView, url: String?) {
                    pageReady = true
                    pendingJs?.let { view.evaluateJavascript(it, null) }
                    pendingJs = null
                }
            }
            addJavascriptInterface(Bridge(), "Native")
            loadUrl("https://$APP_HOST/assets/index.html")
        }
        setContentView(web)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    /* 알림을 눌러 들어오면 복약 알림 창을 엽니다 */
    private fun handleIntent(i: Intent?) {
        if (i?.getStringExtra("mnmd") == "open") js("window.MediNoteMeds && window.MediNoteMeds.open()")
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

    private fun callback(json: String) = js("window.onNativeHealth && window.onNativeHealth($json)")

    private fun js(code: String) {
        runOnUiThread {
            if (pageReady) web.evaluateJavascript(code, null) else pendingJs = code
        }
    }

    private fun notifyGranted(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

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

        /* ── 복약 알림 (MN-16-6) ── */
        @JavascriptInterface fun medsNative(): Boolean = true
        @JavascriptInterface fun scheduleMeds(json: String) {
            MedScheduler.save(this@MainActivity, json)
            runOnUiThread {
                val on = try { JSONObject(json).optBoolean("on", false) } catch (_: Exception) { false }
                if (on && !notifyGranted()) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                else MedScheduler.reschedule(this@MainActivity)
            }
        }
        @JavascriptInterface fun medsLogTake(): String = MedScheduler.takeLog(this@MainActivity)
        @JavascriptInterface fun exactAlarmAllowed(): Boolean =
            Build.VERSION.SDK_INT < 31 ||
                (getSystemService(ALARM_SERVICE) as android.app.AlarmManager).canScheduleExactAlarms()
        @JavascriptInterface fun openExactAlarmSettings() {
            if (Build.VERSION.SDK_INT >= 31) {
                try { startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).setData(android.net.Uri.parse("package:$packageName"))) } catch (_: Exception) {}
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (this::web.isInitialized && web.canGoBack()) web.goBack() else super.onBackPressed()
    }
}
