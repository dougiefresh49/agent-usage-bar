package com.agentusagebar.android.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ClaudeUsageResponse(
    @SerialName("five_hour") val fiveHour: UsageBucket? = null,
    @SerialName("seven_day") val sevenDay: UsageBucket? = null,
    @SerialName("seven_day_opus") val sevenDayOpus: UsageBucket? = null,
    @SerialName("seven_day_sonnet") val sevenDaySonnet: UsageBucket? = null,
    @SerialName("extra_usage") val extraUsage: ExtraUsage? = null,
    val limits: List<ClaudeUsageLimit>? = null,
)

@Serializable
data class UsageBucket(
    val utilization: Double? = null,
    @SerialName("resets_at") val resetsAt: String? = null,
)

@Serializable
data class ExtraUsage(
    @SerialName("is_enabled") val isEnabled: Boolean = false,
    val utilization: Double? = null,
    @SerialName("used_credits") val usedCredits: Double? = null,
    @SerialName("monthly_limit") val monthlyLimit: Double? = null,
) {
    val usedCreditsAmount: Double? get() = usedCredits?.div(100.0)
    val monthlyLimitAmount: Double? get() = monthlyLimit?.div(100.0)
}

@Serializable
data class ClaudeUsageLimit(
    val kind: String,
    val group: String? = null,
    val percent: Double? = null,
    val severity: String? = null,
    @SerialName("resets_at") val resetsAt: String? = null,
    val scope: ClaudeUsageScope? = null,
    @SerialName("is_active") val isActive: Boolean? = null,
)

@Serializable
data class ClaudeUsageScope(
    val model: ClaudeUsageModel? = null,
    val surface: String? = null,
)

@Serializable
data class ClaudeUsageModel(
    val id: String? = null,
    @SerialName("display_name") val displayName: String? = null,
)

@Serializable
data class CursorUsageResponse(
    val billingCycleStart: String? = null,
    val billingCycleEnd: String? = null,
    val planUsage: CursorPlanUsage? = null,
    val spendLimitUsage: CursorSpendLimitUsage? = null,
    val displayMessage: String? = null,
)

@Serializable
data class CursorPlanUsage(
    val totalSpend: Double? = null,
    val includedSpend: Double? = null,
    val bonusSpend: Double? = null,
    val limit: Double? = null,
    val remainingBonus: Boolean? = null,
    val autoPercentUsed: Double? = null,
    val apiPercentUsed: Double? = null,
    val totalPercentUsed: Double? = null,
)

@Serializable
data class CursorSpendLimitUsage(
    val individualLimit: Double? = null,
    val individualRemaining: Double? = null,
    val limitType: String? = null,
) {
    val spent: Double?
        get() {
            val limit = individualLimit ?: return null
            val remaining = individualRemaining ?: return null
            return maxOf(0.0, limit - remaining)
        }

    val utilization: Double?
        get() {
            val limit = individualLimit ?: return null
            if (limit <= 0) return null
            val spentAmount = spent ?: return null
            return minOf(100.0, maxOf(0.0, spentAmount / limit * 100))
        }
}

@Serializable
data class OpenAIUsageResponse(
    val email: String? = null,
    @SerialName("plan_type") val planType: String? = null,
    @SerialName("rate_limit") val rateLimit: OpenAIRateLimit? = null,
    @SerialName("additional_rate_limits") val additionalRateLimits: List<OpenAIAdditionalRateLimit>? = null,
)

@Serializable
data class OpenAIRateLimit(
    val allowed: Boolean? = null,
    @SerialName("limit_reached") val limitReached: Boolean? = null,
    @SerialName("primary_window") val primaryWindow: OpenAIUsageWindow? = null,
    @SerialName("secondary_window") val secondaryWindow: OpenAIUsageWindow? = null,
)

@Serializable
data class OpenAIAdditionalRateLimit(
    val type: String? = null,
    val label: String? = null,
    @SerialName("rate_limit") val rateLimit: OpenAIRateLimit? = null,
)

@Serializable
data class OpenAIUsageWindow(
    @SerialName("used_percent") val usedPercent: Double? = null,
    @SerialName("limit_window_seconds") val limitWindowSeconds: Double? = null,
    @SerialName("reset_after_seconds") val resetAfterSeconds: Double? = null,
    @SerialName("reset_at") val resetAt: Double? = null,
)

@Serializable
data class ClaudeCredentials(
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresAtEpochMs: Long? = null,
    val scopes: List<String> = emptyList(),
) {
    fun needsRefresh(nowMs: Long = System.currentTimeMillis(), leewayMs: Long = 300_000): Boolean {
        val refresh = refreshToken
        val expiresAt = expiresAtEpochMs
        if (refresh.isNullOrBlank() || expiresAt == null) return false
        return expiresAt <= nowMs + leewayMs
    }

    fun isExpired(nowMs: Long = System.currentTimeMillis()): Boolean {
        val expiresAt = expiresAtEpochMs ?: return false
        return expiresAt <= nowMs
    }
}

@Serializable
data class ElevenLabsSubscriptionResponse(
    val tier: String? = null,
    @SerialName("character_count") val characterCount: Int? = null,
    @SerialName("character_limit") val characterLimit: Int? = null,
    @SerialName("next_character_count_reset_unix") val nextCharacterCountResetUnix: Double? = null,
    val status: String? = null,
    @SerialName("billing_period") val billingPeriod: String? = null,
    @SerialName("character_refresh_period") val characterRefreshPeriod: String? = null,
) {
    val creditsRemaining: Int?
        get() {
            val used = characterCount ?: return null
            val limit = characterLimit ?: return null
            return maxOf(0, limit - used)
        }

    val utilization: Double?
        get() {
            val used = characterCount ?: return null
            val limit = characterLimit ?: return null
            if (limit <= 0) return null
            return used.toDouble() / limit.toDouble() * 100.0
        }
}

@Serializable
data class ConnectedCredentials(
    val openAISessionToken: String? = null,
    val cursorSessionToken: String? = null,
    val elevenLabsAPIKey: String? = null,
) {
    val isEmpty: Boolean
        get() = openAISessionToken.isNullOrBlank()
            && cursorSessionToken.isNullOrBlank()
            && elevenLabsAPIKey.isNullOrBlank()
}

enum class UsageProvider(val displayName: String, val shortName: String) {
    CLAUDE("Claude", "Claude"),
    OPENAI("OpenAI / Codex", "Codex"),
    CURSOR("Cursor", "Cursor"),
    ELEVENLABS("ElevenLabs", "11Labs"),
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

data class AppUsageSnapshot(
    val generatedAtEpochMs: Long = 0L,
    val providers: Map<UsageProvider, ProviderUsageState> = emptyMap(),
)
