package com.agentusagebar.android.data.credentials

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.agentusagebar.android.data.model.ClaudeCredentials
import com.agentusagebar.android.data.model.ConnectedCredentials
import com.agentusagebar.android.data.sync.DeviceSyncCodec
import com.agentusagebar.android.data.sync.TrustedDesktopDevice
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class CredentialsStore(context: Context) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "agent_usage_bar_secure",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun loadClaude(): ClaudeCredentials? {
        val raw = prefs.getString(KEY_CLAUDE, null) ?: return null
        return runCatching { json.decodeFromString<ClaudeCredentials>(raw) }.getOrNull()
    }

    fun saveClaude(credentials: ClaudeCredentials) {
        prefs.edit().putString(KEY_CLAUDE, json.encodeToString(credentials)).apply()
    }

    fun clearClaude() {
        prefs.edit().remove(KEY_CLAUDE).apply()
    }

    fun loadConnected(): ConnectedCredentials {
        val raw = prefs.getString(KEY_CONNECTED, null) ?: return ConnectedCredentials()
        return runCatching { json.decodeFromString<ConnectedCredentials>(raw) }
            .getOrDefault(ConnectedCredentials())
    }

    fun saveConnected(credentials: ConnectedCredentials) {
        if (credentials.isEmpty) {
            prefs.edit().remove(KEY_CONNECTED).apply()
            return
        }
        prefs.edit().putString(KEY_CONNECTED, json.encodeToString(credentials)).apply()
    }

    fun wipeCredentialsImportedFrom(device: TrustedDesktopDevice): Boolean {
        val current = loadConnected()
        val updated = current.copy(
            openAISessionToken = current.openAISessionToken.clearIfMatching(
                device.openAITokenHash,
            ),
            cursorSessionToken = current.cursorSessionToken.clearIfMatching(
                device.cursorTokenHash,
            ),
            elevenLabsAPIKey = current.elevenLabsAPIKey.clearIfMatching(
                device.elevenLabsKeyHash,
            ),
        )
        val changed = updated != current
        if (changed) saveConnected(updated)
        return changed
    }

    private fun String?.clearIfMatching(importedHash: String?): String? {
        if (this == null || importedHash == null) return this
        return if (DeviceSyncCodec.credentialHash(this) == importedHash) null else this
    }

    companion object {
        private const val KEY_CLAUDE = "claude_credentials"
        private const val KEY_CONNECTED = "connected_credentials"
    }
}

object TokenNormalizer {
    private val authHeaderRegex =
        Regex("""(?i)authorization:\s*(?:bearer\s+)?([^'"\s\\]+)""")
    private val cursorCookieRegex =
        Regex("""(?i)WorkosCursorSessionToken=([^;'"\\\s]+)""")
    private val bearerPrefixRegex = Regex("""(?i)^bearer\s+""")

    fun openAI(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null
        authHeaderRegex.find(trimmed)?.groupValues?.getOrNull(1)?.let { return it }
        return trimmed.replace(bearerPrefixRegex, "")
    }

    fun cursor(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null
        cursorCookieRegex.find(trimmed)?.groupValues?.getOrNull(1)?.let { return it }
        return trimmed
    }

    fun elevenLabs(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null
        xiApiKeyRegex.find(trimmed)?.groupValues?.getOrNull(1)?.let { return it }
        envKeyRegex.find(trimmed)?.groupValues?.getOrNull(1)?.let { return it }
        return trimmed
    }

    private val xiApiKeyRegex = Regex("""(?i)xi-api-key:\s*([^'"\s\\]+)""")
    private val envKeyRegex = Regex("""(?i)ELEVENLABS_API_KEY\s*=\s*['"]?([^'"\s\\]+)""")
}
