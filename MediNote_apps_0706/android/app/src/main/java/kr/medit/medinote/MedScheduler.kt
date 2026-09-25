package kr.medit.medinote

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 복약 알림 — 앱을 닫아도 울리게 (2026-09-25 · #16 MN-16-6 안드로이드 쪽)
 *
 * 웹 화면(MediNote_app.html 복약 알림 레이어)은 앱이 열려 있는 동안 30초마다 시각을 보고
 * 알림을 띄웁니다. 그래서 앱을 닫으면 알림이 끊겼습니다. 여기서는 같은 일정을
 * AlarmManager 에 걸어 두어, 앱이 닫혀 있거나 폰이 잠겨 있어도 정한 시각에 울립니다.
 * 서버는 필요 없습니다 — 일정도 기록도 이 폰 안에만 있습니다.
 *
 * 흐름
 *   웹 save()  → Native.scheduleMeds(json)  → 여기 save()+reschedule()
 *                json = {on, quiet:{from,to}, items:[{id,name,times:["08:00",…]}]}
 *   정한 시각  → MedAlarmReceiver(MED_FIRE) → 알림(복용했어요 · 10분 뒤) → 다음 날 같은 시각 다시 걺
 *   단추       → MedAlarmReceiver(MED_TAKEN · MED_LATER) → 기록(log)에 남김 → 웹이 열리면 Native.medsLogTake() 로 가져감
 *   재부팅     → MedAlarmReceiver(BOOT_COMPLETED) → 저장된 일정으로 다시 걺
 *
 * 정확한 시각(setExactAndAllowWhileIdle)은 Android 12 이상에서 사용자가 「알람 및 리마인더」를
 * 허용했을 때만 씁니다. 안 했으면 setAndAllowWhileIdle 로 걸며, 몇 분 늦을 수 있습니다.
 */
object MedScheduler {

    private const val PREFS = "medinote_meds"
    private const val KEY_SCHED = "sched"
    private const val KEY_LOG = "log"
    private const val KEY_CODES = "codes"
    const val CHANNEL = "meds"

    const val ACT_FIRE = "kr.medit.medinote.MED_FIRE"
    const val ACT_TAKEN = "kr.medit.medinote.MED_TAKEN"
    const val ACT_LATER = "kr.medit.medinote.MED_LATER"

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(c: Context, json: String) {
        prefs(c).edit().putString(KEY_SCHED, json).apply()
    }

    fun schedule(c: Context): JSONObject? = try {
        prefs(c).getString(KEY_SCHED, null)?.let { JSONObject(it) }
    } catch (_: Exception) { null }

    /** 저장된 일정으로 알람을 전부 다시 겁니다 (이전 것은 지우고). */
    fun reschedule(c: Context) {
        ensureChannel(c)
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelAll(c, am)
        val sc = schedule(c) ?: return
        if (!sc.optBoolean("on", false)) return
        val items = sc.optJSONArray("items") ?: return
        val codes = JSONArray()
        for (i in 0 until items.length()) {
            val it = items.optJSONObject(i) ?: continue
            val times = it.optJSONArray("times") ?: continue
            for (j in 0 until times.length()) {
                val t = times.optString(j)
                if (!t.matches(Regex("\\d\\d:\\d\\d"))) continue
                val code = requestCode(it.optString("id"), t)
                setAlarm(c, am, code, it.optString("id"), it.optString("name"), t, nextOccurrence(t))
                codes.put(code)
            }
        }
        prefs(c).edit().putString(KEY_CODES, codes.toString()).apply()
    }

    /** 다음 날 같은 시각 (알림이 울린 뒤 다시 겁니다) */
    fun rescheduleOne(c: Context, id: String, name: String, time: String) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        setAlarm(c, am, requestCode(id, time), id, name, time, nextOccurrence(time))
    }

    /** 10분 뒤 한 번 더 */
    fun snooze(c: Context, id: String, name: String, time: String) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        setAlarm(c, am, requestCode(id, time) + 1, id, name, time, System.currentTimeMillis() + 10 * 60_000L)
    }

    private fun setAlarm(c: Context, am: AlarmManager, code: Int, id: String, name: String, time: String, at: Long) {
        val i = Intent(c, MedAlarmReceiver::class.java).setAction(ACT_FIRE)
            .putExtra("id", id).putExtra("name", name).putExtra("time", time)
        val pi = PendingIntent.getBroadcast(c, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
        try {
            if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    private fun cancelAll(c: Context, am: AlarmManager) {
        val codes = try { JSONArray(prefs(c).getString(KEY_CODES, "[]") ?: "[]") } catch (_: Exception) { JSONArray() }
        for (i in 0 until codes.length()) {
            val code = codes.optInt(i)
            for (k in 0..1) {
                val i2 = Intent(c, MedAlarmReceiver::class.java).setAction(ACT_FIRE)
                val pi = PendingIntent.getBroadcast(c, code + k, i2, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                if (pi != null) { am.cancel(pi); pi.cancel() }
            }
        }
    }

    /** 같은 약·같은 시각은 늘 같은 번호 — 다시 걸면 이전 것을 덮습니다. 짝수만 써서 +1 은 10분 뒤용으로 남깁니다. */
    private fun requestCode(id: String, time: String): Int =
        ((id + "|" + time).hashCode() and 0x3fffffff) * 2

    private fun nextOccurrence(hhmm: String): Long {
        val (h, m) = hhmm.split(":").map { it.toInt() }
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= System.currentTimeMillis() + 30_000L) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    /** 조용한 시간 안인지 — 웹 화면과 같은 규칙 */
    fun inQuiet(c: Context, nowMin: Int): Boolean {
        val q = schedule(c)?.optJSONObject("quiet") ?: return false
        fun hm(s: String): Int { val p = s.split(":"); return if (p.size == 2) p[0].toInt() * 60 + p[1].toInt() else 0 }
        val a = hm(q.optString("from", "21:30")); val b = hm(q.optString("to", "08:00"))
        return if (a <= b) nowMin in a until b else (nowMin >= a || nowMin < b)
    }

    fun ensureChannel(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "복약 알림", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "정한 시각에 약 드실 때를 알려 드립니다"
        })
    }

    fun notify(c: Context, id: String, name: String, time: String) {
        ensureChannel(c)
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val nid = requestCode(id, time)
        fun act(action: String, code: Int) = PendingIntent.getBroadcast(
            c, code,
            Intent(c, MedAlarmReceiver::class.java).setAction(action)
                .putExtra("id", id).putExtra("name", name).putExtra("time", time).putExtra("nid", nid),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(c, nid,
            Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("mnmd", "open"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val b = Notification.Builder(c).apply {
            if (Build.VERSION.SDK_INT >= 26) setChannelId(CHANNEL)
            setSmallIcon(R.mipmap.ic_launcher)
            setContentTitle("메디노트 복약 알림")
            setContentText("$name 드실 시간이에요 ($time)")
            setContentIntent(open)
            setAutoCancel(true)
            setCategory(Notification.CATEGORY_REMINDER)
            addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, "복용했어요", act(ACT_TAKEN, nid + 3)).build())
            addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, "10분 뒤", act(ACT_LATER, nid + 5)).build())
            if (Build.VERSION.SDK_INT < 26) setPriority(Notification.PRIORITY_HIGH)
        }
        nm.notify(nid, b.build())
    }

    /** 기록 — 웹이 열리면 가져가서 localStorage 기록에 합칩니다 */
    fun addLog(c: Context, action: String, id: String, name: String, time: String) {
        val arr = try { JSONArray(prefs(c).getString(KEY_LOG, "[]") ?: "[]") } catch (_: Exception) { JSONArray() }
        arr.put(JSONObject().put("action", action).put("id", id).put("name", name).put("time", time).put("at", System.currentTimeMillis()))
        val trimmed = JSONArray()
        val start = maxOf(0, arr.length() - 500)
        for (i in start until arr.length()) trimmed.put(arr.get(i))
        prefs(c).edit().putString(KEY_LOG, trimmed.toString()).apply()
    }

    /** 기록을 돌려주고 비웁니다 */
    fun takeLog(c: Context): String {
        val s = prefs(c).getString(KEY_LOG, "[]") ?: "[]"
        prefs(c).edit().remove(KEY_LOG).apply()
        return s
    }
}
