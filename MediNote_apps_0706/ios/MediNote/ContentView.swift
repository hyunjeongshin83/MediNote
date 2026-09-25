import SwiftUI
import WebKit

// 앱 안에 포함된 index.html 을 WKWebView로 보여주는 화면입니다.
//
// index.html 은 손으로 만든 파일이 아닙니다.
// 저장소 맨 위의 MediNote_app.html 에서 tools/build-packaged-app.py 가 만듭니다.
// React·Supabase·접속 설정이 그 파일 안에 들어 있어, 인터넷 없이도 화면이 뜹니다.
//
// [나중에 확장할 부분]
// - 더 큰 로컬 데이터베이스가 필요하면, WKWebView의 저장소 대신
//   iOS 기본 저장소(Core Data / SQLite)를 붙이고
//   WKScriptMessageHandler로 자바스크립트와 연결하면 됩니다.
// - HealthKitManager 는 아직 이 화면에 연결돼 있지 않습니다. 웹 화면에서 건강
//   데이터를 읽으려면 WKScriptMessageHandler 로 다리를 놓아야 합니다.
// - 글꼴은 아직 인터넷에서 받습니다. 인터넷이 없으면 기기 기본 글꼴로 보입니다.
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
