package com.agentusagebar.android.data.repository

import android.content.Context
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.model.AppUsageSnapshot
import com.agentusagebar.android.data.sync.DevicePairingClient
import com.agentusagebar.android.data.sync.DeviceRedeemResult
import com.agentusagebar.android.data.sync.DeviceSyncPayload
import com.agentusagebar.android.data.sync.TrustedDesktopDevice
import com.agentusagebar.android.data.sync.TrustedDeviceStore
import com.agentusagebar.android.data.sync.UsageSnapshotDocument
import com.agentusagebar.android.data.sync.emptyAppUsageSnapshot
import com.agentusagebar.android.data.sync.parseIsoToEpochMs
import com.agentusagebar.android.data.sync.toAppUsageSnapshot
import com.agentusagebar.android.widget.WidgetSnapshotStore
import com.agentusagebar.android.widget.WidgetUpdater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

enum class DeviceSyncCheckResult {
    UP_TO_DATE,
    SETTINGS_APPLIED,
    UNLINKED_BY_MAC,
}

data class UnlinkMacResult(
    val macWasNotified: Boolean,
)

class UsageRepository(
    context: Context,
    private val settingsStore: SettingsStore = SettingsStore(context),
    private val trustedDeviceStore: TrustedDeviceStore = TrustedDeviceStore(context),
    private val devicePairingClient: DevicePairingClient = DevicePairingClient(trustedDeviceStore),
) {
    private val appContext = context.applicationContext
    private val trustedDeviceMutex = Mutex()
    private val refreshMutex = Mutex()
    private val snapshotCache = MacSnapshotCache(appContext)
    private val snapshotsByDesktop = mutableMapOf<String, CachedPull>()

    private val _snapshot = MutableStateFlow(restoreSnapshot())
    val snapshot: StateFlow<AppUsageSnapshot> = _snapshot.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _trustedDevices = MutableStateFlow(activeTrustedDevices())
    val trustedDevices: StateFlow<List<TrustedDesktopDevice>> =
        _trustedDevices.asStateFlow()

    val settings = settingsStore.settings

    suspend fun pairDevice(
        rawValue: String,
        onWaitingForApproval: (desktopName: String, confirmationCode: String) -> Unit,
    ): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val result = devicePairingClient.pair(rawValue, onWaitingForApproval)
            applyImportedPayload(result.payload)
            trustedDeviceStore.save(result.trustedDevice)
            publishTrustedDevices()
            refreshAll()

            val categories = buildList {
                if (result.payload.general != null) add("polling")
                if (result.payload.appearance != null) add("appearance")
                if (result.payload.notifications != null) add("notifications")
            }
            val imported = if (categories.isEmpty()) {
                "no settings"
            } else {
                categories.joinToString()
            }
            "Paired with ${result.trustedDevice.desktopName}; imported $imported."
        }
    }

    private suspend fun applyImportedPayload(payload: DeviceSyncPayload) {
        settingsStore.applyDeviceSync(payload)
        publishWidgets()
    }

    suspend fun checkForSync(desktopID: String): Result<DeviceSyncCheckResult> =
        withContext(Dispatchers.IO) {
            runCatching {
                trustedDeviceMutex.withLock {
                    val device = trustedDeviceStore.load()
                        .firstOrNull {
                            it.desktopID == desktopID && it.revokedAtEpochMs == null
                        }
                        ?: error("This Mac is no longer linked.")
                    checkTrustedDevice(device)
                }
            }.also {
                publishTrustedDevices()
            }
        }

    suspend fun unlinkMac(desktopID: String): Result<UnlinkMacResult> =
        withContext(Dispatchers.IO) {
            runCatching {
                trustedDeviceMutex.withLock {
                    val device = trustedDeviceStore.load()
                        .firstOrNull { it.desktopID == desktopID }
                        ?: error("This Mac is no longer linked.")
                    val macWasNotified = runCatching {
                        devicePairingClient.unlink(device)
                    }.isSuccess
                    trustedDeviceStore.remove(desktopID)
                    dropCachedSnapshot(desktopID)
                    publishTrustedDevices()
                    publishDisplayedSnapshot()
                    UnlinkMacResult(macWasNotified = macWasNotified)
                }
            }
        }

    suspend fun redeemResetCredit(creditId: String): Result<DeviceRedeemResult> =
        withContext(Dispatchers.IO) {
            runCatching {
                val device = displayedDesktop()
                    ?: error("No paired Mac is available.")
                if (_snapshot.value.macUnreachable) {
                    error("Mac unreachable")
                }
                val result = devicePairingClient.redeemResetCredit(device, creditId)
                refreshAll()
                result
            }
        }

    private suspend fun checkTrustedDevice(
        device: TrustedDesktopDevice,
    ): DeviceSyncCheckResult {
        val command = devicePairingClient.checkStatus(device)
        val now = System.currentTimeMillis() / 1_000
        require(kotlin.math.abs(now - command.issuedAtEpochSeconds) <= 60) {
            "The Mac returned a stale device command."
        }
        trustedDeviceStore.markChecked(device.desktopID, revoked = false)

        return when (command.action) {
            "wipe" -> {
                devicePairingClient.acknowledgeWipe(device)
                trustedDeviceStore.markChecked(device.desktopID, revoked = true)
                dropCachedSnapshot(device.desktopID)
                DeviceSyncCheckResult.UNLINKED_BY_MAC
            }

            "sync" -> {
                val syncID = requireNotNull(command.syncID) {
                    "The Mac sent an invalid sync command."
                }
                val envelope = requireNotNull(command.syncEnvelope) {
                    "The Mac sent no settings to sync."
                }
                val payload = devicePairingClient.openSyncPayload(
                    device,
                    syncID,
                    envelope,
                )
                applyImportedPayload(payload)
                trustedDeviceStore.markSettingsSynced(device.desktopID)
                try {
                    devicePairingClient.acknowledgeSync(device, syncID)
                } catch (error: Exception) {
                    throw IllegalStateException(
                        "Settings were applied, but the Mac could not confirm the acknowledgement. The same update may be offered again.",
                        error,
                    )
                }
                DeviceSyncCheckResult.SETTINGS_APPLIED
            }

            "none" -> DeviceSyncCheckResult.UP_TO_DATE
            else -> error("The Mac returned an unsupported device command.")
        }
    }

    private suspend fun checkTrustedDevices() {
        trustedDeviceMutex.withLock {
            trustedDeviceStore.load()
                .filter { it.revokedAtEpochMs == null }
                .forEach { device ->
                    runCatching { checkTrustedDevice(device) }
                }
            publishTrustedDevices()
        }
    }

    private fun activeTrustedDevices(): List<TrustedDesktopDevice> =
        trustedDeviceStore.load()
            .filter { it.revokedAtEpochMs == null }
            .sortedByDescending { it.pairedAtEpochMs }

    private fun publishTrustedDevices() {
        _trustedDevices.value = activeTrustedDevices()
    }

    suspend fun setPollingMinutes(minutes: Int) = settingsStore.setPollingMinutes(minutes)
    suspend fun setSetupComplete(complete: Boolean) = settingsStore.setSetupComplete(complete)
    suspend fun setWidgetProvider(provider: com.agentusagebar.android.data.model.UsageProvider) {
        settingsStore.setWidgetProvider(provider)
        publishWidgets()
    }

    suspend fun setPrimaryMetric(metricID: String) {
        settingsStore.setPrimaryMetric(metricID)
        publishWidgets()
    }

    suspend fun setSecondaryMetric(metricID: String) {
        settingsStore.setSecondaryMetric(metricID)
        publishWidgets()
    }

    suspend fun setClaudeWidgetOrbitCenterMetric(metricID: String) {
        settingsStore.setClaudeWidgetOrbitCenterMetric(metricID)
        publishWidgets()
    }

    suspend fun setClaudeWidgetDisplayMetric(metricID: String) {
        settingsStore.setClaudeWidgetDisplayMetric(metricID)
        publishWidgets()
    }

    suspend fun setDetailStyle(style: com.agentusagebar.android.data.model.DetailVisualizationStyle) {
        settingsStore.setDetailStyle(style)
        publishWidgets()
    }

    suspend fun setFillMode(mode: com.agentusagebar.android.data.model.UsageFillMode) {
        settingsStore.setFillMode(mode)
        publishWidgets()
    }

    suspend fun setTextSize(size: com.agentusagebar.android.data.model.UsageTextSize) =
        settingsStore.setTextSize(size)

    suspend fun setClaudeSessionThreshold(value: Int) = settingsStore.setClaudeSessionThreshold(value)
    suspend fun setClaudeSevenDayThreshold(value: Int) = settingsStore.setClaudeSevenDayThreshold(value)
    suspend fun setClaudeFableThreshold(value: Int) = settingsStore.setClaudeFableThreshold(value)
    suspend fun setOpenAIWeeklyThreshold(value: Int) = settingsStore.setOpenAIWeeklyThreshold(value)
    suspend fun setOpenAIResetCreditsThreshold(value: Int) = settingsStore.setOpenAIResetCreditsThreshold(value)
    suspend fun setCursorAPIThreshold(value: Int) = settingsStore.setCursorAPIThreshold(value)
    suspend fun setCursorAutoThreshold(value: Int) = settingsStore.setCursorAutoThreshold(value)
    suspend fun setCursorCreditThreshold(value: Int) = settingsStore.setCursorCreditThreshold(value)

    suspend fun refreshAll() = withContext(Dispatchers.IO) {
        refreshMutex.withLock {
            _isRefreshing.value = true
            try {
                checkTrustedDevices()
                val devices = activeTrustedDevices()
                if (devices.isEmpty()) {
                    snapshotsByDesktop.clear()
                    snapshotCache.clear()
                    _snapshot.value = emptyAppUsageSnapshot()
                    publishWidgets()
                    return@withLock
                }
                val pulls = coroutineScope {
                    devices.map { device ->
                        async {
                            runCatching {
                                CachedPull(
                                    desktopID = device.desktopID,
                                    desktopName = device.desktopName,
                                    document = devicePairingClient.fetchSnapshot(device),
                                    pulledAtEpochMs = System.currentTimeMillis(),
                                )
                            }
                        }
                    }.awaitAll()
                }
                val successes = pulls.mapNotNull { it.getOrNull() }
                if (successes.isEmpty()) {
                    _snapshot.value = _snapshot.value.copy(
                        macUnreachable = true,
                        pairedDesktopCount = devices.size,
                    )
                    return@withLock
                }
                successes.forEach { pull ->
                    snapshotsByDesktop[pull.desktopID] = pull
                }
                val newest = successes.maxBy { parseIsoToEpochMs(it.document.generatedAt) ?: 0L }
                snapshotCache.save(newest)
                publishDisplayedSnapshot(newest)
            } finally {
                _isRefreshing.value = false
            }
        }
    }

    private fun displayedDesktop(): TrustedDesktopDevice? {
        val displayedID = snapshotsByDesktop.maxByOrNull {
            parseIsoToEpochMs(it.value.document.generatedAt) ?: 0L
        }?.key
        return activeTrustedDevices().firstOrNull { it.desktopID == displayedID }
            ?: activeTrustedDevices().firstOrNull()
    }

    private fun dropCachedSnapshot(desktopID: String) {
        snapshotsByDesktop.remove(desktopID)
        val persisted = snapshotCache.load()
        if (persisted?.desktopID == desktopID) {
            snapshotCache.clear()
        }
    }

    private fun publishDisplayedSnapshot(preferred: CachedPull? = null) {
        val devices = activeTrustedDevices()
        val newest = preferred
            ?: snapshotsByDesktop.values
                .filter { pull -> devices.any { it.desktopID == pull.desktopID } }
                .maxByOrNull { parseIsoToEpochMs(it.document.generatedAt) ?: 0L }
            ?: snapshotCache.load()?.takeIf { cached ->
                devices.any { it.desktopID == cached.desktopID }
            }
        if (newest == null) {
            _snapshot.value = emptyAppUsageSnapshot(pairedDesktopCount = devices.size)
            publishWidgets()
            return
        }
        val name = newest.desktopName.takeIf { devices.size > 1 }
        _snapshot.value = newest.document.toAppUsageSnapshot(
            desktopName = name,
            pairedDesktopCount = devices.size,
            lastSuccessfulPullEpochMs = newest.pulledAtEpochMs,
            macUnreachable = false,
        )
        publishWidgets()
    }

    private fun restoreSnapshot(): AppUsageSnapshot {
        val cached = snapshotCache.load() ?: return emptyAppUsageSnapshot()
        val devices = activeTrustedDevices()
        if (devices.none { it.desktopID == cached.desktopID }) {
            snapshotCache.clear()
            return emptyAppUsageSnapshot()
        }
        val name = cached.desktopName.takeIf { devices.size > 1 }
        snapshotsByDesktop[cached.desktopID] = cached
        return cached.document.toAppUsageSnapshot(
            desktopName = name,
            pairedDesktopCount = devices.size,
            lastSuccessfulPullEpochMs = cached.pulledAtEpochMs,
            macUnreachable = false,
        )
    }

    private fun publishWidgets() {
        WidgetSnapshotStore.save(appContext, _snapshot.value)
        WidgetUpdater.updateAll(appContext)
    }
}

private data class CachedPull(
    val desktopID: String,
    val desktopName: String,
    val document: UsageSnapshotDocument,
    val pulledAtEpochMs: Long,
)

@Serializable
private data class CachedPullRecord(
    val desktopID: String,
    val desktopName: String,
    val documentJson: String,
    val pulledAtEpochMs: Long,
)

private class MacSnapshotCache(context: Context) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val prefs = context.applicationContext.getSharedPreferences(
        "agent_usage_bar_mac_snapshot",
        Context.MODE_PRIVATE,
    )

    fun save(pull: CachedPull) {
        val record = CachedPullRecord(
            desktopID = pull.desktopID,
            desktopName = pull.desktopName,
            documentJson = json.encodeToString(pull.document),
            pulledAtEpochMs = pull.pulledAtEpochMs,
        )
        prefs.edit().putString(KEY, json.encodeToString(record)).apply()
    }

    fun load(): CachedPull? {
        val raw = prefs.getString(KEY, null) ?: return null
        val record = runCatching {
            json.decodeFromString<CachedPullRecord>(raw)
        }.getOrNull() ?: return null
        val document = runCatching {
            json.decodeFromString<UsageSnapshotDocument>(record.documentJson)
        }.getOrNull() ?: return null
        return CachedPull(
            desktopID = record.desktopID,
            desktopName = record.desktopName,
            document = document,
            pulledAtEpochMs = record.pulledAtEpochMs,
        )
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val KEY = "cached_pull"
    }
}
