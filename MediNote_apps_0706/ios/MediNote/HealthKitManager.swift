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

    /// 표본이 적힌 시각의 시간대 오프셋(분). 표본에 시간대(HKMetadataKeyTimeZone)가 있으면 그것을, 없으면 지금 시간대의 그날 오프셋을 씁니다.
    /// 지금 오프셋 하나를 24시간 전체에 붙이면 여행·서머타임 경계에서 어긋납니다 (#92).
    private func zoneMin(_ s: HKSample?, at date: Date) -> Int {
        if let id = s?.metadata?[HKMetadataKeyTimeZone] as? String, let tz = TimeZone(identifier: id) {
            return tz.secondsFromGMT(for: date) / 60
        }
        return TimeZone.current.secondsFromGMT(for: date) / 60
    }
    private func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

    /// 지난 24시간 걸음 — 한 시간 단위 합계 (구간 · 개수)
    ///
    /// HKSampleQuery 로 원본 표본을 더하면 아이폰과 Apple Watch 가 같은 걸음을 각자 써서 두 배로 세고, limit 500 에서 잘립니다.
    /// HKStatisticsCollectionQuery(.cumulativeSum) 은 건강 앱과 같은 방식으로 겹친 출처를 걸러 준 합계입니다 (#63 MN-63-2).
    /// JSON 모양은 그대로 — 표본 대신 한 시간 칸입니다.
    private func readSteps24h(completion: @escaping ([[String: Any]]) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { completion([]); return }
        let end = Date(), start = end.addingTimeInterval(-86_400)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let cal = Calendar.current
        let anchor = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: start)) ?? start
        let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred,
                                            options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(hour: 1))
        q.initialResultsHandler = { _, results, _ in
            var rows: [[String: Any]] = []
            results?.enumerateStatistics(from: start, to: end) { stat, _ in
                let count = Int((stat.sumQuantity()?.doubleValue(for: .count()) ?? 0).rounded())
                if count > 0 {
                    rows.append(["start": self.ms(stat.startDate), "end": self.ms(stat.endDate),
                                 "zoneOffsetMin": self.zoneMin(nil, at: stat.startDate), "count": count])
                }
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
        // 최신부터 500개를 받아 오래된 순으로 뒤집습니다. 오래된 순으로 500개를 받으면 운동 중(초 단위 표본)이 있었던 날
        // 6시간 앞쪽에서 500개가 차 버려 「가장 최근 심박」이 몇 시간 전 값이 됩니다 (#92).
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 500, sortDescriptors: [sort]) { _, samples, _ in
            let rows = (samples as? [HKQuantitySample] ?? []).reversed().map { s -> [String: Any] in
                ["time": self.ms(s.startDate), "zoneOffsetMin": self.zoneMin(s, at: s.startDate),
                 "bpm": Int(s.quantity.doubleValue(for: unit).rounded())]
            }
            completion(rows)
        }
        store.execute(q)
    }

    typealias Span = (start: Date, end: Date, zone: Int)

    /// 겹친 구간을 합집합으로
    private func union(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for s in spans.sorted(by: { $0.start < $1.start }) {
            if let l = out.last, s.start <= l.end {
                if s.end > l.end { out[out.count - 1].end = s.end }
            } else {
                out.append(s)
            }
        }
        return out
    }

    /// a 에서 b 구간을 뺍니다 (둘 다 union 을 거친 시작 순 목록)
    private func subtract(_ a: [Span], _ b: [Span]) -> [Span] {
        var out: [Span] = []
        for s in a {
            var cursor = s.start
            for w in b where w.end > cursor && w.start < s.end {
                if w.start > cursor { out.append((start: cursor, end: min(w.start, s.end), zone: s.zone)) }
                cursor = max(cursor, w.end)
            }
            if s.end > cursor { out.append((start: cursor, end: s.end, zone: s.zone)) }
        }
        return out
    }

    /// 지난 24시간 수면 — 잠든 구간만 (inBed 는 세지 않고, awake 는 뺍니다). 출처가 달라 겹친 구간은 하나로 합칩니다.
    ///
    /// 아이폰의 수면 앱과 Apple Watch(또는 서드파티 수면 앱)가 같은 밤을 각자 쓰면 표본이 겹쳐 있는데, 하나씩 더하면 그 밤이 두 배가 됩니다.
    /// 합계 API 가 없으니(수면은 HKStatisticsQuery 대상이 아님) 구간을 합집합으로 만듭니다 (#92).
    /// 표본 수 제한도 뺐습니다 — 오래된 순 200개 제한은 단계가 많은 밤에 마지막 단계들을 조용히 자릅니다.
    private func readSleep24h(completion: @escaping ([[String: Any]]) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { completion([]); return }
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-86_400), end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let asleep: Set<Int> = {
                var v: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
                if #available(iOS 16.0, *) {
                    v.formUnion([HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                 HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                }
                return v
            }()
            var spans: [Span] = [], awakeSpans: [Span] = []
            for s in (samples as? [HKCategorySample] ?? []) {
                if asleep.contains(s.value) {
                    spans.append((start: s.startDate, end: s.endDate, zone: self.zoneMin(s, at: s.startDate)))
                } else if s.value == HKCategoryValueSleepAnalysis.awake.rawValue {
                    awakeSpans.append((start: s.startDate, end: s.endDate, zone: self.zoneMin(s, at: s.startDate)))
                }
            }
            // 어느 출처가 「깨어 있었다」고 적은 구간은 다른 출처의 잠든 구간에서도 뺍니다 (#93 Codex)
            let merged = self.subtract(self.union(spans), self.union(awakeSpans))
            let rows = merged.map { s -> [String: Any] in
                ["start": self.ms(s.start), "end": self.ms(s.end), "zoneOffsetMin": s.zone,
                 "minutes": Int(s.end.timeIntervalSince(s.start) / 60)]
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
