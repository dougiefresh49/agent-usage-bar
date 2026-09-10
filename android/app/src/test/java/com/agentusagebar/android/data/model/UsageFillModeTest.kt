package com.agentusagebar.android.data.model

import org.junit.Assert.assertEquals
import org.junit.Test

class UsageFillModeTest {
    @Test
    fun barFraction_fillAndDrain_andClamping() {
        assertEquals(0.31f, UsageFillMode.FILL.barFraction(31.0), 0.0001f)
        assertEquals(0.69f, UsageFillMode.DRAIN.barFraction(31.0), 0.0001f)
        assertEquals(0f, UsageFillMode.FILL.barFraction(-10.0), 0.0001f)
        assertEquals(1f, UsageFillMode.FILL.barFraction(150.0), 0.0001f)
        assertEquals(1f, UsageFillMode.DRAIN.barFraction(-10.0), 0.0001f)
        assertEquals(0f, UsageFillMode.DRAIN.barFraction(150.0), 0.0001f)
    }

    @Test
    fun displayValue_percentMetric_bothModes() {
        val metric = UsageMetric(id = "claude.5h", label = "5-Hour", percentUsed = 31.4)
        assertEquals("31%", metric.displayValue(UsageFillMode.FILL))
        assertEquals("69%", metric.displayValue(UsageFillMode.DRAIN))
        assertEquals("31%", metric.displayValue)
    }

    @Test
    fun displayValue_halfPoints_roundUpLikeTheMac() {
        val metric = UsageMetric(id = "claude.5h", label = "5-Hour", percentUsed = 31.5)
        assertEquals("32%", metric.displayValue(UsageFillMode.FILL))
        assertEquals("69%", metric.displayValue(UsageFillMode.DRAIN))
    }

    @Test
    fun barFraction_nullPercent_drawsNothingInBothModes() {
        assertEquals(0f, UsageFillMode.FILL.barFraction(null), 0.0001f)
        assertEquals(0f, UsageFillMode.DRAIN.barFraction(null), 0.0001f)
    }

    @Test
    fun displayValue_countMetric_unchanged() {
        val metric = UsageMetric(id = "openai.resetCredits", label = "Reset Credits", countValue = 3)
        assertEquals("3", metric.displayValue(UsageFillMode.FILL))
        assertEquals("3", metric.displayValue(UsageFillMode.DRAIN))
    }

    @Test
    fun displayValue_nullPercent_isEmDash() {
        val metric = UsageMetric(id = "x", label = "X")
        assertEquals("—", metric.displayValue(UsageFillMode.FILL))
        assertEquals("—", metric.displayValue(UsageFillMode.DRAIN))
    }

    @Test
    fun drainLabels_elevenLabsAndCursor_claudeUnchanged() {
        assertEquals(
            "Credits",
            metricLabelForMode(
                UsageMetricPreferences.ELEVENLABS_CREDITS,
                "Credits Used",
                UsageFillMode.DRAIN,
            ),
        )
        assertEquals(
            "Credits Used",
            metricLabelForMode(
                UsageMetricPreferences.ELEVENLABS_CREDITS,
                "Credits Used",
                UsageFillMode.FILL,
            ),
        )
        assertEquals(
            "Total Plan",
            metricLabelForMode(
                UsageMetricPreferences.CURSOR_TOTAL,
                "Total Plan Usage",
                UsageFillMode.DRAIN,
            ),
        )
        assertEquals(
            "5-Hour Window",
            metricLabelForMode("claude.5h", "5-Hour Window", UsageFillMode.DRAIN),
        )
        assertEquals(
            "5-Hour Window",
            metricLabelForMode("claude.5h", "5-Hour Window", UsageFillMode.FILL),
        )
    }
}
