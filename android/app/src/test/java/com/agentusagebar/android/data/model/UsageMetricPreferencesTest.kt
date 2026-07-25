package com.agentusagebar.android.data.model

import org.junit.Assert.assertEquals
import org.junit.Test

class UsageMetricPreferencesTest {
    @Test
    fun providerUsagePageUrls() {
        assertEquals(
            "https://claude.ai/new#settings/usage",
            UsageProvider.CLAUDE.usagePageUrl,
        )
        assertEquals(
            "https://chatgpt.com/#settings/Usage",
            UsageProvider.OPENAI.usagePageUrl,
        )
        assertEquals(
            "https://cursor.com/dashboard/spending",
            UsageProvider.CURSOR.usagePageUrl,
        )
        assertEquals(
            "https://elevenlabs.io/app/subscription/",
            UsageProvider.ELEVENLABS.usagePageUrl,
        )
    }

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

    @Test
    fun claudeLimitMetricIdsAreStableAcrossResetWindows() {
        val first = UsageMetricPreferences.claudeLimitMetricId(
            kind = "model",
            modelDisplayName = "Fable",
            group = "weekly",
        )
        val second = UsageMetricPreferences.claudeLimitMetricId(
            kind = "model",
            modelDisplayName = "Fable",
            group = "weekly",
        )
        assertEquals("claude.limit.model:Fable:weekly", first)
        assertEquals(first, second)
    }

    @Test
    fun resolvesLegacyClaudeLimitIdsThatEmbeddedResetsAt() {
        val liveId = UsageMetricPreferences.claudeLimitMetricId(
            kind = "model",
            modelDisplayName = "Fable",
            group = "weekly",
        )
        val legacyStored = "claude.limit.model:Fable:2026-07-31T12:00:00Z"
        val metrics = listOf(
            UsageMetric(UsageMetricPreferences.CLAUDE_FIVE_HOUR, "5-Hour Window", percentUsed = 13.0),
            UsageMetric(UsageMetricPreferences.CLAUDE_SEVEN_DAY, "7-Day Window", percentUsed = 40.0),
            UsageMetric(liveId, "Fable (7 day)", percentUsed = 65.0),
        )

        val resolved = UsageMetricPreferences.resolvedPair(
            provider = UsageProvider.CLAUDE,
            primaryID = UsageMetricPreferences.CLAUDE_FIVE_HOUR,
            secondaryID = legacyStored,
            available = metrics,
        )

        assertEquals(
            listOf(UsageMetricPreferences.CLAUDE_FIVE_HOUR, liveId),
            resolved.map { it.id },
        )
    }
}
