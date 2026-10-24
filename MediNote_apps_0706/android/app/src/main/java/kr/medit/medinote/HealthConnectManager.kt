package kr.medit.medinote

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.Instant

/**
 * MediNote — Health Connect 읽기 (걸음 · 심박 · 수면)
 *
 * [설계 원칙]
 * - 건강 센서 데이터는 개인정보보호법상 '민감정보'입니다. 이 매니저는 기기 안(Health Connect)에서 읽어
 *   웹 화면에 넘기기만 합니다. 서버로 가는 것은 사용자가 「클라우드에 저장」을 눌렀을 때의 심박뿐이고,
 *   그 규칙은 웹 화면 쪽(measurements · metric_defs)에 있습니다 (#33 MN-33-1).
 * - 사용자 동의는 OS 권한 화면으로 별도로 받습니다.
 *
 * [MN-18-4] 걸음을 합계로, 심박을 값 목록으로만 돌려주던 것을 고쳐 레코드마다 startTime · endTime · zoneOffset 을
 * 함께 돌려줍니다. 시각이 사라지지 않아야 수면·걸음을 심박과 같은 축에 놓을 수 있습니다.
 */
class HealthConnectManager(private val context: Context) {

    private companion object {
        /** 심박 쪽 수 상한 — 쪽당 최대 1,000건. 넘으면 오래된 쪽부터 빠집니다 */
        const val MAX_HEART_PAGES = 20
    }

    val client: HealthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
    )

    fun isAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    /** "available" · "update"(앱은 있으나 오래됨) · "none"(Android 13 이하에서 미설치) — #33 MN-33-2 */
    fun status(): String = when (HealthConnectClient.getSdkStatus(context)) {
        HealthConnectClient.SDK_AVAILABLE -> "available"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update"
        else -> "none"
    }

    suspend fun hasAllPermissions(): Boolean =
        client.permissionController.getGrantedPermissions().containsAll(permissions)

    /** 셋 중 하나라도 허용돼 있으면 true — 사용자는 권한 화면에서 종류별로 끌 수 있습니다 (MN-120-1) */
    suspend fun hasAnyPermission(): Boolean =
        client.permissionController.getGrantedPermissions().any { it in permissions }

    /** 지난 24시간 걸음 — 한 시간 단위 합계 (구간 · 시간대 오프셋 · 개수)
     *
     *  readRecords 로 원본 레코드를 받아 더하면 폰(삼성 헬스·Google Fit)과 시계가 같은 걸음을 각자 써서 두 배로 세고,
     *  한 번에 1,000건까지만 와서 하루치가 조용히 잘립니다. aggregateGroupByDuration 은 Health Connect 가 앱 우선순위로
     *  겹친 것을 걸러 준 합계라 둘 다 없습니다 (#63 MN-63-1). JSON 모양은 그대로 — 레코드 대신 한 시간 칸입니다. */
    suspend fun readSteps24h(): JSONArray {
        val now = Instant.now()
        val groups = client.aggregateGroupByDuration(AggregateGroupByDurationRequest(
            metrics = setOf(StepsRecord.COUNT_TOTAL),
            timeRangeFilter = TimeRangeFilter.between(now.minusSeconds(86_400), now),
            timeRangeSlicer = Duration.ofHours(1)))
        val arr = JSONArray()
        groups.forEach { g ->
            val count = g.result[StepsRecord.COUNT_TOTAL] ?: 0L
            if (count <= 0L) return@forEach
            arr.put(JSONObject()
                .put("start", g.startTime.toEpochMilli())
                .put("end", g.endTime.toEpochMilli())
                .put("zoneOffsetMin", g.zoneOffset.totalSeconds / 60)
                .put("count", count))
        }
        return arr
    }

    /** 지난 6시간 심박 — 샘플마다 시각(ms) · bpm (오래된 순)
     *
     *  readRecords 는 한 번에 1,000건까지만 주고 나머지는 pageToken 으로 이어집니다. 첫 쪽만 읽으면 레코드 하나에 표본 하나씩 쓰는 앱
     *  (초 단위로 기록하는 시계 등)에서는 6시간치가 조용히 잘리고, 기본 정렬이 오래된 순이라 잘리는 쪽이 가장 최근 심박입니다 —
     *  웹 화면은 그중 가장 늦은 시각을 「최신」으로 보여 줍니다 (iOS 쪽 같은 문제는 #92 에서 고침 · #80 MN-80-4).
     *  최신 순으로 쪽을 이어 받아 상한(20쪽)에서 멈추면 모자라더라도 오래된 쪽이 빠집니다. */
    suspend fun readHeartRate6h(): JSONArray {
        val now = Instant.now()
        val filter = TimeRangeFilter.between(now.minusSeconds(6 * 3_600), now)
        val samples = mutableListOf<JSONObject>()
        var token: String? = null
        var pages = 0
        do {
            val r = client.readRecords(ReadRecordsRequest(
                HeartRateRecord::class, filter, ascendingOrder = false, pageToken = token))
            r.records.forEach { rec ->
                val zone = rec.startZoneOffset?.totalSeconds?.div(60)
                rec.samples.forEach { s ->
                    samples.add(JSONObject()
                        .put("time", s.time.toEpochMilli())
                        .put("zoneOffsetMin", zone ?: JSONObject.NULL)
                        .put("bpm", s.beatsPerMinute))
                }
            }
            token = r.pageToken
            pages++
        } while (token != null && pages < MAX_HEART_PAGES)
        val arr = JSONArray()
        samples.sortedBy { it.getLong("time") }.forEach { arr.put(it) }
        return arr
    }

    /** 「깨어 있던」 단계 — 세션 길이에서 이것만 뺍니다 (#63 MN-63-3 · PR #64 Codex).
     *  잠든 단계만 더하면 단계 사이의 빈 구간(앱이 적지 않은 시간)이 통째로 빠져, 8시간 세션에 AWAKE 5분만 적혀 있으면 0분이 됩니다.
     *  iOS 는 asleep* 표본만 세지만 HealthKit 표본은 구간이 이어져 있어 같은 결과입니다. */
    private val awakeStages = setOf(
        SleepSessionRecord.STAGE_TYPE_AWAKE, SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED,
        SleepSessionRecord.STAGE_TYPE_OUT_OF_BED)

    /** 잠든 구간 하나 — 세션에서 깨어 있던 단계를 뺀 조각 (시각은 epoch ms) */
    private class Span(val start: Long, var end: Long, val zoneMin: Int?)

    /** 겹친 구간을 합집합으로 — 시작 순으로 훑으며 이어 붙입니다 */
    private fun union(list: List<Span>): List<Span> {
        val out = mutableListOf<Span>()
        list.sortedBy { it.start }.forEach { sp ->
            val last = out.lastOrNull()
            if (last != null && sp.start <= last.end) { if (sp.end > last.end) last.end = sp.end }
            else out.add(Span(sp.start, sp.end, sp.zoneMin))
        }
        return out
    }

    /** 지난 24시간 수면 — 잠든 구간 목록 (시작 · 끝 · 분).
     *
     *  앱이 달라 겹친 세션(삼성 헬스와 Fitbit 이 같은 밤을 각자 쓴 경우)은 합집합으로 합칩니다. 세션 길이를 하나씩 더하면
     *  그 밤이 두 배가 됩니다 (#92). 그리고 어느 한 앱이라도 「깨어 있었다」고 적은 단계는 합친 구간에서 뺍니다 —
     *  단계 없이 세션 전체만 적은 앱이 있어도 상세를 적은 앱의 깨어 있던 시간이 잠든 시간으로 되살아나지 않게 (#93 Codex).
     *  합친 구간이라 웹 화면은 구간 길이(end − start)를 더합니다. */
    suspend fun readSleep24h(): JSONArray {
        val now = Instant.now()
        val r = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(now.minusSeconds(86_400), now)))
        val sessions = mutableListOf<Span>()
        val awake = mutableListOf<Span>()
        r.records.forEach { rec ->
            val zone = rec.startZoneOffset?.totalSeconds?.div(60)
            sessions.add(Span(rec.startTime.toEpochMilli(), rec.endTime.toEpochMilli(), zone))
            rec.stages.filter { it.stage in awakeStages }.forEach { st ->
                awake.add(Span(st.startTime.toEpochMilli(), st.endTime.toEpochMilli(), zone))
            }
        }
        val awakeUnion = union(awake)
        val arr = JSONArray()
        union(sessions).forEach { sp ->
            var cursor = sp.start
            fun emit(from: Long, to: Long) {
                if (to > from) arr.put(JSONObject()
                    .put("start", from)
                    .put("end", to)
                    .put("zoneOffsetMin", sp.zoneMin ?: JSONObject.NULL)
                    .put("minutes", (to - from) / 60_000))
            }
            awakeUnion.forEach { aw ->
                if (aw.end > cursor && aw.start < sp.end) {
                    emit(cursor, minOf(aw.start, sp.end))
                    cursor = maxOf(cursor, aw.end)
                }
            }
            emit(cursor, sp.end)
        }
        return arr
    }

    /** 웹 화면으로 넘길 요약 — {steps:[…], heartRate:[…], sleep:[…], denied:[…], at, clockSource:"health_connect"}
     *
     *  허용된 종류만 읽습니다. 허용하지 않은 종류를 읽으면 SecurityException 이고, 그 종류는 빈 목록으로 두고
     *  denied 에 이름(steps · heartRate · sleep)을 적어 돌려줍니다 (MN-120-1). */
    suspend fun readSummary(): JSONObject {
        val granted = client.permissionController.getGrantedPermissions()
        val canSteps = HealthPermission.getReadPermission(StepsRecord::class) in granted
        val canHeart = HealthPermission.getReadPermission(HeartRateRecord::class) in granted
        val canSleep = HealthPermission.getReadPermission(SleepSessionRecord::class) in granted
        val denied = JSONArray()
        if (!canSteps) denied.put("steps")
        if (!canHeart) denied.put("heartRate")
        if (!canSleep) denied.put("sleep")
        return JSONObject()
            .put("steps", if (canSteps) readSteps24h() else JSONArray())
            .put("heartRate", if (canHeart) readHeartRate6h() else JSONArray())
            .put("sleep", if (canSleep) readSleep24h() else JSONArray())
            .put("denied", denied)
            .put("at", Instant.now().toEpochMilli())
            .put("clockSource", "health_connect")
    }
}
