package com.dmonly.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the notification buttons. "Next word" just moves on; "I know it" and
 * "Hide" first mark the current word so it never comes back, then move on.
 */
class NextWordReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra(EXTRA_WORD_ID, -1)
        val status = when (intent.action) {
            ACTION_KNOWN -> WordDatabase.STATUS_KNOWN
            ACTION_HIDE -> WordDatabase.STATUS_HIDDEN
            else -> null
        }
        if (status != null && id >= 0) WordDatabase.get(context).setStatus(id, status)
        WordNotifier.show(context) ?: WordNotifier.cancelWord(context)
    }

    companion object {
        const val ACTION_NEXT = "com.dmonly.app.action.NEXT_WORD"
        const val ACTION_KNOWN = "com.dmonly.app.action.KNOWN_WORD"
        const val ACTION_HIDE = "com.dmonly.app.action.HIDE_WORD"
        const val EXTRA_WORD_ID = "word_id"
    }
}
