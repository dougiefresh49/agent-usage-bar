package com.agentusagebar.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CursorPlanInfoResponse(
    val planInfo: CursorPlanInfo? = null,
    val nextUpgrade: CursorPlanNextUpgrade? = null,
)

@Serializable
data class CursorPlanInfo(
    val planName: String? = null,
    val includedAmountCents: Int? = null,
    val price: String? = null,
    /** Epoch milliseconds as a string, matching the Connect-RPC payload. */
    val billingCycleEnd: String? = null,
    val planOwner: String? = null,
)

@Serializable
data class CursorPlanNextUpgrade(
    val tier: String? = null,
    val name: String? = null,
    val includedAmountCents: Int? = null,
    val price: String? = null,
    val description: String? = null,
)

@Serializable
data class ClaudeProfileResponse(
    val account: ClaudeProfileAccount? = null,
    val organization: ClaudeProfileOrganization? = null,
) {
    /**
     * Maps organization.rate_limit_tier to a short plan label.
     * Shared contract with macOS (#48) and tracking #58.
     */
    val planLabel: String
        get() {
            when (organization?.rateLimitTier) {
                "default_claude_max_20x" -> return "Max 20x"
                "default_claude_max_5x" -> return "Max 5x"
                "claude_pro" -> return "Pro"
            }
            if (account?.hasClaudePro == true && account.hasClaudeMax != true) {
                return "Pro"
            }
            val type = organization?.organizationType
            if (!type.isNullOrBlank()) {
                return type.split('_')
                    .filter { it.isNotBlank() }
                    .joinToString(" ") { part ->
                        part.replaceFirstChar { ch ->
                            if (ch.isLowerCase()) ch.titlecase() else ch.toString()
                        }
                    }
            }
            return when {
                account?.hasClaudeMax == true -> "Max"
                account?.hasClaudePro == true -> "Pro"
                else -> "Claude"
            }
        }
}

@Serializable
data class ClaudeProfileAccount(
    @SerialName("has_claude_max") val hasClaudeMax: Boolean? = null,
    @SerialName("has_claude_pro") val hasClaudePro: Boolean? = null,
)

@Serializable
data class ClaudeProfileOrganization(
    @SerialName("organization_type") val organizationType: String? = null,
    @SerialName("billing_type") val billingType: String? = null,
    /** Live JSON key is singular rate_limit_tier (verified 2026-09-09). */
    @SerialName("rate_limit_tier") val rateLimitTier: String? = null,
    @SerialName("subscription_status") val subscriptionStatus: String? = null,
    @SerialName("subscription_created_at") val subscriptionCreatedAt: String? = null,
    @SerialName("has_extra_usage_enabled") val hasExtraUsageEnabled: Boolean? = null,
)

enum class UsageProvider(
    val displayName: String,
    val shortName: String,
    val usagePageUrl: String,
) {
    CLAUDE("Claude", "Claude", "https://claude.ai/new#settings/usage"),
    OPENAI("OpenAI / Codex", "Codex", "https://chatgpt.com/#settings/Usage"),
    CURSOR("Cursor", "Cursor", "https://cursor.com/dashboard/spending"),
    ELEVENLABS("ElevenLabs", "11Labs", "https://elevenlabs.io/app/subscription/"),
}

enum class DetailVisualizationStyle(val displayName: String) {
    BARS("Bars"),
    CAPSULE("Capsule"),
    ORBIT("Orbit"),
}

enum class UsageTextSize(val displayName: String, val overviewColumns: Int) {
    COMPACT("Compact", 2),
    COMFORTABLE("Comfortable", 2),
    LARGE("Large", 2),
}

object UsageMetricPreferences {
    const val CLAUDE_FIVE_HOUR = "claude.5h"
    const val CLAUDE_SEVEN_DAY = "claude.7d"
    const val CLAUDE_OPUS = "claude.opus"
    const val CLAUDE_SONNET = "claude.sonnet"
    const val CLAUDE_EXTRA = "claude.extra"
    const val OPENAI_PRIMARY = "openai.primary"
    const val OPENAI_SECONDARY = "openai.secondary"
    const val OPENAI_RESET_CREDITS = "openai.resetCredits"
    const val CURSOR_MODELS = "cursor.models"
    const val CURSOR_API = "cursor.api"
    const val CURSOR_TOTAL = "cursor.total"
    const val ELEVENLABS_CREDITS = "elevenlabs.credits"
    const val ELEVENLABS_REMAINING = "elevenlabs.remaining"

    fun defaults(provider: UsageProvider): Pair<String, String> = when (provider) {
        UsageProvider.CLAUDE -> CLAUDE_FIVE_HOUR to CLAUDE_SEVEN_DAY
        UsageProvider.OPENAI -> OPENAI_PRIMARY to OPENAI_SECONDARY
        UsageProvider.CURSOR -> CURSOR_MODELS to CURSOR_API
        UsageProvider.ELEVENLABS -> ELEVENLABS_CREDITS to ELEVENLABS_REMAINING
    }

    fun options(
        provider: UsageProvider,
        available: List<UsageMetric>,
    ): List<UsageMetric> = available.ifEmpty {
        when (provider) {
            UsageProvider.CLAUDE -> listOf(
                UsageMetric(CLAUDE_FIVE_HOUR, "5-Hour Window"),
                UsageMetric(CLAUDE_SEVEN_DAY, "7-Day Window"),
            )
            UsageProvider.OPENAI -> listOf(
                UsageMetric(OPENAI_PRIMARY, "Primary Window"),
                UsageMetric(OPENAI_SECONDARY, "Secondary Window"),
                UsageMetric(OPENAI_RESET_CREDITS, "Reset Credits"),
            )
            UsageProvider.CURSOR -> listOf(
                UsageMetric(CURSOR_MODELS, "First-Party Models"),
                UsageMetric(CURSOR_API, "API"),
                UsageMetric(CURSOR_TOTAL, "Total Plan Usage"),
            )
            UsageProvider.ELEVENLABS -> listOf(
                UsageMetric(ELEVENLABS_CREDITS, "Credits Used"),
                UsageMetric(ELEVENLABS_REMAINING, "Credits Remaining"),
            )
        }
    }

    fun resolvedPair(
        provider: UsageProvider,
        primaryID: String,
        secondaryID: String,
        available: List<UsageMetric>,
    ): List<UsageMetric> {
        if (available.isEmpty()) return emptyList()
        val defaults = defaults(provider)
        val primary = available.firstOrNull { metricIdMatches(primaryID, it.id) }
            ?: available.firstOrNull { it.id == defaults.first }
            ?: available.first()
        val secondary = available.firstOrNull {
            metricIdMatches(secondaryID, it.id) && it.id != primary.id
        } ?: available.firstOrNull {
            it.id == defaults.second && it.id != primary.id
        } ?: available.firstOrNull { it.id != primary.id }
        return listOfNotNull(primary, secondary)
    }

    fun resolvedMetric(
        storedID: String,
        fallbackID: String,
        available: List<UsageMetric>,
    ): UsageMetric? {
        return available.firstOrNull { metricIdMatches(storedID, it.id) }
            ?: available.firstOrNull { it.id == fallbackID }
            ?: available.firstOrNull()
    }

    fun orderedMetrics(
        provider: UsageProvider,
        primaryID: String,
        secondaryID: String,
        available: List<UsageMetric>,
    ): List<UsageMetric> {
        val pair = resolvedPair(provider, primaryID, secondaryID, available)
        val selectedIDs = pair.mapTo(mutableSetOf()) { it.id }
        return pair + available.filterNot { it.id in selectedIDs }
    }

    /**
     * Stable id for Claude scoped model limits (e.g. Fable). Must not include
     * a reset timestamp — that changes every window and would make saved
     * primary/secondary preferences look like they reset to defaults.
     */
    fun claudeLimitMetricId(kind: String, modelDisplayName: String, group: String?): String {
        val safeGroup = group?.takeIf { it.isNotBlank() } ?: "ungrouped"
        return "claude.limit.$kind:$modelDisplayName:$safeGroup"
    }

    /**
     * Match stored preference ids to live metrics. Legacy Claude limit ids appended
     * `resetsAt` as the final segment; treat kind+model as the stable identity.
     */
    fun metricIdMatches(storedID: String, metricID: String): Boolean {
        if (storedID.isBlank()) return false
        if (storedID == metricID) return true
        val prefix = "claude.limit."
        if (!storedID.startsWith(prefix) || !metricID.startsWith(prefix)) return false
        val storedParts = storedID.removePrefix(prefix).split(':')
        val metricParts = metricID.removePrefix(prefix).split(':')
        return storedParts.size >= 2 &&
            metricParts.size >= 2 &&
            storedParts[0] == metricParts[0] &&
            storedParts[1] == metricParts[1]
    }
}

data class UsageMetric(
    val id: String,
    val label: String,
    val percentUsed: Double? = null,
    val resetsAtEpochMs: Long? = null,
    /** Window length in ms; used for orbit center countdown drain fill. */
    val resetIntervalMs: Long? = null,
    val detail: String? = null,
    val countValue: Int? = null,
) {
    val displayValue: String
        get() = when {
            percentUsed != null -> "${kotlin.math.round(percentUsed).toInt()}%"
            countValue != null -> "%,d".format(countValue)
            else -> "—"
        }
}

data class ProviderUsageState(
    val provider: UsageProvider,
    val isConfigured: Boolean,
    val metrics: List<UsageMetric> = emptyList(),
    val error: String? = null,
    val updatedAtEpochMs: Long? = null,
)

data class SnapshotCreditItem(
    val id: String,
    val expiresAtEpochMs: Long? = null,
)

data class AppUsageSnapshot(
    val generatedAtEpochMs: Long = 0L,
    val providers: Map<UsageProvider, ProviderUsageState> = emptyMap(),
    val claudeProfile: ClaudeProfileResponse? = null,
    val cursorPlanInfo: CursorPlanInfoResponse? = null,
    /** Codex plan type from the Mac snapshot; null when absent or not configured. */
    val openAIPlanType: String? = null,
    val openAICreditsAvailable: Int = 0,
    val openAICreditItems: List<SnapshotCreditItem> = emptyList(),
    val sourceDesktopName: String? = null,
    val pairedDesktopCount: Int = 0,
    val lastSuccessfulPullEpochMs: Long? = null,
    val macUnreachable: Boolean = false,
)
