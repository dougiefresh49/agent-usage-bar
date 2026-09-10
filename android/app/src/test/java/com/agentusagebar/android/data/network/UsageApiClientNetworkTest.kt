package com.agentusagebar.android.data.network

import com.agentusagebar.android.data.model.ClaudeCredentials
import com.agentusagebar.android.data.model.ClaudeProfileResponse
import com.agentusagebar.android.data.model.ConnectedCredentials
import com.agentusagebar.android.data.model.CursorPlanInfoResponse
import com.agentusagebar.android.data.sync.DeviceSyncConnections
import com.agentusagebar.android.data.sync.mergingImported
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsageApiClientNetworkTest {
    @Test
    fun connectRpcUsageUsesBearerHeadersBodyAndDecodesIntoCursorUsageResponse() {
        val recorded = mutableListOf<okhttp3.Request>()
        val client = recordingClient(recorded) {
            """
            {
              "billingCycleStart": "1785083079000",
              "billingCycleEnd": "1787681079000",
              "planUsage": {
                "totalSpend": 3332,
                "includedSpend": 2000,
                "autoPercentUsed": 10.2,
                "apiPercentUsed": 6,
                "totalPercentUsed": 9.65
              },
              "spendLimitUsage": {
                "individualLimit": 1500,
                "individualRemaining": 1200,
                "limitType": "user"
              }
            }
            """.trimIndent()
        }
        val api = UsageApiClient(
            client = client,
            connectedCredentials = {
                ConnectedCredentials(cursorAccessToken = "cli-token")
            },
        )

        val usage = api.fetchCursorUsage().getOrThrow()

        assertEquals(1, recorded.size)
        val request = recorded.single()
        assertEquals(
            "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            request.url.toString(),
        )
        assertEquals("POST", request.method)
        assertEquals("Bearer cli-token", request.header("Authorization"))
        assertEquals("application/json", request.header("Content-Type"))
        assertEquals("1", request.header("connect-protocol-version"))
        assertEquals("cli-agent-usage-bar", request.header("x-cursor-client-version"))
        assertEquals("cli", request.header("x-cursor-client-type"))
        assertEquals("{}", request.bodyUtf8())
        assertNull(request.header("Cookie"))
        assertEquals("1787681079000", usage.billingCycleEnd)
        assertEquals(9.65, usage.planUsage?.totalPercentUsed)
        assertEquals(1200.0, usage.spendLimitUsage?.individualRemaining)
    }

    @Test
    fun cookieCursorPathKeepsCursorComEndpoint() {
        val recorded = mutableListOf<okhttp3.Request>()
        val client = recordingClient(recorded) {
            """{"billingCycleEnd":"1","planUsage":{"autoPercentUsed":1.0}}"""
        }
        val api = UsageApiClient(
            client = client,
            connectedCredentials = {
                ConnectedCredentials(cursorSessionToken = "cookie-token")
            },
        )

        api.fetchCursorUsage().getOrThrow()

        val request = recorded.single()
        assertEquals(
            "https://cursor.com/api/dashboard/get-current-period-usage",
            request.url.toString(),
        )
        assertEquals("WorkosCursorSessionToken=cookie-token", request.header("Cookie"))
        assertNull(request.header("Authorization"))
        assertNull(request.header("connect-protocol-version"))
    }

    @Test
    fun openAICallsSendCodexHeadersAndAccountId() {
        val recorded = mutableListOf<okhttp3.Request>()
        val client = recordingClient(recorded) {
            """{"rate_limit":{"primary_window":{"used_percent":12.0}}}"""
        }
        val api = UsageApiClient(
            client = client,
            connectedCredentials = {
                ConnectedCredentials(
                    codexAccessToken = "codex-cli",
                    codexAccountId = "acct-123",
                    openAISessionToken = "pasted-should-lose",
                )
            },
        )

        api.fetchOpenAIUsage().getOrThrow()

        val request = recorded.single()
        assertEquals("Bearer codex-cli", request.header("Authorization"))
        assertEquals("codex-1", request.header("OpenAI-Beta"))
        assertEquals("Codex Desktop", request.header("Originator"))
        assertEquals("acct-123", request.header("Chatgpt-Account-Id"))
        assertEquals(
            "https://chatgpt.com/backend-api/wham/usage",
            request.url.toString(),
        )
    }

    @Test
    fun openAIOmitsAccountIdHeaderWhenUnknown() {
        val recorded = mutableListOf<okhttp3.Request>()
        val client = recordingClient(recorded) {
            """{"rate_limit":{"primary_window":{"used_percent":4.0}}}"""
        }
        val api = UsageApiClient(
            client = client,
            connectedCredentials = {
                ConnectedCredentials(openAISessionToken = "pasted-token")
            },
        )

        api.fetchOpenAIUsage().getOrThrow()

        val request = recorded.single()
        assertEquals("Bearer pasted-token", request.header("Authorization"))
        assertEquals("codex-1", request.header("OpenAI-Beta"))
        assertEquals("Codex Desktop", request.header("Originator"))
        assertNull(request.header("Chatgpt-Account-Id"))
    }

    @Test
    fun planInfoDecodesFixtureAndRequiresCliToken() {
        val recorded = mutableListOf<okhttp3.Request>()
        val client = recordingClient(recorded) {
            """
            {"planInfo":{"planName":"Pro","includedAmountCents":2000,"price":"$20/mo",
             "billingCycleEnd":"1790439879000","planOwner":"PLAN_OWNER_STRIPE"},
             "nextUpgrade":{"tier":"pro_plus","name":"Pro+","includedAmountCents":7000,
             "price":"$60/mo","description":"Unlock 3x more usage on Agent & more"}}
            """.trimIndent()
        }
        val api = UsageApiClient(
            client = client,
            connectedCredentials = {
                ConnectedCredentials(cursorAccessToken = "cli-token")
            },
        )

        val plan: CursorPlanInfoResponse = api.fetchCursorPlanInfo().getOrThrow()

        assertEquals(
            "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo",
            recorded.single().url.toString(),
        )
        assertEquals("Pro", plan.planInfo?.planName)
        assertEquals(2000, plan.planInfo?.includedAmountCents)
        assertEquals("$20/mo", plan.planInfo?.price)
        assertEquals("1790439879000", plan.planInfo?.billingCycleEnd)
        assertEquals("Pro+", plan.nextUpgrade?.name)

        val cookieOnly = UsageApiClient(
            client = client,
            connectedCredentials = {
                ConnectedCredentials(cursorSessionToken = "cookie-only")
            },
        )
        assertTrue(cookieOnly.fetchCursorPlanInfo().isFailure)
    }

    @Test
    fun claudeProfileDecodesFixtureAndMapsPlanLabel() {
        val recorded = mutableListOf<okhttp3.Request>()
        val body = """
            {"account":{"has_claude_max":true,"has_claude_pro":false},
             "organization":{"organization_type":"claude_max","billing_type":"stripe_subscription",
             "rate_limit_tier":"default_claude_max_20x","subscription_status":"active",
             "subscription_created_at":"2026-04-10T15:53:44.244879Z",
             "has_extra_usage_enabled":true}}
        """.trimIndent()
        val client = recordingClient(recorded) { body }
        val api = UsageApiClient(
            client = client,
            claudeCredentials = {
                ClaudeCredentials(accessToken = "claude-access")
            },
        )

        val profile: ClaudeProfileResponse = api.fetchClaudeProfile().getOrThrow()

        val request = recorded.single()
        assertEquals(
            "https://api.anthropic.com/api/oauth/profile",
            request.url.toString(),
        )
        assertEquals("GET", request.method)
        assertEquals("Bearer claude-access", request.header("Authorization"))
        assertEquals("oauth-2025-04-20", request.header("anthropic-beta"))
        assertEquals("Max 20x", profile.planLabel)
        assertEquals(true, profile.account?.hasClaudeMax)
        assertEquals("active", profile.organization?.subscriptionStatus)

        val fiveX = """
            {"account":{"has_claude_max":true,"has_claude_pro":false},
             "organization":{"organization_type":"claude_max",
             "rate_limit_tier":"default_claude_max_5x"}}
        """.trimIndent()
        val fiveXClient = recordingClient(mutableListOf()) { fiveX }
        val fiveXProfile = UsageApiClient(
            client = fiveXClient,
            claudeCredentials = { ClaudeCredentials(accessToken = "claude-access") },
        ).fetchClaudeProfile().getOrThrow()
        assertEquals("Max 5x", fiveXProfile.planLabel)

        val pro = """
            {"account":{"has_claude_max":false,"has_claude_pro":true},
             "organization":{"organization_type":"claude_pro","rate_limit_tier":"claude_pro"}}
        """.trimIndent()
        val proClient = recordingClient(mutableListOf()) { pro }
        val proProfile = UsageApiClient(
            client = proClient,
            claudeCredentials = { ClaudeCredentials(accessToken = "claude-access") },
        ).fetchClaudeProfile().getOrThrow()
        assertEquals("Pro", proProfile.planLabel)

        val titled = """
            {"account":{},"organization":{"organization_type":"team_enterprise"}}
        """.trimIndent()
        val titledClient = recordingClient(mutableListOf()) { titled }
        val titledProfile = UsageApiClient(
            client = titledClient,
            claudeCredentials = { ClaudeCredentials(accessToken = "claude-access") },
        ).fetchClaudeProfile().getOrThrow()
        assertEquals("Team Enterprise", titledProfile.planLabel)
    }

    @Test
    fun v2ImportMergeLandsCodexAndCursorTokensBesideSessionFields() {
        // Carry-over from #49: UsageRepository.applyImportedPayload now calls
        // CredentialsStore.applyImportedConnections, which uses this merge.
        val current = ConnectedCredentials(
            openAISessionToken = "paste-openai",
            cursorSessionToken = "paste-cursor",
        )
        val imported = DeviceSyncConnections(
            openAISessionToken = "paste-openai",
            cursorSessionToken = "paste-cursor",
            codexAccessToken = "codex-cli",
            codexAccountId = "acct-1",
            cursorAccessToken = "cursor-cli",
        )

        val merged = current.mergingImported(imported)

        assertEquals("codex-cli", merged.codexAccessToken)
        assertEquals("acct-1", merged.codexAccountId)
        assertEquals("cursor-cli", merged.cursorAccessToken)
        assertEquals("codex-cli", merged.openAIBearer)
        assertTrue(merged.cursorAuth is com.agentusagebar.android.data.model.CursorAuth.CliToken)
    }

    private fun recordingClient(
        recorded: MutableList<okhttp3.Request>,
        body: () -> String,
    ): OkHttpClient {
        val interceptor = Interceptor { chain ->
            val request = chain.request()
            recorded += request
            Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(body().toResponseBody("application/json".toMediaType()))
                .build()
        }
        return OkHttpClient.Builder().addInterceptor(interceptor).build()
    }

    private fun okhttp3.Request.bodyUtf8(): String {
        val buffer = okio.Buffer()
        body?.writeTo(buffer)
        return buffer.readUtf8()
    }
}
