package kr.medit.medinote

import android.os.Bundle
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

/**
 * MediNote (메디노트) - Android 셸
 *
 * 앱 화면(예방접종·복약 안내)은 assets/index.html 에 번들된 웹앱을 그대로 사용합니다.
 * - 오프라인: 인터넷 없이도 앱이 열립니다(HTML이 앱 안에 포함됨).
 * - 로컬 저장: WebView의 DOM Storage(local storage)를 켜 두어, 기기 안에 데이터를 보관합니다.
 *
 * [나중에 확장할 부분]
 * - 더 큰 로컬 데이터베이스가 필요하면, WebView의 저장소 대신
 *   Room(안드로이드 기본 DB)을 붙이고 JavascriptInterface로 연결하면 됩니다.
 * - React/폰트를 완전 오프라인으로 쓰려면, index.html이 참조하는
 *   외부 CDN 파일도 assets 폴더에 함께 넣어 경로를 바꿔야 합니다.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { inner ->
                    MediNoteWebView(modifier = Modifier.fillMaxSize().padding(inner))
                }
            }
        }
    }
}

@Composable
fun MediNoteWebView(modifier: Modifier = Modifier) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                webViewClient = WebViewClient() // 링크를 앱 안에서 열기
                settings.apply {
                    javaScriptEnabled = true            // 웹앱 실행에 필요
                    domStorageEnabled = true            // 로컬 저장(local storage) 사용
                    databaseEnabled = true              // 로컬 DB 사용
                    cacheMode = WebSettings.LOAD_DEFAULT
                    // 번들된 자바스크립트가 파일에 접근해야 할 때를 대비
                    allowFileAccess = true
                    allowContentAccess = true
                }
                // 앱 안에 포함된 HTML을 로드 (오프라인)
                loadUrl("file:///android_asset/index.html")
            }
        }
    )
}
