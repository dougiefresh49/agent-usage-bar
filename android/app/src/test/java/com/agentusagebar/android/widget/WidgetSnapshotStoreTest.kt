package com.agentusagebar.android.widget

import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.ClaudeProfileAccount
import com.agentusagebar.android.data.model.ClaudeProfileOrganization
import com.agentusagebar.android.data.model.ClaudeProfileResponse
import com.agentusagebar.android.data.model.CursorPlanInfo
import com.agentusagebar.android.data.model.CursorPlanInfoResponse
import com.agentusagebar.android.data.model.ProviderUsageState
import com.agentusagebar.android.data.model.UsageMetric
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.concurrent.TimeUnit

class WidgetSnapshotStoreTest {
    @Test
    fun snapshotRoundTripKeepsPlanAndRenewalFields() {
        val renewsAt = 1_790_439_879_000L
        val snapshot = AppUsageSnapshot(
            generatedAtEpochMs = 1_700_000_000_000L,
            providers = mapOf(
                UsageProvider.CURSOR to ProviderUsageState(
                    provider = UsageProvider.CURSOR,
                    isConfigured = true,
                    metrics = listOf(
                        UsageMetric(
                            id = UsageMetricPreferences.CURSOR_TOTAL,
                            label = "Total Plan Usage",
                            percentUsed = 20.3,
                            resetsAtEpochMs = renewsAt,
                        ),
                    ),
                    updatedAtEpochMs = 1_700_000_000_100L,
                ),
            ),
            claudeProfile = ClaudeProfileResponse(
                account = ClaudeProfileAccount(hasClaudeMax = true, hasClaudePro = true),
                organization = ClaudeProfileOrganization(
                    rateLimitTier = "default_claude_max_20x",
                    subscriptionStatus = "active",
                ),
            ),
            cursorPlanInfo = CursorPlanInfoResponse(
                planInfo = CursorPlanInfo(
                    planName = "Pro",
                    includedAmountCents = 2000,
                    price = "$20/mo",
                    billingCycleEnd = renewsAt.toString(),
                ),
            ),
        )

        val encoded = encodeWidgetSnapshotPayload(widgetSnapshotPayload(snapshot))
        val loaded = loadedWidgetSnapshot(decodeWidgetSnapshotPayload(encoded))

        assertEquals(renewsAt, loaded.cursorRenewsAtEpochMs)
        assertEquals("Pro", loaded.cursorPlanName)
        assertEquals("Max 20x", loaded.claudePlanLabel)
        assertEquals(
            20.3,
            loaded.providers[UsageProvider.CURSOR]
                ?.metrics
                ?.first { it.id == UsageMetricPreferences.CURSOR_TOTAL }
                ?.percentUsed,
        )
    }

    @Test
    fun snapshotRoundTripLeavesPlanFieldsNullWhenAbsent() {
        val snapshot = AppUsageSnapshot(
            generatedAtEpochMs = 1L,
            providers = emptyMap(),
        )
        val loaded = loadedWidgetSnapshot(
            decodeWidgetSnapshotPayload(encodeWidgetSnapshotPayload(widgetSnapshotPayload(snapshot))),
        )
        assertNull(loaded.cursorRenewsAtEpochMs)
        assertNull(loaded.cursorPlanName)
        assertNull(loaded.claudePlanLabel)
    }

    @Test
    fun renewsInFormatsWholeDays() {
        val now = 1_700_000_000_000L
        val inTwelveDays = now + TimeUnit.DAYS.toMillis(12)
        assertEquals("renews in 12d", formatRenewsIn(inTwelveDays, now))
    }

    @Test
    fun renewsInFormatsHoursWhenUnderADay() {
        val now = 1_700_000_000_000L
        val inFiveHours = now + TimeUnit.HOURS.toMillis(5)
        assertEquals("renews in 5h", formatRenewsIn(inFiveHours, now))
    }

    @Test
    fun cursorPlanRowJoinsNamePriceAndRenewal() {
        val now = 1_700_000_000_000L
        val renewsAt = now + TimeUnit.DAYS.toMillis(12)
        assertEquals(
            "Pro · $20/mo · renews in 12d",
            formatCursorPlanRow("Pro", "$20/mo", renewsAt, now),
        )
        assertNull(formatCursorPlanRow(null, null, null, now))
    }

    @Test
    fun cursorSpendRowUsesPercentOfIncludedAmount() {
        assertEquals(
            "used $4.06 of $20.00",
            formatCursorSpendRow(percentUsed = 20.3, includedAmountCents = 2000),
        )
        assertNull(formatCursorSpendRow(percentUsed = 20.3, includedAmountCents = null))
        assertNull(formatCursorSpendRow(percentUsed = null, includedAmountCents = 2000))
    }

    @Test
    fun claudePlanRowJoinsLabelAndStatus() {
        assertEquals("Max 20x · active", formatClaudePlanRow("Max 20x", "active"))
        assertEquals("Max 20x", formatClaudePlanRow("Max 20x", null))
        assertNull(formatClaudePlanRow(null, null))
    }

    @Test
    fun renewsAtComesFromBillingCycleEndOnly() {
        val metricReset = 1_790_439_879_000L
        val snapshot = AppUsageSnapshot(
            generatedAtEpochMs = 1L,
            providers = mapOf(
                UsageProvider.CURSOR to ProviderUsageState(
                    provider = UsageProvider.CURSOR,
                    isConfigured = true,
                    metrics = listOf(
                        UsageMetric(
                            id = UsageMetricPreferences.CURSOR_TOTAL,
                            label = "Total Plan Usage",
                            percentUsed = 10.0,
                            resetsAtEpochMs = metricReset,
                        ),
                    ),
                ),
            ),
            cursorPlanInfo = CursorPlanInfoResponse(
                planInfo = CursorPlanInfo(
                    planName = "Pro",
                    includedAmountCents = 2000,
                    price = "$20/mo",
                    billingCycleEnd = null,
                ),
            ),
        )
        val payload = widgetSnapshotPayload(snapshot)
        assertNull(payload.cursorRenewsAtEpochMs)
    }

    @Test
    fun legacySnapshotWithoutPlanFieldsStillDecodes() {
        val legacy = """
            {"generatedAtEpochMs":1,"providers":{"CURSOR":{"isConfigured":true,"metrics":[]}}}
        """.trimIndent()
        val loaded = loadedWidgetSnapshot(decodeWidgetSnapshotPayload(legacy))
        assertNull(loaded.cursorRenewsAtEpochMs)
        assertEquals(true, loaded.providers[UsageProvider.CURSOR]?.isConfigured)
    }
}
