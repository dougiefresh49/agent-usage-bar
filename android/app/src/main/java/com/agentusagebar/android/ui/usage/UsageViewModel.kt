package com.agentusagebar.android.ui.usage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.agentusagebar.android.data.credentials.AppSettings
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.repository.UsageRepository
import com.agentusagebar.android.worker.UsageRefreshScheduler
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class UsageViewModel(
    private val repository: UsageRepository,
) : ViewModel() {
    val snapshot: StateFlow<AppUsageSnapshot> = repository.snapshot
    val settings: StateFlow<AppSettings> = repository.settings.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        AppSettings(),
    )
    val isRefreshing = repository.isRefreshing
    val awaitingClaudeCode = repository.awaitingClaudeCode
    val claudeEmail = repository.claudeEmail

    private val _selectedProvider = MutableStateFlow(UsageProvider.CLAUDE)
    val selectedProvider = _selectedProvider.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message = _message.asStateFlow()

    private val _claudeCode = MutableStateFlow("")
    val claudeCode = _claudeCode.asStateFlow()

    init {
        viewModelScope.launch {
            repository.refreshAll()
            UsageRefreshScheduler.ensureScheduled(AgentUsageBarAppHolder.context())
        }
    }

    fun selectProvider(provider: UsageProvider) {
        _selectedProvider.value = provider
    }

    fun setClaudeCode(value: String) {
        _claudeCode.value = value
    }

    fun refresh() {
        viewModelScope.launch { repository.refreshAll() }
    }

    fun startClaudeOAuth(): String = repository.startClaudeOAuth()

    fun cancelClaudeOAuth() {
        repository.cancelClaudeOAuth()
        _claudeCode.value = ""
    }

    fun submitClaudeCode() {
        viewModelScope.launch {
            repository.submitClaudeCode(_claudeCode.value)
                .onSuccess {
                    _claudeCode.value = ""
                    _message.value = "Claude connected."
                }
                .onFailure { _message.value = it.message }
        }
    }

    fun signOutClaude() {
        viewModelScope.launch { repository.signOutClaude() }
    }

    fun saveOpenAIToken(token: String) {
        viewModelScope.launch {
            repository.saveOpenAIToken(token)
                .onSuccess { _message.value = "OpenAI session token saved locally." }
                .onFailure { _message.value = it.message }
        }
    }

    fun saveCursorToken(token: String) {
        viewModelScope.launch {
            repository.saveCursorToken(token)
                .onSuccess { _message.value = "Cursor session token saved locally." }
                .onFailure { _message.value = it.message }
        }
    }

    fun clearOpenAIToken() {
        viewModelScope.launch { repository.clearOpenAIToken() }
    }

    fun clearCursorToken() {
        viewModelScope.launch { repository.clearCursorToken() }
    }

    fun saveElevenLabsAPIKey(key: String) {
        viewModelScope.launch {
            repository.saveElevenLabsAPIKey(key)
                .onSuccess { _message.value = "ElevenLabs API key saved locally." }
                .onFailure { _message.value = it.message }
        }
    }

    fun clearElevenLabsAPIKey() {
        viewModelScope.launch { repository.clearElevenLabsAPIKey() }
    }

    fun setPollingMinutes(minutes: Int) {
        viewModelScope.launch {
            repository.setPollingMinutes(minutes)
            UsageRefreshScheduler.ensureScheduled(
                AgentUsageBarAppHolder.context(),
                forceReschedule = true,
            )
        }
    }

    fun completeSetup() {
        viewModelScope.launch { repository.setSetupComplete(true) }
    }

    fun setWidgetProvider(provider: UsageProvider) {
        viewModelScope.launch { repository.setWidgetProvider(provider) }
    }

    fun setDetailStyle(style: com.agentusagebar.android.data.model.DetailVisualizationStyle) {
        viewModelScope.launch { repository.setDetailStyle(style) }
    }

    fun setTextSize(size: com.agentusagebar.android.data.model.UsageTextSize) {
        viewModelScope.launch { repository.setTextSize(size) }
    }

    fun setClaudeSessionThreshold(value: Int) {
        viewModelScope.launch { repository.setClaudeSessionThreshold(value) }
    }

    fun setClaudeSevenDayThreshold(value: Int) {
        viewModelScope.launch { repository.setClaudeSevenDayThreshold(value) }
    }

    fun setClaudeFableThreshold(value: Int) {
        viewModelScope.launch { repository.setClaudeFableThreshold(value) }
    }

    fun setOpenAIWeeklyThreshold(value: Int) {
        viewModelScope.launch { repository.setOpenAIWeeklyThreshold(value) }
    }

    fun setOpenAIResetCreditsThreshold(value: Int) {
        viewModelScope.launch { repository.setOpenAIResetCreditsThreshold(value) }
    }

    fun setCursorAPIThreshold(value: Int) {
        viewModelScope.launch { repository.setCursorAPIThreshold(value) }
    }

    fun setCursorAutoThreshold(value: Int) {
        viewModelScope.launch { repository.setCursorAutoThreshold(value) }
    }

    fun setCursorCreditThreshold(value: Int) {
        viewModelScope.launch { repository.setCursorCreditThreshold(value) }
    }

    fun consumeMessage() {
        _message.value = null
    }
}

class UsageViewModelFactory(
    private val repository: UsageRepository,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        require(modelClass.isAssignableFrom(UsageViewModel::class.java))
        return UsageViewModel(repository) as T
    }
}

object AgentUsageBarAppHolder {
    fun context() = com.agentusagebar.android.AgentUsageBarApp.instance
}
