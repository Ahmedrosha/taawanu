package com.taawanu.taawanu

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Date

// ويدجتس الشاشة الرئيسية. البيانات بيكتبها التطبيق (Flutter) في SharedPreferences كـ JSON بالنصوص جاهزة باللغة المختارة،
// والويدجت بيقراها ويعرضها من غير نت.
object Widgets {
    const val REFRESH = "com.taawanu.taawanu.WIDGET_REFRESH"

    fun data(context: Context, key: String): JSONObject? = try {
        val raw = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.$key", null)
        if (raw == null) null else JSONObject(raw)
    } catch (e: Exception) {
        null
    }

    /** الضغط على الويدجت بيفتح التطبيق على الصفحة دي. */
    fun open(context: Context, path: String, request: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://taawanu.app$path"), context, MainActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(context, request, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun ids(context: Context, cls: Class<*>): IntArray =
        AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, cls))

    fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        PrayerWidget.render(context, mgr, ids(context, PrayerWidget::class.java))
        WardWidget.render(context, mgr, ids(context, WardWidget::class.java))
        DhikrWidget.render(context, mgr, ids(context, DhikrWidget::class.java))
    }
}

/** الصلاة الجاية: الاسم والوقت وعدّاد تنازلي. بيتحدث لوحده عند كل صلاة. */
class PrayerWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = render(context, mgr, ids)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Widgets.REFRESH) {
            render(context, AppWidgetManager.getInstance(context), Widgets.ids(context, PrayerWidget::class.java))
        }
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            val d = Widgets.data(context, "widget_prayer")
            val now = System.currentTimeMillis()
            val times = d?.optJSONArray("times")
            var nextName: String? = null
            var nextAt = 0L
            var thenName: String? = null
            var thenAt = 0L
            if (times != null) {
                for (i in 0 until times.length()) {
                    val o = times.getJSONObject(i)
                    val at = o.optLong("t")
                    if (at <= now) continue
                    if (nextName == null) {
                        nextName = o.optString("n")
                        nextAt = at
                    } else {
                        thenName = o.optString("n")
                        thenAt = at
                        break
                    }
                }
            }
            val fmt = DateFormat.getTimeFormat(context)
            val views = RemoteViews(context.packageName, R.layout.widget_prayer)
            views.setTextViewText(R.id.w_title, d?.optString("title")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_prayer_label))
            if (nextName == null) {
                views.setTextViewText(R.id.w_name, d?.optString("empty")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_open_app))
                views.setTextViewText(R.id.w_time, "")
                views.setViewVisibility(R.id.w_count, View.GONE)
                views.setTextViewText(R.id.w_then, "")
            } else {
                views.setTextViewText(R.id.w_name, nextName)
                views.setTextViewText(R.id.w_time, fmt.format(Date(nextAt)))
                views.setViewVisibility(R.id.w_count, View.VISIBLE)
                views.setChronometerCountDown(R.id.w_count, true)
                views.setChronometer(R.id.w_count, SystemClock.elapsedRealtime() + (nextAt - now), null, true)
                views.setTextViewText(R.id.w_then, if (thenName == null) "" else "$thenName ${fmt.format(Date(thenAt))}")
            }
            views.setOnClickPendingIntent(R.id.w_root, Widgets.open(context, "/prayer", 1))
            for (id in ids) mgr.updateAppWidget(id, views)

            // تحديث عند الصلاة الجاية (تقريبي، من غير إذن التنبيه الدقيق).
            if (nextName != null) {
                val pi = PendingIntent.getBroadcast(
                    context, 11, Intent(context, PrayerWidget::class.java).setAction(Widgets.REFRESH),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.set(AlarmManager.RTC, nextAt + 20_000L, pi)
            }
        }
    }
}

/** وردي: الورد الحالي وتقدمه والوقت الباقي في الدورة. */
class WardWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = render(context, mgr, ids)

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            val d = Widgets.data(context, "widget_ward")
            val items = d?.optJSONArray("items")
            // أول ورد لسه مخلصش، وإلا أول ورد.
            var item: JSONObject? = null
            if (items != null) {
                for (i in 0 until items.length()) {
                    val o = items.getJSONObject(i)
                    if (item == null) item = o
                    if (!o.optBoolean("done")) {
                        item = o
                        break
                    }
                }
            }
            val views = RemoteViews(context.packageName, R.layout.widget_ward)
            var path = "/home"
            if (item == null) {
                views.setTextViewText(R.id.w_title, context.getString(R.string.widget_ward_label))
                views.setTextViewText(R.id.w_name, d?.optString("empty")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_open_app))
                views.setViewVisibility(R.id.w_bar, View.GONE)
                views.setTextViewText(R.id.w_time, "")
                views.setTextViewText(R.id.w_then, "")
            } else {
                val total = item.optInt("total").coerceAtLeast(1)
                val read = item.optInt("read")
                views.setTextViewText(R.id.w_title, item.optString("group"))
                views.setTextViewText(R.id.w_name, item.optString("title"))
                views.setViewVisibility(R.id.w_bar, View.VISIBLE)
                views.setProgressBar(R.id.w_bar, 100, (read * 100 / total).coerceIn(0, 100), false)
                views.setTextViewText(R.id.w_time, if (item.optBoolean("done")) d?.optString("doneText") ?: "" else item.optString("progress"))
                val left = item.optLong("endsAt") - System.currentTimeMillis()
                val day = 86_400_000L
                val text = when {
                    item.optLong("endsAt") == 0L || left <= 0 -> ""
                    left >= day -> (d?.optString("leftDays") ?: "").replace("{n}", (left / day).toString())
                    else -> (d?.optString("leftHours") ?: "").replace("{n}", (left / 3_600_000L).coerceAtLeast(1).toString())
                }
                views.setTextViewText(R.id.w_then, text)
                path = "/group/" + item.optString("gid")
            }
            views.setOnClickPendingIntent(R.id.w_root, Widgets.open(context, path, 2))
            for (id in ids) mgr.updateAppWidget(id, views)
        }
    }
}

/** ذكر اليوم: بيتغير كل يوم من قايمة بيكتبها التطبيق. */
class DhikrWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = render(context, mgr, ids)

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            val d = Widgets.data(context, "widget_dhikr")
            val items = d?.optJSONArray("items")
            val views = RemoteViews(context.packageName, R.layout.widget_dhikr)
            views.setTextViewText(R.id.w_title, d?.optString("title")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_dhikr_label))
            if (items == null || items.length() == 0) {
                views.setTextViewText(R.id.w_name, context.getString(R.string.widget_open_app))
            } else {
                // اليوم بتوقيت الموبايل.
                val offset = java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis())
                val dayIndex = ((System.currentTimeMillis() + offset) / 86_400_000L).toInt()
                views.setTextViewText(R.id.w_name, items.optString(Math.floorMod(dayIndex, items.length())))
            }
            views.setOnClickPendingIntent(R.id.w_root, Widgets.open(context, "/adhkar", 3))
            for (id in ids) mgr.updateAppWidget(id, views)
        }
    }
}
