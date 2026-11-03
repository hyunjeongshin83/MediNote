import Foundation
import UIKit
import UserNotifications
import WebKit

/**
 복약 알림 — 앱을 닫아도 울리게 (iOS · #16 MN-16-6). 안드로이드 MedScheduler.kt 와 짝입니다.

 웹 화면(복약 알림 레이어)이 Native.scheduleMeds(json) 으로 일정을 넘기면
   json = {on, quiet:{from,to}, items:[{id,name,times:["08:00",…]}]}
 매일 그 시각에 울리는 지역 알림(UNCalendarNotificationTrigger)을 겁니다. 서버는 없습니다.
 조용한 시간 안의 시각은 걸지 않습니다(웹과 같은 규칙).

 알림은 시각마다 하나 — 같은 시각의 약은 한 통으로 묶고 본문에 약 이름을 쓰지 않습니다 (「약 N가지 드실 시간이에요」 ·
 잠금화면에 약 이름이 보이지 않게 · #83 MN-83-4 · #123 MN-123-1). 대기 알림 64개 한도도 약 수가 아니라 시각 수로 셉니다 (#36 MN-36-4).

 알림의 「복용했어요」·「10분 뒤」는 여기서 받아 기록(앱 지원 폴더 · iCloud 백업 제외)에 남기고,
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
    private let logKey = "medinote.meds.log"       // 예전 자리(UserDefaults) — 처음 한 번 옮기고 지웁니다
    private let quietKey = "medinote.meds.quiet"   // 「10분 뒤」가 조용한 시간을 보도록 일정과 함께 둡니다 (#36 MN-36-3)
    private let logFile = "log.json", quietFile = "quiet.json"
    private let category = "MNMD"
    private static let maxPending = 64             // iOS 가 걸어 두는 지역 알림 한도

    /// 복용 기록·조용한 시간은 앱 지원 폴더 안 MediNoteMeds/ 에 둡니다. 이 폴더는 iCloud 기기 백업에서 뺍니다 (대표님 결정 2026-11-03 · #83 MN-83-3).
    /// UserDefaults(Library/Preferences)는 파일을 통째로 바꿔 쓰므로 백업 제외 표시가 남지 않아 옮겼습니다.
    private let storeDir: URL = {
        var u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MediNoteMeds", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        MedNotifier.excludeFromBackup(&u)
        return u
    }()

    static func excludeFromBackup(_ u: inout URL) {
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
    }

    /// WKWebView 저장소(localStorage 등 · Library/WebKit)를 iCloud 기기 백업에서 뺍니다 (#83 MN-83-3).
    /// 폴더는 WebKit 이 처음 쓸 때 생기므로 앱이 뜰 때와 화면이 뜬 뒤에 다시 겁니다.
    static func excludeWebKitFromBackup() {
        var u = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebKit", isDirectory: true)
        if FileManager.default.fileExists(atPath: u.path) { excludeFromBackup(&u) }
    }

    private func load(_ name: String) -> Any? {
        guard let d = try? Data(contentsOf: storeDir.appendingPathComponent(name)) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    private func store(_ name: String, _ obj: Any?) {
        let f = storeDir.appendingPathComponent(name)
        guard let obj = obj, let d = try? JSONSerialization.data(withJSONObject: obj) else {
            try? FileManager.default.removeItem(at: f)
            return
        }
        try? d.write(to: f, options: .atomic)
    }

    private override init() {
        super.init()
        let ud = UserDefaults.standard
        if let old = ud.array(forKey: logKey) { store(logFile, old); ud.removeObject(forKey: logKey) }
        if let old = ud.dictionary(forKey: quietKey) { store(quietFile, old); ud.removeObject(forKey: quietKey) }
        center.delegate = self
        // 설정 앱에서 알림을 끄고 돌아오는 경우를 잡습니다 (#94)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshNotifyState()
        }
        let taken = UNNotificationAction(identifier: "taken", title: "복용했어요", options: [])
        let later = UNNotificationAction(identifier: "later", title: "10분 뒤", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [taken, later], intentIdentifiers: [], options: [])
        ])
    }

    // MARK: 일정

    func schedule(json: String) {
        // 일정에 남아 있는 시각 → 그 시각의 약 — 꺼져 있거나 형식이 틀리면 빈 목록(= 전부 지움)
        var groups: [String: [[String: String]]] = [:]
        var quiet: [String: String] = [:]
        if let data = json.data(using: .utf8),
           let sc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           sc["on"] as? Bool == true,
           let items = sc["items"] as? [[String: Any]] {
            quiet = sc["quiet"] as? [String: String] ?? [:]
            store(quietFile, quiet)
            for it in items {
                let id = it["id"] as? String ?? "", name = it["name"] as? String ?? ""
                for t in it["times"] as? [String] ?? [] where Self.hm(t) != nil {
                    var g = groups[t] ?? []
                    if !g.contains(where: { $0["id"] == id }) { g.append(["id": id, "name": name]) }
                    groups[t] = g
                }
            }
        }
        let keep = Set(groups.keys.map { "mnmd-\($0)" })
        // 매일 알림(mnmd-<id>-<time>)은 전부 지우고 다시 걸되, 대기 중인 「10분 뒤」(…-later)는 그 약·시각이 일정에 남아 있으면 살려 둡니다 —
        // 약을 하나 더 추가하기만 해도 방금 누른 「10분 뒤」가 사라지던 것 (#66 MN-66-3). 안드로이드 MedScheduler.reschedule 과 같은 규칙.
        center.getPendingNotificationRequests { reqs in
            var rewrite: [(time: String, meds: [[String: String]], at: Date)] = []
            let gone = reqs.filter { req in
                let id = req.identifier
                guard id.hasPrefix("mnmd-") else { return false }
                if id.hasSuffix("-later") {
                    if !keep.contains(String(id.dropLast(6))) { return true }
                    // 조용한 시간이 바뀌어 대기 중인 「10분 뒤」가 그 안에 들어가면 지웁니다 — iOS 는 울릴 때 다시 보지 않습니다 (PR #67 Codex)
                    let at = (req.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                    if let t = at {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                        if Self.inQuiet(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0), quiet: quiet) { return true }
                    }
                    // 「10분 뒤」에 묶인 약 중 지금 일정에 그 시각으로 남아 있는 것만 — 하나도 없으면 지우고, 줄었으면 남은 약으로 다시 겁니다 (PR #167 Codex)
                    let time = String(id.dropFirst(5).dropLast(6))
                    let oldIds = req.content.userInfo["ids"] as? [String] ?? []
                    let remaining = (groups[time] ?? []).filter { oldIds.contains($0["id"] ?? "") }
                    if remaining.isEmpty { return true }
                    if remaining.count != oldIds.count, let t = at { rewrite.append((time: time, meds: remaining, at: t)) }
                    return false
                }
                return true
            }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: gone)
            // 같은 식별자로 다시 넣으면 대기 중인 것을 바꿉니다 — 울릴 시각은 그대로
            for r in rewrite {
                self.add(time: r.time, meds: r.meds,
                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(r.at.timeIntervalSinceNow, 1), repeats: false), suffix: "-later")
            }
            guard !groups.isEmpty else { return }
            // 남겨 둔 「10분 뒤」만큼 빼고 남은 자리까지만 겁니다. 넘치면 iOS 가 소리 없이 버리므로 화면에 알립니다 (#36 MN-36-4)
            let laterKept = reqs.filter { $0.identifier.hasPrefix("mnmd-") && !gone.contains($0.identifier) }.count
            let room = max(Self.maxPending - laterKept, 0)
            let times = groups.keys.sorted().filter { t in
                guard let hm = Self.hm(t) else { return false }
                return !Self.inQuiet(minutes: hm.0 * 60 + hm.1, quiet: quiet)
            }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                guard ok else {
                    self.js("window.onNativeMeds && window.onNativeMeds({granted:false})")
                    return
                }
                for t in times.prefix(room) {
                    guard let hm = Self.hm(t) else { continue }
                    var dc = DateComponents()
                    dc.hour = hm.0
                    dc.minute = hm.1
                    self.add(time: t, meds: groups[t] ?? [],
                             trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true), suffix: "")
                }
                let limit = times.count > room ? "true" : "false"
                self.js("window.onNativeMeds && window.onNativeMeds({granted:true, limit:\(limit)})")
            }
        }
    }

    private func add(time: String, meds: [[String: String]], trigger: UNNotificationTrigger, suffix: String) {
        guard !meds.isEmpty else { return }
        let c = UNMutableNotificationContent()
        c.title = "메디노트 복약 알림"
        c.body = "약 \(meds.count)가지 드실 시간이에요 (\(time))"
        c.sound = .default
        c.categoryIdentifier = category
        let ids: [String] = meds.map { $0["id"] ?? "" }
        let names: [String] = meds.map { $0["name"] ?? "" }
        c.userInfo = ["time": time, "ids": ids, "names": names]
        center.add(UNNotificationRequest(identifier: "mnmd-\(time)\(suffix)", content: c, trigger: trigger))
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
        let time = u["time"] as? String ?? ""
        // 그 알림에 묶인 약 전부 (#123 MN-123-1). id·name 하나만 든 것은 묶기 전에 걸린 알림입니다
        var ids = u["ids"] as? [String] ?? [], names = u["names"] as? [String] ?? []
        if ids.isEmpty, let id = u["id"] as? String { ids = [id]; names = [u["name"] as? String ?? ""] }
        var meds: [[String: String]] = []
        for (k, id) in ids.enumerated() { meds.append(["id": id, "name": k < names.count ? names[k] : ""]) }
        switch response.actionIdentifier {
        case "taken":
            for m in meds { addLog(action: "taken", id: m["id"] ?? "", name: m["name"] ?? "", time: time) }
        case "later":
            for m in meds { addLog(action: "later", id: m["id"] ?? "", name: m["name"] ?? "", time: time) }
            // 10분 뒤가 조용한 시간 안이면 기록만 남기고 울리지 않습니다 — 안드로이드(MED_FIRE 에서 확인)와 같은 결과 (#36 MN-36-3)
            let quiet = load(quietFile) as? [String: String] ?? [:]
            let later = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSinceNow: 600))
            let laterMin = (later.hour ?? 0) * 60 + (later.minute ?? 0)
            if !Self.inQuiet(minutes: laterMin, quiet: quiet) {
                add(time: time, meds: meds,
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
        var arr = load(logFile) as? [[String: Any]] ?? []
        arr.append(["action": action, "id": id, "name": name, "time": time,
                    "at": Int64(Date().timeIntervalSince1970 * 1000)])
        if arr.count > 500 { arr.removeFirst(arr.count - 500) }
        store(logFile, arr)
    }

    func clearLog() { store(logFile, nil) }

    /// 웹의 Native.medsLogTake() 가 읽어 갈 자리에 기록을 올려 둡니다
    func pushLogToWeb() {
        guard ready, web != nil else { return }   // 화면이 뜨기 전 — pageDidLoad() 가 한 번 올립니다
        let arr = load(logFile) as? [[String: Any]] ?? []
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
            self.refreshNotifyState()
            Self.excludeWebKitFromBackup()
        }
    }

    /// 설정 앱에서 알림을 껐는지 웹에 알립니다 — 알림이 꺼져 있어도 앱은 모르고, 복약 창은 「켜짐」으로 보였습니다 (#94).
    /// 앱이 켜질 때(pageDidLoad · 앞으로 올 때)마다 다시 봅니다. 아직 묻지 않은 상태(.notDetermined)는 막힌 것이 아닙니다.
    func refreshNotifyState() {
        center.getNotificationSettings { s in
            self.js("window.__mnNotifyOk = \(s.authorizationStatus != .denied ? "true" : "false"); window.__mnNotifyChanged && window.__mnNotifyChanged();")
        }
    }

    private func js(_ code: String) {
        DispatchQueue.main.async {
            if !self.ready || self.web == nil { self.pending.append(code); return }
            self.web?.evaluateJavaScript(code, completionHandler: nil)
        }
    }
}
