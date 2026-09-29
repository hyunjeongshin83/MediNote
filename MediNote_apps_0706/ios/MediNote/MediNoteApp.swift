import SwiftUI

// MediNote (메디노트) - iOS 앱 진입점
//
// 앱 화면(예방접종·복약 안내)은 번들에 포함된 index.html 웹앱을 그대로 사용합니다.
// - 오프라인: 인터넷 없이도 열립니다(HTML이 앱 안에 포함됨).
// - 로컬 저장: WKWebView의 저장소(local storage)를 사용해 기기 안에 데이터를 보관합니다.
// 복약 알림의 「복용했어요」·「10분 뒤」는 앱이 꺼져 있어도 옵니다 — iOS 가 앱을 뒤에서 띄워 알림 센터 delegate 를
// 부르는데, 그 delegate 는 앱이 다 뜨기 전에 걸려 있어야 합니다. WebView 를 만들 때(makeUIView) 거는 것은
// 뒤에서 뜬 앱에서는 화면이 없어 아예 안 걸립니다 (#47 MN-47-2). 여기서 MedNotifier.shared 를 만들어 겁니다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = MedNotifier.shared   // init 에서 UNUserNotificationCenter.current().delegate = self
        return true
    }
}

@main
struct MediNoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea() // 앱을 전체 화면으로
        }
    }
}
