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
 * assets/index.html 은 손으로 만든 파일이 아닙니다.
 * 저장소 맨 위의 MediNote_app.html 에서 tools/build-packaged-app.py 가 만듭니다.
 * React·Supabase·접속 설정이 그 파일 안에 들어 있어, 인터넷 없이도 화면이 뜹니다.
 *
 * [나중에 확장할 부분]
 * - 더 큰 로컬 데이터베이스가 필요하면, WebView의 저장소 대신
 *   Room(안드로이드 기본 DB)을 붙이고 JavascriptInterface로 연결하면 됩니다.
 * - 글꼴은 아직 인터넷에서 받습니다. 인터넷이 없으면 기기 기본 글꼴로 보입니다
 *   (글자는 그대로 읽힙니다). 글꼴까지 넣으려면 assets 에 함께 담아야 합니다.
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
