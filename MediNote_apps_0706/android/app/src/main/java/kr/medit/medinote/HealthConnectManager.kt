package kr.medit.medinote

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import org.json.JSONObject
import java.time.Instant

/**
 * MediNote - Health Connect 연동 매니저 (Android)
 *
 * [설계 원칙 — 합법적 구조]
 * - 건강 센서 데이터는 개인정보보호법상 '민감정보'입니다.
 * - 이 매니저는 데이터를 서버로 보내지 않습니다. 기기 안(Health Connect)에서 읽어,
 *   앱이 로컬에서만 계산·표시합니다. (raw 데이터는 기기를 떠나지 않음)
 * - 사용자 동의는 안드로이드 OS의 권한 화면을 통해 별도로 받습니다.
 *
 * [연동 흐름]
 *   워치/밴드 → 폰의 Health Connect → (사용자 동의) → 이 앱이 로컬에서 읽음
 *   앱은 워치와 직접 통신하지 않고, 폰의 Health Connect 플랫폼에서 읽습니다.
 *
 * [화면에 연결됨 — MN-14-2, 2026-09-25]
 * - MainActivity 의 window.Native 다리가 readSummary() 를 웹 화면으로 넘깁니다.
 * - 웹 화면은 「건강기기 연결」 시트에서 값을 보여 주고 기기 localStorage(medinote:hc:v1)에만 둡니다.
 * - 금연노트 셸과 같은 약속입니다. 수면을 더했습니다.
 */
class HealthConnectManager(private val context: Context) {

    // Health Connect 클라이언트 (기기에 Health Connect가 설치되어 있어야 함)
    val client: HealthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    // 읽을 데이터 종류 — 필요 최소한만 (걸음 수, 심박수, 수면)
    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
    )

    /** Health Connect 사용 가능 여부 확인 */
    fun isAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    /** 이미 권한이 있는지 확인 */
    suspend fun hasAllPermissions(): Boolean =
        client.permissionController.getGrantedPermissions().containsAll(permissions)

    /** 오늘 걸음 수 읽기 (로컬에서만 사용) */
    suspend fun readTodaySteps(): Long {
        val start = Instant.now().minusSeconds(60 * 60 * 24)
        val response = client.readRecords(
            ReadRecordsRequest(
                recordType = StepsRecord::class,
                timeRangeFilter = TimeRangeFilter.between(start, Instant.now())
            )
        )
        return response.records.sumOf { it.count }
    }

    /** 최근 심박수 읽기 (로컬에서만 사용) */
    suspend fun readRecentHeartRate(): List<Long> {
        val start = Instant.now().minusSeconds(60 * 60 * 6)
        val response = client.readRecords(
            ReadRecordsRequest(
                recordType = HeartRateRecord::class,
                timeRangeFilter = TimeRangeFilter.between(start, Instant.now())
            )
        )
        return response.records.flatMap { rec -> rec.samples.map { it.beatsPerMinute } }
    }

    /** 지난 24시간 수면 합 (분, 로컬에서만 사용) */
    suspend fun readSleepMinutes24h(): Long {
        val now = Instant.now()
        val response = client.readRecords(
            ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(now.minusSeconds(60 * 60 * 24), now)
            )
        )
        return response.records.sumOf { (it.endTime.epochSecond - it.startTime.epochSecond) / 60 }
    }

    /** 웹 화면으로 넘길 요약 — {steps, hrAvg, hrN, sleepMin, at} (금연노트와 같은 모양) */
    suspend fun readSummary(): JSONObject {
        val hr = readRecentHeartRate()
        return JSONObject()
            .put("steps", readTodaySteps())
            .put("hrAvg", if (hr.isEmpty()) JSONObject.NULL else hr.average().toInt())
            .put("hrN", hr.size)
            .put("sleepMin", readSleepMinutes24h())
            .put("at", Instant.now().toEpochMilli())
    }
}
