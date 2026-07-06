import SwiftUI

// MediNote (메디노트) - iOS 앱 진입점
//
// 앱 화면(예방접종·복약 안내)은 번들에 포함된 index.html 웹앱을 그대로 사용합니다.
// - 오프라인: 인터넷 없이도 열립니다(HTML이 앱 안에 포함됨).
// - 로컬 저장: WKWebView의 저장소(local storage)를 사용해 기기 안에 데이터를 보관합니다.
@main
struct MediNoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea() // 앱을 전체 화면으로
        }
    }
}
