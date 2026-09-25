package kr.medit.medinote

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/**
 * MediNote — Health Connect 읽기 (걸음 · 심박 · 수면)
 *
 * [설계 원칙]
 * - 건강 센서 데이터는 개인정보보호법상 '민감정보'입니다. 이 매니저는 서버로 보내지 않습니다.
 *   기기 안(Health Connect)에서 읽어 웹 화면이 보여 주고, 「클라우드에 저장」은 사용자가 단추를 눌렀을 때만
 *   웹 화면 쪽 규칙(measurements · metric_defs)으로 갑니다.
 * - 사용자 동의는 OS 권한 화면으로 별도로 받습니다.
 *
 * [MN-18-4] 걸음을 합계로, 심박을 값 목록으로만 돌려주던 것을 고쳐 레코드마다 startTime · endTime · zoneOffset 을
 * 함께 돌려줍니다. 시각이 사라지지 않아야 수면·걸음을 심박과 같은 축에 놓을 수 있습니다.
 */
class HealthConnectManager(private val context: Context) {

    val client: HealthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
    )

    fun isAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    suspend fun hasAllPermissions(): Boolean =
        client.permissionController.getGrantedPermissions().containsAll(permissions)

    /** 지난 24시간 걸음 — 레코드별 구간 · 시간대 오프셋 · 개수 */
    suspend fun readSteps24h(): JSONArray {
        val now = Instant.now()
        val r = client.readRecords(ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(now.minusSeconds(86_400), now)))
        val arr = JSONArray()
        r.records.forEach { rec ->
            arr.put(JSONObject()
                .put("start", rec.startTime.toEpochMilli())
                .put("end", rec.endTime.toEpochMilli())
                .put("zoneOffsetMin", rec.startZoneOffset?.totalSeconds?.div(60) ?: JSONObject.NULL)
                .put("count", rec.count))
        }
        return arr
    }

    /** 지난 6시간 심박 — 샘플마다 시각(ms) · bpm */
    suspend fun readHeartRate6h(): JSONArray {
        val now = Instant.now()
        val r = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, TimeRangeFilter.between(now.minusSeconds(6 * 3_600), now)))
        val arr = JSONArray()
        r.records.forEach { rec ->
            val zone = rec.startZoneOffset?.totalSeconds?.div(60)
            rec.samples.forEach { s ->
                arr.put(JSONObject()
                    .put("time", s.time.toEpochMilli())
                    .put("zoneOffsetMin", zone ?: JSONObject.NULL)
                    .put("bpm", s.beatsPerMinute))
            }
        }
        return arr
    }

    /** 지난 24시간 수면 세션 — 시작 · 끝 · 분 */
    suspend fun readSleep24h(): JSONArray {
        val now = Instant.now()
        val r = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(now.minusSeconds(86_400), now)))
        val arr = JSONArray()
        r.records.forEach { rec ->
            arr.put(JSONObject()
                .put("start", rec.startTime.toEpochMilli())
                .put("end", rec.endTime.toEpochMilli())
                .put("zoneOffsetMin", rec.startZoneOffset?.totalSeconds?.div(60) ?: JSONObject.NULL)
                .put("minutes", (rec.endTime.epochSecond - rec.startTime.epochSecond) / 60))
        }
        return arr
    }

    /** 웹 화면으로 넘길 요약 — {steps:[…], heartRate:[…], sleep:[…], at, clockSource:"health_connect"} */
    suspend fun readSummary(): JSONObject = JSONObject()
        .put("steps", readSteps24h())
        .put("heartRate", readHeartRate6h())
        .put("sleep", readSleep24h())
        .put("at", Instant.now().toEpochMilli())
        .put("clockSource", "health_connect")
}
