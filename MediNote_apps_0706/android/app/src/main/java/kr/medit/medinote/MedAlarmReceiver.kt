package kr.medit.medinote

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * 복약 알림 수신기 (MedScheduler 참고)
 *  MED_FIRE        정한 시각 — 조용한 시간이 아니면 알림을 띄우고, 다음 날 같은 시각을 다시 겁니다
 *  MED_TAKEN       알림의 「복용했어요」 — 기록에 남기고 알림을 닫습니다
 *  MED_LATER       알림의 「10분 뒤」 — 10분 뒤 한 번 더 울리게 하고 알림을 닫습니다
 *  BOOT_COMPLETED  재부팅 — 저장된 일정으로 알람을 다시 겁니다 (알람은 재부팅하면 사라집니다)
 */
class MedAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val id = i.getStringExtra("id") ?: ""
        val name = i.getStringExtra("name") ?: ""
        val time = i.getStringExtra("time") ?: ""
        when (i.action) {
            Intent.ACTION_BOOT_COMPLETED, "android.intent.action.QUICKBOOT_POWERON" -> MedScheduler.reschedule(c)
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
