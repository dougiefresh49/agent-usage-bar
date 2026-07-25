package com.agentusagebar.android.data.sync

import android.content.Context
import android.os.Build
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class TrustedDesktopDevice(
    val desktopID: String,
    val desktopName: String,
    val host: String,
    val port: Int,
    val desktopPublicKey: String,
    val deviceID: String,
    val deviceName: String,
    val privateKey: String,
    val devicePublicKey: String? = null,
    val pairedAtEpochMs: Long,
    val lastCheckedAtEpochMs: Long? = null,
    val revokedAtEpochMs: Long? = null,
    val openAITokenHash: String? = null,
    val cursorTokenHash: String? = null,
    val elevenLabsKeyHash: String? = null,
)

class TrustedDeviceStore(context: Context) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "agent_usage_bar_trusted_devices",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun load(): List<TrustedDesktopDevice> {
        val raw = prefs.getString(KEY_DEVICES, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<TrustedDesktopDevice>>(raw) }
            .getOrDefault(emptyList())
    }

    fun save(device: TrustedDesktopDevice) {
        val current = load()
        val previous = current.firstOrNull { it.desktopID == device.desktopID }
        val merged = device.copy(
            openAITokenHash = device.openAITokenHash ?: previous?.openAITokenHash,
            cursorTokenHash = device.cursorTokenHash ?: previous?.cursorTokenHash,
            elevenLabsKeyHash = device.elevenLabsKeyHash ?: previous?.elevenLabsKeyHash,
        )
        val devices = current.filterNot { it.desktopID == device.desktopID } + merged
        prefs.edit().putString(KEY_DEVICES, json.encodeToString(devices)).apply()
    }

    fun markChecked(desktopID: String, revoked: Boolean) {
        val now = System.currentTimeMillis()
        val devices = load().map {
            if (it.desktopID == desktopID) {
                it.copy(
                    lastCheckedAtEpochMs = now,
                    revokedAtEpochMs = if (revoked) now else it.revokedAtEpochMs,
                )
            } else {
                it
            }
        }
        prefs.edit().putString(KEY_DEVICES, json.encodeToString(devices)).apply()
    }

    companion object {
        fun androidDeviceName(): String {
            val manufacturer = Build.MANUFACTURER
                .replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            return "$manufacturer ${Build.MODEL}".trim().take(80)
        }

        private const val KEY_DEVICES = "trusted_desktops"
    }
}
