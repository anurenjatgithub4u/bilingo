package com.dmonly.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** Flutter host plus the channel the home screen uses to control the word service. */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    /** Word from a tapped notification that Flutter has not picked up yet. */
    private var launchWord: Map<String, String>? = null

    /** Arrest from a tapped Scroll Patrol notification, likewise. */
    private var launchArrest: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        launchWord = wordFrom(intent)
        launchArrest = arrestFrom(intent)
    }

    override fun onResume() {
        super.onResume()
        // Some OEMs (Realme/ColorOS) kill the listener in the background; opening
        // the app should bring it back without the user having to toggle anything.
        val prefs = WordPrefs(this)
        if (prefs.enabled || prefs.getActiveBlockedApps().isNotEmpty()) WordService.start(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        wordFrom(intent)?.let { channel?.invokeMethod("openWord", it) }
        arrestFrom(intent)?.let { channel?.invokeMethod("openArrest", it) }
    }

    /** Reads (and clears) the arrest extras, like [wordFrom]. */
    private fun arrestFrom(intent: Intent?): Map<String, Any>? {
        val app = intent?.getStringExtra(EXTRA_ARREST_APP) ?: return null
        val minutes = intent.getIntExtra(EXTRA_ARREST_MINUTES, 0)
        intent.removeExtra(EXTRA_ARREST_APP)
        intent.removeExtra(EXTRA_ARREST_MINUTES)
        return mapOf("app" to app, "minutes" to minutes)
    }

    /** Reads (and clears) the word extras so a later relaunch from Recents does not reopen it. */
    private fun wordFrom(intent: Intent?): Map<String, String>? {
        val word = intent?.getStringExtra(EXTRA_WORD) ?: return null
        val meaning = intent.getStringExtra(EXTRA_MEANING) ?: return null
        val lang = intent.getStringExtra(EXTRA_LANG) ?: "en"
        intent.removeExtra(EXTRA_WORD)
        intent.removeExtra(EXTRA_MEANING)
        intent.removeExtra(EXTRA_LANG)
        return mapOf("word" to word, "meaning" to meaning, "lang" to lang)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            val prefs = WordPrefs(this)
            when (call.method) {
                "getState" -> result.success(state(prefs))
                "takeLaunchWord" -> {
                    result.success(launchWord)
                    launchWord = null
                }
                "takeLaunchArrest" -> {
                    result.success(launchArrest)
                    launchArrest = null
                }
                "takeArrests" -> result.success(prefs.takeArrests())
                "patrolCounts" -> result.success(
                    mapOf("warnings" to prefs.patrolWarnings, "heeded" to prefs.patrolHeeded),
                )
                "getBlockedApps" -> result.success(prefs.getActiveBlockedApps())
                "setBlockedApps" -> {
                    val apps = call.argument<List<Map<String, Any>>>("apps") ?: emptyList()
                    val jsonArray = org.json.JSONArray()
                    for (item in apps) {
                        jsonArray.put(org.json.JSONObject(item))
                    }
                    prefs.blockedAppsJson = jsonArray.toString()
                    if (apps.isNotEmpty() && AppUsageTracker.hasUsageAccess(this)) {
                        WordService.start(this)
                    }
                    result.success(true)
                }
                "unblockApp" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    prefs.unblockApp(pkg)
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(this))
                    } else {
                        result.success(true)
                    }
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                        }
                    }
                    result.success(null)
                }
                    "setSettings" -> {
                        call.argument<Boolean>("enabled")?.let { prefs.enabled = it }
                        call.argument<Boolean>("onScreenOn")?.let { prefs.onScreenOn = it }
                        call.argument<Boolean>("onUnlock")?.let { prefs.onUnlock = it }
                        call.argument<List<String>>("languages")?.let { prefs.languages = it.toSet() }
                        call.argument<List<String>>("trackedApps")?.let { prefs.trackedApps = it.toSet() }
                        call.argument<Int>("limitMinutes")?.let { prefs.limitMinutes = it }
                        call.argument<String>("mascot")?.let { prefs.mascot = it }
                        if (prefs.enabled) WordService.start(this) else WordService.stop(this)
                        result.success(state(prefs))
                    }
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "showWordNow" -> {
                        val word = WordNotifier.show(this)
                        result.success(
                            word?.let { mapOf("word" to it.word, "meaning" to it.meaning, "lang" to it.lang) }
                        )
                    }
                    "lookup" -> {
                        val words = WordDatabase.get(this).search(call.argument<String>("query") ?: "", prefs.languages)
                        result.success(words.map { mapOf("word" to it.word, "meaning" to it.meaning, "lang" to it.lang) })
                    }
                    "setWordStatus" -> {
                        WordDatabase.get(this).setStatus(
                            call.argument<String>("lang") ?: "",
                            call.argument<String>("word") ?: "",
                            call.argument<Int>("status") ?: WordDatabase.STATUS_ACTIVE,
                        )
                        result.success(state(prefs))
                    }
                    "wordsWithStatus" -> {
                        val words = WordDatabase.get(this).wordsWithStatus(call.argument<Int>("status") ?: 0)
                        result.success(words.map { mapOf("word" to it.word, "meaning" to it.meaning, "lang" to it.lang) })
                    }
                    "pathWords" -> {
                        val words = WordDatabase.get(this).pathWords(call.argument<String>("lang") ?: "en")
                        result.success(
                            words.map { (w, level) ->
                                mapOf("word" to w.word, "meaning" to w.meaning, "lang" to w.lang, "level" to level)
                            }
                        )
                    }
                    "randomWord" -> {
                        val word = WordDatabase.get(this).peekWord(prefs.languages)
                        result.success(
                            word?.let { mapOf("word" to it.word, "meaning" to it.meaning, "lang" to it.lang) }
                        )
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "appVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf("name" to (info.versionName ?: ""), "code" to code.toInt()))
                    }
                    "openUrl" -> {
                        // A market:// link falls back to the web store when there is no Play Store.
                        val url = call.argument<String>("url") ?: ""
                        val fallback = call.argument<String>("fallback")
                        val opened = tryOpen(url) || (fallback != null && tryOpen(fallback))
                        result.success(opened)
                    }
                    "openAppSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    "shareText" -> {
                        val send = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        startActivity(Intent.createChooser(send, null))
                        result.success(null)
                    }
                    "shareImage" -> {
                        val png = call.argument<ByteArray>("png")
                        if (png == null) {
                            result.error("bad_args", "png missing", null)
                        } else try {
                            val uri = ShareProvider.publish(this, png, "bilingo-word.png")
                            val send = Intent(Intent.ACTION_SEND)
                                .setType("image/png")
                                .putExtra(Intent.EXTRA_STREAM, uri)
                                .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            // The clip carries the read grant through the chooser to the picked app.
                            send.clipData = android.content.ClipData.newRawUri("", uri)
                            startActivity(
                                Intent.createChooser(send, null)
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "installedApps" -> {
                        // Loading labels and icons for every app takes a moment; keep it off the UI thread.
                        Thread {
                            val apps = installedApps()
                            runOnUiThread { result.success(apps) }
                        }.start()
                    }
                    "usageSummary" -> {
                        // Reads days of events and loads icons; keep it off the UI thread.
                        Thread {
                            val summary = try {
                                UsageSummary.load(this) { iconPng(it) }
                            } catch (e: Exception) {
                                mapOf<String, Any>("granted" to false)
                            }
                            runOnUiThread { result.success(summary) }
                        }.start()
                    }
                    "openUsageAccessSettings" -> {
                        openUsageAccessSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun state(prefs: WordPrefs): Map<String, Any> {
        val db = WordDatabase.get(this)
        val stats = db.stats()
        return mapOf(
            "enabled" to prefs.enabled,
            "onScreenOn" to prefs.onScreenOn,
            "onUnlock" to prefs.onUnlock,
            "languages" to prefs.languages.toList(),
            "notificationsGranted" to WordNotifier.hasPermission(this),
            "batteryUnrestricted" to isIgnoringBatteryOptimizations(),
            "usageAccessGranted" to AppUsageTracker.hasUsageAccess(this),
            "trackedApps" to prefs.trackedApps.toList(),
            "limitMinutes" to prefs.limitMinutes,
            "wordCount" to db.count(prefs.languages),
            "shownToday" to prefs.shownToday,
            "totalShown" to stats.totalShown,
            "streak" to prefs.streak,
            "learned" to stats.learned,
            "available" to stats.available,
        )
    }

    private fun tryOpen(url: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    private fun isIgnoringBatteryOptimizations(): Boolean =
        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)

    private fun requestIgnoreBatteryOptimizations() {
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    /** Every app with a launcher icon (except this one), A to Z, with a small PNG icon. */
    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .distinctBy { it.activityInfo.packageName }
            .filter { it.activityInfo.packageName != packageName }
            .map {
                mapOf(
                    "package" to it.activityInfo.packageName,
                    "label" to it.loadLabel(pm).toString(),
                    "icon" to iconPng(it.loadIcon(pm)),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    private fun iconPng(icon: Drawable, size: Int = 96): ByteArray {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        icon.setBounds(0, 0, size, size)
        icon.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun openUsageAccessSettings() {
        // Many phones jump straight to this app's toggle with the package URI; others reject it.
        try {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (WordNotifier.hasPermission(this)) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    companion object {
        const val EXTRA_WORD = "word"
        const val EXTRA_MEANING = "meaning"
        const val EXTRA_LANG = "lang"
        const val EXTRA_ARREST_APP = "arrest_app"
        const val EXTRA_ARREST_MINUTES = "arrest_minutes"
        private const val CHANNEL = "com.dmonly.app/words"
        private const val REQUEST_NOTIFICATIONS = 4101
    }
}
