package com.agentusagebar.android.data.repository

import android.content.Context
import com.agentusagebar.android.data.credentials.CredentialsStore
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.credentials.TokenNormalizer
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.ClaudeUsageResponse
import com.agentusagebar.android.data.model.CursorUsageResponse
import com.agentusagebar.android.data.model.ElevenLabsSubscriptionResponse
import com.agentusagebar.android.data.model.OpenAIUsageResponse
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.network.UsageApiClient
import com.agentusagebar.android.widget.WidgetSnapshotStore
import com.agentusagebar.android.widget.WidgetUpdater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.format.DateTimeFormatter

class UsageRepository(
    context: Context,
    private val credentialsStore: CredentialsStore = CredentialsStore(context),
    private val settingsStore: SettingsStore = SettingsStore(context),
    private val api: UsageApiClient = UsageApiClient(credentialsStore),
) {
    private val appContext = context.applicationContext

    private val _snapshot = MutableStateFlow(
        AppUsageSnapshot(
            providers = mapOf(
                UsageProvider.CLAUDE to ProviderUsageState(
                    provider = UsageProvider.CLAUDE,
                    isConfigured = api.isClaudeConfigured(),
                ),
                UsageProvider.OPENAI to ProviderUsageState(
                    provider = UsageProvider.OPENAI,
                    isConfigured = api.isOpenAIConfigured(),
                ),
                UsageProvider.CURSOR to ProviderUsageState(
                    provider = UsageProvider.CURSOR,
                    isConfigured = api.isCursorConfigured(),
                ),
                UsageProvider.ELEVENLABS to ProviderUsageState(
                    provider = UsageProvider.ELEVENLABS,
                    isConfigured = api.isElevenLabsConfigured(),
                ),
            ),
        ),
    )
    val snapshot: StateFlow<AppUsageSnapshot> = _snapshot.asStateFlow()

    private val _claudeEmail = MutableStateFlow<String?>(null)
    val claudeEmail: StateFlow<String?> = _claudeEmail.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _awaitingClaudeCode = MutableStateFlow(false)
    val awaitingClaudeCode: StateFlow<Boolean> = _awaitingClaudeCode.asStateFlow()

    val settings = settingsStore.settings

    fun startClaudeOAuth(): String {
        val url = api.startClaudeOAuthUrl()
        _awaitingClaudeCode.value = true
        return url
    }

    fun cancelClaudeOAuth() {
        _awaitingClaudeCode.value = false
    }

    suspend fun submitClaudeCode(rawCode: String): Result<Unit> = withContext(Dispatchers.IO) {
        api.exchangeClaudeCode(rawCode).onSuccess {
            _awaitingClaudeCode.value = false
            refreshConfiguredFlags()
            refreshAll()
            _claudeEmail.value = api.fetchClaudeProfileEmail()
        }
    }

    suspend fun signOutClaude() = withContext(Dispatchers.IO) {
        api.signOutClaude()
        _claudeEmail.value = null
        refreshConfiguredFlags()
        publishWidgets()
    }

    suspend fun saveOpenAIToken(raw: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val token = TokenNormalizer.openAI(raw) ?: error("Token is empty")
            val current = credentialsStore.loadConnected()
            credentialsStore.saveConnected(current.copy(openAISessionToken = token))
            refreshConfiguredFlags()
            refreshAll()
        }
    }

    suspend fun saveCursorToken(raw: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val token = TokenNormalizer.cursor(raw) ?: error("Token is empty")
            val current = credentialsStore.loadConnected()
            credentialsStore.saveConnected(current.copy(cursorSessionToken = token))
            refreshConfiguredFlags()
            refreshAll()
        }
    }

    suspend fun clearOpenAIToken() = withContext(Dispatchers.IO) {
        val current = credentialsStore.loadConnected()
        credentialsStore.saveConnected(current.copy(openAISessionToken = null))
        refreshConfiguredFlags()
        publishWidgets()
    }

    suspend fun clearCursorToken() = withContext(Dispatchers.IO) {
        val current = credentialsStore.loadConnected()
        credentialsStore.saveConnected(current.copy(cursorSessionToken = null))
        refreshConfiguredFlags()
        publishWidgets()
    }

    suspend fun saveElevenLabsAPIKey(raw: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val key = TokenNormalizer.elevenLabs(raw) ?: error("API key is empty")
            val current = credentialsStore.loadConnected()
            credentialsStore.saveConnected(current.copy(elevenLabsAPIKey = key))
            refreshConfiguredFlags()
            refreshAll()
        }
    }

    suspend fun clearElevenLabsAPIKey() = withContext(Dispatchers.IO) {
        val current = credentialsStore.loadConnected()
        credentialsStore.saveConnected(current.copy(elevenLabsAPIKey = null))
        refreshConfiguredFlags()
        publishWidgets()
    }

    suspend fun setPollingMinutes(minutes: Int) = settingsStore.setPollingMinutes(minutes)
    suspend fun setSetupComplete(complete: Boolean) = settingsStore.setSetupComplete(complete)
    suspend fun setWidgetProvider(provider: UsageProvider) {
        settingsStore.setWidgetProvider(provider)
        publishWidgets()
    }

    suspend fun setDetailStyle(style: com.agentusagebar.android.data.model.DetailVisualizationStyle) =
        settingsStore.setDetailStyle(style)

    suspend fun setTextSize(size: com.agentusagebar.android.data.model.UsageTextSize) =
        settingsStore.setTextSize(size)

    suspend fun setClaudeSessionThreshold(value: Int) = settingsStore.setClaudeSessionThreshold(value)
    suspend fun setClaudeSevenDayThreshold(value: Int) = settingsStore.setClaudeSevenDayThreshold(value)
    suspend fun setClaudeFableThreshold(value: Int) = settingsStore.setClaudeFableThreshold(value)
    suspend fun setOpenAIWeeklyThreshold(value: Int) = settingsStore.setOpenAIWeeklyThreshold(value)
    suspend fun setOpenAIResetCreditsThreshold(value: Int) = settingsStore.setOpenAIResetCreditsThreshold(value)
    suspend fun setCursorAPIThreshold(value: Int) = settingsStore.setCursorAPIThreshold(value)
    suspend fun setCursorAutoThreshold(value: Int) = settingsStore.setCursorAutoThreshold(value)
    suspend fun setCursorCreditThreshold(value: Int) = settingsStore.setCursorCreditThreshold(value)

    suspend fun refreshAll() = withContext(Dispatchers.IO) {
        _isRefreshing.value = true
        try {
            coroutineScope {
                val claude = async { refreshClaude() }
                val openAI = async { refreshOpenAI() }
                val cursor = async { refreshCursor() }
                val eleven = async { refreshElevenLabs() }
                claude.await()
                openAI.await()
                cursor.await()
                eleven.await()
            }
            _snapshot.update { it.copy(generatedAtEpochMs = System.currentTimeMillis()) }
            publishWidgets()
        } finally {
            _isRefreshing.value = false
        }
    }

    private fun refreshClaude() {
        if (!api.isClaudeConfigured()) {
            updateProvider(
                ProviderUsageState(
                    provider = UsageProvider.CLAUDE,
                    isConfigured = false,
                ),
            )
            return
        }
        api.fetchClaudeUsage()
            .onSuccess { usage ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.CLAUDE,
                        isConfigured = true,
                        metrics = claudeMetrics(usage),
                        updatedAtEpochMs = System.currentTimeMillis(),
                    ),
                )
            }
            .onFailure { error ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.CLAUDE,
                        isConfigured = api.isClaudeConfigured(),
                        metrics = _snapshot.value.providers[UsageProvider.CLAUDE]?.metrics.orEmpty(),
                        error = error.message,
                        updatedAtEpochMs = _snapshot.value.providers[UsageProvider.CLAUDE]?.updatedAtEpochMs,
                    ),
                )
            }
    }

    private fun refreshOpenAI() {
        if (!api.isOpenAIConfigured()) {
            updateProvider(
                ProviderUsageState(
                    provider = UsageProvider.OPENAI,
                    isConfigured = false,
                ),
            )
            return
        }
        api.fetchOpenAIUsage()
            .onSuccess { usage ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.OPENAI,
                        isConfigured = true,
                        metrics = openAIMetrics(usage),
                        updatedAtEpochMs = System.currentTimeMillis(),
                    ),
                )
            }
            .onFailure { error ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.OPENAI,
                        isConfigured = true,
                        metrics = _snapshot.value.providers[UsageProvider.OPENAI]?.metrics.orEmpty(),
                        error = error.message,
                        updatedAtEpochMs = _snapshot.value.providers[UsageProvider.OPENAI]?.updatedAtEpochMs,
                    ),
                )
            }
    }

    private fun refreshCursor() {
        if (!api.isCursorConfigured()) {
            updateProvider(
                ProviderUsageState(
                    provider = UsageProvider.CURSOR,
                    isConfigured = false,
                ),
            )
            return
        }
        api.fetchCursorUsage()
            .onSuccess { usage ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.CURSOR,
                        isConfigured = true,
                        metrics = cursorMetrics(usage),
                        updatedAtEpochMs = System.currentTimeMillis(),
                    ),
                )
            }
            .onFailure { error ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.CURSOR,
                        isConfigured = true,
                        metrics = _snapshot.value.providers[UsageProvider.CURSOR]?.metrics.orEmpty(),
                        error = error.message,
                        updatedAtEpochMs = _snapshot.value.providers[UsageProvider.CURSOR]?.updatedAtEpochMs,
                    ),
                )
            }
    }

    private fun refreshElevenLabs() {
        if (!api.isElevenLabsConfigured()) {
            updateProvider(
                ProviderUsageState(
                    provider = UsageProvider.ELEVENLABS,
                    isConfigured = false,
                ),
            )
            return
        }
        api.fetchElevenLabsUsage()
            .onSuccess { usage ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.ELEVENLABS,
                        isConfigured = true,
                        metrics = elevenLabsMetrics(usage),
                        updatedAtEpochMs = System.currentTimeMillis(),
                    ),
                )
            }
            .onFailure { error ->
                updateProvider(
                    ProviderUsageState(
                        provider = UsageProvider.ELEVENLABS,
                        isConfigured = true,
                        metrics = _snapshot.value.providers[UsageProvider.ELEVENLABS]?.metrics.orEmpty(),
                        error = error.message,
                        updatedAtEpochMs = _snapshot.value.providers[UsageProvider.ELEVENLABS]?.updatedAtEpochMs,
                    ),
                )
            }
    }

    private fun refreshConfiguredFlags() {
        _snapshot.update { current ->
            current.copy(
                providers = current.providers.mapValues { (provider, state) ->
                    state.copy(
                        isConfigured = when (provider) {
                            UsageProvider.CLAUDE -> api.isClaudeConfigured()
                            UsageProvider.OPENAI -> api.isOpenAIConfigured()
                            UsageProvider.CURSOR -> api.isCursorConfigured()
                            UsageProvider.ELEVENLABS -> api.isElevenLabsConfigured()
                        },
                    )
                },
            )
        }
    }

    private fun updateProvider(state: ProviderUsageState) {
        _snapshot.update { current ->
            current.copy(
                providers = current.providers + (state.provider to state),
            )
        }
    }

    private fun publishWidgets() {
        WidgetSnapshotStore.save(appContext, _snapshot.value)
        WidgetUpdater.updateAll(appContext)
    }

    companion object {
        private val FIVE_HOURS_MS = 5L * 60 * 60 * 1000
        private val SEVEN_DAYS_MS = 7L * 24 * 60 * 60 * 1000
        private val THIRTY_DAYS_MS = 30L * 24 * 60 * 60 * 1000

        fun claudeMetrics(usage: ClaudeUsageResponse): List<UsageMetric> {
            val metrics = mutableListOf<UsageMetric>()
            metrics += UsageMetric(
                id = "five_hour",
                label = "5-Hour Window",
                percentUsed = usage.fiveHour?.utilization,
                resetsAtEpochMs = parseIso(usage.fiveHour?.resetsAt),
                resetIntervalMs = FIVE_HOURS_MS,
            )
            metrics += UsageMetric(
                id = "seven_day",
                label = "7-Day Window",
                percentUsed = usage.sevenDay?.utilization,
                resetsAtEpochMs = parseIso(usage.sevenDay?.resetsAt),
                resetIntervalMs = SEVEN_DAYS_MS,
            )
            usage.sevenDayOpus?.utilization?.let {
                metrics += UsageMetric(
                    id = "seven_day_opus",
                    label = "Opus (7 day)",
                    percentUsed = it,
                    resetsAtEpochMs = parseIso(usage.sevenDayOpus.resetsAt),
                    resetIntervalMs = SEVEN_DAYS_MS,
                )
            }
            usage.sevenDaySonnet?.utilization?.let {
                metrics += UsageMetric(
                    id = "seven_day_sonnet",
                    label = "Sonnet (7 day)",
                    percentUsed = it,
                    resetsAtEpochMs = parseIso(usage.sevenDaySonnet.resetsAt),
                    resetIntervalMs = SEVEN_DAYS_MS,
                )
            }
            usage.limits.orEmpty()
                .filter { !it.scope?.model?.displayName.isNullOrBlank() }
                .forEach { limit ->
                    val model = limit.scope?.model?.displayName ?: "Model"
                    val label = when (limit.group) {
                        "weekly" -> "$model (7 day)"
                        "session" -> "$model (session)"
                        null -> model
                        else -> "$model (${limit.group.replace('_', ' ')})"
                    }
                    val interval = when (limit.group) {
                        "weekly" -> SEVEN_DAYS_MS
                        "session" -> FIVE_HOURS_MS
                        else -> null
                    }
                    metrics += UsageMetric(
                        id = "limit_${limit.kind}_$model",
                        label = label,
                        percentUsed = limit.percent,
                        resetsAtEpochMs = parseIso(limit.resetsAt),
                        resetIntervalMs = interval,
                    )
                }
            val extra = usage.extraUsage
            if (extra != null && (extra.usedCredits != null || extra.monthlyLimit != null)) {
                val used = extra.usedCreditsAmount
                val limit = extra.monthlyLimitAmount
                metrics += UsageMetric(
                    id = "extra_usage",
                    label = "Extra Usage",
                    percentUsed = extra.utilization,
                    detail = if (used != null && limit != null) {
                        "$%.2f / $%.2f".format(used, limit)
                    } else {
                        null
                    },
                )
            }
            return metrics
        }

        fun openAIMetrics(usage: OpenAIUsageResponse): List<UsageMetric> {
            val metrics = mutableListOf<UsageMetric>()
            val primary = usage.rateLimit?.primaryWindow
            metrics += UsageMetric(
                id = "primary",
                label = windowLabel(primary?.limitWindowSeconds, "Primary Window"),
                percentUsed = primary?.usedPercent,
                resetsAtEpochMs = primary?.resetAt?.times(1000)?.toLong(),
                resetIntervalMs = primary?.limitWindowSeconds?.times(1000)?.toLong(),
            )
            usage.rateLimit?.secondaryWindow?.let { secondary ->
                metrics += UsageMetric(
                    id = "secondary",
                    label = windowLabel(secondary.limitWindowSeconds, "Secondary Window"),
                    percentUsed = secondary.usedPercent,
                    resetsAtEpochMs = secondary.resetAt?.times(1000)?.toLong(),
                    resetIntervalMs = secondary.limitWindowSeconds?.times(1000)?.toLong(),
                )
            }
            usage.additionalRateLimits.orEmpty().forEach { additional ->
                val window = additional.rateLimit?.primaryWindow ?: return@forEach
                metrics += UsageMetric(
                    id = "additional_${additional.type ?: additional.label}",
                    label = additional.label ?: additional.type ?: "Additional Limit",
                    percentUsed = window.usedPercent,
                    resetsAtEpochMs = window.resetAt?.times(1000)?.toLong(),
                    resetIntervalMs = window.limitWindowSeconds?.times(1000)?.toLong(),
                )
            }
            return metrics
        }

        fun cursorMetrics(usage: CursorUsageResponse): List<UsageMetric> {
            val resetAt = usage.billingCycleEnd?.toDoubleOrNull()?.toLong()
            val metrics = mutableListOf(
                UsageMetric(
                    id = "models",
                    label = "First-Party Models",
                    percentUsed = usage.planUsage?.autoPercentUsed,
                    resetsAtEpochMs = resetAt,
                    resetIntervalMs = THIRTY_DAYS_MS,
                ),
                UsageMetric(
                    id = "api",
                    label = "API",
                    percentUsed = usage.planUsage?.apiPercentUsed,
                    resetsAtEpochMs = resetAt,
                    resetIntervalMs = THIRTY_DAYS_MS,
                ),
            )
            val spend = usage.spendLimitUsage
            if (spend?.spent != null && spend.individualLimit != null) {
                metrics += UsageMetric(
                    id = "on_demand",
                    label = "On-Demand",
                    percentUsed = spend.utilization,
                    resetsAtEpochMs = resetAt,
                    resetIntervalMs = THIRTY_DAYS_MS,
                    detail = "%s / %s".format(
                        formatUsd(spend.spent!! / 100.0),
                        formatUsd(spend.individualLimit!! / 100.0),
                    ),
                )
            }
            return metrics
        }

        fun compactWindowLabel(seconds: Double?, fallback: String): String {
            if (seconds == null) return fallback
            val hours = (seconds / 3600).toInt()
            return when {
                hours > 0 && hours % 24 == 0 -> "${hours / 24}d"
                hours > 0 -> "${hours}h"
                else -> fallback
            }
        }

        private fun windowLabel(seconds: Double?, fallback: String): String {
            if (seconds == null) return fallback
            val hours = (seconds / 3600).toInt()
            return when {
                hours > 0 && hours % 24 == 0 -> "${hours / 24}-Day Window"
                hours > 0 -> "$hours-Hour Window"
                else -> fallback
            }
        }

        private fun parseIso(value: String?): Long? {
            if (value.isNullOrBlank()) return null
            return runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
                ?: runCatching {
                    DateTimeFormatter.ISO_DATE_TIME.parse(value, Instant::from).toEpochMilli()
                }.getOrNull()
        }

        private fun formatUsd(amount: Double): String = "$%.2f".format(amount)

        fun elevenLabsMetrics(usage: ElevenLabsSubscriptionResponse): List<UsageMetric> {
            return listOf(
                UsageMetric(
                    id = "credits",
                    label = "Credits Used",
                    percentUsed = usage.utilization,
                    resetsAtEpochMs = usage.nextCharacterCountResetUnix?.times(1000)?.toLong(),
                    resetIntervalMs = billingIntervalMs(usage.characterRefreshPeriod),
                ),
                UsageMetric(
                    id = "remaining",
                    label = "Credits Remaining",
                    countValue = usage.creditsRemaining,
                    detail = usage.characterLimit?.let { limit ->
                        val used = usage.characterCount ?: 0
                        "%,d / %,d".format(used, limit)
                    },
                ),
            )
        }

        private fun billingIntervalMs(period: String?): Long? = when (period) {
            "daily_period" -> 24L * 60 * 60 * 1000
            "weekly_period" -> SEVEN_DAYS_MS
            "monthly_period" -> THIRTY_DAYS_MS
            "annual_period", "yearly_period" -> 365L * 24 * 60 * 60 * 1000
            else -> null
        }

    }
}
