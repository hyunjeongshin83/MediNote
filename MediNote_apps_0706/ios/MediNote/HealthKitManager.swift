import Foundation
import HealthKit

/**
 MediNote — HealthKit 읽기 (걸음 · 심박 · 수면) · iOS

 [설계 원칙]
 - 건강 센서 데이터는 개인정보보호법상 '민감정보'입니다. 이 매니저는 기기 안(HealthKit)에서 읽어
   웹 화면에 넘기기만 합니다. 「클라우드에 저장」은 웹 화면에서 사용자가 눌렀을 때만 갑니다.
 - 사용자 동의는 iOS 의 HealthKit 권한 화면으로 별도로 받습니다.

 [연동 흐름]
   Apple Watch · 블루투스 혈압계(건강 앱 연동) → 아이폰 HealthKit → (동의) → 이 앱이 읽음 → window.onNativeHealth(json)
   json 모양은 안드로이드 HealthConnectManager.readSummary() 와 같습니다 (MN-18-4: 레코드마다 시각이 붙습니다).
     { steps:[{start,end,zoneOffsetMin,count}], heartRate:[{time,zoneOffsetMin,bpm}],
       sleep:[{start,end,zoneOffsetMin,minutes}], at, clockSource:"healthkit" }

 [Xcode 설정] Signing & Capabilities → HealthKit. Info.plist 의 NSHealthShareUsageDescription (project.yml 에 있습니다).
*/
final class HealthKitManager {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { s.insert(steps) }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { s.insert(hr) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    func isAvailable() -> Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable() else { completion(false); return }
        store.requestAuthorization(toShare: [], read: readTypes) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    private var zoneOffsetMin: Int { TimeZone.current.secondsFromGMT() / 60 }
    private func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

    /// 지난 24시간 걸음 — 레코드별 구간 · 개수
    private func readSteps24h(completion: @escaping ([[String: Any]]) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { completion([]); return }
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86_400), end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 500, sortDescriptors: [sort]) { _, samples, _ in
            let rows = (samples as? [HKQuantitySample] ?? []).map { s -> [String: Any] in
                ["start": self.ms(s.startDate), "end": self.ms(s.endDate),
                 "zoneOffsetMin": self.zoneOffsetMin,
                 "count": Int(s.quantity.doubleValue(for: .count()))]
            }
            completion(rows)
        }
        store.execute(q)
    }

    /// 지난 6시간 심박 — 샘플마다 시각 · bpm
    private func readHeartRate6h(completion: @escaping ([[String: Any]]) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { completion([]); return }
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-6 * 3_600), end: Date())
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 500, sortDescriptors: [sort]) { _, samples, _ in
            let rows = (samples as? [HKQuantitySample] ?? []).map { s -> [String: Any] in
                ["time": self.ms(s.startDate), "zoneOffsetMin": self.zoneOffsetMin,
                 "bpm": Int(s.quantity.doubleValue(for: unit).rounded())]
            }
            completion(rows)
        }
        store.execute(q)
    }

    /// 지난 24시간 수면 — 잠든 구간만 (inBed · awake 는 뺍니다)
    private func readSleep24h(completion: @escaping ([[String: Any]]) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { completion([]); return }
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86_400), end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 200, sortDescriptors: [sort]) { _, samples, _ in
            let asleep: Set<Int> = {
                var v: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
                if #available(iOS 16.0, *) {
                    v.formUnion([HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                 HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                }
                return v
            }()
            let rows = (samples as? [HKCategorySample] ?? [])
                .filter { asleep.contains($0.value) }
                .map { s -> [String: Any] in
                    ["start": self.ms(s.startDate), "end": self.ms(s.endDate),
                     "zoneOffsetMin": self.zoneOffsetMin,
                     "minutes": Int(s.endDate.timeIntervalSince(s.startDate) / 60)]
                }
            completion(rows)
        }
        store.execute(q)
    }

    /// 웹 화면으로 넘길 요약 (JSON 문자열)
    func readSummary(completion: @escaping (String) -> Void) {
        var steps: [[String: Any]] = [], hr: [[String: Any]] = [], sleep: [[String: Any]] = []
        let g = DispatchGroup()
        g.enter(); readSteps24h { steps = $0; g.leave() }
        g.enter(); readHeartRate6h { hr = $0; g.leave() }
        g.enter(); readSleep24h { sleep = $0; g.leave() }
        g.notify(queue: .main) {
            let obj: [String: Any] = ["steps": steps, "heartRate": hr, "sleep": sleep,
                                      "at": self.ms(Date()), "clockSource": "healthkit"]
            if let data = try? JSONSerialization.data(withJSONObject: obj),
               let s = String(data: data, encoding: .utf8) {
                completion(s)
            } else {
                completion("{\"error\":\"encode\"}")
            }
        }
    }
}
