package com.dmonly.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/**
 * Brings the word service back if the system or an aggressive OEM battery
 * manager (Realme, ColorOS, MIUI...) killed it. Fires every 15 minutes, and
 * once shortly after the app is swiped away from Recents.
 */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!WordPrefs(context).enabled) return
        if (!WordService.running) {
            Log.d("BiLingo", "watchdog: restarting service")
            WordService.start(context)
        }
    }

    companion object {
        private const val INTERVAL_MS = 15 * 60 * 1000L

        private fun pending(context: Context, requestCode: Int): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, WatchdogReceiver::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        private fun alarms(context: Context) =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        fun schedule(context: Context) {
            alarms(context).setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + INTERVAL_MS,
                INTERVAL_MS,
                pending(context, 10),
            )
        }

        fun scheduleSoon(context: Context) {
            alarms(context).setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 2_000L,
                pending(context, 11),
            )
        }

        fun cancel(context: Context) {
            alarms(context).cancel(pending(context, 10))
            alarms(context).cancel(pending(context, 11))
        }
    }
}
