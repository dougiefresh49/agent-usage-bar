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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.UsageFillMode
import com.agentusagebar.android.data.model.UsagePace
import com.agentusagebar.android.data.model.metricLabelForMode
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageMetricPreferences
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
    preferredProvider: UsageProvider = UsageProvider.CLAUDE,
    primaryMetric: String = "",
    secondaryMetric: String = "",
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
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
                        primaryMetric = if (provider == preferredProvider) primaryMetric else "",
                        secondaryMetric = if (provider == preferredProvider) secondaryMetric else "",
                        fillMode = fillMode,
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
    primaryMetric: String,
    secondaryMetric: String,
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)
    val borderColor = if (selected) MaterialTheme.colorScheme.primary
    else MaterialTheme.colorScheme.outline.copy(alpha = 0.25f)
    val background = if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
    else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
    val summaryMetrics = UsageMetricPreferences.resolvedPair(
        provider = state.provider,
        primaryID = primaryMetric,
        secondaryID = secondaryMetric,
        available = state.metrics,
    )

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
            else -> summaryMetrics.take(2).forEach { MiniMetricRow(it, fillMode = fillMode) }
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
private fun MiniMetricRow(
    metric: UsageMetric,
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
) {
    val compact = when (metric.id) {
        UsageMetricPreferences.CLAUDE_FIVE_HOUR -> "5h"
        UsageMetricPreferences.CLAUDE_SEVEN_DAY -> "7d"
        UsageMetricPreferences.CURSOR_MODELS -> "Models"
        UsageMetricPreferences.CURSOR_API -> "API"
        UsageMetricPreferences.CURSOR_GROK_BOT -> "Grok"
        UsageMetricPreferences.OPENAI_PRIMARY -> compactWindowLabel(metric.resetIntervalMs) ?: "Pri"
        UsageMetricPreferences.OPENAI_SECONDARY -> compactWindowLabel(metric.resetIntervalMs) ?: "Sec"
        UsageMetricPreferences.OPENAI_RESET_CREDITS -> "Reset"
        UsageMetricPreferences.ELEVENLABS_CREDITS ->
            if (fillMode == UsageFillMode.DRAIN) "Credits" else "Used"
        UsageMetricPreferences.ELEVENLABS_REMAINING -> "Left"
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
                text = metric.displayValue(fillMode),
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
            )
        }
        if (metric.percentUsed != null) {
            UsageBar(
                percent = metric.percentUsed,
                height = 3.dp,
                style = DetailVisualizationStyle.BARS,
                fillMode = fillMode,
            )
        }
    }
}

@Composable
fun ProviderDetailSection(
    metrics: List<UsageMetric>,
    style: DetailVisualizationStyle,
    provider: UsageProvider,
    primaryMetric: String = "",
    secondaryMetric: String = "",
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
) {
    val ordered = UsageMetricPreferences.orderedMetrics(
        provider = provider,
        primaryID = primaryMetric,
        secondaryID = secondaryMetric,
        available = metrics,
    )
    when (style) {
        DetailVisualizationStyle.ORBIT -> {
            val pair = UsageMetricPreferences.resolvedPair(
                provider = provider,
                primaryID = primaryMetric,
                secondaryID = secondaryMetric,
                available = metrics,
            )
            val ringMetrics = pair.filter { it.percentUsed != null }.take(2)
            val legendMetrics = orbitLegendMetrics(pair.ifEmpty { ordered })
            if (ringMetrics.isNotEmpty()) {
                OrbitUsageBlock(
                    ringMetrics = ringMetrics,
                    legendMetrics = legendMetrics,
                    fillMode = fillMode,
                )
                Spacer(modifier = Modifier.height(12.dp))
            }
            val shownIds = (ringMetrics + legendMetrics).map { it.id }.toSet()
            ordered.filter { it.id !in shownIds }.forEach { metric ->
                UsageMetricRow(metric, style = DetailVisualizationStyle.BARS, fillMode = fillMode)
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
        else -> ordered.forEach { metric ->
            UsageMetricRow(metric, style = style, fillMode = fillMode)
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
    if (ordered.any { it.pace() != null }) {
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "↗ ahead of pace   — on pace   ↘ under pace",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Legend next to the orbit. Prefer the resolved preference pair when provided; otherwise
 * fall back to first percent metric + count metric (e.g. OpenAI reset credits).
 */
fun orbitLegendMetrics(metrics: List<UsageMetric>): List<UsageMetric> {
    if (metrics.isEmpty()) return emptyList()
    val preferred = metrics.take(2)
    if (preferred.size == 2 || preferred.any { it.countValue != null }) {
        return preferred
    }
    val percentMetrics = metrics.filter { it.percentUsed != null }
    val primary = percentMetrics.firstOrNull() ?: return metrics.take(2)
    val countMetric = metrics.firstOrNull { it.countValue != null }
    val secondary = countMetric
        ?: percentMetrics.firstOrNull { it.id != primary.id }
    return listOfNotNull(primary, secondary)
}

@Composable
fun OrbitUsageBlock(
    ringMetrics: List<UsageMetric>,
    legendMetrics: List<UsageMetric> = ringMetrics,
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
) {
    val primary = ringMetrics.getOrNull(0)
    val secondary = ringMetrics.getOrNull(1)
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
                fillMode = fillMode,
                modifier = Modifier.size(120.dp),
            )
            Text(
                text = resetLabel,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            legendMetrics.take(2).forEachIndexed { index, metric ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(
                                when {
                                    metric.countValue != null -> Color(0xFF9CA3AF)
                                    index == 0 -> Color(0xFF5B8CFF)
                                    else -> Color(0xFFFF9F0A)
                                },
                            ),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    val pace = metric.pace()
                    val label = metricLabelForMode(metric.id, metric.label, fillMode)
                    val value = metric.displayValue(fillMode)
                    val glyphColor = MaterialTheme.colorScheme.onSurfaceVariant
                    Text(
                        text = buildAnnotatedString {
                            append(label)
                            append(" ")
                            if (pace != null) {
                                withStyle(SpanStyle(color = glyphColor)) { append(pace.glyph) }
                                append(" ")
                            }
                            append(value)
                            if (metric.countValue != null) append(" available")
                        },
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
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
    modifier: Modifier = Modifier,
) {
    val primary = fillMode.barFraction(primaryPercent)
    val secondary = fillMode.barFraction(secondaryPercent)
    val hasSecondary = secondaryPercent != null
    val drain = countdownFraction.coerceIn(0f, 1f)
    Canvas(modifier = modifier) {
        // Match macOS UsageOrbitView proportions in a 120pt frame so the
        // session timer well and orbital bars keep a visible gap.
        val container = min(size.width, size.height)
        val scale = container / 120f
        val stroke = 8f * scale
        val outerDiameter = (if (hasSecondary) 112f else 106f) * scale
        val innerDiameter = 84f * scale
        val centerDiameter = 58f * scale

        fun arc(progress: Float, color: Color, diameter: Float) {
            val inset = (container - diameter) / 2f
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
            arc(secondary, Color(0xFFFF9F0A), outerDiameter)
            arc(primary, Color(0xFF5B8CFF), innerDiameter)
        } else {
            arc(primary, Color(0xFF5B8CFF), outerDiameter)
        }

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
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
) {
    val pace = metric.pace()
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = metricLabelForMode(metric.id, metric.label, fillMode),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (pace != null && style != DetailVisualizationStyle.ORBIT) {
                    Text(
                        text = pace.glyph,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                }
                Text(
                    text = metric.displayValue(fillMode),
                    style = MaterialTheme.typography.bodyMedium,
                    fontFamily = FontFamily.Monospace,
                )
            }
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
            UsageBar(
                percent = metric.percentUsed,
                height = if (style == DetailVisualizationStyle.CAPSULE) 10.dp else 6.dp,
                style = style,
                fillMode = fillMode,
            )
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
    fillMode: UsageFillMode = UsageFillMode.DRAIN,
) {
    val progress = fillMode.barFraction(percent)
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

/** Compact window label from its length (e.g. "5h", "7d"); null when unknown. */
fun compactWindowLabel(intervalMs: Long?): String? {
    if (intervalMs == null || intervalMs <= 0) return null
    val hours = intervalMs / (60L * 60L * 1000L)
    return when {
        hours > 0 && hours % 24 == 0L -> "${hours / 24}d"
        hours > 0 -> "${hours}h"
        else -> null
    }
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
