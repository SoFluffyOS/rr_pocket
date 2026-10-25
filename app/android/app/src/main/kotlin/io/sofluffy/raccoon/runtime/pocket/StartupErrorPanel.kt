package io.sofluffy.raccoon.runtime.pocket

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.lang.ref.WeakReference

/**
 * What the phone shows when a project throws as it starts. If it failed
 * before its first frame, RR Pocket's own Flutter screen is gone and
 * nothing answers taps, so this is drawn natively; if it started anyway,
 * this card at the bottom leaves the rest of the app usable.
 */
object StartupErrorPanel {
    /** Weak: the view holds its activity, which a rotation may replace. */
    private var shown = WeakReference<View>(null)

    /** Main thread. [back] returns to RR Pocket's own screen. */
    fun show(activity: Activity, message: String, back: () -> Unit) {
        dismiss()
        val dark = activity.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val surface = if (dark) Color.parseColor("#1C1C1E") else Color.WHITE
        val ink = if (dark) Color.parseColor("#F2F2F7") else Color.parseColor("#1F2933")
        val muted = if (dark) Color.parseColor("#9AA0A6") else Color.parseColor("#6B7280")
        val code = if (dark) Color.parseColor("#000000") else Color.parseColor("#F2F2F7")
        fun dp(value: Int) = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), activity.resources.displayMetrics,
        ).toInt()
        fun rounded(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
            stroke?.let { setStroke(dp(1), it) }
        }
        fun text(value: String, size: Float, color: Int, bold: Boolean = false) =
            TextView(activity).apply {
                text = value
                setTextColor(color)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
                if (bold) typeface = Typeface.DEFAULT_BOLD
            }
        fun button(label: String, fill: Int, color: Int, border: Int?, onClick: () -> Unit) =
            text(label, 15f, color, bold = true).apply {
                gravity = Gravity.CENTER
                background = rounded(fill, 14, border)
                setPadding(dp(16), dp(12), dp(16), dp(12))
                setOnClickListener { onClick() }
            }

        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(surface, 24, muted)
            elevation = dp(8).toFloat()
            isClickable = true
            setPadding(dp(20), dp(20), dp(20), dp(16))
            addView(text("Your app hit an error as it started", 18f, ink, bold = true))
            addView(text(
                "If it showed nothing, this is why. The full error and stack " +
                    "trace are in flutter run's output.",
                14f, muted,
            ).apply { setPadding(0, dp(6), 0, dp(12)) })
            addView(text(message, 13f, ink).apply {
                typeface = Typeface.MONOSPACE
                background = rounded(code, 12)
                setPadding(dp(12), dp(10), dp(12), dp(10))
            })
            addView(LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, dp(16), 0, 0)
                val weight = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                addView(button("Dismiss", surface, ink, muted) { dismiss() }, weight)
                addView(View(activity), LinearLayout.LayoutParams(dp(12), 1))
                addView(
                    button("Back to RR Pocket", Color.parseColor("#FFB547"), Color.parseColor("#1F2933"), null) {
                        dismiss()
                        back()
                    },
                    LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
                )
            })
        }
        // Not clickable, no scrim: taps outside the card reach the app.
        val scrim = FrameLayout(activity).apply {
            setPadding(dp(16), dp(16), dp(16), dp(32))
            addView(
                card,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM,
                ),
            )
        }
        activity.addContentView(
            scrim,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        shown = WeakReference(scrim)
    }

    /** Main thread. */
    fun dismiss() {
        val view = shown.get() ?: return
        shown.clear()
        (view.parent as? ViewGroup)?.removeView(view)
    }
}
