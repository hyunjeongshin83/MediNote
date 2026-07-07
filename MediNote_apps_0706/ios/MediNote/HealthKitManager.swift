import Foundation
import HealthKit

/**
 MediNote - HealthKit 연동 매니저 (iOS)

 [설계 원칙 — 합법적 구조]
 - 건강 센서 데이터는 개인정보보호법상 '민감정보'입니다.
 - 이 매니저는 데이터를 서버로 보내지 않습니다. 기기 안(HealthKit)에서 읽어,
   앱이 로컬에서만 계산·표시합니다. (raw 데이터는 기기를 떠나지 않음)
 - 사용자 동의는 iOS의 HealthKit 권한 화면을 통해 별도로 받습니다.

 [연동 흐름]
   Apple Watch → 아이폰의 HealthKit → (사용자 동의) → 이 앱이 로컬에서 읽음
   앱은 워치와 직접 통신하지 않고, 아이폰의 HealthKit에서 읽습니다.
   ※ Apple Watch 데이터는 오직 아이폰 네이티브 앱의 HealthKit로만 접근 가능합니다.
     (웹페이지나 안드로이드/윈도우 PC에서는 접근 불가)

 [연결 직전까지 구현됨]
 - 읽을 데이터 타입 정의, 권한 요청, 로컬 읽기 함수까지 준비 완료.
 - 실제 '연결' 버튼과 UI 연결만 붙이면 빌드 후 바로 테스트 가능합니다.
 - Xcode에서 HealthKit Capability를 켜고, Info.plist에 사용 목적 문구를 넣어야 합니다.
*/
final class HealthKitManager {
    let store = HKHealthStore()

    // 읽을 데이터 종류 — 필요 최소한만 (걸음 수, 심박수)
    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { s.insert(steps) }
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { s.insert(hr) }
        return s
    }

    /// HealthKit 사용 가능 여부
    func isAvailable() -> Bool { HKHealthStore.isHealthDataAvailable() }

    /// 권한 요청 (iOS 권한 화면 표시)
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable() else { completion(false); return }
        store.requestAuthorization(toShare: [], read: readTypes) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// 오늘 걸음 수 읽기 (로컬에서만 사용)
    func readTodaySteps(completion: @escaping (Double) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            completion(0); return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, result, _ in
            let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            DispatchQueue.main.async { completion(steps) }
        }
        store.execute(query)
    }

    /// 최근 심박수 읽기 (로컬에서만 사용)
    func readRecentHeartRate(completion: @escaping ([Double]) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion([]); return
        }
        let start = Date().addingTimeInterval(-6 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit = HKUnit.count().unitDivided(by: .minute())
        let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: 100, sortDescriptors: nil) { _, samples, _ in
            let values = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: unit) } ?? []
            DispatchQueue.main.async { completion(values) }
        }
        store.execute(query)
    }
}
