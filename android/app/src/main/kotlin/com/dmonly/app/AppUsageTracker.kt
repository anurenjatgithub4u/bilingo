package com.dmonly.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log

/**
 * Times how long the user stays in their chosen apps and, once they pass their
 * limit, nudges them with a word. Polls usage events every few seconds, only
 * while the phone is unlocked and in use, so it costs nothing in a pocket.
 *
 * Hopping between tracked apps (Instagram to YouTube) keeps the clock running;
 * leaving to any other app or locking the phone resets it.
 */
class AppUsageTracker(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val usage = context.getSystemService(UsageStatsManager::class.java)

    private var running = false
    private var startedAt = 0L
    private var lastQuery = 0L
    private var foreground: String? = null
    private var foregroundSince = 0L

    /** When the current stretch in tracked apps began, or 0 when not in one. */
    private var sessionStart = 0L

    /** When Scroll Patrol warned about this stretch, or 0 before a warning. */
    private var warnedAt = 0L

    private val tick = object : Runnable {
        override fun run() {
            poll()
            if (running) {
                val delay = if (WordPrefs(context).getActiveBlockedApps().isNotEmpty()) FAST_POLL_MS else POLL_MS
                handler.postDelayed(this, delay)
            }
        }
    }

    fun start() {
        if (running) return
        val prefs = WordPrefs(context)
        val hasBlocked = prefs.getActiveBlockedApps().isNotEmpty()
        if ((prefs.trackedApps.isEmpty() && !hasBlocked) || !hasUsageAccess(context)) return
        running = true
        startedAt = System.currentTimeMillis()
        // Look back a little so an app already open at unlock is picked up.
        lastQuery = startedAt - LOOKBACK_MS
        foreground = null
        foregroundSince = 0L
        sessionStart = 0L
        handler.post(tick)
        Log.d("BiLingo", "tracker started")
    }

    fun stop() {
        if (!running) return
        running = false
        handler.removeCallbacks(tick)
        sessionStart = 0L
        // Locking the phone is stopping, so a pending warning is cleared.
        clearWarning()
        Log.d("BiLingo", "tracker stopped")
    }

    private var lastBlockedIntercept = 0L

    private fun interceptBlockedApp(app: String) {
        val now = System.currentTimeMillis()
        if (now - lastBlockedIntercept < 1500L) return // debounce
        lastBlockedIntercept = now
        Log.d("BiLingo", "Intercepting blocked app: $app")

        // 1. Minimize blocked app back to Home
        try {
            val homeIntent = android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                addCategory(android.content.Intent.CATEGORY_HOME)
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(homeIntent)
        } catch (_: Exception) {}

        // 2. Launch BlockActivity
        try {
            val blockIntent = android.content.Intent(context, BlockActivity::class.java).apply {
                putExtra(BlockActivity.EXTRA_APP_LABEL, appLabel(app))
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            context.startActivity(blockIntent)
        } catch (_: Exception) {}
    }

    private fun poll() {
        val prefs = WordPrefs(context)
        val tracked = prefs.trackedApps
        val hasBlocked = prefs.getActiveBlockedApps().isNotEmpty()
        if (!hasUsageAccess(context) || (tracked.isEmpty() && !hasBlocked)) {
            stop()
            return
        }
        val now = System.currentTimeMillis()
        // Overlap the window a bit: events can land with a slightly older timestamp.
        val events = usage.queryEvents(lastQuery - OVERLAP_MS, now)
        lastQuery = now
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            @Suppress("DEPRECATION")
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND &&
                event.timeStamp >= foregroundSince
            ) {
                foreground = event.packageName
                foregroundSince = event.timeStamp
            }
        }

        val app = foreground
        if (app != null && app != context.packageName && prefs.isAppBlocked(app)) {
            interceptBlockedApp(app)
            sessionStart = 0L
            clearWarning()
            return
        }

        if (app == null || app !in tracked) {
            sessionStart = 0L
            // Left the tracked apps: stopped in time.
            clearWarning()
            return
        }
        if (sessionStart == 0L) sessionStart = maxOf(foregroundSince, startedAt)
        val minutes = prefs.limitMinutes
        if (prefs.mascot == "police") {
            patrol(app, minutes, now)
            return
        }
        if (now - sessionStart >= minutes * 60_000L) {
            Log.d("BiLingo", "limit reached: $minutes min in $app")
            WordNotifier.onScrollLimit(context, appLabel(app), minutes)
            // The next nudge waits for another full stretch.
            sessionStart = now
        }
    }

    /** Scroll Patrol: warn at the limit, arrest after [GRACE_MINUTES] more. */
    private fun patrol(app: String, minutes: Int, now: Long) {
        if (warnedAt == 0L) {
            if (now - sessionStart >= minutes * 60_000L) {
                Log.d("BiLingo", "patrol warning: $minutes min in $app")
                warnedAt = now
                WordPrefs(context).countWarning()
                WordNotifier.onScrollWarning(context, appLabel(app), minutes, GRACE_MINUTES)
            }
        } else if (now - warnedAt >= GRACE_MINUTES * 60_000L) {
            val total = ((now - sessionStart) / 60_000L).toInt()
            Log.d("BiLingo", "patrol arrest: $total min in $app")
            WordNotifier.onArrest(context, appLabel(app), total)
            warnedAt = 0L
            // The next warning waits for another full stretch.
            sessionStart = now
        }
    }

    /** Stopped within the grace period: counted as a warning heeded. */
    private fun clearWarning() {
        if (warnedAt == 0L) return
        warnedAt = 0L
        WordPrefs(context).countHeeded()
        WordNotifier.cancelWarning(context)
    }

    private fun appLabel(pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    companion object {
        private const val POLL_MS = 3_000L
        private const val FAST_POLL_MS = 1_500L

        /** Minutes Scroll Patrol waits after the warning before an arrest. */
        const val GRACE_MINUTES = 5
        private const val LOOKBACK_MS = 5 * 60_000L
        private const val OVERLAP_MS = 2_000L

        /** Usage access is an app-op the user flips in Settings, not a runtime permission. */
        fun hasUsageAccess(context: Context): Boolean {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            return mode == AppOpsManager.MODE_ALLOWED
        }
    }
}
