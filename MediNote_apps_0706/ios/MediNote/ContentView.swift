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
//   알림 단추(복용했어요)는 앱이 꺼져 있어도 받아야 하므로 알림 센터 delegate 는 MediNoteApp 의 AppDelegate 가
//   앱이 뜨는 순간 겁니다 — 여기(makeUIView)서 거는 것으로는 늦습니다 (#47 MN-47-2)
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
        // iOS 「텍스트 크기」(Dynamic Type)를 웹 화면에 옮깁니다 — WKWebView 는 혼자서는 따르지 않습니다.
        // 상한 200% (APP-STYLE 3-2-2 · MediNote #31 MN-31-5). 설정이 바뀌면 Coordinator 가 다시 넣습니다.
        ucc.addUserScript(WKUserScript(
            source: TextSizeBridge.script(percent: TextSizeBridge.percent()),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator          // target="_blank" 링크 (#78 MN-78-2)
        webView.scrollView.bounces = false
        context.coordinator.web = webView
        MedNotifier.shared.web = webView
        context.coordinator.watchTextSize()

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
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

        /// 사용자가 설정 앱에서 「텍스트 크기」를 바꾸면 열린 화면에도 바로 반영합니다 (MN-31-5)
        func watchTextSize() {
            NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.js(TextSizeBridge.apply(percent: TextSizeBridge.percent()))
            }
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

        // target="_blank" 링크 — UIDelegate 가 없으면 WKWebView 는 아무 일도 하지 않습니다. 「웹 주소에서 해 주세요」 링크가
        // 눌러도 안 열리던 것 (#78 MN-78-2). 안드로이드(shouldOverrideUrlLoading)처럼 바깥 브라우저로 넘깁니다.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url, url.scheme != "file" {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MedNotifier.shared.pageDidLoad()   // 화면이 뜨기 전에 보낸 JS(알림을 눌러 켠 앱의 복약 창 열기)를 이제 보냅니다 (#78 MN-78-3)
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
            // 빈 것을 가져갈 때는 지우라고 하지 않습니다 — 화면이 먼저 (빈 값을) 가져가고 그 뒤 didFinish 가 기록을 올리므로,
            // 빈 가져가기에도 지우면 앱이 닫혀 있는 동안 누른 「복용했어요」가 올라오기 전에 사라집니다 (#47 MN-47-3)
            medsLogTake: function(){ var s = window.__mnMedsLog || "[]"; window.__mnMedsLog = "[]"; if (s !== "[]") post({fn:"medsLogAck"}); return s; },
            exactAlarmAllowed: function(){ return true; },
            openExactAlarmSettings: function(){}
          };
        })();
        """
    }
}

/// iOS 「텍스트 크기」 → 웹 화면 (APP-STYLE 3-2-2 · MN-31-5)
/// Dynamic Type 의 본문 17pt 가 지금 몇 pt 인지로 배율을 구해 <html> 의 -webkit-text-size-adjust 에 넣습니다.
/// 상한 200% — 그 위 배율은 검사한 적이 없습니다. 더 키우려면 손가락 확대(maximum-scale 없음).
enum TextSizeBridge {
    static func percent() -> Int {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17)
        let pct = Int((scaled / 17 * 100).rounded())
        return min(max(pct, 100), 200)
    }
    static func apply(percent: Int) -> String {
        "document.documentElement.style.webkitTextSizeAdjust='\(percent)%';"
    }
    static func script(percent: Int) -> String {
        "(function(){ try { \(apply(percent: percent)) } catch(e) {} })();"
    }
}

#Preview {
    ContentView()
}
