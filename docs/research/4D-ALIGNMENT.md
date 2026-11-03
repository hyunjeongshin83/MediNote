# 4D 정합 — 순간·구간·표본을 한 시간축에 놓는 규칙

A 갈래(4D 인체 프로파일)의 「② 정합」에서 흩어져 있던 사실을 모은 문서입니다 (MN-134-2).
**사실과 출처만** 적습니다. 앱 동작은 바꾸지 않았고, 결정은 각 이슈의 `fix` 칸에 있습니다.

```
모은 이슈   #18 (2026-09-23)  잰 시각이 없었다
            #101 (2026-10-13) 잰 시각을 믿을 수 있는지 검사하는 곳이 없다
            #134 (2026-10-23) 구간 자리는 있는데 아무도 구간을 안 쓴다
정리한 날   2026-11-03
```

## 0. 관측 하나의 모양

```
관측 = 값 + 시작(effective_time) + 끝(effective_end) + 시간대 오프셋(zone_offset_min) + 시계 출처(clock_source)

  순간값   시작 = 끝          혈압 · 체온 · 심박 표본 하나
  구간값   시작 < 끝          걸음 구간 · 수면 세션
  표본     구간 안의 (시각, 값) 목록 → 저장할 때는 순간값 여러 개
```

- 이 모양은 세 플랫폼과 뜻이 같습니다.
  - HealthKit `HKSample`: 모든 표본이 `startDate`·`endDate` 를 갖고, 순간값은 둘이 같습니다 (#18).
  - Health Connect: `IntervalRecord`(시작·끝·각각의 zoneOffset — 걸음·수면)와 `InstantaneousRecord`(time·zoneOffset)로 나눕니다 (#18).
  - Open mHealth 계열: `effective_time_frame` 이 `date_time`(순간) 또는 `time_interval`(구간) 중 하나입니다 (#134).
- `measurements` 에는 이 열이 모두 있습니다 (MN-18-3 반영). `lifelogs` 에는 `sleep_start` · `sleep_end` · `zone_offset_min` 이 있습니다 (#101 에서 확인).
- 시간축 자체는 **UTC 순간**으로 둡니다. 오프셋은 「그 사람의 하루 경계」를 그릴 때만 씁니다 (#18).

## 1. 규칙 ① 구간 안 포함 질의

**수면 세션 [시작, 끝] 안에 들어오는 심박 표본을 골라 이어 붙인다.**

- Health Connect 는 수면 중 심박을 `SleepSessionRecord` 안에 담지 않습니다. 심박은 별도 레코드이고, **세션의 시작·끝 사이를 다시 조회해** 이어 붙이라고 안내합니다 (#134, 검색 요약 기준).
- `HeartRateRecord` 는 구간 레코드 하나 안에 **(시각, bpm) 표본 목록**을 담고, 분 단위 레코드를 권합니다 (#134).
- 이 질의를 하려면 두 가지가 저장돼 있어야 합니다.
  - 수면: (시작, 끝) — 끝 시각만으로는 안 됩니다.
  - 심박: 표본 전부, 또는 분 단위 요약.
- 드문드문 오는 값(혈압·체온)은 **보간하지 않습니다.** 다음 값이 올 때까지 「유효 구간」으로 그리되 상한(예: 24시간)을 두고, 비면 비었다고 보입니다 (#18).

**지금 앱 (#134 에서 확인한 코드)**

| 자리 | 지금 | 규칙에 필요한 것 |
|---|---|---|
| 수면 (`onNativeHealth`) | 합계 분 · 마지막 세션의 **끝**만 | 세션별 (시작, 끝, 단계) |
| 심박 (`onNativeHealth`) | 화면은 「표본 N개」, 저장 후보는 **가장 늦은 1개** | 표본 전부 |
| `toRows` | 모든 행을 순간(시작=끝)으로 씀 | 구간은 시작<끝 |

시작 시각은 **저장 단계가 아니라 읽는 단계**(`addRead` 로 넘기는 값)에서 버려집니다. 저장 표를 정해도 읽기 코드를 같이 바꾸지 않으면 구간 행이 생기지 않습니다 (#134 해석 2).
→ 결정: MN-134-1 (건강 데이터 저장 범위 — 대표님)

## 2. 규칙 ② 걸음 누적은 겹쳐 더하지 않는다

**걸음은 구간별로 두고, 합계를 낼 때는 플랫폼의 집계를 쓴다.**

- Health Connect `StepsRecord` 는 구간의 **누적** 걸음 수입니다. 여러 앱·기기가 같은 시간을 적으면 구간이 겹치므로, 겹침·중복 합산을 피하려면 raw 레코드를 더하지 말고 `aggregate()` 를 쓰라고 안내합니다 (#134).
- HealthKit 쪽 매니저는 `HKStatisticsQuery(.cumulativeSum)` 로 합계를 냅니다 (#18 시점 코드).
- 24시간 합계 한 줄은 시간축에 놓을 수 없습니다. 시간축에는 구간별로 둡니다 (#134 해석 3).
- **확인하지 못한 것**: 안드로이드 셸이 걸음을 `aggregate()` 로 읽는지 raw 구간으로 읽는지 (#134).

## 3. 규칙 ③ 시간대 오프셋은 「잰 순간」의 것

**`zone_offset_min` 은 값을 잰 순간의 오프셋이어야 한다. 읽은 순간의 것이 아니다.**

- Health Connect 는 레코드마다 오프셋을 따로 둡니다 (시작·끝 각각) (#18).
- 블루투스 혈압·체온 측정의 Time Stamp 필드에는 시간대가 없습니다. 앱은 `new Date(y, mo-1, da, h, mi, se)` 로 **폰의 현재 시간대**로 해석합니다 (#101).
  - 한국은 서머타임이 없어 평소에는 문제가 없습니다.
  - 서머타임 지역에서는 겹치는 시각(뉴욕 2026-11-01 01:30)이 앞쪽으로, 없는 시각(2026-03-08 02:30)이 한 시간 뒤로 밀립니다 (#101, TZ=America/New_York 으로 시험).
- 블루투스 Current Time Service 는 날짜시각과 따로 Local Time Information(15분 단위 오프셋 + 서머타임 여부)을 둡니다. 혈압·체온 측정 특성의 Time Stamp 가 시간대를 담는지는 **확인하지 못했습니다** (#101).
- 지금 `zone_offset_min` 은 읽은 순간의 폰 오프셋입니다 → 결정: MN-101-3

## 4. 규칙 ④ 시계 출처마다 믿는 정도가 다르다

**`clock_source` 로 출처를 남기고, 기기 시계는 걸러서 믿는다.**

```
device_clock     기기 자체 시계 (블루투스 Time Stamp) — 메모리에 쌓였다 나중에 동기화된 값의 유일한 「잰 시각」
health_connect   Health Connect 레코드의 시각
phone_receive    폰이 값을 받은 시각 — 실시간 수신이면 잰 시각에 가깝다
user_entered     사람이 적은 시각
server_receive   서버가 받은 시각
```

- **타당성은 정합 앞에서 거른다.** 공장 초기값과 달력에 없는 날짜는 정합이 고칠 수 있는 것이 아니라 걸러야 하는 것입니다 (#101).
  - 지금 `readTs` 는 연 2000~2100 · 월 1~12 · 일 1~31 만 봅니다. 2000-01-01, 2099-12-31, 2026-02-30(→ 3월 2일로 밀림), 25시 61분이 모두 `device_clock` 으로 통과했습니다 (#101 시험).
  - → 결정: MN-101-1 (허용 범위 숫자 — 대표님)
- **시계 어긋남은 상수 이동으로 먼저 구한다.** 픽셀 워치와 가슴 ECG 를 함께 기록한 데이터셋은 R 파 도달 시각의 평균 차이로 상수 이동을 구했습니다 (HEART-Watch, arXiv 2512.03988, #101).
  - 수정 발진기 오차 50 ppm 이면 30분에 약 0.1초 어긋납니다 (Sensors 25(3):756, #101).
  - 이것을 구하려면 쌍(기기 시각, 폰 수신 시각)이 필요한데, 지금 `client_ts` 는 모든 행에 「저장 단추를 누른 시각」 하나입니다 → 결정: MN-101-2
- **원본은 두고 맞춘 복사본을 따로 만든다.** 위 데이터셋은 기기별 원래 샘플링을 그대로 두고, 맞춘 판(250 Hz 선형 보간)을 따로 만들면서 「고주파 성분이 뭉개질 수 있다」고 적었습니다 (#101).
- 샘플링 속도가 크게 다른 신호는 길이로 자르지 말고 **시간 기준**으로 나눕니다 (UbiComp 워크숍 논문, Siegen 대학 게시본, #101).

## 5. 출처

| 출처 | 쓴 곳 | 확인한 날 · 방식 |
|---|---|---|
| [Health Connect — Read raw data](https://developer.android.com/health-and-fitness/health-connect/read-data) | 규칙 ①② | 2026-10-23 · 검색 요약 (전문·갱신일 미확인) |
| [Health Connect — Write data](https://developer.android.com/health-and-fitness/health-connect/write-data) | 규칙 ① | 2026-10-23 · 검색 요약 |
| [Health Connect — Track sleep sessions](https://developer.android.com/health-and-fitness/health-connect/features/sleep-sessions) | 규칙 ① | 2026-10-23 · 검색 요약, 「오래된 판」 표시 있었음 |
| Apple HealthKit `HKSample` (developer.apple.com) | 0절 | 2026-09-23 · 원문 인용 |
| [HealthKitOnOMH](https://swiftpackageregistry.com/StanfordBDHG/HealthKitOnOMH) (Open mHealth 변환 예) | 0절 | 2026-10-23 · 2차 자료, OMH 스키마 본문 미확인 |
| [HEART-Watch, arXiv 2512.03988](https://arxiv.org/pdf/2512.03988) | 규칙 ④ | 2026-10-13 · 검색 요약 |
| [Sensors 25(3):756](https://iris.univpm.it/bitstream/11566/341392/1/sensors-25-00756.pdf) | 규칙 ④ | 2026-10-13 · 검색 요약 |
| [Siegen 대학 UbiComp 게시본](https://www.eti.uni-siegen.de/ubicomp/papers/ubi_percomws21b.pdf) | 규칙 ④ | 2026-10-13 · 검색 요약 |
| [BlueZ time/server.c](https://coral.googlesource.com/bluez-imx/+/refs/tags/5.27/profiles/time/server.c) | 규칙 ③ | 2026-10-13 · 코드 주석 |
| FHIR Observation `effective[x]` | 0절 | 2026-09-23 · 망 정책으로 원문 대조 못 함 |

이 문서를 쓰면서 위 출처를 다시 열어 보지는 않았습니다. 확인한 날과 방식은 각 이슈에 적힌 그대로입니다.

## 6. 아직 모르는 것

- 안드로이드 셸이 걸음을 `aggregate()` 로 읽는지, 심박 표본을 몇 개 넘기는지 (#134)
- 혈압·체온 Time Stamp 필드의 시간대 규정 (블루투스 규격 원문 미대조, #101)
- 실기기 시계가 실제로 얼마나 어긋나는지 — `measurements` 가 0건이라 잴 데이터가 없음 (#101 · #134)
