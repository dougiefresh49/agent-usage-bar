package com.agentusagebar.android.data.credentials

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.model.UsageTextSize
import com.agentusagebar.android.data.sync.DeviceSyncPayload
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "agent_usage_bar_settings",
)

data class AppSettings(
    val pollingMinutes: Int = 30,
    val setupComplete: Boolean = false,
    val widgetProvider: UsageProvider = UsageProvider.CLAUDE,
    val detailStyle: DetailVisualizationStyle = DetailVisualizationStyle.BARS,
    val textSize: UsageTextSize = UsageTextSize.COMFORTABLE,
    val claudeSessionThreshold: Int = 80,
    val claudeSevenDayThreshold: Int = 0,
    val claudeFableThreshold: Int = 0,
    val openAIWeeklyThreshold: Int = 0,
    val openAIResetCreditsThreshold: Int = 0,
    val cursorAPIThreshold: Int = 0,
    val cursorAutoThreshold: Int = 0,
    val cursorCreditThreshold: Int = 0,
)

class SettingsStore(private val context: Context) {
    val settings: Flow<AppSettings> = context.settingsDataStore.data.map { prefs ->
        AppSettings(
            pollingMinutes = prefs[KEY_POLLING]?.takeIf { it in POLLING_OPTIONS } ?: 30,
            setupComplete = prefs[KEY_SETUP] ?: false,
            widgetProvider = prefs[KEY_WIDGET_PROVIDER]
                ?.let { runCatching { UsageProvider.valueOf(it) }.getOrNull() }
                ?: UsageProvider.CLAUDE,
            detailStyle = prefs[KEY_DETAIL_STYLE]
                ?.let { runCatching { DetailVisualizationStyle.valueOf(it) }.getOrNull() }
                ?: DetailVisualizationStyle.BARS,
            textSize = prefs[KEY_TEXT_SIZE]
                ?.let { runCatching { UsageTextSize.valueOf(it) }.getOrNull() }
                ?: UsageTextSize.COMFORTABLE,
            claudeSessionThreshold = prefs[KEY_CLAUDE_SESSION] ?: prefs[KEY_LEGACY_5H] ?: 80,
            claudeSevenDayThreshold = prefs[KEY_CLAUDE_SEVEN_DAY] ?: prefs[KEY_LEGACY_7D] ?: 0,
            claudeFableThreshold = prefs[KEY_CLAUDE_FABLE] ?: 0,
            openAIWeeklyThreshold = prefs[KEY_OPENAI_WEEKLY] ?: 0,
            openAIResetCreditsThreshold = prefs[KEY_OPENAI_RESET_CREDITS] ?: 0,
            cursorAPIThreshold = prefs[KEY_CURSOR_API] ?: 0,
            cursorAutoThreshold = prefs[KEY_CURSOR_AUTO] ?: 0,
            cursorCreditThreshold = prefs[KEY_CURSOR_CREDIT] ?: 0,
        )
    }

    suspend fun setPollingMinutes(minutes: Int) {
        context.settingsDataStore.edit { it[KEY_POLLING] = minutes }
    }

    suspend fun setSetupComplete(complete: Boolean) {
        context.settingsDataStore.edit { it[KEY_SETUP] = complete }
    }

    suspend fun setWidgetProvider(provider: UsageProvider) {
        context.settingsDataStore.edit { it[KEY_WIDGET_PROVIDER] = provider.name }
    }

    suspend fun setDetailStyle(style: DetailVisualizationStyle) {
        context.settingsDataStore.edit { it[KEY_DETAIL_STYLE] = style.name }
    }

    suspend fun setTextSize(size: UsageTextSize) {
        context.settingsDataStore.edit { it[KEY_TEXT_SIZE] = size.name }
    }

    suspend fun setClaudeSessionThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_CLAUDE_SESSION] = value }
    }

    suspend fun setClaudeSevenDayThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_CLAUDE_SEVEN_DAY] = value }
    }

    suspend fun setClaudeFableThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_CLAUDE_FABLE] = value }
    }

    suspend fun setOpenAIWeeklyThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_OPENAI_WEEKLY] = value }
    }

    suspend fun setOpenAIResetCreditsThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_OPENAI_RESET_CREDITS] = value }
    }

    suspend fun setCursorAPIThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_CURSOR_API] = value }
    }

    suspend fun setCursorAutoThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_CURSOR_AUTO] = value }
    }

    suspend fun setCursorCreditThreshold(value: Int) {
        context.settingsDataStore.edit { it[KEY_CURSOR_CREDIT] = value }
    }

    suspend fun applyDeviceSync(payload: DeviceSyncPayload) {
        context.settingsDataStore.edit { prefs ->
            payload.general?.let { general ->
                if (general.pollingMinutes in POLLING_OPTIONS) {
                    prefs[KEY_POLLING] = general.pollingMinutes
                }
            }
            payload.appearance?.let { appearance ->
                providerFromMacValue(appearance.preferredProvider)?.let {
                    prefs[KEY_WIDGET_PROVIDER] = it.name
                }
                enumValueOrNull<DetailVisualizationStyle>(appearance.detailStyle)?.let {
                    prefs[KEY_DETAIL_STYLE] = it.name
                }
                enumValueOrNull<UsageTextSize>(appearance.textSize)?.let {
                    prefs[KEY_TEXT_SIZE] = it.name
                }
            }
            payload.notifications?.let { notifications ->
                prefs[KEY_CLAUDE_SESSION] = notifications.claudeSession.coerceIn(0, 100)
                prefs[KEY_CLAUDE_SEVEN_DAY] = notifications.claudeSevenDay.coerceIn(0, 100)
                prefs[KEY_CLAUDE_FABLE] = notifications.claudeFable.coerceIn(0, 100)
                prefs[KEY_OPENAI_WEEKLY] = notifications.openAIWeekly.coerceIn(0, 100)
                prefs[KEY_OPENAI_RESET_CREDITS] =
                    notifications.openAIResetCredits.coerceIn(0, 10)
                prefs[KEY_CURSOR_API] = notifications.cursorAPI.coerceIn(0, 100)
                prefs[KEY_CURSOR_AUTO] = notifications.cursorAuto.coerceIn(0, 100)
                prefs[KEY_CURSOR_CREDIT] = notifications.cursorCredit.coerceIn(0, 100)
            }
            prefs[KEY_SETUP] = true
        }
    }

    private inline fun <reified T : Enum<T>> enumValueOrNull(rawValue: String): T? =
        enumValues<T>().firstOrNull { it.name.equals(rawValue, ignoreCase = true) }

    private fun providerFromMacValue(rawValue: String): UsageProvider? = when (rawValue) {
        "claude" -> UsageProvider.CLAUDE
        "openAI" -> UsageProvider.OPENAI
        "cursor" -> UsageProvider.CURSOR
        "elevenLabs" -> UsageProvider.ELEVENLABS
        else -> null
    }

    companion object {
        val POLLING_OPTIONS = listOf(5, 15, 30, 60)
        private val KEY_POLLING = intPreferencesKey("polling_minutes")
        private val KEY_SETUP = booleanPreferencesKey("setup_complete")
        private val KEY_WIDGET_PROVIDER = stringPreferencesKey("widget_provider")
        private val KEY_DETAIL_STYLE = stringPreferencesKey("detail_style")
        private val KEY_TEXT_SIZE = stringPreferencesKey("text_size")
        private val KEY_CLAUDE_SESSION = intPreferencesKey("threshold_claude_session")
        private val KEY_CLAUDE_SEVEN_DAY = intPreferencesKey("threshold_claude_seven_day")
        private val KEY_CLAUDE_FABLE = intPreferencesKey("threshold_claude_fable")
        private val KEY_OPENAI_WEEKLY = intPreferencesKey("threshold_openai_weekly")
        private val KEY_OPENAI_RESET_CREDITS = intPreferencesKey("threshold_openai_reset_credits")
        private val KEY_CURSOR_API = intPreferencesKey("threshold_cursor_api")
        private val KEY_CURSOR_AUTO = intPreferencesKey("threshold_cursor_auto")
        private val KEY_CURSOR_CREDIT = intPreferencesKey("threshold_cursor_credit")
        private val KEY_LEGACY_5H = intPreferencesKey("threshold_5h")
        private val KEY_LEGACY_7D = intPreferencesKey("threshold_7d")
    }
}
