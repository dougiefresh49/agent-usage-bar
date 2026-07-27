package com.agentusagebar.android.widget

import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import org.junit.Assert.assertEquals
import org.junit.Test

class ClaudeWidgetMetricPreferencesTest {
    @Test
    fun orbitCenterAndCaptionResolveIndependentlyFromPrimaryMetric() {
        val fableID = UsageMetricPreferences.claudeLimitMetricId(
            kind = "model",
            modelDisplayName = "Fable",
            group = "weekly",
        )
        val fiveHour = UsageMetric(
            id = UsageMetricPreferences.CLAUDE_FIVE_HOUR,
            label = "5-Hour Window",
            percentUsed = 23.0,
        )
        val fable = UsageMetric(
            id = fableID,
            label = "Fable (7 day)",
            percentUsed = 90.0,
        )
        val state = ProviderUsageState(
            provider = UsageProvider.CLAUDE,
            isConfigured = true,
            metrics = listOf(fiveHour, fable),
        )

        val orbitCenter = claudeWidgetMetric(
            state = state,
            metricID = UsageMetricPreferences.CLAUDE_FIVE_HOUR,
            fallback = fable,
        )
        val caption = claudeWidgetMetric(
            state = state,
            metricID = fableID,
            fallback = fiveHour,
        )

        assertEquals(UsageMetricPreferences.CLAUDE_FIVE_HOUR, orbitCenter?.id)
        assertEquals(fableID, caption?.id)
        assertEquals("90%", caption?.displayValue)
    }
}
