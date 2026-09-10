package com.agentusagebar.android.ui.usage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.agentusagebar.android.data.credentials.AppSettings
import com.agentusagebar.android.data.credentials.CredentialsStore
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.model.OpenAIResetCredit
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.network.ResetCreditClient
import com.agentusagebar.android.data.network.ResetCreditFailure
import com.agentusagebar.android.data.repository.DeviceSyncCheckResult
import com.agentusagebar.android.data.repository.UsageRepository
import com.agentusagebar.android.worker.UsageRefreshScheduler
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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


sealed class ResetCreditUiState {
    data object Idle : ResetCreditUiState()
    data object Confirming : ResetCreditUiState()
    data object InFlight : ResetCreditUiState()
    data class Outcome(val message: String) : ResetCreditUiState()
    data class Error(val message: String) : ResetCreditUiState()
}

data class ResetCreditSummary(
    val availableCount: Int = 0,
    val nextExpiresInDays: Int? = null,
    val soonestCreditId: String? = null,
)

class UsageViewModel(
    private val repository: UsageRepository,
    private val resetCreditClient: ResetCreditClient = ResetCreditClient(
        ResetCreditClient.encryptedPendingStore(AgentUsageBarAppHolder.context()),
    ),
    private val credentialsStore: CredentialsStore = CredentialsStore(
        AgentUsageBarAppHolder.context(),
    ),
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

    private val _resetCreditState =
        MutableStateFlow<ResetCreditUiState>(ResetCreditUiState.Idle)
    val resetCreditState = _resetCreditState.asStateFlow()

    private val _resetCreditSummary = MutableStateFlow(ResetCreditSummary())
    val resetCreditSummary = _resetCreditSummary.asStateFlow()

    private var outcomeClearJob: Job? = null

    init {
        viewModelScope.launch {
            repository.refreshAll()
            UsageRefreshScheduler.ensureScheduled(AgentUsageBarAppHolder.context())
            refreshResetCreditSummary()
        }
    }

    fun selectProvider(provider: UsageProvider) {
        _selectedProvider.value = provider
        if (provider == UsageProvider.OPENAI) {
            viewModelScope.launch { refreshResetCreditSummary() }
        }
    }

    fun setClaudeCode(value: String) {
        _claudeCode.value = value
    }

    fun refresh() {
        viewModelScope.launch {
            repository.refreshAll()
            refreshResetCreditSummary()
        }
    }

    fun beginResetCreditConfirm() {
        if (_resetCreditSummary.value.soonestCreditId == null) return
        if (_resetCreditState.value is ResetCreditUiState.InFlight) return
        _resetCreditState.value = ResetCreditUiState.Confirming
    }

    fun cancelResetCreditConfirm() {
        if (_resetCreditState.value is ResetCreditUiState.Confirming) {
            _resetCreditState.value = ResetCreditUiState.Idle
        }
    }

    fun confirmResetCredit() {
        val creditId = _resetCreditSummary.value.soonestCreditId ?: return
        redeemResetCredit(creditId)
    }

    fun redeemResetCredit(creditId: String) {
        if (_resetCreditState.value is ResetCreditUiState.InFlight) return
        outcomeClearJob?.cancel()
        _resetCreditState.value = ResetCreditUiState.InFlight
        viewModelScope.launch {
            val credentials = credentialsStore.loadConnected()
            val bearer = credentials.openAIBearer
            val accountId = credentials.openAIAccountId
            if (bearer.isNullOrBlank()) {
                _resetCreditState.value =
                    ResetCreditUiState.Error("OpenAI session token missing.")
                scheduleOutcomeClear()
                return@launch
            }
            try {
                val outcome = withContext(Dispatchers.IO) {
                    resetCreditClient.redeem(
                        bearer = bearer,
                        accountId = accountId,
                        creditId = creditId,
                    )
                }
                _resetCreditState.value = ResetCreditUiState.Outcome(outcome.message)
                repository.refreshAll()
                refreshResetCreditSummary()
            } catch (_: ResetCreditFailure.InFlight) {
                _resetCreditState.value = ResetCreditUiState.InFlight
            } catch (error: ResetCreditFailure.SendFailed) {
                _resetCreditState.value = ResetCreditUiState.Error(error.message ?: "Redeem failed")
            } catch (error: Exception) {
                _resetCreditState.value =
                    ResetCreditUiState.Error(error.message ?: "Redeem failed")
            }
            scheduleOutcomeClear()
        }
    }

    private fun scheduleOutcomeClear() {
        outcomeClearJob?.cancel()
        outcomeClearJob = viewModelScope.launch {
            delay(4_000)
            if (_resetCreditState.value !is ResetCreditUiState.InFlight &&
                _resetCreditState.value !is ResetCreditUiState.Confirming
            ) {
                _resetCreditState.value = ResetCreditUiState.Idle
            }
        }
    }

    private suspend fun refreshResetCreditSummary() {
        val summary = withContext(Dispatchers.IO) {
            runCatching {
                val credentials = credentialsStore.loadConnected()
                val bearer = credentials.openAIBearer
                    ?: error("OpenAI not configured")
                val response = resetCreditClient.fetchCredits(
                    bearer = bearer,
                    accountId = credentials.openAIAccountId,
                )
                val available = response.credits.filter {
                    it.isAvailable && it.resetType == CODEX_RATE_LIMITS_RESET_TYPE
                }
                val soonest = available.minByOrNull { credit ->
                    expiresEpochMs(credit) ?: Long.MAX_VALUE
                }
                val days = soonest?.let { credit ->
                    expiresEpochMs(credit)?.let { expiresAt ->
                        ChronoUnit.DAYS.between(
                            Instant.now(),
                            Instant.ofEpochMilli(expiresAt),
                        ).toInt().coerceAtLeast(0)
                    }
                }
                ResetCreditSummary(
                    availableCount = available.size,
                    nextExpiresInDays = days,
                    soonestCreditId = soonest?.id,
                )
            }.getOrElse { ResetCreditSummary() }
        }
        _resetCreditSummary.value = summary
    }

    private fun expiresEpochMs(credit: OpenAIResetCredit): Long? {
        val raw = credit.expiresAt?.takeIf { it.isNotBlank() } ?: return null
        return runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()
            ?: raw.toLongOrNull()?.let { if (it < 1_000_000_000_000L) it * 1_000 else it }
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

    companion object {
        private const val CODEX_RATE_LIMITS_RESET_TYPE = "codex_rate_limits"
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
