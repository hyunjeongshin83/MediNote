package kr.medit.medinote

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * MediNote (메디노트) - Android 셸
 *
 * 앱 화면(예방접종·복약 안내)은 assets/index.html 에 번들된 웹앱을 그대로 사용합니다.
 * - 오프라인: 인터넷 없이도 앱이 열립니다(HTML이 앱 안에 포함됨).
 * - 로컬 저장: WebView의 DOM Storage(local storage)를 켜 두어, 기기 안에 데이터를 보관합니다.
 *
 * assets/index.html 은 손으로 만든 파일이 아닙니다.
 * 저장소 맨 위의 MediNote_app.html 에서 tools/build-packaged-app.py 가 만듭니다.
 * React·Supabase·접속 설정이 그 파일 안에 들어 있어, 인터넷 없이도 화면이 뜹니다.
 *
 * 네이티브가 더해 주는 것 (window.Native) — MN-14-2, 금연노트 셸과 같은 약속
 *   healthAvailable()  Health Connect 가 이 폰에 있는지
 *   requestHealth()    걸음·심박·수면 읽기 권한을 OS 화면으로 묻고, 허락되면 바로 읽어
 *                      window.onNativeHealth(json) 으로 돌려줌
 *   readHealth()       이미 권한이 있으면 읽어서 같은 콜백으로
 *   json = {steps, hrAvg, hrN, sleepMin, at} 또는 {error: "denied"|"unavailable"|"no-permission"|…}
 * 이 경로의 값은 웹 화면이 기기 localStorage(medinote:hc:v1)에만 둡니다. 서버로 보내지 않습니다.
 * (블루투스 읽기의 「클라우드에 저장」은 별개 경로입니다 — CLAUDE.md 3절)
 *
 * 화면은 지금처럼 file:///android_asset/ 에서 띄웁니다 (WebViewAssetLoader 로 바꿀지는 MN-20-2).
 * window.Native 는 건강 데이터를 돌려주므로, 지금 떠 있는 페이지가 우리 assets 일 때만 답합니다.
 *
 * [나중에 확장할 부분]
 * - 더 큰 로컬 데이터베이스가 필요하면, WebView의 저장소 대신
 *   Room(안드로이드 기본 DB)을 붙이고 JavascriptInterface로 연결하면 됩니다.
 * - 글꼴은 아직 인터넷에서 받습니다. 인터넷이 없으면 기기 기본 글꼴로 보입니다
 *   (글자는 그대로 읽힙니다). 글꼴까지 넣으려면 assets 에 함께 담아야 합니다.
 */
class MainActivity : ComponentActivity() {

    companion object { const val APP_ORIGIN = "file:///android_asset/" }

    private var web: WebView? = null
    private lateinit var health: HealthConnectManager

    /** 지금 떠 있는 페이지 주소. JavascriptInterface 는 UI 스레드가 아닌 곳에서 불려서 따로 둡니다. */
    @Volatile private var pageUrl: String? = null

    private val askHealth = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        if (granted.containsAll(health.permissions)) pushHealth()
        else callback("""{"error":"denied"}""")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        health = HealthConnectManager(this)
        setContent {
            MaterialTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { inner ->
                    MediNoteWebView(
                        modifier = Modifier.fillMaxSize().padding(inner),
                        bridge = Bridge(),
                        onPage = { pageUrl = it },
                        onCreated = { web = it },
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        web?.removeJavascriptInterface("Native")
        web = null
        super.onDestroy()
    }

    private fun isOurPage(): Boolean = pageUrl?.startsWith(APP_ORIGIN) == true

    private fun pushHealth() {
        lifecycleScope.launch {
            val json = try {
                health.readSummary().toString()
            } catch (e: Exception) {
                JSONObject().put("error", e.message ?: "read").toString()
            }
            callback(json)
        }
    }

    private fun callback(json: String) {
        runOnUiThread {
            val w = web ?: return@runOnUiThread
            if (!isOurPage()) return@runOnUiThread
            w.evaluateJavascript("window.onNativeHealth && window.onNativeHealth($json)", null)
        }
    }

    inner class Bridge {
        @JavascriptInterface fun platform(): String = "android"
        @JavascriptInterface fun healthAvailable(): Boolean = isOurPage() && health.isAvailable()
        @JavascriptInterface fun requestHealth() {
            if (!isOurPage()) return
            if (!health.isAvailable()) { callback("""{"error":"unavailable"}"""); return }
            lifecycleScope.launch {
                if (health.hasAllPermissions()) pushHealth()
                else askHealth.launch(health.permissions)
            }
        }
        @JavascriptInterface fun readHealth() {
            if (!isOurPage()) return
            lifecycleScope.launch {
                if (health.isAvailable() && health.hasAllPermissions()) pushHealth()
                else callback("""{"error":"no-permission"}""")
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
@Composable
fun MediNoteWebView(
    modifier: Modifier = Modifier,
    bridge: Any,
    onPage: (String?) -> Unit,
    onCreated: (WebView) -> Unit,
) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                // 링크를 앱 안에서 열기 (지금 동작 그대로). 페이지가 바뀌면 주소만 알려 줍니다.
                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                        onPage(url)
                        super.onPageStarted(view, url, favicon)
                    }
                }
                settings.apply {
                    javaScriptEnabled = true            // 웹앱 실행에 필요
                    domStorageEnabled = true            // 로컬 저장(local storage) 사용
                    databaseEnabled = true              // 로컬 DB 사용
                    cacheMode = WebSettings.LOAD_DEFAULT
                    // 번들된 자바스크립트가 파일에 접근해야 할 때를 대비
                    allowFileAccess = true
                    allowContentAccess = true
                }
                addJavascriptInterface(bridge, "Native")
                onCreated(this)
                // 앱 안에 포함된 HTML을 로드 (오프라인)
                loadUrl("file:///android_asset/index.html")
            }
        }
    )
}
