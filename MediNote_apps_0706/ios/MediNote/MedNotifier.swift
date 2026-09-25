import Foundation
import UserNotifications
import WebKit

/**
 복약 알림 — 앱을 닫아도 울리게 (iOS · #16 MN-16-6). 안드로이드 MedScheduler.kt 와 짝입니다.

 웹 화면(복약 알림 레이어)이 Native.scheduleMeds(json) 으로 일정을 넘기면
   json = {on, quiet:{from,to}, items:[{id,name,times:["08:00",…]}]}
 매일 그 시각에 울리는 지역 알림(UNCalendarNotificationTrigger)을 겁니다. 서버는 없습니다.
 조용한 시간 안의 시각은 걸지 않습니다(웹과 같은 규칙).

 알림의 「복용했어요」·「10분 뒤」는 여기서 받아 기록(UserDefaults)에 남기고,
 웹이 열리면 window.__mnMedsLog 로 넘겨 웹의 기록에 합쳐집니다 (Native.medsLogTake).
*/
final class MedNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MedNotifier()
    weak var web: WKWebView?

    private let center = UNUserNotificationCenter.current()
    private let logKey = "medinote.meds.log"
    private let category = "MNMD"

    private override init() {
        super.init()
        center.delegate = self
        let taken = UNNotificationAction(identifier: "taken", title: "복용했어요", options: [])
        let later = UNNotificationAction(identifier: "later", title: "10분 뒤", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [taken, later], intentIdentifiers: [], options: [])
        ])
    }

    // MARK: 일정

    func schedule(json: String) {
        center.removeAllPendingNotificationRequests()
        guard let data = json.data(using: .utf8),
              let sc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              sc["on"] as? Bool == true,
              let items = sc["items"] as? [[String: Any]] else { return }
        let quiet = sc["quiet"] as? [String: String] ?? [:]

        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            guard ok else {
                self.js("window.onNativeMeds && window.onNativeMeds({granted:false})")
                return
            }
            for it in items {
                let id = it["id"] as? String ?? ""
                let name = it["name"] as? String ?? ""
                for t in it["times"] as? [String] ?? [] {
                    guard let hm = Self.hm(t), !Self.inQuiet(minutes: hm.0 * 60 + hm.1, quiet: quiet) else { continue }
                    var dc = DateComponents()
                    dc.hour = hm.0
                    dc.minute = hm.1
                    self.add(id: id, name: name, time: t,
                             trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true), suffix: "")
                }
            }
            self.js("window.onNativeMeds && window.onNativeMeds({granted:true})")
        }
    }

    private func add(id: String, name: String, time: String, trigger: UNNotificationTrigger, suffix: String) {
        let c = UNMutableNotificationContent()
        c.title = "메디노트 복약 알림"
        c.body = "\(name) 드실 시간이에요 (\(time))"
        c.sound = .default
        c.categoryIdentifier = category
        c.userInfo = ["id": id, "name": name, "time": time]
        center.add(UNNotificationRequest(identifier: "mnmd-\(id)-\(time)\(suffix)", content: c, trigger: trigger))
    }

    static func hm(_ s: String) -> (Int, Int)? {
        let p = s.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// 조용한 시간 안인지 — 웹 화면·안드로이드와 같은 규칙
    static func inQuiet(minutes: Int, quiet: [String: String]) -> Bool {
        func mins(_ s: String?, _ d: Int) -> Int { if let s = s, let hm = hm(s) { return hm.0 * 60 + hm.1 }; return d }
        let a = mins(quiet["from"], 21 * 60 + 30), b = mins(quiet["to"], 8 * 60)
        return a <= b ? (minutes >= a && minutes < b) : (minutes >= a || minutes < b)
    }

    // MARK: 알림 단추

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound]) } else { completionHandler([.alert, .sound]) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let u = response.notification.request.content.userInfo
        let id = u["id"] as? String ?? "", name = u["name"] as? String ?? "", time = u["time"] as? String ?? ""
        switch response.actionIdentifier {
        case "taken":
            addLog(action: "taken", id: id, name: name, time: time)
        case "later":
            addLog(action: "later", id: id, name: name, time: time)
            add(id: id, name: name, time: time,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false), suffix: "-later")
        default:
            js("window.MediNoteMeds && window.MediNoteMeds.open()")
        }
        pushLogToWeb()
        completionHandler()
    }

    // MARK: 기록

    private func addLog(action: String, id: String, name: String, time: String) {
        var arr = UserDefaults.standard.array(forKey: logKey) as? [[String: Any]] ?? []
        arr.append(["action": action, "id": id, "name": name, "time": time,
                    "at": Int64(Date().timeIntervalSince1970 * 1000)])
        if arr.count > 500 { arr.removeFirst(arr.count - 500) }
        UserDefaults.standard.set(arr, forKey: logKey)
    }

    func clearLog() { UserDefaults.standard.removeObject(forKey: logKey) }

    /// 웹의 Native.medsLogTake() 가 읽어 갈 자리에 기록을 올려 둡니다
    func pushLogToWeb() {
        let arr = UserDefaults.standard.array(forKey: logKey) as? [[String: Any]] ?? []
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: data, encoding: .utf8),
              let quoted = try? JSONSerialization.data(withJSONObject: [s]),
              let q = String(data: quoted, encoding: .utf8) else { return }
        // ["..."] 에서 바깥 대괄호를 벗겨 JS 문자열 리터럴로 씁니다
        let lit = String(q.dropFirst().dropLast())
        js("window.__mnMedsLog=\(lit)")
    }

    private func js(_ code: String) {
        DispatchQueue.main.async { self.web?.evaluateJavaScript(code, completionHandler: nil) }
    }
}
