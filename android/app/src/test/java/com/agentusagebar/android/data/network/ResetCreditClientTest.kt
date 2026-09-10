package com.agentusagebar.android.data.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * OkHttp interceptor fake stands in for MockWebServer: build.gradle.kts is outside
 * this lane's file ownership, so mockwebserver is not on the test classpath.
 */
class ResetCreditClientTest {

    @Test
    fun uuidV5MatchesRfcDnsVector() {
        val client = ResetCreditClient(InMemoryPendingResetAttemptStore())
        // Task text lists a trailing hex that does not match RFC/stdlib for this
        // name; assert the real DNS + www.example.com value.
        assertEquals(
            UUID.fromString("2ed6657d-e927-568b-95e1-2665a8aea6a2"),
            client.uuidV5(ResetCreditClient.DNS_NAMESPACE, "www.example.com"),
        )
    }

    @Test
    fun requestIdIsDeterministicAndUsesLocalFallback() {
        val client = ResetCreditClient(InMemoryPendingResetAttemptStore())
        val localA = client.requestId(null, "credit-1")
        val localB = client.requestId("", "credit-1")
        val named = client.requestId("acct-9", "credit-1")
        assertEquals(localA, localB)
        assertEquals(UUID.fromString("3c692655-5852-5c02-8e79-b5693af4e815"), localA)
        assertEquals(UUID.fromString("02c3b28a-4c92-5a41-811a-25d822fc021a"), named)
        assertNotEquals(localA, named)
    }

    @Test
    fun redeemSendsExpectedRequestShape() = runBlocking {
        val recorded = CopyOnWriteArrayList<okhttp3.Request>()
        val http = fakeClient { request ->
            recorded += request
            jsonResponse(request, 200, """{"code":"reset"}""")
        }
        val client = ResetCreditClient(
            pendingStore = InMemoryPendingResetAttemptStore(),
            httpClient = http,
            consumeUrl = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume",
        )

        val result = client.redeem(
            bearer = "tok_test",
            accountId = "acct-9",
            creditId = "credit-1",
        )

        assertTrue(result is ResetCreditRedeemResult.Completed)
        assertEquals(
            ResetCreditOutcome.RESET,
            (result as ResetCreditRedeemResult.Completed).outcome,
        )
        assertEquals(1, recorded.size)
        val req = recorded.first()
        assertEquals("POST", req.method)
        assertEquals(
            "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume",
            req.url.toString(),
        )
        assertEquals("Bearer tok_test", req.header("Authorization"))
        assertEquals("application/json", req.header("Content-Type"))
        assertEquals("application/json", req.header("Accept"))
        assertEquals("codex-1", req.header("OpenAI-Beta"))
        assertEquals("Codex Desktop", req.header("Originator"))
        assertEquals("acct-9", req.header("Chatgpt-Account-Id"))
        val body = Json.parseToJsonElement(req.body!!.utf8()).jsonObject
        assertEquals("credit-1", body.getValue("credit_id").jsonPrimitive.content)
        assertEquals(
            client.requestId("acct-9", "credit-1").toString(),
            body.getValue("redeem_request_id").jsonPrimitive.content,
        )
    }

    @Test
    fun redeemDecodesEachOutcome() = runBlocking {
        for (outcome in ResetCreditOutcome.entries) {
            val http = fakeClient { request ->
                jsonResponse(request, 200, """{"code":"${outcome.code}"}""")
            }
            val client = ResetCreditClient(InMemoryPendingResetAttemptStore(), http)
            val result = client.redeem("tok", null, "c-${outcome.code}")
            assertTrue(result is ResetCreditRedeemResult.Completed)
            assertEquals(outcome, (result as ResetCreditRedeemResult.Completed).outcome)
        }
    }

    @Test
    fun pendingIdReusedAfterFailedSend() = runBlocking {
        val store = InMemoryPendingResetAttemptStore()
        val bodies = CopyOnWriteArrayList<String>()
        val calls = AtomicInteger(0)
        val http = fakeClient { request ->
            val n = calls.incrementAndGet()
            bodies += request.body!!.utf8()
            if (n == 1) {
                jsonResponse(request, 500, """{"error":"boom"}""")
            } else {
                jsonResponse(request, 200, """{"code":"reset"}""")
            }
        }
        val client = ResetCreditClient(store, http)

        val first = client.redeem("tok", "acct-9", "credit-1")
        assertTrue(first is ResetCreditRedeemResult.Failed)
        assertEquals("credit-1", store.load()!!.creditId)

        val second = client.redeem("tok", "acct-9", "credit-1")
        assertTrue(second is ResetCreditRedeemResult.Completed)
        assertNull(store.load())

        val id1 = Json.parseToJsonElement(bodies[0]).jsonObject
            .getValue("redeem_request_id").jsonPrimitive.content
        val id2 = Json.parseToJsonElement(bodies[1]).jsonObject
            .getValue("redeem_request_id").jsonPrimitive.content
        assertEquals(id1, id2)
        assertEquals(client.requestId("acct-9", "credit-1").toString(), id1)
    }

    @Test
    fun singleFlightReturnsInFlight() = runBlocking {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val http = fakeClient { request ->
            started.countDown()
            assertTrue(release.await(5, TimeUnit.SECONDS))
            jsonResponse(request, 200, """{"code":"reset"}""")
        }
        val client = ResetCreditClient(InMemoryPendingResetAttemptStore(), http)

        // Run the in-flight call on IO so the OkHttp interceptor can block without
        // stalling this coroutine before the second redeem runs.
        val first = async(Dispatchers.IO) { client.redeem("tok", null, "credit-1") }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        assertEquals(ResetCreditRedeemResult.InFlight, client.redeem("tok", null, "credit-1"))
        release.countDown()
        assertTrue(first.await() is ResetCreditRedeemResult.Completed)
    }

    private fun fakeClient(handler: (okhttp3.Request) -> Response): OkHttpClient =
        OkHttpClient.Builder()
            .addInterceptor(Interceptor { chain -> handler(chain.request()) })
            .build()

    private fun jsonResponse(request: okhttp3.Request, code: Int, body: String): Response =
        Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(code)
            .message(if (code in 200..299) "OK" else "ERR")
            .body(body.toResponseBody("application/json".toMediaType()))
            .build()

    private fun okhttp3.RequestBody.utf8(): String {
        val buffer = okio.Buffer()
        writeTo(buffer)
        return buffer.readUtf8()
    }
}
