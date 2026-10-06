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
 앱이 꺼진 채로 단추를 누르면 iOS 가 앱을 뒤에서 띄워 didReceive 를 부르는데, 그때 delegate 가 이미 걸려 있어야
 합니다 — MediNoteApp 의 AppDelegate 가 앱이 뜨는 순간 MedNotifier.shared 를 만듭니다 (#47 MN-47-2).
*/
final class MedNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MedNotifier()
    weak var web: WKWebView?
    /// 화면이 다 뜨기 전에 보낸 JS 는 여기 모았다가 pageDidLoad() 에서 보냅니다 — 알림을 눌러 앱을 켜면 didReceive 가
    /// 화면보다 먼저 와서 「복약 창 열기」가 버려졌습니다. 안드로이드의 pendingJs 와 같은 구실 (#78 MN-78-3)
    private var ready = false
    private var pending: [String] = []

    private let center = UNUserNotificationCenter.current()
    private let logKey = "medinote.meds.log"
    private let quietKey = "medinote.meds.quiet"   // 「10분 뒤」가 조용한 시간을 보도록 일정과 함께 둡니다 (#36 MN-36-3)
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
        // 일정에 남아 있는 약·시각 목록 — 꺼져 있거나 형식이 틀리면 빈 목록(= 전부 지움)
        var slots: [(id: String, name: String, time: String)] = []
        var quiet: [String: String] = [:]
        if let data = json.data(using: .utf8),
           let sc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           sc["on"] as? Bool == true,
           let items = sc["items"] as? [[String: Any]] {
            quiet = sc["quiet"] as? [String: String] ?? [:]
            UserDefaults.standard.set(quiet, forKey: quietKey)
            for it in items {
                let id = it["id"] as? String ?? "", name = it["name"] as? String ?? ""
                for t in it["times"] as? [String] ?? [] where Self.hm(t) != nil { slots.append((id, name, t)) }
            }
        }
        let keep = Set(slots.map { "mnmd-\($0.id)-\($0.time)" })
        // 매일 알림(mnmd-<id>-<time>)은 전부 지우고 다시 걸되, 대기 중인 「10분 뒤」(…-later)는 그 약·시각이 일정에 남아 있으면 살려 둡니다 —
        // 약을 하나 더 추가하기만 해도 방금 누른 「10분 뒤」가 사라지던 것 (#66 MN-66-3). 안드로이드 MedScheduler.reschedule 과 같은 규칙.
        center.getPendingNotificationRequests { reqs in
            let gone = reqs.filter { req in
                let id = req.identifier
                guard id.hasPrefix("mnmd-") else { return false }
                if id.hasSuffix("-later") {
                    if !keep.contains(String(id.dropLast(6))) { return true }
                    // 조용한 시간이 바뀌어 대기 중인 「10분 뒤」가 그 안에 들어가면 지웁니다 — iOS 는 울릴 때 다시 보지 않습니다 (PR #67 Codex)
                    if let t = (req.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                        if Self.inQuiet(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0), quiet: quiet) { return true }
                    }
                    return false
                }
                return true
            }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: gone)
            guard !slots.isEmpty else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                guard ok else {
                    self.js("window.onNativeMeds && window.onNativeMeds({granted:false})")
                    return
                }
                for s in slots {
                    guard let hm = Self.hm(s.time), !Self.inQuiet(minutes: hm.0 * 60 + hm.1, quiet: quiet) else { continue }
                    var dc = DateComponents()
                    dc.hour = hm.0
                    dc.minute = hm.1
                    self.add(id: s.id, name: s.name, time: s.time,
                             trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true), suffix: "")
                }
                self.js("window.onNativeMeds && window.onNativeMeds({granted:true})")
            }
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
            // 10분 뒤가 조용한 시간 안이면 기록만 남기고 울리지 않습니다 — 안드로이드(MED_FIRE 에서 확인)와 같은 결과 (#36 MN-36-3)
            let quiet = UserDefaults.standard.dictionary(forKey: quietKey) as? [String: String] ?? [:]
            let later = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSinceNow: 600))
            let laterMin = (later.hour ?? 0) * 60 + (later.minute ?? 0)
            if !Self.inQuiet(minutes: laterMin, quiet: quiet) {
                add(id: id, name: name, time: time,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false), suffix: "-later")
            }
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
        guard ready, web != nil else { return }   // 화면이 뜨기 전 — pageDidLoad() 가 한 번 올립니다
        let arr = UserDefaults.standard.array(forKey: logKey) as? [[String: Any]] ?? []
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: data, encoding: .utf8),
              let quoted = try? JSONSerialization.data(withJSONObject: [s]),
              let q = String(data: quoted, encoding: .utf8) else { return }
        // ["..."] 에서 바깥 대괄호를 벗겨 JS 문자열 리터럴로 씁니다
        let lit = String(q.dropFirst().dropLast())
        // 올린 뒤 바로 가져가게 합니다 — 안 그러면 다음 visibilitychange 까지 기록이 화면에 안 보입니다 (#47 MN-47-3)
        js("window.__mnMedsLog=\(lit); window.MediNoteMeds && window.MediNoteMeds.pull && window.MediNoteMeds.pull();")
    }

    func pageDidLoad() {
        DispatchQueue.main.async {
            self.ready = true
            let queued = self.pending; self.pending = []
            queued.forEach { self.web?.evaluateJavaScript($0, completionHandler: nil) }
            // 기록은 여기서 한 번만 올립니다 — 화면 전에 온 pushLogToWeb() 는 아래 guard 로 아무것도 하지 않으므로,
            // 알림으로 켠 앱에서 같은 기록이 두 번 들어가지 않습니다 (PR #79 Codex P1)
            self.pushLogToWeb()
        }
    }

    private func js(_ code: String) {
        DispatchQueue.main.async {
            if !self.ready || self.web == nil { self.pending.append(code); return }
            self.web?.evaluateJavaScript(code, completionHandler: nil)
        }
    }
}
