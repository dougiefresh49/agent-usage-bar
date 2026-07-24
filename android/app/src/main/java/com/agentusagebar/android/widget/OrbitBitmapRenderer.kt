package com.agentusagebar.android.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.min

object OrbitBitmapRenderer {
    private val trackColor = 0xFF3A3845.toInt()
    private val primaryColor = 0xFF5B8CFF.toInt()
    private val secondaryColor = 0xFFFF9F0A.toInt()
    private val bgColor = 0x001C1B1F // transparent so widget bg shows through
    private val centerWell = 0xFF2A2833.toInt()
    private val drainFill = 0xFF5B8CFF.toInt()
    private val textColor = 0xFFFFFFFF.toInt()

    fun render(
        sizePx: Int,
        primaryPercent: Double?,
        secondaryPercent: Double?,
        centerLabel: String,
        countdownFraction: Float = 0f,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        // Transparent outside the rings — Glance widget bg shows through.
        canvas.drawColor(0x00000000)

        val stroke = sizePx * 0.085f
        val cx = sizePx / 2f
        val cy = sizePx / 2f
        val hasSecondary = secondaryPercent != null

        fun ring(progress: Float, color: Int, inset: Float) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.ROUND
            }
            val diameter = min(sizePx.toFloat(), sizePx.toFloat()) - inset * 2
            val oval = RectF(inset, inset, inset + diameter, inset + diameter)
            paint.color = trackColor
            canvas.drawArc(oval, -90f, 360f, false, paint)
            if (progress > 0f) {
                paint.color = color
                canvas.drawArc(oval, -90f, 360f * progress.coerceIn(0f, 1f), false, paint)
            }
        }

        val p = ((primaryPercent ?: 0.0) / 100.0).toFloat()
        if (hasSecondary) {
            ring(((secondaryPercent ?: 0.0) / 100.0).toFloat(), secondaryColor, stroke * 0.55f)
            ring(p, primaryColor, stroke * 2.55f)
        } else {
            ring(p, primaryColor, stroke * 0.55f)
        }

        // Center well + bottom-up drain (100% = window just started, 0% = about to reset).
        val centerDiameter = sizePx * (if (hasSecondary) 0.48f else 0.55f)
        val centerLeft = cx - centerDiameter / 2f
        val centerTop = cy - centerDiameter / 2f
        val centerOval = RectF(
            centerLeft,
            centerTop,
            centerLeft + centerDiameter,
            centerTop + centerDiameter,
        )

        val wellPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = centerWell
        }
        canvas.drawOval(centerOval, wellPaint)

        val drain = countdownFraction.coerceIn(0f, 1f)
        if (drain > 0.005f) {
            canvas.save()
            val clip = Path().apply { addOval(centerOval, Path.Direction.CW) }
            canvas.clipPath(clip)
            val fillTop = centerOval.bottom - centerDiameter * drain
            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
                color = drainFill
            }
            canvas.drawRect(
                centerOval.left,
                fillTop,
                centerOval.right,
                centerOval.bottom,
                fillPaint,
            )
            canvas.restore()
        }

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textAlign = Paint.Align.CENTER
            textSize = sizePx * 0.13f
            isFakeBoldText = true
        }
        val label = centerLabel.ifBlank { "—" }
        val textY = cy - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(label, cx, textY, textPaint)
        return bitmap
    }
}
