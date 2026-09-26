import SwiftUI
import WebKit
import HealthKit

// MediNote (메디노트) — iOS 셸 (2026-09-25 · #14 MN-14-2 · #16 MN-16-6 · #20 MN-20-3)
//
// 앱 안에 포함된 index.html 을 WKWebView 로 보여줍니다.
// index.html 은 손으로 만든 파일이 아닙니다 — 저장소 맨 위의 MediNote_app.html 에서
// tools/build-packaged-app.py 가 만듭니다. 안드로이드와 같은 파일입니다.
//
// 안드로이드 셸(MainActivity.kt)과 같은 다리(window.Native)를 놓습니다.
//   platform() · healthAvailable() · requestHealth() · readHealth()   → HealthKitManager (걸음·심박·수면)
//   medsNative() · scheduleMeds(json) · medsLogTake()                  → MedNotifier (복약 알림 · 앱을 닫아도 울림)
// 값은 기기 안에서만 씁니다. 「클라우드에 저장」은 웹 화면에서 사용자가 눌렀을 때만 갑니다.
//
// 아직 안 되는 것: Google 로그인(OAuth)은 file:// 안에서 돌아오지 못합니다 (#20 MN-20-2 — 배포 주소가 정해져야 합니다).
// Web Bluetooth 는 WKWebView 에 없습니다 — 혈압계·체온계는 HealthKit(건강 앱) 경유로 들어옵니다.
struct ContentView: View {
    var body: some View {
        WebView()
            .ignoresSafeArea()
    }
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // localStorage — 기기 안에 보관
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "Native")
        ucc.addUserScript(WKUserScript(
            source: NativeBridge.script(healthAvailable: HKHealthStore.isHealthDataAvailable()),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        context.coordinator.web = webView
        MedNotifier.shared.web = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var web: WKWebView?
        private let health = HealthKitManager()

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let fn = body["fn"] as? String else { return }
            switch fn {
            case "requestHealth":
                health.requestAuthorization { ok in
                    if ok { self.pushHealth() }
                    else { self.js("window.onNativeHealth && window.onNativeHealth({\"error\":\"denied\"})") }
                }
            case "readHealth":
                pushHealth()
            case "scheduleMeds":
                MedNotifier.shared.schedule(json: body["json"] as? String ?? "")
            case "medsLogAck":
                MedNotifier.shared.clearLog()
            default:
                break
            }
        }

        private func pushHealth() {
            health.readSummary { json in
                self.js("window.onNativeHealth && window.onNativeHealth(\(json))")
            }
        }

        func js(_ code: String) {
            DispatchQueue.main.async { self.web?.evaluateJavaScript(code, completionHandler: nil) }
        }

        // 우리 화면(file://)만 이 안에서 엽니다. 바깥 링크는 Safari 로.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme != "file",
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MedNotifier.shared.pushLogToWeb()
        }
    }
}

/// 웹 화면이 부르는 window.Native — 안드로이드의 addJavascriptInterface 와 같은 모양으로 맞춥니다.
/// 동기 값이 필요한 것(healthAvailable · medsLogTake)은 스크립트 안에 미리 넣어 둡니다.
enum NativeBridge {
    static func script(healthAvailable: Bool) -> String {
        """
        (function(){
          if (window.Native) return;
          var post = function(m){ try { window.webkit.messageHandlers.Native.postMessage(m); } catch(e) {} };
          window.__mnMedsLog = "[]";
          window.Native = {
            platform: function(){ return "ios"; },
            healthAvailable: function(){ return \(healthAvailable ? "true" : "false"); },
            healthStatus: function(){ return "\(healthAvailable ? "available" : "none")"; },
            openHealthConnectInstall: function(){},
            requestHealth: function(){ post({fn:"requestHealth"}); },
            readHealth: function(){ post({fn:"readHealth"}); },
            medsNative: function(){ return true; },
            scheduleMeds: function(j){ post({fn:"scheduleMeds", json:String(j)}); },
            medsLogTake: function(){ var s = window.__mnMedsLog || "[]"; window.__mnMedsLog = "[]"; post({fn:"medsLogAck"}); return s; },
            exactAlarmAllowed: function(){ return true; }
          };
        })();
        """
    }
}

#Preview {
    ContentView()
}
