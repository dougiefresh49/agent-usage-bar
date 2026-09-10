package com.agentusagebar.android.data.network

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.agentusagebar.android.data.model.OpenAIResetCreditsResponse
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Redeems a Codex rate-limit reset credit with a deterministic UUIDv5 request id
 * shared with macOS (#46 / #58) so retries from either device dedupe server-side.
 *
 * Request JSON is built with kotlinx.serialization (not org.json) so JVM unit tests
 * do not hit Android's unmocked JSONObject stubs.
 */
class ResetCreditClient(
    private val pendingStore: PendingResetAttemptStore,
    private val httpClient: OkHttpClient = defaultClient(),
    private val consumeUrl: String = CONSUME_URL,
    private val creditsUrl: String = CREDITS_URL,
) {
    private val flightMutex = Mutex()
    private var inFlight = false

    fun uuidV5(namespace: UUID, name: String): UUID {
        val digest = MessageDigest.getInstance("SHA-1")
        digest.update(uuidToBytes(namespace))
        digest.update(name.toByteArray(Charsets.UTF_8))
        val hash = digest.digest()
        hash[6] = ((hash[6].toInt() and 0x0F) or 0x50).toByte()
        hash[8] = ((hash[8].toInt() and 0x3F) or 0x80).toByte()
        return bytesToUuid(hash.copyOf(16))
    }

    fun requestId(accountId: String?, creditId: String): UUID {
        val account = accountId?.takeIf { it.isNotBlank() } ?: "local"
        return uuidV5(NAMESPACE, "$account:$creditId")
    }

    /**
     * Lists reset credits with the CLI-precedence bearer so a CLI-only phone can
     * populate the Codex row without touching UsageApiClient.
     */
    fun fetchCredits(bearer: String, accountId: String?): OpenAIResetCreditsResponse {
        val builder = Request.Builder()
            .url(creditsUrl)
            .get()
            .header("Authorization", "Bearer $bearer")
            .header("Accept", "application/json")
        if (!accountId.isNullOrBlank()) {
            builder.header("Chatgpt-Account-Id", accountId)
        }
        httpClient.newCall(builder.build()).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw ResetCreditFailure.SendFailed("HTTP ${response.code}")
            }
            return CREDITS_JSON.decodeFromString(OpenAIResetCreditsResponse.serializer(), body)
        }
    }

    /**
     * Posts the consume call. Reuses a persisted request id after a failed send.
     * A second call while one is already in flight throws [ResetCreditFailure.InFlight].
     */
    suspend fun redeem(
        bearer: String,
        accountId: String?,
        creditId: String,
    ): ResetCreditOutcome {
        val acquired = flightMutex.withLock {
            if (inFlight) {
                false
            } else {
                inFlight = true
                true
            }
        }
        if (!acquired) throw ResetCreditFailure.InFlight

        try {
            val requestUuid = pendingStore.load()
                ?.takeIf { it.creditId == creditId }
                ?.let { UUID.fromString(it.requestId) }
                ?: requestId(accountId, creditId).also { id ->
                    pendingStore.save(
                        PendingResetAttempt(
                            creditId = creditId,
                            requestId = id.toString(),
                        ),
                    )
                }

            val bodyJson = JsonObject(
                mapOf(
                    "redeem_request_id" to JsonPrimitive(requestUuid.toString()),
                    "credit_id" to JsonPrimitive(creditId),
                ),
            ).toString()

            val builder = Request.Builder()
                .url(consumeUrl)
                .post(bodyJson.toRequestBody(JSON_MEDIA))
                .header("Authorization", "Bearer $bearer")
                .header("Content-Type", "application/json")
                .header("Accept", "application/json")
                .header("OpenAI-Beta", "codex-1")
                .header("Originator", "Codex Desktop")
            if (!accountId.isNullOrBlank()) {
                builder.header("Chatgpt-Account-Id", accountId)
            }

            val response = httpClient.newCall(builder.build()).execute()
            val responseBody = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw ResetCreditFailure.SendFailed("HTTP ${response.code}")
            }

            val code = runCatching {
                Json.parseToJsonElement(responseBody)
                    .jsonObject["code"]
                    ?.jsonPrimitive
                    ?.contentOrNull
            }.getOrNull()
                ?: throw ResetCreditFailure.SendFailed("Undecodable response")

            val outcome = ResetCreditOutcome.fromCode(code)
                ?: throw ResetCreditFailure.SendFailed("Unknown code: $code")

            pendingStore.clear()
            return outcome
        } catch (error: ResetCreditFailure) {
            throw error
        } catch (error: Exception) {
            throw ResetCreditFailure.SendFailed(error.message ?: "Redeem failed")
        } finally {
            flightMutex.withLock { inFlight = false }
        }
    }

    companion object {
        /** Shared with macOS (#46). Do not change. */
        val NAMESPACE: UUID = UUID.fromString("1b5476e9-b78c-4c12-a16e-bd64b2431354")

        /** RFC 4122 DNS namespace for the UUIDv5 test vector. */
        val DNS_NAMESPACE: UUID = UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

        private const val CONSUME_URL =
            "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume"
        private const val CREDITS_URL =
            "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
        private val JSON_MEDIA = "application/json".toMediaType()
        private val CREDITS_JSON = Json { ignoreUnknownKeys = true }

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .callTimeout(20, TimeUnit.SECONDS)
            .build()

        fun encryptedPendingStore(context: Context): PendingResetAttemptStore {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val prefs = EncryptedSharedPreferences.create(
                context,
                "agent_usage_bar_reset_credit_pending",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
            return SharedPreferencesPendingResetAttemptStore(prefs)
        }

        private fun uuidToBytes(uuid: UUID): ByteArray {
            val buffer = ByteBuffer.wrap(ByteArray(16))
            buffer.putLong(uuid.mostSignificantBits)
            buffer.putLong(uuid.leastSignificantBits)
            return buffer.array()
        }

        private fun bytesToUuid(bytes: ByteArray): UUID {
            val buffer = ByteBuffer.wrap(bytes)
            return UUID(buffer.long, buffer.long)
        }
    }
}

enum class ResetCreditOutcome(val code: String, val message: String) {
    RESET("reset", "Limits reset"),
    NOTHING_TO_RESET("nothing_to_reset", "Nothing to reset yet"),
    NO_CREDIT("no_credit", "No credit available"),
    ALREADY_REDEEMED("already_redeemed", "Already redeemed"),
    ;

    companion object {
        fun fromCode(code: String): ResetCreditOutcome? =
            entries.firstOrNull { it.code == code }
    }
}

/** Typed failure path for in-flight and send errors; redeem still returns [ResetCreditOutcome]. */
sealed class ResetCreditFailure(message: String) : Exception(message) {
    data object InFlight : ResetCreditFailure("Redeem already in flight")
    class SendFailed(message: String) : ResetCreditFailure(message)
}

data class PendingResetAttempt(
    val creditId: String,
    val requestId: String,
)

interface PendingResetAttemptStore {
    fun load(): PendingResetAttempt?
    fun save(attempt: PendingResetAttempt)
    fun clear()
}

class SharedPreferencesPendingResetAttemptStore(
    private val prefs: SharedPreferences,
) : PendingResetAttemptStore {
    override fun load(): PendingResetAttempt? {
        val creditId = prefs.getString(KEY_CREDIT_ID, null) ?: return null
        val requestId = prefs.getString(KEY_REQUEST_ID, null) ?: return null
        return PendingResetAttempt(creditId = creditId, requestId = requestId)
    }

    override fun save(attempt: PendingResetAttempt) {
        prefs.edit()
            .putString(KEY_CREDIT_ID, attempt.creditId)
            .putString(KEY_REQUEST_ID, attempt.requestId)
            .apply()
    }

    override fun clear() {
        prefs.edit()
            .remove(KEY_CREDIT_ID)
            .remove(KEY_REQUEST_ID)
            .apply()
    }

    companion object {
        private const val KEY_CREDIT_ID = "pending_credit_id"
        private const val KEY_REQUEST_ID = "pending_request_id"
    }
}
