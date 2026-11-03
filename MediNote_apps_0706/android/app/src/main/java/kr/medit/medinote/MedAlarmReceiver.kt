package kr.medit.medinote

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * 복약 알림 수신기 — 앱 전용 (MedScheduler 참고). 매니페스트에서 exported=false 라 이 앱의 PendingIntent 만 닿습니다 (#66 MN-66-1).
 *  MED_FIRE        정한 시각 — 조용한 시간이 아니면 알림을 띄우고, 다음 날 같은 시각을 다시 겁니다
 *  MED_TAKEN       알림의 「복용했어요」 — 그 알림에 묶인 약 전부를 기록에 남기고 알림을 닫습니다
 *  MED_LATER       알림의 「10분 뒤」 — 10분 뒤 한 번 더 울리게 하고 알림을 닫습니다
 *  재부팅 · 앱 업데이트 · 시간대/시계 변경 · 정확 알람 권한 변경은 MedSystemReceiver 가 받습니다 (#36 MN-36-1)
 */
class MedAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val time = i.getStringExtra("time") ?: ""
        // 알람·알림은 시각마다 하나 — 그 시각의 약 전부를 묶습니다 (#123 MN-123-1). id·name 하나만 든 것은 묶기 전에 걸린 알람·알림입니다
        val legacyId = i.getStringExtra("id")
        val ids = i.getStringArrayExtra("ids") ?: legacyId?.let { arrayOf(it) }
        when (i.action) {
            MedScheduler.ACT_FIRE -> {
                val now = Calendar.getInstance()
                val min = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
                val sc = MedScheduler.schedule(c)
                if (sc != null && sc.optBoolean("on", false) && !MedScheduler.inQuiet(c, min)) {
                    // 「10분 뒤」로 다시 울릴 때는 그 알림에 묶였던 약만
                    val meds = MedScheduler.itemsAt(c, time).filter { m -> ids == null || legacyId != null || m.first in ids }
                    if (meds.isNotEmpty()) MedScheduler.notify(c, time, meds)
                }
                // 다시 걸기 전에 지금 일정을 다시 봅니다 — 그 사이 알림을 껐거나 그 시각을 지웠으면 걸지 않습니다 (PR #167 Sourcery)
                if (time.isNotEmpty() && MedScheduler.itemsAt(c, time).isNotEmpty()) MedScheduler.rescheduleOne(c, time)
            }
            MedScheduler.ACT_TAKEN, MedScheduler.ACT_LATER -> {
                val action = if (i.action == MedScheduler.ACT_TAKEN) "taken" else "later"
                // 지금 일정에 그 시각으로 남아 있는 약만 — 알림을 껐거나 약·시각을 지운 뒤 남은 알림의 단추는 기록하지 않습니다 (PR #168 Codex)
                val now = MedScheduler.itemsAt(c, time).map { it.first }.toSet()
                val all = ids ?: emptyArray()
                val names = i.getStringArrayExtra("names") ?: arrayOf(i.getStringExtra("name") ?: "")
                val keep = all.indices.filter { all[it] in now }
                keep.forEach { k -> MedScheduler.addLog(c, action, all[k], names.getOrNull(k) ?: "", time) }
                if (action == "later" && keep.isNotEmpty()) MedScheduler.snooze(c, time, keep.map { all[it] }.toTypedArray())
                dismiss(c, i.getIntExtra("nid", 0))
            }
        }
    }

    private fun dismiss(c: Context, nid: Int) {
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(nid)
    }
}
