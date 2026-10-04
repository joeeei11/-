package com.example.personal_decision_assistant

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object ReviewAlarm {
    private const val storeName = "review_alarm_dates"
    private const val channelId = "decision_review"

    private fun pending(context: Context, id: String): PendingIntent {
        val intent = Intent(context, ReviewReceiver::class.java).putExtra("id", id)
        return PendingIntent.getBroadcast(context, id.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun schedule(context: Context, id: String, at: Long) {
        context.getSharedPreferences(storeName, Context.MODE_PRIVATE).edit().putLong(id, at).apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(context, id))
    }

    fun cancel(context: Context, id: String) {
        context.getSharedPreferences(storeName, Context.MODE_PRIVATE).edit().remove(id).apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.cancel(pending(context, id))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(id.hashCode())
    }

    fun restore(context: Context) {
        val dates = context.getSharedPreferences(storeName, Context.MODE_PRIVATE).all
        for ((id, value) in dates) {
            if (value is Long && value > System.currentTimeMillis()) schedule(context, id, value)
        }
    }

    fun show(context: Context, id: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channelId, "决策复查",
                NotificationManager.IMPORTANCE_DEFAULT))
        }
        val launch = Intent(context, MainActivity::class.java)
            .putExtra("open_records", true)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open = PendingIntent.getActivity(context, id.hashCode(), launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("该复查一项决策了")
            .setContentText("打开记录，查看并更新你的决定。")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(id.hashCode(), notification)
        context.getSharedPreferences(storeName, Context.MODE_PRIVATE).edit().remove(id).apply()
    }
}

class ReviewReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        intent.getStringExtra("id")?.let { ReviewAlarm.show(context, it) }
    }
}

class ReviewBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) ReviewAlarm.restore(context)
    }
}
