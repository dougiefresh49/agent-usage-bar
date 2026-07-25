package com.agentusagebar.android.data.model

import org.junit.Assert.assertEquals
import org.junit.Test

class UsageMetricPreferencesTest {
    @Test
    fun resolvesStoredPairInPreferenceOrder() {
        val metrics = listOf(
            UsageMetric(UsageMetricPreferences.CURSOR_MODELS, "First-Party Models"),
            UsageMetric(UsageMetricPreferences.CURSOR_API, "API"),
            UsageMetric(UsageMetricPreferences.CURSOR_TOTAL, "Total Plan Usage"),
        )

        val resolved = UsageMetricPreferences.resolvedPair(
            provider = UsageProvider.CURSOR,
            primaryID = UsageMetricPreferences.CURSOR_TOTAL,
            secondaryID = UsageMetricPreferences.CURSOR_MODELS,
            available = metrics,
        )

        assertEquals(
            listOf(
                UsageMetricPreferences.CURSOR_TOTAL,
                UsageMetricPreferences.CURSOR_MODELS,
            ),
            resolved.map { it.id },
        )
    }

    @Test
    fun fallsBackToProviderDefaultsForSyncedUnavailableMetrics() {
        val metrics = listOf(
            UsageMetric(UsageMetricPreferences.OPENAI_PRIMARY, "Primary Window"),
            UsageMetric(UsageMetricPreferences.OPENAI_SECONDARY, "Secondary Window"),
        )

        val resolved = UsageMetricPreferences.resolvedPair(
            provider = UsageProvider.OPENAI,
            primaryID = "openai.resetCredits",
            secondaryID = "openai.missing",
            available = metrics,
        )

        assertEquals(
            listOf(
                UsageMetricPreferences.OPENAI_PRIMARY,
                UsageMetricPreferences.OPENAI_SECONDARY,
            ),
            resolved.map { it.id },
        )
    }

    @Test
    fun ordersSelectedMetricsBeforeRemainingWidgetMetrics() {
        val metrics = listOf(
            UsageMetric(UsageMetricPreferences.CLAUDE_FIVE_HOUR, "5-Hour Window"),
            UsageMetric(UsageMetricPreferences.CLAUDE_SEVEN_DAY, "7-Day Window"),
            UsageMetric(UsageMetricPreferences.CLAUDE_SONNET, "Sonnet (7 day)"),
        )

        val ordered = UsageMetricPreferences.orderedMetrics(
            provider = UsageProvider.CLAUDE,
            primaryID = UsageMetricPreferences.CLAUDE_SONNET,
            secondaryID = UsageMetricPreferences.CLAUDE_FIVE_HOUR,
            available = metrics,
        )

        assertEquals(
            listOf(
                UsageMetricPreferences.CLAUDE_SONNET,
                UsageMetricPreferences.CLAUDE_FIVE_HOUR,
                UsageMetricPreferences.CLAUDE_SEVEN_DAY,
            ),
            ordered.map { it.id },
        )
    }
}
