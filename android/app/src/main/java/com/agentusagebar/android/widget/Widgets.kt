package com.agentusagebar.android.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.agentusagebar.android.MainActivity
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.ui.components.compactRemainingTime
import com.agentusagebar.android.ui.components.countdownProgress
import com.agentusagebar.android.ui.components.relativeTime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private val WidgetBg = Color(0xFF1C1B1F)
private val WidgetFg = Color(0xFFFFFFFF)
private val WidgetMuted = Color(0xFFB0AEC0)
private val Track = Color(0xFF3A3845)
private val Green = Color(0xFF34C759)
private val Yellow = Color(0xFFFFCC00)
private val Red = Color(0xFFFF3B30)
private val OrbitBlue = Color(0xFF5B8CFF)
private val OrbitOrange = Color(0xFFFF9F0A)

private val widgetScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

class OverviewWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // Always read the persisted snapshot so all four providers render even if
        // the activity process is cold.
        val providers = WidgetSnapshotStore.load(context)
        val style = SettingsStore(context).settings.first().detailStyle
        provideContent {
            GlanceTheme {
                OverviewWidgetContent(providers = providers, style = style)
            }
        }
    }
}

class ProviderWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val settings = SettingsStore(context).settings.first()
        val providers = WidgetSnapshotStore.load(context)
        val state = providers[settings.widgetProvider]
            ?: ProviderUsageState(settings.widgetProvider, false)
        provideContent {
            GlanceTheme {
                ProviderWidgetContent(state = state, style = settings.detailStyle)
            }
        }
    }
}

@Composable
private fun OverviewWidgetContent(
    providers: Map<UsageProvider, ProviderUsageState>,
    style: DetailVisualizationStyle,
) {
    val claude = providers[UsageProvider.CLAUDE] ?: ProviderUsageState(UsageProvider.CLAUDE, false)
    val openAI = providers[UsageProvider.OPENAI] ?: ProviderUsageState(UsageProvider.OPENAI, false)
    val cursor = providers[UsageProvider.CURSOR] ?: ProviderUsageState(UsageProvider.CURSOR, false)
    val eleven = providers[UsageProvider.ELEVENLABS] ?: ProviderUsageState(UsageProvider.ELEVENLABS, false)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .cornerRadius(20.dp)
            .background(ColorProvider(WidgetBg))
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .clickable(actionStartActivity<MainActivity>()),
    ) {
        Text(
            text = "AI Usage",
            style = TextStyle(
                color = ColorProvider(WidgetFg),
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
            ),
        )
        Spacer(GlanceModifier.height(6.dp))

        // Weighted rows fill the widget height so the 2x2 doesn't hug the top.
        Row(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OverviewCell(claude, style, GlanceModifier.defaultWeight().fillMaxHeight())
            Spacer(GlanceModifier.width(10.dp))
            OverviewCell(openAI, style, GlanceModifier.defaultWeight().fillMaxHeight())
        }
        Spacer(GlanceModifier.height(6.dp))
        Row(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OverviewCell(cursor, style, GlanceModifier.defaultWeight().fillMaxHeight())
            Spacer(GlanceModifier.width(10.dp))
            OverviewCell(eleven, style, GlanceModifier.defaultWeight().fillMaxHeight())
        }
    }
}

@Composable
private fun OverviewCell(
    state: ProviderUsageState,
    style: DetailVisualizationStyle,
    modifier: GlanceModifier,
) {
    val primary = state.metrics.firstOrNull { it.percentUsed != null } ?: state.metrics.firstOrNull()
    val secondary = state.metrics.filter { it.percentUsed != null }.getOrNull(1)
        ?: state.metrics.getOrNull(1)
    val value = when {
        !state.isConfigured -> "Connect"
        primary == null -> "…"
        else -> primary.displayValue
    }

    Column(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = state.provider.shortName,
            style = TextStyle(color = ColorProvider(WidgetMuted), fontSize = 11.sp),
            maxLines = 1,
        )
        Spacer(GlanceModifier.height(4.dp))
        if (style == DetailVisualizationStyle.ORBIT && primary?.percentUsed != null) {
            val label = compactRemainingTime(primary.resetsAtEpochMs) ?: "—"
            val countdown = countdownProgress(primary.resetsAtEpochMs, primary.resetIntervalMs)
            val bitmap = OrbitBitmapRenderer.render(
                sizePx = 220,
                primaryPercent = primary.percentUsed,
                secondaryPercent = secondary?.percentUsed,
                centerLabel = label.take(7),
                countdownFraction = countdown,
            )
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = state.provider.shortName,
                modifier = GlanceModifier.size(72.dp),
            )
            Spacer(GlanceModifier.height(4.dp))
            Text(
                text = listOfNotNull(
                    primary.displayValue,
                    secondary?.takeIf { it.percentUsed != null || it.countValue != null }?.displayValue,
                ).joinToString(" · "),
                style = TextStyle(color = ColorProvider(WidgetFg), fontSize = 11.sp),
                maxLines = 1,
            )
        } else {
            Text(
                text = value,
                style = TextStyle(
                    color = ColorProvider(WidgetFg),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(5.dp))
            UsageBarGlance(primary?.percentUsed)
            secondary?.let {
                Spacer(GlanceModifier.height(3.dp))
                Text(
                    text = it.displayValue,
                    style = TextStyle(color = ColorProvider(WidgetMuted), fontSize = 10.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun ProviderWidgetContent(
    state: ProviderUsageState,
    style: DetailVisualizationStyle,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .cornerRadius(20.dp)
            .background(ColorProvider(WidgetBg))
            .padding(14.dp)
            .clickable(actionStartActivity<MainActivity>()),
    ) {
        Text(
            text = state.provider.displayName,
            style = TextStyle(
                color = ColorProvider(WidgetFg),
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
            ),
        )
        Spacer(GlanceModifier.height(8.dp))
        when {
            !state.isConfigured -> {
                Text(
                    text = "Not connected",
                    style = TextStyle(color = ColorProvider(WidgetMuted), fontSize = 12.sp),
                )
            }
            state.metrics.isEmpty() -> {
                Text(
                    text = state.error ?: "Loading…",
                    style = TextStyle(color = ColorProvider(WidgetMuted), fontSize = 12.sp),
                )
            }
            style == DetailVisualizationStyle.ORBIT -> {
                val ringMetrics = state.metrics.filter { it.percentUsed != null }.take(2)
                val primary = ringMetrics.getOrNull(0)
                val secondary = ringMetrics.getOrNull(1)
                val center = compactRemainingTime(primary?.resetsAtEpochMs) ?: "—"
                val countdown = countdownProgress(primary?.resetsAtEpochMs, primary?.resetIntervalMs)
                val bitmap = OrbitBitmapRenderer.render(
                    sizePx = 320,
                    primaryPercent = primary?.percentUsed,
                    secondaryPercent = secondary?.percentUsed,
                    centerLabel = center.take(8),
                    countdownFraction = countdown,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(bitmap),
                        contentDescription = "Orbit usage",
                        modifier = GlanceModifier.size(96.dp),
                    )
                    Spacer(GlanceModifier.width(10.dp))
                    Column {
                        ringMetrics.forEachIndexed { index, metric ->
                            val tint = if (index == 0) OrbitBlue else OrbitOrange
                            Text(
                                text = "● ${shortMetricLabel(metric)} ${metric.displayValue}",
                                style = TextStyle(color = ColorProvider(tint), fontSize = 11.sp),
                                maxLines = 1,
                            )
                            Spacer(GlanceModifier.height(4.dp))
                        }
                    }
                }
                state.metrics.filter { m -> ringMetrics.none { it.id == m.id } }.take(2).forEach { metric ->
                    Spacer(GlanceModifier.height(6.dp))
                    MetricLine(metric, compact = false)
                }
            }
            else -> {
                state.metrics.take(3).forEach { metric ->
                    MetricLine(metric, compact = false)
                    Spacer(GlanceModifier.height(8.dp))
                }
            }
        }
    }
}

@Composable
private fun MetricLine(metric: UsageMetric, compact: Boolean) {
    val label = if (compact) shortMetricLabel(metric) else metric.label
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            Text(
                text = label,
                style = TextStyle(
                    color = ColorProvider(if (compact) WidgetMuted else WidgetFg),
                    fontSize = if (compact) 11.sp else 12.sp,
                ),
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight(),
            )
            Text(
                text = metric.displayValue,
                style = TextStyle(
                    color = ColorProvider(WidgetFg),
                    fontSize = if (compact) 11.sp else 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }
        Spacer(GlanceModifier.height(3.dp))
        UsageBarGlance(metric.percentUsed)
        if (!compact) {
            metric.resetsAtEpochMs?.let { reset ->
                Spacer(GlanceModifier.height(2.dp))
                Text(
                    text = "Resets ${relativeTime(reset)}",
                    style = TextStyle(color = ColorProvider(WidgetMuted), fontSize = 10.sp),
                )
            }
            metric.detail?.let { detail ->
                Text(
                    text = detail,
                    style = TextStyle(color = ColorProvider(WidgetMuted), fontSize = 10.sp),
                )
            }
        }
    }
}

private fun shortMetricLabel(metric: UsageMetric): String = when (metric.id) {
    "five_hour" -> "5h"
    "seven_day" -> "7d"
    "models" -> "Models"
    "api" -> "API"
    "primary" -> "Primary"
    "secondary" -> "Secondary"
    "credits" -> "Used"
    "remaining" -> "Left"
    else -> metric.label
        .replace(" Window", "")
        .replace(" (7 day)", "")
        .replace(" (session)", "")
        .take(14)
}

@Composable
private fun UsageBarGlance(percent: Double?) {
    val fraction = ((percent ?: 0.0) / 100.0).toFloat().coerceIn(0f, 1f)
    val fill = when {
        fraction < 0.60f -> Green
        fraction < 0.80f -> Yellow
        else -> Red
    }
    LinearProgressIndicator(
        progress = fraction,
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(4.dp)
            .cornerRadius(50.dp),
        color = ColorProvider(fill),
        backgroundColor = ColorProvider(Track),
    )
}

class OverviewWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = OverviewWidget()
}

class ProviderWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ProviderWidget()
}

object WidgetUpdater {
    fun updateAll(context: Context) {
        val appContext = context.applicationContext
        widgetScope.launch {
            runCatching {
                val manager = GlanceAppWidgetManager(appContext)
                manager.getGlanceIds(OverviewWidget::class.java).forEach { id ->
                    OverviewWidget().update(appContext, id)
                }
                manager.getGlanceIds(ProviderWidget::class.java).forEach { id ->
                    ProviderWidget().update(appContext, id)
                }
            }
        }
    }
}
