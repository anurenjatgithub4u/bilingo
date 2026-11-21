package com.dmonly.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import org.json.JSONObject

/** Builds and posts the "word + meaning" local notification. */
object WordNotifier {
    private const val ARTICLES_ASSET = "german_articles.json"
    private const val PLURALS_ASSET = "german_plurals.json"

    /**
     * German words stored capitalised that aren't nouns, as they should be
     * written (the app's word cards use the same spellings).
     */
    private val GERMAN_DISPLAY = mapOf(
        "Verschlimmbessern" to "verschlimmbessern",
        "Hilfsbereit" to "hilfsbereit",
        "Aufwiedersehen" to "Auf Wiedersehen",
    )

    private const val WORD_CHANNEL = "word_of_the_moment_v2"
    private const val SERVICE_CHANNEL = "word_service"
    private const val WORD_NOTIFICATION_ID = 1001
    const val SERVICE_NOTIFICATION_ID = 1002
    private const val PATROL_CHANNEL = "scroll_patrol"
    private const val WARNING_NOTIFICATION_ID = 1003
    private const val ARREST_NOTIFICATION_ID = 1004
    private const val PATROL_RED = 0xFFE5484D.toInt()

    /** Screen-on within this window of the last word is ignored. */
    private const val SCREEN_ON_THROTTLE_MS = 30_000L

    /** An unlock within this window of the last word re-alerts that word instead of picking a new one. */
    private const val SAME_WORD_WINDOW_MS = 15_000L

    fun hasPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return context.checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
            PackageManager.PERMISSION_GRANTED
    }

    fun onScreenOn(context: Context) {
        val prefs = WordPrefs(context)
        if (System.currentTimeMillis() - prefs.lastShownAt < SCREEN_ON_THROTTLE_MS) {
            Log.d("BiLingo", "screen-on skipped: throttled")
            return
        }
        show(context)
    }

    /**
     * Unlock is the moment the user actually sees the screen, so it always pops
     * the notification. If screen-on just showed a word (seconds ago, same wake-up)
     * that word is re-alerted rather than counted twice. Any other unlock gets a
     * new word, so quick successive unlocks never repeat one.
     */
    fun onUnlock(context: Context) {
        val prefs = WordPrefs(context)
        val last = prefs.lastWord
        if (prefs.onScreenOn && last != null &&
            System.currentTimeMillis() - prefs.lastShownAt < SAME_WORD_WINDOW_MS &&
            WordDatabase.get(context).isActive(last.id)
        ) {
            Log.d("BiLingo", "unlock: re-alerting '${last.word}'")
            // The screen-on copy was posted on the lock screen and already "seen";
            // an in-place update may not heads-up, so post it fresh.
            cancelWord(context)
            post(context, last)
        } else {
            show(context)
        }
    }

    /**
     * The user passed their limit in a tracked app: same word notification, but
     * headed with a nudge to stop scrolling and learn instead.
     */
    fun onScrollLimit(context: Context, app: String, minutes: Int) {
        val unit = if (minutes == 1) "minute" else "minutes"
        show(context, Nudge("Enough scrolling! Let's learn something new", "$minutes $unit on $app"))
    }

    /**
     * Scroll Patrol, step one: the limit is reached. Stopping within [grace]
     * minutes clears it; carrying on gets the learner arrested.
     */
    fun onScrollWarning(context: Context, app: String, minutes: Int, grace: Int) {
        val unit = if (minutes == 1) "minute" else "minutes"
        postPatrol(
            context,
            WARNING_NOTIFICATION_ID,
            "\u26A0\uFE0F Time to stop scrolling!",
            "$minutes $unit on $app. Stop within $grace minutes or you're under arrest!",
            openApp(context, 7),
        )
    }

    /** The learner stopped in time (or locked the phone): the warning goes. */
    fun cancelWarning(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(WARNING_NOTIFICATION_ID)
    }

    /** Scroll Patrol, step two: still scrolling after the warning. */
    fun onArrest(context: Context, app: String, minutes: Int) {
        WordPrefs(context).recordArrest(app, minutes)
        cancelWarning(context)
        postPatrol(
            context,
            ARREST_NOTIFICATION_ID,
            "\uD83D\uDEA8 You're under arrest!",
            "You kept scrolling $app after a warning ($minutes minutes). Open BiLingo to pay bail.",
            openArrest(context, Arrest(app, minutes)),
        )
    }

    private fun postPatrol(context: Context, id: Int, title: String, text: String, intent: PendingIntent) {
        if (!hasPermission(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannels(manager)
        val notification = builder(context, PATROL_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_word)
            .setLargeIcon(badge(context, "!", PATROL_RED, surprised = true))
            .setColor(PATROL_RED)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(intent)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_REMINDER)
            .build()
        manager.notify(id, notification)
    }

    /** Headline and note that replace the usual title when posting a scroll nudge. */
    private class Nudge(val title: String, val note: String)

    /** A Scroll Patrol arrest: tapping the notification opens the arrest screen. */
    private class Arrest(val app: String, val minutes: Int)

    /** Picks a new word, counts it, and posts it. Returns the word, or null if there was none to show. */
    fun show(context: Context): Word? = show(context, null)

    private fun show(context: Context, nudge: Nudge?): Word? {
        val prefs = WordPrefs(context)
        val word = WordDatabase.get(context).nextWord(prefs.languages, prefs.lastWord?.id ?: -1) ?: return null
        prefs.lastShownAt = System.currentTimeMillis()
        prefs.lastWord = word
        prefs.recordShown()
        Log.d("BiLingo", "showing '${word.word}', permission=${hasPermission(context)}")
        post(context, word, nudge)
        return word
    }

    /** German noun -> der/die/das, from assets (same data as the app's word cards). */
    @Volatile private var germanArticles: Map<String, String>? = null

    private fun articles(context: Context): Map<String, String> =
        germanArticles ?: try {
            val json = JSONObject(
                context.assets.open(ARTICLES_ASSET).bufferedReader().use { it.readText() },
            )
            json.keys().asSequence().associateWith { json.getString(it) }
        } catch (e: Exception) {
            // Better a word without its article than no notification.
            Log.w("BiLingo", "no German articles", e)
            emptyMap()
        }.also { germanArticles = it }

    /** German noun -> plural ("" when it has none), from assets. */
    @Volatile private var germanPlurals: Map<String, String>? = null

    private fun plurals(context: Context): Map<String, String> =
        germanPlurals ?: try {
            val json = JSONObject(
                context.assets.open(PLURALS_ASSET).bufferedReader().use { it.readText() },
            )
            json.keys().asSequence().associateWith { json.getString(it) }
        } catch (e: Exception) {
            Log.w("BiLingo", "no German plurals", e)
            emptyMap()
        }.also { germanPlurals = it }

    /**
     * The word as a learner should see it: "die Gemeinschaft" for German
     * nouns, with the plural when there is one ("der Apfel · die Äpfel").
     */
    private fun headword(context: Context, word: Word): String {
        if (word.lang != "de") return word.word
        val article = articles(context)[word.word]
            ?: return GERMAN_DISPLAY[word.word] ?: word.word
        val plural = plurals(context)[word.word].orEmpty()
        return if (plural.isEmpty()) "$article ${word.word}"
        else "$article ${word.word} \u00B7 die $plural"
    }

    private fun post(context: Context, word: Word, nudge: Nudge? = null) {
        if (!hasPermission(context)) return
        val prefs = WordPrefs(context)
        val db = WordDatabase.get(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannels(manager)

        val lang = Languages.byCode(word.lang)
        val color = lang.color
        val headword = headword(context, word)
        val language = lang.label
        val stats = db.stats()
        val learned = stats.learned[word.lang] ?: 0
        val available = stats.available[word.lang] ?: 0
        val streak = prefs.streak
        val streakText = if (streak > 0) "  ·  $streak-day streak" else ""
        // Collapsed view shows this as the sub text, so keep it short.
        val progress = "$language  ·  Word #${stats.totalShown}  ·  Today ${prefs.shownToday}"
        val summary = "Word #${stats.totalShown}  ·  Today ${prefs.shownToday}$streakText  ·  " +
            "$language $learned/$available learned"

        // Android shows up to three buttons; all of them move on to a new word.
        val known = action(context, 4, "I know it", NextWordReceiver.ACTION_KNOWN, word)
        val hide = action(context, 5, "Hide", NextWordReceiver.ACTION_HIDE, word)
        val next = action(context, 2, "Next word", NextWordReceiver.ACTION_NEXT, word)

        val notification = builder(context, WORD_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_word)
            .setLargeIcon(badge(context, lang.badge, color, surprised = nudge != null))
            .setColor(color)
            .setContentTitle(nudge?.title ?: headword)
            .setContentText(if (nudge != null) "$headword  ·  ${word.meaning}" else word.meaning)
            .setSubText(nudge?.note ?: progress)
            .setStyle(
                Notification.BigTextStyle()
                    .setBigContentTitle(nudge?.title ?: headword)
                    .bigText(if (nudge != null) "$headword\n${word.meaning}" else word.meaning)
                    .setSummaryText(nudge?.note ?: summary)
            )
            .addAction(known)
            .addAction(hide)
            .addAction(next)
            .setContentIntent(openWord(context, word))
            .setAutoCancel(true)
            // Alert every time, even when replacing a word still in the shade.
            .setOnlyAlertOnce(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_RECOMMENDATION)
            .setTimeoutAfter(10 * 60 * 1000L)
            .build()
        // Same id: a new word replaces the previous one instead of stacking.
        manager.notify(WORD_NOTIFICATION_ID, notification)
    }

    /** Removes the word notification, e.g. when every word has been hidden or learned. */
    fun cancelWord(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(WORD_NOTIFICATION_ID)
    }

    private fun action(context: Context, requestCode: Int, label: String, action: String, word: Word) =
        Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_stat_word),
            label,
            PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, NextWordReceiver::class.java)
                    .setAction(action)
                    .putExtra(NextWordReceiver.EXTRA_WORD_ID, word.id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        ).build()

    fun serviceNotification(context: Context): Notification {
        ensureChannels(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        return builder(context, SERVICE_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_word)
            .setContentTitle("Word reminders are on")
            .setContentText("Waiting for your next screen-on or unlock")
            .setContentIntent(openApp(context, 1))
            .setOngoing(true)
            .build()
    }

    /**
     * The notification's large icon: the ghost mascot on a pale circle, with a
     * small coloured language tag. Happy for a word; surprised for a scroll nudge.
     */
    private fun badge(context: Context, label: String, color: Int, surprised: Boolean, size: Int = 192): Bitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val s = size.toFloat()

        paint.color = Color.rgb(0xDD, 0xEF, 0xF5)
        canvas.drawCircle(s / 2, s / 2, s / 2, paint)

        // The rendered ghost has room around it; draw it a bit larger than the circle.
        val ghost = BitmapFactory.decodeResource(
            context.resources,
            if (surprised) R.drawable.ghost_surprised else R.drawable.ghost_happy,
        )
        canvas.save()
        canvas.clipPath(Path().apply { addCircle(s / 2, s / 2, s / 2, Path.Direction.CW) })
        canvas.drawBitmap(ghost, null, RectF(-s * 0.14f, -s * 0.12f, s * 1.14f, s * 1.16f), paint)
        canvas.restore()

        // Language tag, kept inside the circle so round crops don't cut it off.
        val cx = s * 0.74f
        val cy = s * 0.74f
        val r = s * 0.16f
        paint.color = Color.WHITE
        canvas.drawCircle(cx, cy, r + s * 0.02f, paint)
        paint.color = color
        canvas.drawCircle(cx, cy, r, paint)
        paint.color = Color.WHITE
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = r * 0.95f
        paint.textAlign = Paint.Align.CENTER
        canvas.drawText(label, cx, cy - (paint.descent() + paint.ascent()) / 2f, paint)
        return bitmap
    }

    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel)
        else @Suppress("DEPRECATION") Notification.Builder(context)

    /** Opens the app on the word's detail screen. */
    private fun openWord(context: Context, word: Word): PendingIntent =
        PendingIntent.getActivity(
            context,
            3,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MainActivity.EXTRA_WORD, word.word)
                .putExtra(MainActivity.EXTRA_MEANING, word.meaning)
                .putExtra(MainActivity.EXTRA_LANG, word.lang),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** Opens the app on the arrest screen. */
    private fun openArrest(context: Context, arrest: Arrest): PendingIntent =
        PendingIntent.getActivity(
            context,
            6,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MainActivity.EXTRA_ARREST_APP, arrest.app)
                .putExtra(MainActivity.EXTRA_ARREST_MINUTES, arrest.minutes),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun openApp(context: Context, requestCode: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun ensureChannels(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        // Importance cannot be raised on an existing channel, hence the v2 id.
        manager.deleteNotificationChannel("word_of_the_moment")
        manager.createNotificationChannel(
            NotificationChannel(WORD_CHANNEL, "Word of the moment", NotificationManager.IMPORTANCE_HIGH)
                .apply {
                    description = "A word and its meaning when you wake or unlock your phone"
                    setSound(null, null)
                    enableVibration(false)
                }
        )
        manager.createNotificationChannel(
            NotificationChannel(PATROL_CHANNEL, "App Usage Warnings", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "A warning when you pass your scrolling limit, then an arrest if you keep going" }
        )
        manager.createNotificationChannel(
            NotificationChannel(SERVICE_CHANNEL, "Background listener", NotificationManager.IMPORTANCE_MIN)
                .apply { description = "Keeps the app listening for screen-on and unlock events" }
        )
    }
}
