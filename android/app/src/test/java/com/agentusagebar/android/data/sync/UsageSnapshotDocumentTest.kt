package com.agentusagebar.android.data.sync

import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.ui.components.compactWindowLabel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class UsageSnapshotDocumentTest {
    private val json = DeviceSyncCodec.json

    @Test
    fun v3MacFixtureMapsPlanCreditsUpdatedAtAndMetrics() {
        val document = json.decodeFromString<UsageSnapshotDocument>(MAC_V3_SAMPLE)
        val snapshot = document.toAppUsageSnapshot(
            desktopName = "Doug's MacBook",
            pairedDesktopCount = 1,
            lastSuccessfulPullEpochMs = 1_757_521_026_000L,
        )

        assertEquals(3, document.version)
        val openai = snapshot.providers.getValue(UsageProvider.OPENAI)
        assertTrue(openai.isConfigured)
        assertEquals("plus", snapshot.openAIPlanType)
        assertEquals(2, snapshot.openAICreditsAvailable)
        assertEquals("crd_1", snapshot.openAICreditItems.single().id)
        assertEquals(
            Instant.parse("2026-09-20T00:00:00Z").toEpochMilli(),
            snapshot.openAICreditItems.single().expiresAtEpochMs,
        )
        assertNull(openai.error)
        assertEquals(Instant.parse("2026-09-10T16:53:44Z").toEpochMilli(), openai.updatedAtEpochMs)
        assertEquals(Instant.parse("2026-09-10T16:53:46Z").toEpochMilli(), snapshot.generatedAtEpochMs)
        val primary = openai.metrics.single()
        assertEquals(UsageMetricPreferences.OPENAI_PRIMARY, primary.id)
        assertEquals("7-day window", primary.label)
        assertEquals(43.0, primary.percentUsed)
        assertFalse(snapshot.providers.getValue(UsageProvider.CLAUDE).isConfigured)
        assertFalse(snapshot.providers.getValue(UsageProvider.CURSOR).isConfigured)
        assertFalse(snapshot.providers.getValue(UsageProvider.ELEVENLABS).isConfigured)
    }

    @Test
    fun v2DocumentMapsMissingPlanCreditsAndErrorAsNull() {
        val document = json.decodeFromString<UsageSnapshotDocument>(V2_CLAUDE)
        val snapshot = document.toAppUsageSnapshot(
            desktopName = null,
            pairedDesktopCount = 1,
            lastSuccessfulPullEpochMs = 1L,
        )

        assertEquals(2, document.version)
        val claude = snapshot.providers.getValue(UsageProvider.CLAUDE)
        assertTrue(claude.isConfigured)
        assertNull(document.providers["claude"]?.plan)
        assertNull(document.providers["claude"]?.credits)
        assertNull(document.providers["claude"]?.error)
        assertNull(snapshot.claudeProfile)
        assertNull(claude.error)
        assertEquals(UsageMetricPreferences.CLAUDE_FIVE_HOUR, claude.metrics.single().id)
        assertEquals(28.0, claude.metrics.single().percentUsed)
        assertFalse(snapshot.providers.getValue(UsageProvider.OPENAI).isConfigured)
    }

    @Test
    fun unconfiguredProviderIsNotConfigured() {
        val document = json.decodeFromString<UsageSnapshotDocument>(
            """{"version":3,"generatedAt":"2026-09-10T16:53:46Z","providers":{}}""",
        )
        val snapshot = document.toAppUsageSnapshot(
            desktopName = null,
            pairedDesktopCount = 1,
            lastSuccessfulPullEpochMs = 1L,
        )

        UsageProvider.entries.forEach { provider ->
            assertFalse(snapshot.providers.getValue(provider).isConfigured)
        }
    }

    @Test
    fun v3MapsErrorClaudePlanAndCursorPlanIntoExistingUiFields() {
        val document = json.decodeFromString<UsageSnapshotDocument>(V3_RICH)
        val snapshot = document.toAppUsageSnapshot(
            desktopName = "Studio",
            pairedDesktopCount = 2,
            lastSuccessfulPullEpochMs = 2L,
        )

        assertEquals(
            "On the Mac: OpenAI session expired — update it in Settings",
            snapshot.providers.getValue(UsageProvider.OPENAI).error,
        )
        assertEquals("Max 20x", snapshot.claudeProfile?.planLabel)
        assertEquals("active", snapshot.claudeProfile?.organization?.subscriptionStatus)
        assertEquals("Pro", snapshot.cursorPlanInfo?.planInfo?.planName)
        assertEquals("$20/mo", snapshot.cursorPlanInfo?.planInfo?.price)
        assertEquals(2000, snapshot.cursorPlanInfo?.planInfo?.includedAmountCents)
        assertEquals(406, snapshot.cursorPlanInfo?.planInfo?.usedAmountCents)
        assertEquals(
            Instant.parse("2026-09-26T16:24:39Z").toEpochMilli().toString(),
            snapshot.cursorPlanInfo?.planInfo?.billingCycleEnd,
        )
        assertEquals("Studio", snapshot.sourceDesktopName)
        assertEquals(2, snapshot.pairedDesktopCount)
        assertEquals(
            UsageMetricPreferences.CLAUDE_SEVEN_DAY,
            snapshot.providers.getValue(UsageProvider.CLAUDE).metrics[1].id,
        )
        assertEquals(
            5L * 60 * 60 * 1000,
            snapshot.providers.getValue(UsageProvider.CLAUDE).metrics[0].resetIntervalMs,
        )
        assertEquals("used $4.06 / $20.00", snapshot.providers.getValue(UsageProvider.CURSOR).metrics
            .first { it.id == UsageMetricPreferences.CURSOR_GROK_BOT }.detail)
    }

    companion object {
        // Compact sorted-keys JSON from macos DeviceSyncManagerTests.sampleSnapshotJSON.
        const val MAC_V3_SAMPLE =
            """{"generatedAt":"2026-09-10T16:53:46Z","providers":{"openai":{"credits":{"available":2,"items":[{"expiresAt":"2026-09-20T00:00:00Z","id":"crd_1"}]},"metrics":[{"id":"primary","label":"7-day window","percentUsed":43}],"plan":{"label":"plus"},"updatedAt":"2026-09-10T16:53:44Z"}},"version":3}"""

        const val V2_CLAUDE = """
        {
          "version": 2,
          "generatedAt": "2026-09-10T16:53:46Z",
          "providers": {
            "claude": {
              "updatedAt": "2026-09-10T16:53:44Z",
              "metrics": [
                {"id": "five_hour", "label": "5-hour window", "percentUsed": 28}
              ]
            }
          }
        }
        """

        const val V3_RICH = """
        {
          "version": 3,
          "generatedAt": "2026-09-10T16:53:46Z",
          "providers": {
            "claude": {
              "updatedAt": "2026-09-10T16:53:44Z",
              "plan": {"label": "Max 20x", "status": "active"},
              "metrics": [
                {"id": "five_hour", "label": "5-hour window", "percentUsed": 28, "resetInterval": 18000},
                {"id": "seven_day", "label": "7-day window", "percentUsed": 21, "resetInterval": 604800}
              ]
            },
            "openai": {
              "updatedAt": "2026-09-10T16:50:00Z",
              "error": "OpenAI session expired — update it in Settings",
              "plan": {"label": "plus"},
              "metrics": [{"id": "primary", "label": "7-day window", "percentUsed": 70}]
            },
            "cursor": {
              "updatedAt": "2026-09-10T16:53:44Z",
              "plan": {
                "label": "Pro",
                "priceText": "${'$'}20/mo",
                "renewsAt": "2026-09-26T16:24:39Z",
                "includedAmountCents": 2000,
                "usedAmountCents": 406
              },
              "metrics": [
                {"id": "grok_bot", "label": "Grok Bot", "percentUsed": 0.059292, "valueText": "used ${'$'}4.06 / ${'$'}20.00"}
              ]
            }
          }
        }
        """
    }
}

class CompactWindowLabelTest {
    @Test
    fun compactWindowLabelDerivesHoursAndDays() {
        assertEquals("5h", compactWindowLabel(5L * 60L * 60L * 1000L))
        assertEquals("7d", compactWindowLabel(7L * 24L * 60L * 60L * 1000L))
        assertNull(compactWindowLabel(null))
        assertNull(compactWindowLabel(0L))
    }
}
