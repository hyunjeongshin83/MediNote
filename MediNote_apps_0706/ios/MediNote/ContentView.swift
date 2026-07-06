import SwiftUI
import WebKit

// 앱 안에 포함된 index.html 을 WKWebView로 보여주는 화면입니다.
//
// [나중에 확장할 부분]
// - 더 큰 로컬 데이터베이스가 필요하면, WKWebView의 저장소 대신
//   iOS 기본 저장소(Core Data / SQLite)를 붙이고
//   WKScriptMessageHandler로 자바스크립트와 연결하면 됩니다.
// - React/폰트를 완전 오프라인으로 쓰려면, index.html이 참조하는
//   외부 CDN 파일도 번들에 함께 넣고 경로를 바꿔야 합니다.
struct ContentView: View {
    var body: some View {
        WebView()
            .ignoresSafeArea()
    }
}

struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 로컬 저장(local storage) 사용 - 기기 안에 데이터 보관
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 앱 번들에 포함된 index.html 로드 (오프라인)
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}

#Preview {
    ContentView()
}
