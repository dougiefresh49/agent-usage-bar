package com.agentusagebar.android.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ResponsiveWidgetLayoutTest {
    @Test
    fun `wide short widget uses a row and grows beyond the old fixed chart size`() {
        val spec = responsiveOverviewSpec(
            widthDp = 320f,
            heightDp = 110f,
            actionsAvailable = false,
        )

        assertEquals(ResponsiveOverviewLayout.HORIZONTAL, spec.layout)
        assertTrue(spec.chartSizeDp > 70f)
        assertFalse(spec.showSecondaryMetrics)
        assertFalse(spec.showActions)
    }

    @Test
    fun `narrow tall widget uses a compact column`() {
        val spec = responsiveOverviewSpec(
            widthDp = 70f,
            heightDp = 220f,
            actionsAvailable = false,
        )

        assertEquals(ResponsiveOverviewLayout.VERTICAL, spec.layout)
        assertTrue(spec.chartSizeDp in 30f..60f)
        assertFalse(spec.showSecondaryMetrics)
    }

    @Test
    fun `balanced widget uses a two by two grid with large charts`() {
        val spec = responsiveOverviewSpec(
            widthDp = 300f,
            heightDp = 260f,
            actionsAvailable = false,
        )

        assertEquals(ResponsiveOverviewLayout.GRID, spec.layout)
        assertTrue(spec.chartSizeDp > 100f)
        assertTrue(spec.showSecondaryMetrics)
    }

    @Test
    fun `intermediate two by three size becomes a compact grid`() {
        val spec = responsiveOverviewSpec(
            widthDp = 150f,
            heightDp = 210f,
            actionsAvailable = false,
        )

        assertEquals(ResponsiveOverviewLayout.GRID, spec.layout)
        assertTrue(spec.chartSizeDp > 60f)
        assertFalse(spec.showSecondaryMetrics)
    }

    @Test
    fun `dashboard actions appear only when a grid has enough room`() {
        val large = responsiveOverviewSpec(300f, 280f, actionsAvailable = true)
        val short = responsiveOverviewSpec(300f, 110f, actionsAvailable = true)
        val narrow = responsiveOverviewSpec(90f, 280f, actionsAvailable = true)

        assertTrue(large.showActions)
        assertFalse(short.showActions)
        assertFalse(narrow.showActions)
    }
}
