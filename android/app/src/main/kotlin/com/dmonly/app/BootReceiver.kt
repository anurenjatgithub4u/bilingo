package com.dmonly.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the listener after a reboot or app update if the user had it on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            val prefs = WordPrefs(context)
            if (prefs.enabled || prefs.getActiveBlockedApps().isNotEmpty()) {
                WordService.start(context)
            }
        }
    }
}
