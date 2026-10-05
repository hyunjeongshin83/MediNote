package kr.medit.medinote

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 시스템 방송 전용 수신기 (#66 MN-66-1 · #36 MN-36-1)
 *  BOOT_COMPLETED · QUICKBOOT_POWERON · MY_PACKAGE_REPLACED · TIMEZONE_CHANGED · TIME_SET ·
 *  SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED → 저장된 일정으로 알람을 다시 겁니다.
 *
 * 왜 따로 두나: 이 액션들은 시스템만 보낼 수 있는 보호 방송이라 exported 여도 안전하지만, 같은 수신기가 MED_TAKEN·MED_FIRE
 * 까지 받으면 다른 앱이 그 액션으로 「복용했어요」 기록을 꾸며 넣거나 알림을 울릴 수 있습니다. 앱 전용 액션은 비공개
 * MedAlarmReceiver 가 받습니다. 여기서는 위 액션이 아니면 아무것도 하지 않습니다.
 */
class MedSystemReceiver : BroadcastReceiver() {
    private val actions = setOf(
        Intent.ACTION_BOOT_COMPLETED, "android.intent.action.QUICKBOOT_POWERON",
        Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED,
        "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")

    override fun onReceive(c: Context, i: Intent) {
        if (i.action !in actions) return
        // 시계·시간대가 바뀌면 벽시계로 걸어 둔 「10분 뒤」는 뜻을 잃습니다 — 그때만 지웁니다 (PR #67 Codex)
        val clockMoved = i.action == Intent.ACTION_TIME_CHANGED || i.action == Intent.ACTION_TIMEZONE_CHANGED
        MedScheduler.reschedule(c, keepSnooze = !clockMoved)
    }
}
