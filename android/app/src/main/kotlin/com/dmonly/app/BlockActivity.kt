package com.dmonly.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Clean, Google Play-compliant blocking interception activity shown when a user
 * tries to open an application they have actively blocked.
 */
class BlockActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val appLabel = intent.getStringExtra(EXTRA_APP_LABEL) ?: "This application"
        val remaining = intent.getStringExtra(EXTRA_REMAINING) ?: "a while"

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F7F9FC"))
            val pad = dp(28)
            setPadding(pad, pad, pad, pad)
        }

        // Card container
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(24).toFloat()
            }
            val pad = dp(28)
            setPadding(pad, pad, pad, pad)
            elevation = dp(8).toFloat()
        }

        // Mascot / Lock icon
        val iconText = TextView(this).apply {
            text = "🔒"
            textSize = 44f
            gravity = Gravity.CENTER
        }
        card.addView(iconText)

        // Title
        val title = TextView(this).apply {
            text = "App Blocked"
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#1E2028"))
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(6))
        }
        card.addView(title)

        // Message
        val message = TextView(this).apply {
            text = "$appLabel is currently blocked to help you stay focused ($remaining)."
            textSize = 15f
            setTextColor(Color.parseColor("#5A5D6B"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(20))
        }
        card.addView(message)

        // Primary Action: Open Bilingo Microlearning
        val learnBtn = Button(this).apply {
            text = "⚡ Take a Quick Learning Break"
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#2F80FF")) // kBrandBlue
                cornerRadius = dp(16).toFloat()
            }
            setPadding(dp(16), dp(12), dp(16), dp(12))
            setOnClickListener {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    startActivity(launchIntent)
                }
                finish()
            }
        }
        card.addView(learnBtn)

        val spacer = TextView(this).apply { height = dp(10) }
        card.addView(spacer)

        // Secondary Action: Go Home
        val homeBtn = Button(this).apply {
            text = "Back to Home Screen"
            setTextColor(Color.parseColor("#5A5D6B"))
            textSize = 14f
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F1F3F8"))
                cornerRadius = dp(16).toFloat()
            }
            setPadding(dp(16), dp(12), dp(16), dp(12))
            setOnClickListener {
                goHome()
            }
        }
        card.addView(homeBtn)

        root.addView(card)
        setContentView(root)
    }

    private fun goHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Prevent bypassing the block by pressing Back
        goHome()
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()

    companion object {
        const val EXTRA_APP_LABEL = "app_label"
        const val EXTRA_REMAINING = "remaining"
    }
}
