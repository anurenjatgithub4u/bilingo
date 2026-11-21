package com.dmonly.app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

/**
 * How long social, video and game apps were open, hour by hour, today and on
 * each of the last seven days, for the Your Time screen. Only durations from
 * Android's usage events; never what happened inside an app. Nothing leaves
 * the phone.
 */
object UsageSummary {
    private const val PAST_DAYS = 7
    private const val MAX_APPS = 12
    private const val HOURS = 24
    private const val HOUR_MS = 3_600_000L

    /**
     * Longest single stretch counted. A screen left on with an app open reports
     * no end, which would otherwise look like many hours of use.
     */
    private const val MAX_STRETCH_MS = 3 * HOUR_MS

    private val SOCIAL = setOf(
        "com.instagram.android",
        "com.facebook.katana",
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill",
        "com.snapchat.android",
        "com.twitter.android",
        "com.reddit.frontpage",
        "in.mohalla.sharechat",
        "in.mohalla.video",
        "com.eterno.shortvideos",
        "com.pinterest",
    )
    private val VIDEO = setOf("com.google.android.youtube", "com.netflix.mediaclient")

    /** "social", "video", "games", or null for an app that isn't counted. */
    private fun category(info: ApplicationInfo, tracked: Set<String>): String? {
        val pkg = info.packageName
        if (pkg in SOCIAL) return "social"
        if (pkg in VIDEO) return "video"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            when (info.category) {
                ApplicationInfo.CATEGORY_SOCIAL -> return "social"
                ApplicationInfo.CATEGORY_VIDEO -> return "video"
                ApplicationInfo.CATEGORY_GAME -> return "games"
            }
        }
        @Suppress("DEPRECATION")
        if (info.flags and ApplicationInfo.FLAG_IS_GAME != 0) return "games"
        return if (pkg in tracked) "other" else null
    }

    /** Local midnight [daysAgo] days ago. */
    private fun dayStart(daysAgo: Int): Long = Calendar.getInstance().run {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        add(Calendar.DAY_OF_YEAR, -daysAgo)
        timeInMillis
    }

    fun load(context: Context, iconPng: (android.graphics.drawable.Drawable) -> ByteArray): Map<String, Any> {
        if (!AppUsageTracker.hasUsageAccess(context)) return mapOf("granted" to false)

        // Oldest first; the last start is today's.
        val starts = LongArray(PAST_DAYS + 1) { dayStart(PAST_DAYS - it) }
        val now = System.currentTimeMillis()
        val slots = starts.size * HOURS
        val perApp = HashMap<String, LongArray>()
        val anyUse = BooleanArray(starts.size)

        /** Splits one stretch across the hours and days it covers. */
        fun add(pkg: String, from: Long, to: Long) {
            val totals = perApp.getOrPut(pkg) { LongArray(slots) }
            val end = minOf(to, from + MAX_STRETCH_MS, now)
            var t = maxOf(from, starts[0])
            while (t < end) {
                val day = starts.indexOfLast { it <= t }
                val nextDay = if (day + 1 < starts.size) starts[day + 1] else Long.MAX_VALUE
                val hour = ((t - starts[day]) / HOUR_MS).toInt().coerceAtMost(HOURS - 1)
                // The last hour runs to midnight, so a 25-hour day still adds up.
                val hourEnd = if (hour == HOURS - 1) nextDay else starts[day] + (hour + 1) * HOUR_MS
                val stop = minOf(end, hourEnd)
                totals[day * HOURS + hour] += stop - t
                anyUse[day] = true
                t = stop
            }
        }

        val usage = context.getSystemService(UsageStatsManager::class.java)
        val events = usage.queryEvents(starts[0], now)
        val event = UsageEvents.Event()
        var current: String? = null
        var since = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            @Suppress("DEPRECATION")
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    current?.let { add(it, since, event.timeStamp) }
                    current = event.packageName
                    since = event.timeStamp
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> if (current == event.packageName) {
                    add(event.packageName, since, event.timeStamp)
                    current = null
                }
                // Screen off ends the stretch, even if no app reported it.
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    current?.let { add(it, since, event.timeStamp) }
                    current = null
                }
            }
        }
        current?.let { add(it, since, now) }

        val pm = context.packageManager
        val tracked = WordPrefs(context).trackedApps
        val hourly = LongArray(slots)
        val todayFrom = (starts.size - 1) * HOURS
        val apps = ArrayList<Pair<Long, Map<String, Any>>>()
        val categories = HashMap<String, Long>()
        for ((pkg, totals) in perApp) {
            if (pkg == context.packageName) continue
            val info = try {
                pm.getApplicationInfo(pkg, 0)
            } catch (e: PackageManager.NameNotFoundException) {
                continue
            }
            val cat = category(info, tracked) ?: continue
            for (i in totals.indices) hourly[i] += totals[i]
            var today = 0L
            for (i in todayFrom until slots) today += totals[i]
            if (today > 0) {
                categories[cat] = (categories[cat] ?: 0L) + today
                apps.add(
                    today to mapOf(
                        "package" to pkg,
                        "label" to pm.getApplicationLabel(info).toString(),
                        "category" to cat,
                        "todayMs" to today,
                        "info" to info,
                    ),
                )
            }
        }
        // Icons are slow, so only for the apps shown; every app counts in the totals.
        val shown = apps.sortedByDescending { it.first }.take(MAX_APPS).map { (_, app) ->
            val info = app["info"] as ApplicationInfo
            (app - "info") + ("icon" to iconPng(pm.getApplicationIcon(info)))
        }
        return mapOf(
            "granted" to true,
            "apps" to shown,
            "categories" to categories,
            "hourly" to hourly.toList(),
            "hasData" to anyUse.toList(),
        )
    }
}
