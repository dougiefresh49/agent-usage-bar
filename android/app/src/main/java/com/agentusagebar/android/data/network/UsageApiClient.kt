package com.agentusagebar.android.data.network

import com.agentusagebar.android.data.credentials.CredentialsStore
import com.agentusagebar.android.data.model.ClaudeCredentials
import com.agentusagebar.android.data.model.ClaudeUsageResponse
import com.agentusagebar.android.data.model.CursorUsageResponse
import com.agentusagebar.android.data.model.ElevenLabsSubscriptionResponse
import com.agentusagebar.android.data.model.OpenAIUsageResponse
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

class UsageApiClient(
    private val credentialsStore: CredentialsStore,
    private val client: OkHttpClient = defaultClient(),
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    },
) {
    private var codeVerifier: String? = null
    private var oauthState: String? = null

    fun isClaudeConfigured(): Boolean = credentialsStore.loadClaude() != null
    fun isOpenAIConfigured(): Boolean =
        !credentialsStore.loadConnected().openAISessionToken.isNullOrBlank()

    fun isCursorConfigured(): Boolean =
        !credentialsStore.loadConnected().cursorSessionToken.isNullOrBlank()

    fun isElevenLabsConfigured(): Boolean =
        !credentialsStore.loadConnected().elevenLabsAPIKey.isNullOrBlank()

    fun startClaudeOAuthUrl(): String {
        val verifier = generateCodeVerifier()
        val state = generateCodeVerifier()
        codeVerifier = verifier
        oauthState = state
        val challenge = generateCodeChallenge(verifier)
        return buildString {
            append(AUTHORIZE_ENDPOINT)
            append("?code=true")
            append("&client_id=").append(CLIENT_ID)
            append("&response_type=code")
            append("&redirect_uri=").append(java.net.URLEncoder.encode(REDIRECT_URI, "UTF-8"))
            append("&scope=").append(
                java.net.URLEncoder.encode(DEFAULT_SCOPES.joinToString(" "), "UTF-8"),
            )
            append("&code_challenge=").append(challenge)
            append("&code_challenge_method=S256")
            append("&state=").append(state)
        }
    }

    fun pendingOAuthState(): String? = oauthState

    fun exchangeClaudeCode(rawCode: String): Result<Unit> = runCatching {
        val parts = rawCode.trim().split("#", limit = 2)
        val code = parts.firstOrNull().orEmpty()
        require(code.isNotBlank()) { "No OAuth code entered" }

        if (parts.size > 1) {
            require(parts[1] == oauthState) { "OAuth state mismatch — try again" }
        }

        val verifier = codeVerifier ?: error("No pending OAuth flow")
        val body = """
            {
              "grant_type":"authorization_code",
              "code":${code.jsonQuote()},
              "state":${(oauthState ?: "").jsonQuote()},
              "client_id":${CLIENT_ID.jsonQuote()},
              "redirect_uri":${REDIRECT_URI.jsonQuote()},
              "code_verifier":${verifier.jsonQuote()}
            }
        """.trimIndent()

        val request = Request.Builder()
            .url(TOKEN_ENDPOINT)
            .post(body.toRequestBody(JSON_MEDIA))
            .header("Content-Type", "application/json")
            .build()

        client.newCall(request).execute().use { response ->
            val responseBody = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                error("Token exchange failed: HTTP ${response.code} $responseBody")
            }
            val credentials = parseTokenResponse(responseBody)
                ?: error("Could not parse token response")
            credentialsStore.saveClaude(credentials)
            codeVerifier = null
            oauthState = null
        }
    }

    fun signOutClaude() {
        credentialsStore.clearClaude()
        codeVerifier = null
        oauthState = null
    }

    fun fetchClaudeUsage(): Result<ClaudeUsageResponse> = runCatching {
        val data = sendAuthorizedGet(USAGE_ENDPOINT)
        json.decodeFromString<ClaudeUsageResponse>(data)
    }

    fun fetchClaudeProfileEmail(): String? = runCatching {
        val data = sendAuthorizedGet(USERINFO_ENDPOINT, expireOnAuthFailure = false)
        val obj = json.parseToJsonElement(data).jsonObject
        obj["email"]?.jsonPrimitive?.contentOrNull
            ?: obj["name"]?.jsonPrimitive?.contentOrNull
    }.getOrNull()

    fun fetchOpenAIUsage(): Result<OpenAIUsageResponse> = runCatching {
        val token = credentialsStore.loadConnected().openAISessionToken
            ?: error("OpenAI not configured")
        val request = Request.Builder()
            .url(OPENAI_USAGE_ENDPOINT)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw httpError("OpenAI", response.code)
            }
            json.decodeFromString<OpenAIUsageResponse>(body)
        }
    }

    fun fetchCursorUsage(): Result<CursorUsageResponse> = runCatching {
        val token = credentialsStore.loadConnected().cursorSessionToken
            ?: error("Cursor not configured")
        val request = Request.Builder()
            .url(CURSOR_USAGE_ENDPOINT)
            .post("{}".toRequestBody(JSON_MEDIA))
            .header("Content-Type", "application/json")
            .header("Origin", "https://cursor.com")
            .header("Referer", "https://cursor.com/dashboard?tab=spending")
            .header("Cookie", "WorkosCursorSessionToken=$token")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw httpError("Cursor", response.code)
            }
            json.decodeFromString<CursorUsageResponse>(body)
        }
    }

    fun fetchElevenLabsUsage(): Result<ElevenLabsSubscriptionResponse> = runCatching {
        val apiKey = credentialsStore.loadConnected().elevenLabsAPIKey
            ?: error("ElevenLabs not configured")
        val request = Request.Builder()
            .url(ELEVENLABS_SUBSCRIPTION_ENDPOINT)
            .header("xi-api-key", apiKey)
            .header("Accept", "application/json")
            .build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw httpError("ElevenLabs", response.code)
            }
            json.decodeFromString<ElevenLabsSubscriptionResponse>(body)
        }
    }

    private fun sendAuthorizedGet(
        url: String,
        expireOnAuthFailure: Boolean = true,
    ): String {
        var credentials = credentialsStore.loadClaude()
            ?: error("Not signed in")

        if (credentials.needsRefresh()) {
            val refreshed = refreshClaude(force = true)
            if (!refreshed && credentials.isExpired()) {
                if (expireOnAuthFailure) {
                    credentialsStore.clearClaude()
                    error("Session expired — please sign in again")
                }
                error("Token refresh failed")
            }
            credentials = credentialsStore.loadClaude() ?: credentials
        }

        var responseCode: Int
        var body: String
        client.newCall(authorizedRequest(url, credentials.accessToken)).execute().use { response ->
            responseCode = response.code
            body = response.body?.string().orEmpty()
        }

        if (responseCode != 401) {
            if (responseCode !in 200..299) {
                error("HTTP $responseCode")
            }
            return body
        }

        if (!refreshClaude(force = true)) {
            if (expireOnAuthFailure) {
                credentialsStore.clearClaude()
                error("Session expired — please sign in again")
            }
            error("Token refresh failed")
        }

        val refreshed = credentialsStore.loadClaude() ?: error("Not signed in")
        client.newCall(authorizedRequest(url, refreshed.accessToken)).execute().use { response ->
            if (response.code == 401) {
                if (expireOnAuthFailure) {
                    credentialsStore.clearClaude()
                    error("Session expired — please sign in again")
                }
                error("Unauthorized")
            }
            if (!response.isSuccessful) error("HTTP ${response.code}")
            return response.body?.string().orEmpty()
        }
    }

    private fun refreshClaude(force: Boolean): Boolean {
        val current = credentialsStore.loadClaude() ?: return false
        val refreshToken = current.refreshToken
        if (refreshToken.isNullOrBlank()) return false
        if (!force && !current.needsRefresh()) return true

        val body = buildString {
            append("{")
            append("\"grant_type\":\"refresh_token\",")
            append("\"refresh_token\":${refreshToken.jsonQuote()},")
            append("\"client_id\":${CLIENT_ID.jsonQuote()}")
            if (current.scopes.isNotEmpty()) {
                append(",\"scope\":${current.scopes.joinToString(" ").jsonQuote()}")
            }
            append("}")
        }

        val request = Request.Builder()
            .url(TOKEN_ENDPOINT)
            .post(body.toRequestBody(JSON_MEDIA))
            .header("Content-Type", "application/json")
            .build()

        return runCatching {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return response.code !in 400..499
                }
                val updated = parseTokenResponse(
                    response.body?.string().orEmpty(),
                    fallback = current,
                ) ?: return false
                credentialsStore.saveClaude(updated)
                true
            }
        }.getOrDefault(false)
    }

    private fun authorizedRequest(url: String, token: String): Request =
        Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .header("anthropic-beta", "oauth-2025-04-20")
            .build()

    private fun parseTokenResponse(
        body: String,
        fallback: ClaudeCredentials? = null,
    ): ClaudeCredentials? {
        val obj = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            ?: return null
        val accessToken = obj["access_token"]?.jsonPrimitive?.contentOrNull
            ?.takeIf { it.isNotBlank() }
            ?: return null
        val refreshToken = obj["refresh_token"]?.jsonPrimitive?.contentOrNull
            ?: fallback?.refreshToken
        val scopeString = obj["scope"]?.jsonPrimitive?.contentOrNull
        val scopes = scopeString
            ?.split(Regex("\\s+"))
            ?.filter { it.isNotBlank() }
            ?: fallback?.scopes
            ?: DEFAULT_SCOPES
        val expiresIn = obj["expires_in"].asDoubleOrNull()
        val expiresAt = expiresIn?.let { System.currentTimeMillis() + (it * 1000).toLong() }
            ?: fallback?.expiresAtEpochMs
        return ClaudeCredentials(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAtEpochMs = expiresAt,
            scopes = scopes,
        )
    }

    @OptIn(ExperimentalEncodingApi::class)
    private fun generateCodeVerifier(): String {
        val bytes = ByteArray(32)
        java.security.SecureRandom().nextBytes(bytes)
        return Base64.UrlSafe.encode(bytes).trimEnd('=')
    }

    @OptIn(ExperimentalEncodingApi::class)
    private fun generateCodeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
        return Base64.UrlSafe.encode(digest).trimEnd('=')
    }

    private fun httpError(service: String, code: Int): IllegalStateException {
        val message = when {
            code == 401 || code == 403 -> if (service == "ElevenLabs") {
                "ElevenLabs API key was rejected — update it in Settings"
            } else {
                "$service session expired — update it in Settings"
            }
            else -> "$service HTTP $code"
        }
        return IllegalStateException(message)
    }

    private fun String.jsonQuote(): String = JsonPrimitive(this).toString()

    private fun kotlinx.serialization.json.JsonElement?.asDoubleOrNull(): Double? {
        val primitive = this as? JsonPrimitive ?: return null
        return primitive.doubleOrNull
            ?: primitive.intOrNull?.toDouble()
            ?: primitive.contentOrNull?.toDoubleOrNull()
    }

    companion object {
        private val JSON_MEDIA = "application/json".toMediaType()
        private const val CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        private const val REDIRECT_URI = "https://platform.claude.com/oauth/code/callback"
        private const val AUTHORIZE_ENDPOINT = "https://claude.ai/oauth/authorize"
        private const val TOKEN_ENDPOINT = "https://platform.claude.com/v1/oauth/token"
        private const val USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
        private const val USERINFO_ENDPOINT = "https://api.anthropic.com/api/oauth/userinfo"
        private const val OPENAI_USAGE_ENDPOINT = "https://chatgpt.com/backend-api/wham/usage"
        private const val CURSOR_USAGE_ENDPOINT =
            "https://cursor.com/api/dashboard/get-current-period-usage"
        private const val ELEVENLABS_SUBSCRIPTION_ENDPOINT =
            "https://api.elevenlabs.io/v1/user/subscription"
        private val DEFAULT_SCOPES = listOf("user:profile", "user:inference")

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }
}
