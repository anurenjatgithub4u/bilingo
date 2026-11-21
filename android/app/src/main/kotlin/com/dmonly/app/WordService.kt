package com.dmonly.app

import android.app.KeyguardManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/**
 * Foreground service that listens for screen-on and unlock, and times use of
 * the user's chosen apps (see [AppUsageTracker]). ACTION_SCREEN_ON
 * and ACTION_USER_PRESENT cannot be declared in the manifest, so a live
 * runtime-registered receiver is the only way to catch them.
 */
class WordService : Service() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d("BiLingo", "received ${intent.action}")
            val prefs = WordPrefs(context)
            if (!prefs.enabled) return
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> {
                    if (prefs.onScreenOn) WordNotifier.onScreenOn(context)
                    watchForUnlock()
                }
                Intent.ACTION_USER_PRESENT -> watchForUnlock()
                Intent.ACTION_SCREEN_OFF -> {
                    handler.removeCallbacksAndMessages(null)
                    unlockHandled = false
                    tracker.stop()
                }
            }
        }
    }

    /** Set once this wake-up's unlock has been handled; cleared when the screen goes off. */
    private var unlockHandled = false
    private var watchUntil = 0L

    /**
     * Unlock detection that does not rely on USER_PRESENT alone. Some phones
     * (ColorOS/Realme/OnePlus, some Samsung) send it late, before the lock
     * screen is really gone, or not at all for fingerprint and face unlock;
     * and SystemUI drops heads-up notifications posted while the lock screen
     * is still animating away. So after screen-on or USER_PRESENT, watch the
     * keyguard until it is actually gone, let the animation settle, and then
     * act once per wake-up.
     */
    private fun watchForUnlock() {
        if (unlockHandled) return
        watchUntil = SystemClock.uptimeMillis() + WATCH_MS
        handler.removeCallbacks(checkUnlock)
        handler.post(checkUnlock)
    }

    private val checkUnlock = object : Runnable {
        override fun run() {
            if (unlockHandled) return
            if (isInteractive() && !isLocked()) {
                unlockHandled = true
                tracker.start()
                handler.postDelayed(onUnlocked, SETTLE_MS)
            } else if (SystemClock.uptimeMillis() < watchUntil) {
                handler.postDelayed(this, POLL_MS)
            } else {
                // Still on the lock screen; USER_PRESENT will start watching again.
                Log.d("BiLingo", "unlock: still locked, stopped watching")
            }
        }
    }

    private val onUnlocked = Runnable {
        val prefs = WordPrefs(this)
        if (prefs.enabled && prefs.onUnlock && isInteractive() && !isLocked()) {
            Log.d("BiLingo", "unlock detected")
            WordNotifier.onUnlock(this)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tracker by lazy { AppUsageTracker(this) }

    private var registered = false

    private fun isLocked() = getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true

    private fun isInteractive() = getSystemService(PowerManager::class.java)?.isInteractive == true

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        registered = true
        running = true
        WatchdogReceiver.schedule(this)
    }

    /** Swiping the app from Recents kills the service on some OEMs; ask to be restarted. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (WordPrefs(this).enabled) WatchdogReceiver.scheduleSoon(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = WordNotifier.serviceNotification(this)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                WordNotifier.SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(WordNotifier.SERVICE_NOTIFICATION_ID, notification)
        }
        // Also re-checked here so new settings or a fresh usage-access grant take effect.
        if (isInteractive() && !isLocked()) {
            tracker.start()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        tracker.stop()
        if (registered) unregisterReceiver(receiver)
        registered = false
        running = false
        if (WordPrefs(this).enabled) WatchdogReceiver.scheduleSoon(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        /** How often, and for how long after a wake-up, to check whether the lock screen is gone. */
        private const val POLL_MS = 250L
        private const val WATCH_MS = 15_000L

        /** Pause after the lock screen is gone, so the dismiss animation has finished. */
        private const val SETTLE_MS = 700L

        /** True while this process has a live service instance. */
        @Volatile
        var running = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, WordService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (e: Exception) {
                // Android 12+ refuses background starts unless the app is exempt
                // from battery optimisation; the watchdog will try again later.
                Log.w("BiLingo", "service start refused: $e")
            }
        }

        fun stop(context: Context) {
            WatchdogReceiver.cancel(context)
            context.stopService(Intent(context, WordService::class.java))
        }
    }
}
