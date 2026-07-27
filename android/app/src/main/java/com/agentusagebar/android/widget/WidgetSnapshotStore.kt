package com.agentusagebar.android.widget

import android.content.Context
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageProvider
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Widgets run in a separate process lifecycle from the UI. Persist the last
 * usage snapshot so Glance can render Cursor/ElevenLabs even when the activity
 * process is not warm.
 */
object WidgetSnapshotStore {
    private const val PREFS = "agent_usage_bar_widget_snapshot"
    private const val KEY = "snapshot_json"

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun save(context: Context, snapshot: AppUsageSnapshot) {
        val payload = WidgetSnapshot(
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
        )
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, json.encodeToString(payload))
            .apply()
    }

    fun load(context: Context): Map<UsageProvider, ProviderUsageState> {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)
            ?: return UsageProvider.entries.associateWith { ProviderUsageState(it, false) }

        val payload = runCatching { json.decodeFromString<WidgetSnapshot>(raw) }.getOrNull()
            ?: return UsageProvider.entries.associateWith { ProviderUsageState(it, false) }

        return UsageProvider.entries.associateWith { provider ->
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
    }
}

@Serializable
private data class WidgetSnapshot(
    val generatedAtEpochMs: Long = 0L,
    val providers: Map<String, WidgetProviderSnapshot> = emptyMap(),
)

@Serializable
private data class WidgetProviderSnapshot(
    val isConfigured: Boolean = false,
    val error: String? = null,
    val updatedAtEpochMs: Long? = null,
    val metrics: List<WidgetMetricSnapshot> = emptyList(),
)

@Serializable
private data class WidgetMetricSnapshot(
    val id: String,
    val label: String,
    val percentUsed: Double? = null,
    val resetsAtEpochMs: Long? = null,
    val resetIntervalMs: Long? = null,
    val detail: String? = null,
    val countValue: Int? = null,
)
