package com.agentusagebar.android.ui.usage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.agentusagebar.android.data.credentials.AppSettings
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.repository.DeviceSyncCheckResult
import com.agentusagebar.android.data.repository.UsageRepository
import com.agentusagebar.android.worker.UsageRefreshScheduler
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

data class DevicePairingUiState(
    val isPairing: Boolean = false,
    val desktopName: String? = null,
    val confirmationCode: String? = null,
)

enum class DeviceActionPhase {
    IDLE,
    CHECKING,
    UNLINKING,
    SUCCESS,
    ERROR,
}

data class DeviceActionUiState(
    val phase: DeviceActionPhase = DeviceActionPhase.IDLE,
    val message: String? = null,
)

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
    val trustedDevices = repository.trustedDevices
    private val _devicePairing = MutableStateFlow(DevicePairingUiState())
    val devicePairing = _devicePairing.asStateFlow()
    private var devicePairingJob: Job? = null
    private val _deviceActions =
        MutableStateFlow<Map<String, DeviceActionUiState>>(emptyMap())
    val deviceActions = _deviceActions.asStateFlow()

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

    fun startDevicePairing(rawValue: String) {
        devicePairingJob?.cancel()
        _devicePairing.value = DevicePairingUiState(isPairing = true)
        devicePairingJob = viewModelScope.launch {
            repository.pairDevice(rawValue) { desktopName, confirmationCode ->
                _devicePairing.value = DevicePairingUiState(
                    isPairing = true,
                    desktopName = desktopName,
                    confirmationCode = confirmationCode,
                )
            }
                .onSuccess {
                    _message.value = it
                    _devicePairing.value = DevicePairingUiState()
                    UsageRefreshScheduler.ensureScheduled(
                        AgentUsageBarAppHolder.context(),
                        forceReschedule = true,
                    )
                }
                .onFailure {
                    _message.value = it.message
                    _devicePairing.value = DevicePairingUiState()
                }
        }
    }

    fun cancelDevicePairing() {
        devicePairingJob?.cancel()
        devicePairingJob = null
        _devicePairing.value = DevicePairingUiState()
    }

    fun checkForSync(desktopID: String, desktopName: String) {
        if (_deviceActions.value[desktopID]?.phase == DeviceActionPhase.CHECKING) return
        _deviceActions.value = _deviceActions.value + (
            desktopID to DeviceActionUiState(
                phase = DeviceActionPhase.CHECKING,
                message = "Contacting $desktopName…",
            )
        )
        viewModelScope.launch {
            repository.checkForSync(desktopID)
                .onSuccess { result ->
                    val message = when (result) {
                        DeviceSyncCheckResult.UP_TO_DATE ->
                            "Connected successfully. No settings update is queued."
                        DeviceSyncCheckResult.SETTINGS_APPLIED ->
                            "Settings synced successfully."
                        DeviceSyncCheckResult.UNLINKED_BY_MAC ->
                            "$desktopName removed this phone. Imported credentials were removed."
                    }
                    _deviceActions.value = _deviceActions.value + (
                        desktopID to DeviceActionUiState(
                            phase = DeviceActionPhase.SUCCESS,
                            message = message,
                        )
                    )
                }
                .onFailure { error ->
                    val connectionError = generateSequence(error as Throwable?) { it.cause }
                        .any { it is java.io.IOException }
                    val detail = if (
                        error.message?.startsWith("Settings were applied") == true
                    ) {
                        error.message.orEmpty()
                    } else if (connectionError) {
                        "Couldn’t connect to $desktopName. Make sure both devices are on the same network and the Mac app is open."
                    } else {
                        error.message ?: "Couldn’t check for a settings update."
                    }
                    _deviceActions.value = _deviceActions.value + (
                        desktopID to DeviceActionUiState(
                            phase = DeviceActionPhase.ERROR,
                            message = detail,
                        )
                    )
                }
        }
    }

    fun unlinkMac(
        desktopID: String,
        desktopName: String,
        removeImportedCredentials: Boolean,
    ) {
        _deviceActions.value = _deviceActions.value + (
            desktopID to DeviceActionUiState(
                phase = DeviceActionPhase.UNLINKING,
                message = "Unlinking $desktopName…",
            )
        )
        viewModelScope.launch {
            repository.unlinkMac(desktopID, removeImportedCredentials)
                .onSuccess { result ->
                    _deviceActions.value = _deviceActions.value - desktopID
                    val unlinkMessage = if (result.macWasNotified) {
                        "$desktopName was unlinked on both devices."
                    } else {
                        "$desktopName was unlinked from Android. The Mac didn’t confirm the request, so a stale phone entry may need to be removed there manually."
                    }
                    val credentialsMessage = when {
                        !removeImportedCredentials -> ""
                        result.credentialsRemoved ->
                            " Matching imported credentials were removed."
                        else -> " No matching imported credentials remained."
                    }
                    _message.value = unlinkMessage + credentialsMessage
                }
                .onFailure {
                    _deviceActions.value = _deviceActions.value + (
                        desktopID to DeviceActionUiState(
                            phase = DeviceActionPhase.ERROR,
                            message = it.message ?: "Couldn’t unlink $desktopName.",
                        )
                    )
                    _message.value = it.message ?: "Couldn’t unlink $desktopName."
                }
        }
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

    fun setPrimaryMetric(metricID: String) {
        viewModelScope.launch { repository.setPrimaryMetric(metricID) }
    }

    fun setSecondaryMetric(metricID: String) {
        viewModelScope.launch { repository.setSecondaryMetric(metricID) }
    }

    fun setClaudeWidgetOrbitCenterMetric(metricID: String) {
        viewModelScope.launch { repository.setClaudeWidgetOrbitCenterMetric(metricID) }
    }

    fun setClaudeWidgetDisplayMetric(metricID: String) {
        viewModelScope.launch { repository.setClaudeWidgetDisplayMetric(metricID) }
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

    fun showMessage(message: String) {
        _message.value = message
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
