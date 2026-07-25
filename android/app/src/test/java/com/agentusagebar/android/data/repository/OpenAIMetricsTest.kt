package com.agentusagebar.android.data.repository

import com.agentusagebar.android.data.model.OpenAIRateLimit
import com.agentusagebar.android.data.model.OpenAIResetCredit
import com.agentusagebar.android.data.model.OpenAIResetCreditSummary
import com.agentusagebar.android.data.model.OpenAIResetCreditsResponse
import com.agentusagebar.android.data.model.OpenAIUsageResponse
import com.agentusagebar.android.data.model.OpenAIUsageWindow
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.ui.components.orbitLegendMetrics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OpenAIMetricsTest {
    @Test
    fun openAIMetricsIncludesResetCreditsRemaining() {
        val usage = OpenAIUsageResponse(
            rateLimit = OpenAIRateLimit(
                primaryWindow = OpenAIUsageWindow(
                    usedPercent = 69.0,
                    limitWindowSeconds = 604_800.0,
                    resetAt = 1_700_000_000.0,
                ),
            ),
            rateLimitResetCredits = OpenAIResetCreditSummary(
                availableCount = 2,
                applicableAvailableCount = 1,
            ),
        )

        val metrics = UsageRepository.openAIMetrics(usage)
        val resetCredits = metrics.first { it.id == UsageMetricPreferences.OPENAI_RESET_CREDITS }

        assertEquals("Reset Credits", resetCredits.label)
        assertEquals(1, resetCredits.countValue)
        assertNull(resetCredits.percentUsed)
        assertEquals(
            listOf(
                UsageMetricPreferences.OPENAI_PRIMARY,
                UsageMetricPreferences.OPENAI_RESET_CREDITS,
            ),
            metrics.map { it.id }.take(2),
        )
    }

    @Test
    fun openAIMetricsPrefersDedicatedResetCreditsEndpointOverUsageSummary() {
        // Usage summary often reports applicable_available_count: 0 even when
        // credits are available — the dedicated endpoint has the real count.
        val usage = OpenAIUsageResponse(
            rateLimit = OpenAIRateLimit(
                primaryWindow = OpenAIUsageWindow(usedPercent = 82.0),
            ),
            rateLimitResetCredits = OpenAIResetCreditSummary(
                availableCount = 2,
                applicableAvailableCount = 0,
            ),
        )
        val resetCredits = OpenAIResetCreditsResponse(
            credits = listOf(
                OpenAIResetCredit(id = "reset-1", status = "available"),
                OpenAIResetCredit(id = "reset-2", status = "available"),
            ),
            availableCount = 2,
        )

        val metrics = UsageRepository.openAIMetrics(usage, resetCredits)
        val resetMetric = metrics.first { it.id == UsageMetricPreferences.OPENAI_RESET_CREDITS }

        assertEquals(2, resetMetric.countValue)
    }

    @Test
    fun openAIMetricsCountsAvailableCreditsWhenDedicatedCountMissing() {
        val usage = OpenAIUsageResponse(
            rateLimitResetCredits = OpenAIResetCreditSummary(applicableAvailableCount = 0),
        )
        val resetCredits = OpenAIResetCreditsResponse(
            credits = listOf(
                OpenAIResetCredit(id = "reset-1", status = "available"),
                OpenAIResetCredit(id = "reset-2", status = "used"),
                OpenAIResetCredit(id = "reset-3", status = "available"),
            ),
        )

        val metrics = UsageRepository.openAIMetrics(usage, resetCredits)
        val resetMetric = metrics.first { it.id == UsageMetricPreferences.OPENAI_RESET_CREDITS }

        assertEquals(2, resetMetric.countValue)
    }

    @Test
    fun orbitLegendPrefersResetCreditsOverSecondaryPercentRing() {
        val usage = OpenAIUsageResponse(
            rateLimit = OpenAIRateLimit(
                primaryWindow = OpenAIUsageWindow(usedPercent = 69.0),
                secondaryWindow = OpenAIUsageWindow(usedPercent = 40.0),
            ),
            rateLimitResetCredits = OpenAIResetCreditSummary(availableCount = 3),
        )
        val metrics = UsageRepository.openAIMetrics(usage)
        val legend = orbitLegendMetrics(metrics)

        assertEquals(
            listOf(
                UsageMetricPreferences.OPENAI_PRIMARY,
                UsageMetricPreferences.OPENAI_RESET_CREDITS,
            ),
            legend.map { it.id },
        )
        assertEquals(3, legend[1].countValue)
    }
}
