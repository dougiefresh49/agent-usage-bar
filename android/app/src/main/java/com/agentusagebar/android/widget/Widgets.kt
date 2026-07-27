package com.agentusagebar.android.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity as actionStartActivityIntent
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
import com.agentusagebar.android.R
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.ui.components.compactRemainingTime
import com.agentusagebar.android.ui.components.countdownProgress
import com.agentusagebar.android.ui.components.orbitLegendMetrics
import com.agentusagebar.android.ui.components.relativeTime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.min

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

internal enum class ResponsiveOverviewLayout {
    HORIZONTAL,
    VERTICAL,
    GRID,
}

internal data class ResponsiveOverviewSpec(
    val layout: ResponsiveOverviewLayout,
    val chartSizeDp: Float,
    val labelFontSizeSp: Float,
    val showSecondaryMetrics: Boolean,
    val showActions: Boolean,
)

internal fun responsiveOverviewSpec(
    widthDp: Float,
    heightDp: Float,
    actionsAvailable: Boolean,
): ResponsiveOverviewSpec {
    val width = widthDp.coerceAtLeast(1f)
    val height = heightDp.coerceAtLeast(1f)
    val layout = when {
        height <= 105f || width / height >= 2.25f -> ResponsiveOverviewLayout.HORIZONTAL
        width <= 100f && height / width >= 1.35f -> ResponsiveOverviewLayout.VERTICAL
        else -> ResponsiveOverviewLayout.GRID
    }
    val showActions = actionsAvailable &&
        layout == ResponsiveOverviewLayout.GRID &&
        width >= 220f &&
        height >= 230f
    val outerPadding = 6f
    val itemGap = 2f
    val captionHeight = 14f
    val actionSpace = if (showActions) 46f else 0f
    val contentWidth = (width - outerPadding).coerceAtLeast(1f)
    val contentHeight = (height - outerPadding - actionSpace).coerceAtLeast(1f)
    val cellWidth: Float
    val cellHeight: Float
    when (layout) {
        ResponsiveOverviewLayout.HORIZONTAL -> {
            cellWidth = (contentWidth - itemGap * 3f) / 4f
            cellHeight = contentHeight
        }
        ResponsiveOverviewLayout.VERTICAL -> {
            cellWidth = contentWidth
            cellHeight = (contentHeight - itemGap * 3f) / 4f
        }
        ResponsiveOverviewLayout.GRID -> {
            cellWidth = (contentWidth - itemGap) / 2f
            cellHeight = (contentHeight - itemGap) / 2f
        }
    }
    val chartLimit = if (layout == ResponsiveOverviewLayout.GRID) 160f else 120f
    val chartSize = min(cellWidth, cellHeight - captionHeight)
        .coerceIn(24f, chartLimit)
    return ResponsiveOverviewSpec(
        layout = layout,
        chartSizeDp = chartSize,
        labelFontSizeSp = when {
            chartSize < 38f -> 7f
            chartSize < 52f -> 8f
            chartSize < 72f -> 9f
            else -> 10f
        },
        showSecondaryMetrics = layout == ResponsiveOverviewLayout.GRID && cellWidth >= 108f,
        showActions = showActions,
    )
}

abstract class SnapshotOverviewWidget(
    private val actionsAvailable: Boolean = false,
) : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // Always read the persisted snapshot so all four providers render even if
        // the activity process is cold.
        val providers = WidgetSnapshotStore.load(context)
        val settings = SettingsStore(context).settings.first()
        val openAppAction = actionStartActivity<MainActivity>()
        val openSettingsAction = actionStartActivityIntent(
            Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_OPEN_SETTINGS, true),
        )
        provideContent {
            GlanceTheme {
                OverviewWidgetContent(
                    providers = providers,
                    style = settings.detailStyle,
                    preferredProvider = settings.widgetProvider,
                    primaryMetric = settings.primaryMetric,
                    secondaryMetric = settings.secondaryMetric,
                    claudeOrbitCenterMetric = settings.claudeWidgetOrbitCenterMetric,
                    claudeDisplayMetric = settings.claudeWidgetDisplayMetric,
                    size = LocalSize.current,
                    actionsAvailable = actionsAvailable,
                    openAppAction = openAppAction,
                    openSettingsAction = openSettingsAction,
                )
            }
        }
    }
}

class OverviewWidget : SnapshotOverviewWidget()

class DashboardWidget : SnapshotOverviewWidget(actionsAvailable = true)

class HorizontalWidget : SnapshotOverviewWidget()

class VerticalWidget : SnapshotOverviewWidget()

class ProviderWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val settings = SettingsStore(context).settings.first()
        val providers = WidgetSnapshotStore.load(context)
        val state = providers[settings.widgetProvider]
            ?: ProviderUsageState(settings.widgetProvider, false)
        val orderedState = state.copy(
            metrics = UsageMetricPreferences.orderedMetrics(
                provider = state.provider,
                primaryID = settings.primaryMetric,
                secondaryID = settings.secondaryMetric,
                available = state.metrics,
            ),
        )
        provideContent {
            GlanceTheme {
                ProviderWidgetContent(
                    state = orderedState,
                    style = settings.detailStyle,
                    claudeOrbitCenterMetric = settings.claudeWidgetOrbitCenterMetric,
                )
            }
        }
    }
}

@Composable
private fun OverviewWidgetContent(
    providers: Map<UsageProvider, ProviderUsageState>,
    style: DetailVisualizationStyle,
    preferredProvider: UsageProvider,
    primaryMetric: String,
    secondaryMetric: String,
    claudeOrbitCenterMetric: String,
    claudeDisplayMetric: String,
    size: DpSize,
    actionsAvailable: Boolean,
    openAppAction: Action,
    openSettingsAction: Action,
) {
    val states = listOf(
        UsageProvider.CLAUDE,
        UsageProvider.OPENAI,
        UsageProvider.CURSOR,
        UsageProvider.ELEVENLABS,
    ).map { providers[it] ?: ProviderUsageState(it, false) }
    val spec = responsiveOverviewSpec(
        widthDp = size.width.value,
        heightDp = size.height.value,
        actionsAvailable = actionsAvailable,
    )

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .cornerRadius(20.dp)
            .background(ColorProvider(WidgetBg))
            .padding(3.dp)
            .clickable(openAppAction),
    ) {
        when (spec.layout) {
            ResponsiveOverviewLayout.GRID -> OverviewGrid(
                states = states,
                style = style,
                preferredProvider = preferredProvider,
                primaryMetric = primaryMetric,
                secondaryMetric = secondaryMetric,
                claudeOrbitCenterMetric = claudeOrbitCenterMetric,
                claudeDisplayMetric = claudeDisplayMetric,
                chartSizeDp = spec.chartSizeDp,
                labelFontSizeSp = spec.labelFontSizeSp,
                showSecondaryMetrics = spec.showSecondaryMetrics,
                modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            )

            ResponsiveOverviewLayout.HORIZONTAL -> Row(
                modifier = GlanceModifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                states.forEachIndexed { index, state ->
                    StripOverviewCell(
                        state,
                        style,
                        preferredProvider,
                        primaryMetric,
                        secondaryMetric,
                        claudeOrbitCenterMetric,
                        claudeDisplayMetric,
                        chartSizeDp = spec.chartSizeDp,
                        labelFontSizeSp = spec.labelFontSizeSp,
                        modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    )
                    if (index != states.lastIndex) Spacer(GlanceModifier.width(2.dp))
                }
            }

            ResponsiveOverviewLayout.VERTICAL -> Column(
                modifier = GlanceModifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                states.forEachIndexed { index, state ->
                    StripOverviewCell(
                        state,
                        style,
                        preferredProvider,
                        primaryMetric,
                        secondaryMetric,
                        claudeOrbitCenterMetric,
                        claudeDisplayMetric,
                        chartSizeDp = spec.chartSizeDp,
                        labelFontSizeSp = spec.labelFontSizeSp,
                        modifier = GlanceModifier.defaultWeight().fillMaxWidth(),
                    )
                    if (index != states.lastIndex) Spacer(GlanceModifier.height(2.dp))
                }
            }
        }

        if (spec.showActions) {
            Spacer(GlanceModifier.height(4.dp))
            QuickActions(
                openSettingsAction = openSettingsAction,
                refreshAction = actionRunCallback<RefreshWidgetAction>(),
            )
        }
    }
}

@Composable
private fun OverviewGrid(
    states: List<ProviderUsageState>,
    style: DetailVisualizationStyle,
    preferredProvider: UsageProvider,
    primaryMetric: String,
    secondaryMetric: String,
    claudeOrbitCenterMetric: String,
    claudeDisplayMetric: String,
    chartSizeDp: Float,
    labelFontSizeSp: Float,
    showSecondaryMetrics: Boolean,
    modifier: GlanceModifier,
) {
    Column(modifier = modifier) {
        Row(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            states.take(2).forEachIndexed { index, state ->
                OverviewCell(
                    state,
                    style,
                    preferredProvider,
                    primaryMetric,
                    secondaryMetric,
                    claudeOrbitCenterMetric,
                    claudeDisplayMetric,
                    chartSizeDp,
                    labelFontSizeSp,
                    showSecondaryMetrics,
                    GlanceModifier.defaultWeight().fillMaxHeight(),
                )
                if (index == 0) Spacer(GlanceModifier.width(2.dp))
            }
        }
        Spacer(GlanceModifier.height(2.dp))
        Row(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            states.drop(2).forEachIndexed { index, state ->
                OverviewCell(
                    state,
                    style,
                    preferredProvider,
                    primaryMetric,
                    secondaryMetric,
                    claudeOrbitCenterMetric,
                    claudeDisplayMetric,
                    chartSizeDp,
                    labelFontSizeSp,
                    showSecondaryMetrics,
                    GlanceModifier.defaultWeight().fillMaxHeight(),
                )
                if (index == 0) Spacer(GlanceModifier.width(2.dp))
            }
        }
    }
}

@Composable
private fun OverviewCell(
    state: ProviderUsageState,
    style: DetailVisualizationStyle,
    preferredProvider: UsageProvider,
    primaryMetric: String,
    secondaryMetric: String,
    claudeOrbitCenterMetric: String,
    claudeDisplayMetric: String,
    chartSizeDp: Float,
    labelFontSizeSp: Float,
    showSecondaryMetrics: Boolean,
    modifier: GlanceModifier,
) {
    val pair = overviewMetricPair(
        state,
        preferredProvider,
        primaryMetric,
        secondaryMetric,
    )
    val primary = pair.getOrNull(0)
    val secondary = pair.getOrNull(1)
    val orbitCenter = claudeWidgetMetric(
        state = state,
        metricID = claudeOrbitCenterMetric,
        fallback = primary,
    )
    val displayMetric = claudeWidgetMetric(
        state = state,
        metricID = claudeDisplayMetric,
        fallback = primary,
    )
    val displaySecondary = secondary?.takeIf { it.id != displayMetric?.id }
    Column(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (style == DetailVisualizationStyle.ORBIT && primary?.percentUsed != null) {
            val label = compactRemainingTime(orbitCenter?.resetsAtEpochMs) ?: "—"
            val countdown = countdownProgress(
                orbitCenter?.resetsAtEpochMs,
                orbitCenter?.resetIntervalMs,
            )
            val bitmap = OrbitBitmapRenderer.render(
                sizePx = orbitBitmapSize(chartSizeDp),
                primaryPercent = primary.percentUsed,
                secondaryPercent = secondary?.percentUsed,
                centerLabel = label.take(7),
                countdownFraction = countdown,
            )
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = state.provider.shortName,
                modifier = GlanceModifier.size(chartSizeDp.dp),
            )
            ProviderValueRow(
                state = state,
                primary = displayMetric,
                secondary = displaySecondary,
                fontSizeSp = labelFontSizeSp,
                includeSecondary = showSecondaryMetrics,
            )
        } else {
            ProviderValueRow(
                state = state,
                primary = primary,
                secondary = secondary,
                fontSizeSp = labelFontSizeSp,
                includeSecondary = showSecondaryMetrics,
            )
            Spacer(GlanceModifier.height(2.dp))
            UsageBarGlance(primary?.percentUsed)
            secondary?.takeIf { showSecondaryMetrics }?.let {
                Spacer(GlanceModifier.height(2.dp))
                Text(
                    text = it.displayValue,
                    style = TextStyle(
                        color = ColorProvider(WidgetMuted),
                        fontSize = labelFontSizeSp.sp,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun ProviderValueRow(
    state: ProviderUsageState,
    primary: UsageMetric?,
    secondary: UsageMetric?,
    fontSizeSp: Float,
    includeSecondary: Boolean,
) {
    val value = when {
        !state.isConfigured -> "Connect"
        primary == null -> "…"
        else -> listOfNotNull(
            primary.displayValue,
            secondary
                ?.takeIf {
                    includeSecondary && (it.percentUsed != null || it.countValue != null)
                }
                ?.displayValue,
        ).joinToString(" · ")
    }
    // Keep the name + value as a compact centered group under the chart.
    // Filling the cell width (and weighting the name) pushes values to the
    // outer edges as the widget grows, which clips on the right column.
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = state.provider.shortName,
            style = TextStyle(
                color = ColorProvider(WidgetMuted),
                fontSize = fontSizeSp.sp,
            ),
            maxLines = 1,
        )
        Spacer(GlanceModifier.width(4.dp))
        Text(
            text = value,
            style = TextStyle(
                color = ColorProvider(WidgetFg),
                fontSize = fontSizeSp.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun StripOverviewCell(
    state: ProviderUsageState,
    style: DetailVisualizationStyle,
    preferredProvider: UsageProvider,
    primaryMetric: String,
    secondaryMetric: String,
    claudeOrbitCenterMetric: String,
    claudeDisplayMetric: String,
    chartSizeDp: Float,
    labelFontSizeSp: Float,
    modifier: GlanceModifier,
) {
    val pair = overviewMetricPair(state, preferredProvider, primaryMetric, secondaryMetric)
    val primary = pair.getOrNull(0)
    val secondary = pair.getOrNull(1)
    val orbitCenter = claudeWidgetMetric(
        state = state,
        metricID = claudeOrbitCenterMetric,
        fallback = primary,
    )
    val displayMetric = claudeWidgetMetric(
        state = state,
        metricID = claudeDisplayMetric,
        fallback = primary,
    )

    Column(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (style == DetailVisualizationStyle.ORBIT && primary?.percentUsed != null) {
            val label = compactRemainingTime(orbitCenter?.resetsAtEpochMs) ?: "—"
            val bitmap = OrbitBitmapRenderer.render(
                sizePx = orbitBitmapSize(chartSizeDp),
                primaryPercent = primary.percentUsed,
                secondaryPercent = secondary?.percentUsed,
                centerLabel = label.take(6),
                countdownFraction = countdownProgress(
                    orbitCenter?.resetsAtEpochMs,
                    orbitCenter?.resetIntervalMs,
                ),
            )
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = state.provider.shortName,
                modifier = GlanceModifier.size(chartSizeDp.dp),
            )
        } else {
            Text(
                text = primary?.displayValue ?: if (state.isConfigured) "…" else "Connect",
                style = TextStyle(
                    color = ColorProvider(WidgetFg),
                    fontSize = labelFontSizeSp.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(2.dp))
            UsageBarGlance(primary?.percentUsed)
            Spacer(GlanceModifier.height(2.dp))
        }
        Text(
            text = stripCaption(
                state,
                if (style == DetailVisualizationStyle.ORBIT) displayMetric else primary,
            ),
            style = TextStyle(
                color = ColorProvider(WidgetMuted),
                fontSize = labelFontSizeSp.sp,
            ),
            maxLines = 1,
        )
    }
}

private fun orbitBitmapSize(chartSizeDp: Float): Int {
    return (chartSizeDp * 4f).toInt().coerceIn(128, 640)
}

private fun overviewMetricPair(
    state: ProviderUsageState,
    preferredProvider: UsageProvider,
    primaryMetric: String,
    secondaryMetric: String,
): List<UsageMetric> {
    return UsageMetricPreferences.resolvedPair(
        provider = state.provider,
        primaryID = if (state.provider == preferredProvider) primaryMetric else "",
        secondaryID = if (state.provider == preferredProvider) secondaryMetric else "",
        available = state.metrics,
    )
}

internal fun claudeWidgetMetric(
    state: ProviderUsageState,
    metricID: String,
    fallback: UsageMetric?,
): UsageMetric? {
    if (state.provider != UsageProvider.CLAUDE) return fallback
    return UsageMetricPreferences.resolvedMetric(
        storedID = metricID,
        fallbackID = UsageMetricPreferences.CLAUDE_FIVE_HOUR,
        available = state.metrics,
    ) ?: fallback
}

private fun stripCaption(state: ProviderUsageState, primary: UsageMetric?): String {
    val value = when {
        !state.isConfigured -> "Connect"
        primary == null -> "…"
        else -> primary.displayValue
    }
    return "${state.provider.shortName} $value"
}

@Composable
private fun QuickActions(
    openSettingsAction: Action,
    refreshAction: Action,
) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().height(42.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        QuickAction(
            icon = R.drawable.ic_widget_settings,
            label = "Settings",
            action = openSettingsAction,
            modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
        )
        Spacer(GlanceModifier.width(6.dp))
        QuickAction(
            icon = R.drawable.ic_widget_refresh,
            label = "Refresh",
            action = refreshAction,
            modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
        )
        // Keep two equal action slots open for future quick actions.
        Spacer(GlanceModifier.defaultWeight().fillMaxHeight())
        Spacer(GlanceModifier.defaultWeight().fillMaxHeight())
    }
}

@Composable
private fun QuickAction(
    icon: Int,
    label: String,
    action: Action,
    modifier: GlanceModifier,
) {
    Row(
        modifier = modifier
            .cornerRadius(12.dp)
            .background(ColorProvider(Track))
            .padding(horizontal = 6.dp)
            .clickable(action),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            provider = ImageProvider(icon),
            contentDescription = null,
            modifier = GlanceModifier.size(16.dp),
        )
        Spacer(GlanceModifier.width(4.dp))
        Text(
            text = label,
            style = TextStyle(
                color = ColorProvider(WidgetFg),
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun ProviderWidgetContent(
    state: ProviderUsageState,
    style: DetailVisualizationStyle,
    claudeOrbitCenterMetric: String,
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
                val legendMetrics = orbitLegendMetrics(state.metrics)
                val primary = ringMetrics.getOrNull(0)
                val secondary = ringMetrics.getOrNull(1)
                val orbitCenter = claudeWidgetMetric(
                    state = state,
                    metricID = claudeOrbitCenterMetric,
                    fallback = primary,
                )
                val center = compactRemainingTime(orbitCenter?.resetsAtEpochMs) ?: "—"
                val countdown = countdownProgress(
                    orbitCenter?.resetsAtEpochMs,
                    orbitCenter?.resetIntervalMs,
                )
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
                        legendMetrics.forEachIndexed { index, metric ->
                            val tint = when {
                                metric.countValue != null -> WidgetMuted
                                index == 0 -> OrbitBlue
                                else -> OrbitOrange
                            }
                            val value = if (metric.countValue != null) {
                                "${metric.displayValue} available"
                            } else {
                                metric.displayValue
                            }
                            Text(
                                text = "● ${shortMetricLabel(metric)} $value",
                                style = TextStyle(color = ColorProvider(tint), fontSize = 11.sp),
                                maxLines = 1,
                            )
                            Spacer(GlanceModifier.height(4.dp))
                        }
                    }
                }
                val shownIds = (ringMetrics + legendMetrics).map { it.id }.toSet()
                state.metrics.filter { it.id !in shownIds }.take(2).forEach { metric ->
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
    UsageMetricPreferences.CLAUDE_FIVE_HOUR -> "5h"
    UsageMetricPreferences.CLAUDE_SEVEN_DAY -> "7d"
    UsageMetricPreferences.CURSOR_MODELS -> "Models"
    UsageMetricPreferences.CURSOR_API -> "API"
    UsageMetricPreferences.CURSOR_TOTAL -> "Total"
    UsageMetricPreferences.OPENAI_PRIMARY -> "Primary"
    UsageMetricPreferences.OPENAI_SECONDARY -> "Secondary"
    UsageMetricPreferences.OPENAI_RESET_CREDITS -> "Reset Credits"
    UsageMetricPreferences.ELEVENLABS_CREDITS -> "Used"
    UsageMetricPreferences.ELEVENLABS_REMAINING -> "Left"
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

class DashboardWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DashboardWidget()
}

class HorizontalWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HorizontalWidget()
}

class VerticalWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = VerticalWidget()
}

class ProviderWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ProviderWidget()
}

class RefreshWidgetAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        // refreshAll persists the new snapshot and asks every installed widget
        // instance to redraw when the provider requests complete.
        runCatching {
            com.agentusagebar.android.AgentUsageBarApp.instance.repository.refreshAll()
        }
    }
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
                manager.getGlanceIds(DashboardWidget::class.java).forEach { id ->
                    DashboardWidget().update(appContext, id)
                }
                manager.getGlanceIds(HorizontalWidget::class.java).forEach { id ->
                    HorizontalWidget().update(appContext, id)
                }
                manager.getGlanceIds(VerticalWidget::class.java).forEach { id ->
                    VerticalWidget().update(appContext, id)
                }
                manager.getGlanceIds(ProviderWidget::class.java).forEach { id ->
                    ProviderWidget().update(appContext, id)
                }
            }
        }
    }
}
