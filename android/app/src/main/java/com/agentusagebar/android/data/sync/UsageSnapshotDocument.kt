package com.agentusagebar.android.data.sync

import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.ClaudeProfileOrganization
import com.agentusagebar.android.data.model.ClaudeProfileResponse
import com.agentusagebar.android.data.model.CursorPlanInfo
import com.agentusagebar.android.data.model.CursorPlanInfoResponse
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.SnapshotCreditItem
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.format.DateTimeFormatter

@Serializable
data class UsageSnapshotDocument(
    val version: Int = 3,
    val generatedAt: String,
    val preferences: UsageSnapshotPreferencesDocument? = null,
    val providers: Map<String, UsageSnapshotProviderDocument> = emptyMap(),
)

@Serializable
data class UsageSnapshotPreferencesDocument(
    val preferredProvider: String? = null,
    val detailStyle: String? = null,
)

@Serializable
data class UsageSnapshotProviderDocument(
    val updatedAt: String,
    val error: String? = null,
    val plan: UsageSnapshotPlanDocument? = null,
    val credits: UsageSnapshotCreditsDocument? = null,
    val metrics: List<UsageSnapshotMetricDocument> = emptyList(),
)

@Serializable
data class UsageSnapshotPlanDocument(
    val label: String? = null,
    val priceText: String? = null,
    val renewsAt: String? = null,
    val includedAmountCents: Int? = null,
    val status: String? = null,
)

@Serializable
data class UsageSnapshotCreditsDocument(
    val available: Int,
    val items: List<UsageSnapshotCreditItemDocument> = emptyList(),
)

@Serializable
data class UsageSnapshotCreditItemDocument(
    val id: String,
    val expiresAt: String? = null,
)

@Serializable
data class UsageSnapshotMetricDocument(
    val id: String,
    val label: String,
    val shortLabel: String? = null,
    val percentUsed: Double? = null,
    val count: Int? = null,
    val valueText: String? = null,
    val resetsAt: String? = null,
    val resetInterval: Double? = null,
)

@Serializable
data class DeviceRedeemRequest(
    val creditId: String,
    val requestedAtEpochSeconds: Long,
)

@Serializable
data class DeviceRedeemResult(
    val outcome: String? = null,
    val message: String? = null,
    val error: String? = null,
)

fun UsageSnapshotDocument.toAppUsageSnapshot(
    desktopName: String?,
    pairedDesktopCount: Int,
    lastSuccessfulPullEpochMs: Long?,
    macUnreachable: Boolean = false,
): AppUsageSnapshot {
    val providers = UsageProvider.entries.associateWith { provider ->
        val entry = this.providers[provider.snapshotKey]
        if (entry == null) {
            ProviderUsageState(provider = provider, isConfigured = false)
        } else {
            ProviderUsageState(
                provider = provider,
                isConfigured = true,
                metrics = entry.metrics.map { it.toUsageMetric(provider) },
                error = entry.error,
                updatedAtEpochMs = parseIsoToEpochMs(entry.updatedAt),
            )
        }
    }
    val claudePlan = this.providers[UsageProvider.CLAUDE.snapshotKey]?.plan
    val cursorPlan = this.providers[UsageProvider.CURSOR.snapshotKey]?.plan
    val openAI = this.providers[UsageProvider.OPENAI.snapshotKey]
    val credits = openAI?.credits
    return AppUsageSnapshot(
        generatedAtEpochMs = parseIsoToEpochMs(generatedAt) ?: 0L,
        providers = providers,
        claudeProfile = claudePlan?.toClaudeProfile(),
        cursorPlanInfo = cursorPlan?.toCursorPlanInfo(),
        openAIPlanType = openAI?.plan?.label?.takeIf { it.isNotBlank() },
        openAICreditsAvailable = credits?.available ?: 0,
        openAICreditItems = credits?.items.orEmpty().map {
            SnapshotCreditItem(
                id = it.id,
                expiresAtEpochMs = parseIsoToEpochMs(it.expiresAt),
            )
        },
        sourceDesktopName = desktopName,
        pairedDesktopCount = pairedDesktopCount,
        lastSuccessfulPullEpochMs = lastSuccessfulPullEpochMs,
        macUnreachable = macUnreachable,
    )
}

fun emptyAppUsageSnapshot(
    pairedDesktopCount: Int = 0,
    lastSuccessfulPullEpochMs: Long? = null,
    macUnreachable: Boolean = false,
    sourceDesktopName: String? = null,
): AppUsageSnapshot = AppUsageSnapshot(
    providers = UsageProvider.entries.associateWith {
        ProviderUsageState(provider = it, isConfigured = false)
    },
    pairedDesktopCount = pairedDesktopCount,
    lastSuccessfulPullEpochMs = lastSuccessfulPullEpochMs,
    macUnreachable = macUnreachable,
    sourceDesktopName = sourceDesktopName,
)

val UsageProvider.snapshotKey: String
    get() = when (this) {
        UsageProvider.CLAUDE -> "claude"
        UsageProvider.OPENAI -> "openai"
        UsageProvider.CURSOR -> "cursor"
        UsageProvider.ELEVENLABS -> "elevenlabs"
    }

internal fun UsageSnapshotMetricDocument.toUsageMetric(provider: UsageProvider): UsageMetric =
    UsageMetric(
        id = mapSnapshotMetricId(provider, id),
        label = label,
        percentUsed = percentUsed,
        resetsAtEpochMs = parseIsoToEpochMs(resetsAt),
        resetIntervalMs = resetInterval?.let { (it * 1_000.0).toLong() },
        detail = valueText,
        countValue = count,
    )

internal fun mapSnapshotMetricId(provider: UsageProvider, snapshotId: String): String {
    if (snapshotId.startsWith("limit.")) {
        return "claude.limit.${snapshotId.removePrefix("limit.")}"
    }
    return when (provider to snapshotId) {
        UsageProvider.CLAUDE to "five_hour" -> UsageMetricPreferences.CLAUDE_FIVE_HOUR
        UsageProvider.CLAUDE to "seven_day" -> UsageMetricPreferences.CLAUDE_SEVEN_DAY
        UsageProvider.CLAUDE to "seven_day_opus" -> UsageMetricPreferences.CLAUDE_OPUS
        UsageProvider.CLAUDE to "seven_day_sonnet" -> UsageMetricPreferences.CLAUDE_SONNET
        UsageProvider.CLAUDE to "extra_usage" -> UsageMetricPreferences.CLAUDE_EXTRA
        UsageProvider.OPENAI to "primary" -> UsageMetricPreferences.OPENAI_PRIMARY
        UsageProvider.OPENAI to "secondary" -> UsageMetricPreferences.OPENAI_SECONDARY
        UsageProvider.OPENAI to "reset_credits" -> UsageMetricPreferences.OPENAI_RESET_CREDITS
        UsageProvider.CURSOR to "models" -> UsageMetricPreferences.CURSOR_MODELS
        UsageProvider.CURSOR to "api" -> UsageMetricPreferences.CURSOR_API
        UsageProvider.CURSOR to "total" -> UsageMetricPreferences.CURSOR_TOTAL
        UsageProvider.ELEVENLABS to "credits" -> UsageMetricPreferences.ELEVENLABS_CREDITS
        UsageProvider.ELEVENLABS to "remaining" -> UsageMetricPreferences.ELEVENLABS_REMAINING
        else -> snapshotId
    }
}

internal fun parseIsoToEpochMs(value: String?): Long? {
    if (value.isNullOrBlank()) return null
    return runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
        ?: runCatching {
            DateTimeFormatter.ISO_DATE_TIME.parse(value, Instant::from).toEpochMilli()
        }.getOrNull()
}

private fun UsageSnapshotPlanDocument.toClaudeProfile(): ClaudeProfileResponse? {
    val label = this.label?.takeIf { it.isNotBlank() }
    val status = this.status?.takeIf { it.isNotBlank() }
    if (label == null && status == null) return null
    return ClaudeProfileResponse(
        organization = ClaudeProfileOrganization(
            organizationType = label,
            subscriptionStatus = status,
        ),
    )
}

private fun UsageSnapshotPlanDocument.toCursorPlanInfo(): CursorPlanInfoResponse? {
    val name = label?.takeIf { it.isNotBlank() }
    val price = priceText?.takeIf { it.isNotBlank() }
    val renewsAtMs = parseIsoToEpochMs(renewsAt)
    if (name == null && price == null && renewsAtMs == null && includedAmountCents == null) {
        return null
    }
    return CursorPlanInfoResponse(
        planInfo = CursorPlanInfo(
            planName = name,
            includedAmountCents = includedAmountCents,
            price = price,
            billingCycleEnd = renewsAtMs?.toString(),
        ),
    )
}
