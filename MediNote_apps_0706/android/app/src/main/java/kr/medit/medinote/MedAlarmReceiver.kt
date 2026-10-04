package kr.medit.medinote

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * 복약 알림 수신기 — 앱 전용 (MedScheduler 참고). 매니페스트에서 exported=false 라 이 앱의 PendingIntent 만 닿습니다 (#66 MN-66-1).
 *  MED_FIRE        정한 시각 — 조용한 시간이 아니면 알림을 띄우고, 다음 날 같은 시각을 다시 겁니다
 *  MED_TAKEN       알림의 「복용했어요」 — 기록에 남기고 알림을 닫습니다
 *  MED_LATER       알림의 「10분 뒤」 — 10분 뒤 한 번 더 울리게 하고 알림을 닫습니다
 *  재부팅 · 앱 업데이트 · 시간대/시계 변경 · 정확 알람 권한 변경은 MedSystemReceiver 가 받습니다 (#36 MN-36-1)
 */
class MedAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val id = i.getStringExtra("id") ?: ""
        val name = i.getStringExtra("name") ?: ""
        val time = i.getStringExtra("time") ?: ""
        when (i.action) {
            MedScheduler.ACT_FIRE -> {
                val now = Calendar.getInstance()
                val min = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
                val sc = MedScheduler.schedule(c)
                if (sc != null && sc.optBoolean("on", false) && !MedScheduler.inQuiet(c, min)) {
                    MedScheduler.notify(c, id, name, time)
                }
                if (time.isNotEmpty()) MedScheduler.rescheduleOne(c, id, name, time)
            }
            MedScheduler.ACT_TAKEN -> {
                MedScheduler.addLog(c, "taken", id, name, time)
                dismiss(c, i.getIntExtra("nid", 0))
            }
            MedScheduler.ACT_LATER -> {
                MedScheduler.addLog(c, "later", id, name, time)
                MedScheduler.snooze(c, id, name, time)
                dismiss(c, i.getIntExtra("nid", 0))
            }
        }
    }

    private fun dismiss(c: Context, nid: Int) {
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(nid)
    }
}
