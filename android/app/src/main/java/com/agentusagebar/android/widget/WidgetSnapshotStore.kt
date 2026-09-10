package com.agentusagebar.android.widget

import android.content.Context
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Shared encode/decode for prefs and unit-test helpers. */
internal val widgetSnapshotJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

/**
 * Widgets run in a separate process lifecycle from the UI. Persist the last
 * usage snapshot so Glance can render Cursor/ElevenLabs even when the activity
 * process is not warm.
 */
object WidgetSnapshotStore {
    private const val PREFS = "agent_usage_bar_widget_snapshot"
    private const val KEY = "snapshot_json"

    fun save(context: Context, snapshot: AppUsageSnapshot) {
        val payload = widgetSnapshotPayload(snapshot)
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, widgetSnapshotJson.encodeToString(payload))
            .apply()
    }

    fun load(context: Context): LoadedWidgetSnapshot {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)
            ?: return LoadedWidgetSnapshot()

        val payload = runCatching {
            widgetSnapshotJson.decodeFromString<WidgetSnapshotPayload>(raw)
        }.getOrNull()
            ?: return LoadedWidgetSnapshot()

        return loadedWidgetSnapshot(payload)
    }
}

/** In-memory shape Glance widgets read after [WidgetSnapshotStore.load]. */
data class LoadedWidgetSnapshot(
    val providers: Map<UsageProvider, ProviderUsageState> = UsageProvider.entries
        .associateWith { ProviderUsageState(it, false) },
    val cursorRenewsAtEpochMs: Long? = null,
    val cursorPlanName: String? = null,
    val claudePlanLabel: String? = null,
)

@Serializable
internal data class WidgetSnapshotPayload(
    val generatedAtEpochMs: Long = 0L,
    val providers: Map<String, WidgetProviderSnapshot> = emptyMap(),
    val cursorRenewsAtEpochMs: Long? = null,
    val cursorPlanName: String? = null,
    val claudePlanLabel: String? = null,
)

@Serializable
internal data class WidgetProviderSnapshot(
    val isConfigured: Boolean = false,
    val error: String? = null,
    val updatedAtEpochMs: Long? = null,
    val metrics: List<WidgetMetricSnapshot> = emptyList(),
)

@Serializable
internal data class WidgetMetricSnapshot(
    val id: String,
    val label: String,
    val percentUsed: Double? = null,
    val resetsAtEpochMs: Long? = null,
    val resetIntervalMs: Long? = null,
    val detail: String? = null,
    val countValue: Int? = null,
)

internal fun widgetSnapshotPayload(snapshot: AppUsageSnapshot): WidgetSnapshotPayload {
    val planInfo = snapshot.cursorPlanInfo?.planInfo
    val renewsAt = planInfo?.billingCycleEnd?.toDoubleOrNull()?.toLong()
    return WidgetSnapshotPayload(
        generatedAtEpochMs = snapshot.generatedAtEpochMs,
        providers = UsageProvider.entries.associate { provider ->
            val state = snapshot.providers[provider] ?: ProviderUsageState(provider, false)
            provider.name to WidgetProviderSnapshot(
                isConfigured = state.isConfigured,
                error = state.error,
                updatedAtEpochMs = state.updatedAtEpochMs,
                metrics = state.metrics.map {
                    WidgetMetricSnapshot(
                        id = it.id,
                        label = it.label,
                        percentUsed = it.percentUsed,
                        resetsAtEpochMs = it.resetsAtEpochMs,
                        resetIntervalMs = it.resetIntervalMs,
                        detail = it.detail,
                        countValue = it.countValue,
                    )
                },
            )
        },
        cursorRenewsAtEpochMs = renewsAt,
        cursorPlanName = planInfo?.planName?.takeIf { it.isNotBlank() },
        claudePlanLabel = snapshot.claudeProfile?.planLabel?.takeIf { it.isNotBlank() },
    )
}

internal fun loadedWidgetSnapshot(payload: WidgetSnapshotPayload): LoadedWidgetSnapshot {
    val providers = UsageProvider.entries.associateWith { provider ->
        val entry = payload.providers[provider.name]
        if (entry == null) {
            ProviderUsageState(provider, false)
        } else {
            ProviderUsageState(
                provider = provider,
                isConfigured = entry.isConfigured,
                error = entry.error,
                updatedAtEpochMs = entry.updatedAtEpochMs,
                metrics = entry.metrics.map {
                    UsageMetric(
                        id = it.id,
                        label = it.label,
                        percentUsed = it.percentUsed,
                        resetsAtEpochMs = it.resetsAtEpochMs,
                        resetIntervalMs = it.resetIntervalMs,
                        detail = it.detail,
                        countValue = it.countValue,
                    )
                },
            )
        }
    }
    return LoadedWidgetSnapshot(
        providers = providers,
        cursorRenewsAtEpochMs = payload.cursorRenewsAtEpochMs,
        cursorPlanName = payload.cursorPlanName,
        claudePlanLabel = payload.claudePlanLabel,
    )
}

/** JSON round-trip for unit tests; same [widgetSnapshotJson] as prefs. */
internal fun encodeWidgetSnapshotPayload(payload: WidgetSnapshotPayload): String =
    widgetSnapshotJson.encodeToString(payload)

internal fun decodeWidgetSnapshotPayload(raw: String): WidgetSnapshotPayload =
    widgetSnapshotJson.decodeFromString(raw)

/**
 * Cursor plan headline: "Pro · $20/mo · renews in 12d".
 * Null when every part is absent.
 */
internal fun formatCursorPlanRow(
    planName: String?,
    price: String?,
    renewsAtEpochMs: Long?,
    nowMs: Long = System.currentTimeMillis(),
): String? {
    val parts = listOfNotNull(
        planName?.takeIf { it.isNotBlank() },
        price?.takeIf { it.isNotBlank() },
        renewsAtEpochMs?.let { formatRenewsIn(it, nowMs) },
    )
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

/**
 * Spend line from included allotment and total percent (planUsage lives only as
 * percent on the CURSOR_TOTAL metric; raw cents are not on AppUsageSnapshot).
 */
internal fun formatCursorSpendRow(
    percentUsed: Double?,
    includedAmountCents: Int?,
): String? {
    val cents = includedAmountCents ?: return null
    if (cents < 0) return null
    val percent = percentUsed ?: return null
    val limitDollars = cents / 100.0
    val usedDollars = limitDollars * (percent / 100.0)
    return "used $%.2f of $%.2f".format(Locale.US, usedDollars, limitDollars)
}

/** Claude tier line: "Max 20x · active". Null when both parts are absent. */
internal fun formatClaudePlanRow(
    planLabel: String?,
    subscriptionStatus: String?,
): String? {
    val parts = listOfNotNull(
        planLabel?.takeIf { it.isNotBlank() },
        subscriptionStatus?.takeIf { it.isNotBlank() },
    )
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

/** Provider Usage widget caption: "renews in 12d". */
internal fun formatRenewsIn(
    renewsAtEpochMs: Long,
    nowMs: Long = System.currentTimeMillis(),
): String {
    val delta = renewsAtEpochMs - nowMs
    val abs = kotlin.math.abs(delta)
    val value = when {
        abs < java.util.concurrent.TimeUnit.MINUTES.toMillis(1) -> "moments"
        abs < java.util.concurrent.TimeUnit.HOURS.toMillis(1) ->
            "${java.util.concurrent.TimeUnit.MILLISECONDS.toMinutes(abs)}m"
        abs < java.util.concurrent.TimeUnit.DAYS.toMillis(1) ->
            "${java.util.concurrent.TimeUnit.MILLISECONDS.toHours(abs)}h"
        else -> "${java.util.concurrent.TimeUnit.MILLISECONDS.toDays(abs)}d"
    }
    return if (delta >= 0) "renews in $value" else "renewed $value ago"
}

internal fun cursorTotalPercent(state: ProviderUsageState?): Double? {
    if (state == null) return null
    return state.metrics
        .firstOrNull { it.id == UsageMetricPreferences.CURSOR_TOTAL }
        ?.percentUsed
}
