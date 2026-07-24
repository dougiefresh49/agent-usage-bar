package com.agentusagebar.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.model.UsageTextSize
import com.agentusagebar.android.ui.theme.usageColor
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun ProviderOverviewGrid(
    providers: Map<UsageProvider, ProviderUsageState>,
    selected: UsageProvider,
    onSelect: (UsageProvider) -> Unit,
    columns: Int = 2,
) {
    val entries = UsageProvider.entries
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        entries.chunked(columns.coerceAtLeast(2)).forEach { rowProviders ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                rowProviders.forEach { provider ->
                    val state = providers[provider] ?: ProviderUsageState(provider, false)
                    ProviderSummaryCard(
                        state = state,
                        selected = selected == provider,
                        onClick = { onSelect(provider) },
                        modifier = Modifier.weight(1f),
                    )
                }
                repeat(columns - rowProviders.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ProviderSummaryCard(
    state: ProviderUsageState,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)
    val borderColor = if (selected) MaterialTheme.colorScheme.primary
    else MaterialTheme.colorScheme.outline.copy(alpha = 0.25f)
    val background = if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
    else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)

    Column(
        modifier = modifier
            .clip(shape)
            .background(background)
            .border(1.dp, borderColor, shape)
            .clickable(onClick = onClick)
            .padding(10.dp)
            .height(96.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = state.provider.shortName,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        when {
            !state.isConfigured -> StatusChip("Connect")
            state.metrics.all { it.percentUsed == null && it.countValue == null } && state.error != null ->
                StatusChip("Check account", error = true)
            state.metrics.all { it.percentUsed == null && it.countValue == null } -> StatusChip("Loading…")
            else -> state.metrics.take(2).forEach { MiniMetricRow(it) }
        }
    }
}

@Composable
private fun StatusChip(text: String, error: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.height(48.dp)) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(
                    if (error) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                ),
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = if (error) MaterialTheme.colorScheme.error
            else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun MiniMetricRow(metric: UsageMetric) {
    val compact = when (metric.id) {
        "five_hour" -> "5h"
        "seven_day" -> "7d"
        "models" -> "Models"
        "api" -> "API"
        "primary" -> "Pri"
        "secondary" -> "Sec"
        "credits" -> "Used"
        "remaining" -> "Left"
        else -> metric.label.take(6)
    }
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = compact,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = metric.displayValue,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
            )
        }
        if (metric.percentUsed != null) {
            UsageBar(percent = metric.percentUsed, height = 3.dp, style = DetailVisualizationStyle.BARS)
        }
    }
}

@Composable
fun ProviderDetailSection(
    metrics: List<UsageMetric>,
    style: DetailVisualizationStyle,
) {
    when (style) {
        DetailVisualizationStyle.ORBIT -> {
            val ringMetrics = metrics.filter { it.percentUsed != null }.take(2)
            if (ringMetrics.isNotEmpty()) {
                OrbitUsageBlock(ringMetrics)
                Spacer(modifier = Modifier.height(12.dp))
            }
            metrics.filter { m -> ringMetrics.none { it.id == m.id } }.forEach { metric ->
                UsageMetricRow(metric, style = DetailVisualizationStyle.BARS)
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
        else -> metrics.forEach { metric ->
            UsageMetricRow(metric, style = style)
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
fun OrbitUsageBlock(metrics: List<UsageMetric>) {
    val primary = metrics.getOrNull(0)
    val secondary = metrics.getOrNull(1)
    val resetLabel = compactRemainingTime(primary?.resetsAtEpochMs) ?: "—"
    val countdown = countdownProgress(primary?.resetsAtEpochMs, primary?.resetIntervalMs)
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(120.dp)) {
            OrbitRings(
                primaryPercent = primary?.percentUsed,
                secondaryPercent = secondary?.percentUsed,
                countdownFraction = countdown,
                modifier = Modifier.size(120.dp),
            )
            Text(
                text = resetLabel,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            metrics.take(2).forEachIndexed { index, metric ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(if (index == 0) Color(0xFF5B8CFF) else Color(0xFFFF9F0A)),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "${metric.label} ${metric.displayValue}",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}

@Composable
fun OrbitRings(
    primaryPercent: Double?,
    secondaryPercent: Double?,
    countdownFraction: Float = 0f,
    modifier: Modifier = Modifier,
) {
    val primary = ((primaryPercent ?: 0.0) / 100.0).toFloat().coerceIn(0f, 1f)
    val secondary = ((secondaryPercent ?: 0.0) / 100.0).toFloat().coerceIn(0f, 1f)
    val hasSecondary = secondaryPercent != null
    val drain = countdownFraction.coerceIn(0f, 1f)
    Canvas(modifier = modifier) {
        val stroke = 10.dp.toPx()
        val pad = stroke
        fun arc(progress: Float, color: Color, inset: Float) {
            val diameter = min(size.width, size.height) - inset * 2
            drawArc(
                color = color.copy(alpha = 0.18f),
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = Size(diameter, diameter),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
            if (progress > 0f) {
                drawArc(
                    color = color,
                    startAngle = -90f,
                    sweepAngle = 360f * progress,
                    useCenter = false,
                    topLeft = Offset(inset, inset),
                    size = Size(diameter, diameter),
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
            }
        }
        if (hasSecondary) {
            arc(secondary, Color(0xFFFF9F0A), pad)
            arc(primary, Color(0xFF5B8CFF), pad + stroke * 1.6f)
        } else {
            arc(primary, Color(0xFF5B8CFF), pad)
        }

        val centerDiameter = min(size.width, size.height) * (if (hasSecondary) 0.48f else 0.55f)
        val centerLeft = (size.width - centerDiameter) / 2f
        val centerTop = (size.height - centerDiameter) / 2f
        drawOval(
            color = Color(0xFF2A2833),
            topLeft = Offset(centerLeft, centerTop),
            size = Size(centerDiameter, centerDiameter),
        )
        if (drain > 0.005f) {
            // Bottom-up drain clipped to the center circle.
            val fillHeight = centerDiameter * drain
            val fillTop = centerTop + centerDiameter - fillHeight
            val clipPath = androidx.compose.ui.graphics.Path().apply {
                addOval(
                    androidx.compose.ui.geometry.Rect(
                        centerLeft,
                        centerTop,
                        centerLeft + centerDiameter,
                        centerTop + centerDiameter,
                    ),
                )
            }
            drawContext.canvas.save()
            drawContext.canvas.clipPath(clipPath)
            drawRect(
                color = Color(0xFF5B8CFF),
                topLeft = Offset(centerLeft, fillTop),
                size = Size(centerDiameter, fillHeight),
            )
            drawContext.canvas.restore()
        }
    }
}

@Composable
fun UsageMetricRow(
    metric: UsageMetric,
    style: DetailVisualizationStyle = DetailVisualizationStyle.BARS,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(text = metric.label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(
                text = metric.displayValue,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
            )
        }
        metric.detail?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontFamily = FontFamily.Monospace,
            )
        }
        if (metric.percentUsed != null) {
            UsageBar(percent = metric.percentUsed, height = if (style == DetailVisualizationStyle.CAPSULE) 10.dp else 6.dp, style = style)
        }
        metric.resetsAtEpochMs?.let { reset ->
            Text(
                text = "Resets ${relativeTime(reset)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun UsageBar(
    percent: Double?,
    height: Dp,
    style: DetailVisualizationStyle = DetailVisualizationStyle.BARS,
) {
    val progress = ((percent ?: 0.0) / 100.0).toFloat().coerceIn(0f, 1f)
    val shape = if (style == DetailVisualizationStyle.CAPSULE) RoundedCornerShape(50) else RoundedCornerShape(4.dp)
    LinearProgressIndicator(
        progress = { progress },
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(shape),
        color = usageColor(percent),
        trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
        strokeCap = StrokeCap.Round,
    )
}

fun relativeTime(epochMs: Long, nowMs: Long = System.currentTimeMillis()): String {
    val delta = epochMs - nowMs
    val abs = kotlin.math.abs(delta)
    val value = when {
        abs < TimeUnit.MINUTES.toMillis(1) -> "moments"
        abs < TimeUnit.HOURS.toMillis(1) -> "${TimeUnit.MILLISECONDS.toMinutes(abs)}m"
        abs < TimeUnit.DAYS.toMillis(1) -> "${TimeUnit.MILLISECONDS.toHours(abs)}h"
        else -> "${TimeUnit.MILLISECONDS.toDays(abs)}d"
    }
    return if (delta >= 0) "in $value" else "$value ago"
}

/**
 * Fraction of the reset window still remaining (1 = just started, 0 = about to reset).
 * Matches macOS UsagePresentationMetrics.countdownProgress.
 */
fun countdownProgress(
    resetsAtEpochMs: Long?,
    resetIntervalMs: Long?,
    nowMs: Long = System.currentTimeMillis(),
): Float {
    if (resetsAtEpochMs == null || resetIntervalMs == null || resetIntervalMs <= 0L) return 0f
    val remaining = (resetsAtEpochMs - nowMs).toDouble()
    return (remaining / resetIntervalMs.toDouble()).toFloat().coerceIn(0f, 1f)
}

/** Compact remaining-time label for orbit centers (e.g. "5d", "2h 10m", "45m"). */
fun compactRemainingTime(
    resetsAtEpochMs: Long?,
    nowMs: Long = System.currentTimeMillis(),
): String? {
    if (resetsAtEpochMs == null) return null
    val totalMinutes = maxOf(0, ((resetsAtEpochMs - nowMs + 59_999L) / 60_000L).toInt())
    if (totalMinutes >= 24 * 60) {
        val days = totalMinutes / (24 * 60)
        val hours = (totalMinutes % (24 * 60)) / 60
        return if (hours > 0) "${days}d ${hours}h" else "${days}d"
    }
    if (totalMinutes >= 60) {
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60
        return if (minutes > 0) "${hours}h ${minutes}m" else "${hours}h"
    }
    return "${totalMinutes}m"
}

fun formatUpdated(epochMs: Long?): String {
    if (epochMs == null || epochMs == 0L) return "Never"
    val relative = relativeTime(epochMs)
    return if (epochMs <= System.currentTimeMillis()) {
        // relativeTime already ends with "ago" for past times
        if (relative.endsWith("ago")) relative else "$relative ago"
    } else {
        relative
    }
}
