package com.agentusagebar.android.data.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UsagePaceTest {
    @Test
    fun elapsedFraction_nullCases() {
        assertNull(UsagePace.elapsedFraction(null, 3_600_000L, 0L))
        assertNull(UsagePace.elapsedFraction(1_000L, null, 0L))
        assertNull(UsagePace.elapsedFraction(1_000L, 0L, 0L))
        assertNull(UsagePace.elapsedFraction(1_000L, -5L, 0L))
    }

    @Test
    fun elapsedFraction_clamps() {
        val interval = 100_000L
        val resetsAt = 1_000_000L
        assertEquals(1.0, UsagePace.elapsedFraction(resetsAt, interval, resetsAt)!!, 1e-9)
        assertEquals(0.0, UsagePace.elapsedFraction(resetsAt, interval, resetsAt - interval)!!, 1e-9)
        assertEquals(1.0, UsagePace.elapsedFraction(resetsAt, interval, resetsAt + 50_000L)!!, 1e-9)
        assertEquals(0.0, UsagePace.elapsedFraction(resetsAt, interval, resetsAt - interval - 1)!!, 1e-9)
        assertEquals(0.5, UsagePace.elapsedFraction(resetsAt, interval, resetsAt - interval / 2)!!, 1e-9)
    }

    @Test
    fun evaluate_thresholds_gapExactlyFiveIsOnPace() {
        val interval = 100_000L
        val resetsAt = 1_000_000L
        val now = resetsAt - interval / 2 // elapsed 50%
        assertEquals(UsagePace.ON_PACE, UsagePace.evaluate(55.0, resetsAt, interval, now))
        assertEquals(UsagePace.AHEAD, UsagePace.evaluate(56.0, resetsAt, interval, now))
        assertEquals(UsagePace.ON_PACE, UsagePace.evaluate(45.0, resetsAt, interval, now))
        assertEquals(UsagePace.UNDER, UsagePace.evaluate(44.0, resetsAt, interval, now))
    }

    @Test
    fun evaluate_nullWhenElapsedOrUsedMissing() {
        assertNull(UsagePace.evaluate(null, 1_000L, 100L, 0L))
        assertNull(UsagePace.evaluate(50.0, null, 100L, 0L))
    }

    @Test
    fun glyphs() {
        assertEquals("↗", UsagePace.AHEAD.glyph)
        assertEquals("—", UsagePace.ON_PACE.glyph)
        assertEquals("↘", UsagePace.UNDER.glyph)
    }
}
