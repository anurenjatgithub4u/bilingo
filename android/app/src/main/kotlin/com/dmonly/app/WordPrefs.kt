package com.dmonly.app

import android.content.Context

/** User settings, stored natively so the service can read them without Flutter running. */
class WordPrefs(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("word_prefs", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(v) = prefs.edit().putBoolean("enabled", v).apply()

    var onScreenOn: Boolean
        get() = prefs.getBoolean("on_screen_on", true)
        set(v) = prefs.edit().putBoolean("on_screen_on", v).apply()

    var onUnlock: Boolean
        get() = prefs.getBoolean("on_unlock", true)
        set(v) = prefs.edit().putBoolean("on_unlock", v).apply()

    /** Subset of [Languages.codes]. */
    var languages: Set<String>
        // Drops languages that were removed (Hindi) from older settings.
        get() = (prefs.getStringSet("languages", null) ?: Languages.codes)
            .intersect(Languages.codes)
            .ifEmpty { Languages.codes }
        set(v) = prefs.edit().putStringSet("languages", v.toSet()).apply()

    /** Packages whose continuous use is timed; empty turns app tracking off. */
    var trackedApps: Set<String>
        get() = prefs.getStringSet("tracked_apps", null)?.toSet() ?: emptySet()
        set(v) = prefs.edit().putStringSet("tracked_apps", v.toSet()).apply()

    /** Minutes in a row in tracked apps before the "learn something new" nudge. */
    var limitMinutes: Int
        get() = prefs.getInt("limit_minutes", 5)
        set(v) = prefs.edit().putInt("limit_minutes", v).apply()

    /** "police" (Scroll Patrol, the default) or "ghost"; set from the app. */
    var mascot: String
        get() = prefs.getString("mascot", "police") ?: "police"
        set(v) = prefs.edit().putString("mascot", v).apply()

    /**
     * Scroll Patrol arrests the app has not collected yet, as a JSON array of
     * {at, app, minutes}. Kept short so a long absence can't grow it forever.
     */
    fun recordArrest(app: String, minutes: Int) {
        val list = try {
            org.json.JSONArray(prefs.getString("arrests", "[]"))
        } catch (e: Exception) {
            org.json.JSONArray()
        }
        list.put(
            org.json.JSONObject()
                .put("at", System.currentTimeMillis())
                .put("app", app)
                .put("minutes", minutes),
        )
        while (list.length() > MAX_ARRESTS) list.remove(0)
        prefs.edit().putString("arrests", list.toString()).apply()
    }

    /** Scroll Patrol warnings ever given, and how many the user stopped for. */
    val patrolWarnings: Int get() = prefs.getInt("patrol_warnings", 0)
    val patrolHeeded: Int get() = prefs.getInt("patrol_heeded", 0)

    fun countWarning() = prefs.edit().putInt("patrol_warnings", patrolWarnings + 1).apply()
    fun countHeeded() = prefs.edit().putInt("patrol_heeded", patrolHeeded + 1).apply()

    /** Returns the uncollected arrests (JSON array text) and clears them. */
    fun takeArrests(): String {
        val json = prefs.getString("arrests", "[]") ?: "[]"
        prefs.edit().remove("arrests").apply()
        return json
    }

    var lastShownAt: Long
        get() = prefs.getLong("last_shown_at", 0L)
        set(v) = prefs.edit().putLong("last_shown_at", v).apply()

    /** The most recently shown word, so an unlock can re-alert it. */
    var lastWord: Word?
        get() {
            val word = prefs.getString("last_word", null) ?: return null
            val meaning = prefs.getString("last_meaning", null) ?: return null
            return Word(prefs.getLong("last_id", -1), prefs.getString("last_lang", "en") ?: "en", word, meaning)
        }
        set(v) {
            if (v == null) return
            prefs.edit().putString("last_word", v.word).putString("last_meaning", v.meaning)
                .putString("last_lang", v.lang).putLong("last_id", v.id).apply()
        }

    /** Words shown so far today (local date). Resets itself when the date changes. */
    val shownToday: Int
        get() = if (prefs.getString("today_date", null) == today()) prefs.getInt("today_count", 0) else 0

    fun recordShown() {
        val count = shownToday + 1
        val editor = prefs.edit().putString("today_date", today()).putInt("today_count", count)
        // A day with at least one word extends the streak; a missed day restarts it.
        val last = prefs.getString("streak_date", null)
        if (last != today()) {
            val yesterday = java.time.LocalDate.now().minusDays(1).toString()
            val streak = if (last == yesterday) prefs.getInt("streak", 0) + 1 else 1
            editor.putString("streak_date", today()).putInt("streak", streak)
        }
        editor.apply()
    }

    /** Consecutive days with a word shown, ending today or yesterday (0 once broken). */
    val streak: Int
        get() {
            val last = prefs.getString("streak_date", null) ?: return 0
            val yesterday = java.time.LocalDate.now().minusDays(1).toString()
            return if (last == today() || last == yesterday) prefs.getInt("streak", 0) else 0
        }

    private fun today(): String = java.time.LocalDate.now().toString()

    /** Active and scheduled blocked apps JSON. */
    var blockedAppsJson: String
        get() = prefs.getString("blocked_apps", "[]") ?: "[]"
        set(v) = prefs.edit().putString("blocked_apps", v).apply()

    fun getActiveBlockedApps(): List<Map<String, Any>> {
        val raw = blockedAppsJson
        val result = mutableListOf<Map<String, Any>>()
        val now = System.currentTimeMillis()
        try {
            val array = org.json.JSONArray(raw)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val endTime = obj.optLong("endTime", 0L)
                val isActive = obj.optBoolean("isActive", true)
                if (isActive && endTime > now) {
                    val map = mutableMapOf<String, Any>()
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        map[key] = obj.get(key)
                    }
                    result.add(map)
                }
            }
        } catch (_: Exception) {}
        return result
    }

    fun isAppBlocked(pkg: String): Boolean {
        val now = System.currentTimeMillis()
        try {
            val array = org.json.JSONArray(blockedAppsJson)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val p = obj.optString("packageName", "")
                val endTime = obj.optLong("endTime", 0L)
                val isActive = obj.optBoolean("isActive", true)
                if (p == pkg && isActive && endTime > now) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    fun unblockApp(pkg: String) {
        try {
            val array = org.json.JSONArray(blockedAppsJson)
            val newArray = org.json.JSONArray()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                if (obj.optString("packageName", "") != pkg) {
                    newArray.put(obj)
                }
            }
            blockedAppsJson = newArray.toString()
        } catch (_: Exception) {}
    }

    companion object {
        private const val MAX_ARRESTS = 50
    }
}
