package com.agentusagebar.android.data.credentials

import android.content.Context
import java.io.File

/**
 * One-time wiper for provider tokens stored on the phone before #86.
 * Trusted devices live in a different encrypted prefs file.
 */
class CredentialsStore(private val context: Context) {
    fun wipeLegacyProviderCredentials() {
        val prefsDir = File(context.applicationInfo.dataDir, "shared_prefs")
        val exists = File(prefsDir, "$PREFS_NAME.xml").exists() ||
            File(prefsDir, PREFS_NAME).exists()
        if (!exists) return
        context.deleteSharedPreferences(PREFS_NAME)
    }

    companion object {
        const val PREFS_NAME = "agent_usage_bar_secure"
    }
}
