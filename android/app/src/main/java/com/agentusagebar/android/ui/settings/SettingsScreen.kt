package com.agentusagebar.android.ui.settings

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.agentusagebar.android.BuildConfig
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.model.UsageTextSize
import com.agentusagebar.android.data.sync.TrustedDesktopDevice
import com.agentusagebar.android.ui.usage.DeviceActionPhase
import com.agentusagebar.android.ui.usage.ThresholdSlider
import com.agentusagebar.android.ui.usage.UsageViewModel
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private enum class SettingsTab(val title: String, val icon: ImageVector) {
    General("General", Icons.Outlined.Settings),
    Connections("Connections", Icons.Outlined.Link),
    Appearance("Appearance", Icons.Outlined.Palette),
    Notifications("Notifications", Icons.Outlined.Notifications),
    Devices("Devices", Icons.Outlined.Devices),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: UsageViewModel,
    onBack: () -> Unit,
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val email by viewModel.claudeEmail.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val devicePairing by viewModel.devicePairing.collectAsStateWithLifecycle()
    val trustedDevices by viewModel.trustedDevices.collectAsStateWithLifecycle()
    val deviceActions by viewModel.deviceActions.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }

    var openAIToken by remember { mutableStateOf("") }
    var cursorToken by remember { mutableStateOf("") }
    var elevenLabsKey by remember { mutableStateOf("") }
    var pendingUnlink by remember { mutableStateOf<TrustedDesktopDevice?>(null) }
    var removeImportedCredentials by remember { mutableStateOf(false) }
    val activity = LocalContext.current as? Activity
    val uriHandler = LocalUriHandler.current
    val scanner = remember(activity) {
        activity?.let {
            val options = GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .enableAutoZoom()
                .build()
            GmsBarcodeScanning.getClient(it, options)
        }
    }

    val claudeConnected = snapshot.providers[UsageProvider.CLAUDE]?.isConfigured == true
    val openAIConnected = snapshot.providers[UsageProvider.OPENAI]?.isConfigured == true
    val cursorConnected = snapshot.providers[UsageProvider.CURSOR]?.isConfigured == true
    val elevenConnected = snapshot.providers[UsageProvider.ELEVENLABS]?.isConfigured == true
    val metricOptions = UsageMetricPreferences.options(
        provider = settings.widgetProvider,
        available = snapshot.providers[settings.widgetProvider]?.metrics.orEmpty(),
    )
    val selectedMetrics = UsageMetricPreferences.resolvedPair(
        provider = settings.widgetProvider,
        primaryID = settings.primaryMetric,
        secondaryID = settings.secondaryMetric,
        available = metricOptions,
    )
    val selectedPrimaryMetric = selectedMetrics.getOrNull(0)?.id
    val selectedSecondaryMetric = selectedMetrics.getOrNull(1)?.id

    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    pendingUnlink?.let { device ->
        AlertDialog(
            onDismissRequest = { pendingUnlink = null },
            title = { Text("Unlink ${device.desktopName}?") },
            text = {
                Column {
                    Text(
                        "Android will delete this Mac’s trusted key. If the Mac is reachable, it will also remove this phone.",
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Row {
                        Checkbox(
                            checked = removeImportedCredentials,
                            onCheckedChange = { removeImportedCredentials = it },
                        )
                        Text(
                            "Also remove credentials imported from this Mac",
                            modifier = Modifier.padding(top = 12.dp),
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.unlinkMac(
                            device.desktopID,
                            device.desktopName,
                            removeImportedCredentials,
                        )
                        pendingUnlink = null
                    },
                ) { Text("Unlink Mac") }
            },
            dismissButton = {
                TextButton(onClick = { pendingUnlink = null }) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            ScrollableTabRow(selectedTabIndex = selectedTab, edgePadding = 16.dp) {
                SettingsTab.entries.forEachIndexed { index, tab ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        icon = {
                            Icon(
                                tab.icon,
                                contentDescription = tab.title,
                            )
                        },
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Spacer(modifier = Modifier.height(8.dp))
                when (SettingsTab.entries[selectedTab]) {
                    SettingsTab.General -> {
                        Text("Polling Interval", style = MaterialTheme.typography.titleMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SettingsStore.POLLING_OPTIONS.forEach { mins ->
                                FilterChip(
                                    selected = settings.pollingMinutes == mins,
                                    onClick = { viewModel.setPollingMinutes(mins) },
                                    label = { Text(if (mins == 60) "1h" else "${mins}m") },
                                )
                            }
                        }

                        HorizontalDivider()
                        Text("About", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Version ${BuildConfig.VERSION_NAME}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    SettingsTab.Connections -> {
                        Text("OpenAI / Codex", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Paste the bearer token from the Authorization header of a ChatGPT usage request.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedTextField(
                            value = openAIToken,
                            onValueChange = { openAIToken = it },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            placeholder = {
                                Text(
                                    if (openAIConnected) "Session token configured"
                                    else "Bearer session token",
                                )
                            },
                        )
                        Row {
                            Button(
                                onClick = {
                                    viewModel.saveOpenAIToken(openAIToken)
                                    openAIToken = ""
                                },
                                enabled = openAIToken.isNotBlank(),
                            ) { Text("Save Session Token") }
                            if (openAIConnected) {
                                TextButton(onClick = viewModel::clearOpenAIToken) { Text("Clear") }
                            }
                        }

                        HorizontalDivider()
                        Text("Cursor", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Paste the WorkosCursorSessionToken cookie from cursor.com.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedTextField(
                            value = cursorToken,
                            onValueChange = { cursorToken = it },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            placeholder = {
                                Text(
                                    if (cursorConnected) "Session token configured"
                                    else "WorkosCursorSessionToken",
                                )
                            },
                        )
                        Row {
                            Button(
                                onClick = {
                                    viewModel.saveCursorToken(cursorToken)
                                    cursorToken = ""
                                },
                                enabled = cursorToken.isNotBlank(),
                            ) { Text("Save Session Token") }
                            if (cursorConnected) {
                                TextButton(onClick = viewModel::clearCursorToken) { Text("Clear") }
                            }
                        }

                        HorizontalDivider()
                        Text("ElevenLabs", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Add an ElevenLabs API key that can access the user subscription endpoint.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedTextField(
                            value = elevenLabsKey,
                            onValueChange = { elevenLabsKey = it },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            placeholder = {
                                Text(
                                    if (elevenConnected) "API key configured"
                                    else "ElevenLabs API key",
                                )
                            },
                        )
                        Row {
                            Button(
                                onClick = {
                                    viewModel.saveElevenLabsAPIKey(elevenLabsKey)
                                    elevenLabsKey = ""
                                },
                                enabled = elevenLabsKey.isNotBlank(),
                            ) { Text("Save API Key") }
                            if (elevenConnected) {
                                TextButton(onClick = viewModel::clearElevenLabsAPIKey) { Text("Clear") }
                            }
                        }

                        HorizontalDivider()
                        Text("Claude", style = MaterialTheme.typography.titleMedium)
                        if (claudeConnected) {
                            email?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                            TextButton(onClick = viewModel::signOutClaude) { Text("Sign Out of Claude") }
                        } else {
                            Text(
                                "Use Sign in with Claude on the home screen, then paste the browser code.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        Text(
                            "Tokens stay on this phone in encrypted app storage.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    SettingsTab.Appearance -> {
                        Text("Provider Details", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Bars, capsule, or orbit visualization in the provider detail section and widgets.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            DetailVisualizationStyle.entries.forEach { style ->
                                FilterChip(
                                    selected = settings.detailStyle == style,
                                    onClick = { viewModel.setDetailStyle(style) },
                                    label = { Text(style.displayName) },
                                )
                            }
                        }

                        HorizontalDivider()
                        Text("Usage Text Size", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Large / Comfortable use a 2-column overview so all four providers stay readable.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            UsageTextSize.entries.forEach { size ->
                                FilterChip(
                                    selected = settings.textSize == size,
                                    onClick = { viewModel.setTextSize(size) },
                                    label = { Text(size.displayName) },
                                )
                            }
                        }

                        HorizontalDivider()
                        Text("Provider Widget", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Choose which provider the smaller home-screen widget focuses on.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            UsageProvider.entries.forEach { provider ->
                                FilterChip(
                                    selected = settings.widgetProvider == provider,
                                    onClick = { viewModel.setWidgetProvider(provider) },
                                    label = { Text(provider.shortName) },
                                )
                            }
                        }

                        HorizontalDivider()
                        Text("Primary Stat", style = MaterialTheme.typography.titleMedium)
                        Row(
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            metricOptions.forEach { metric ->
                                FilterChip(
                                    selected = selectedPrimaryMetric == metric.id,
                                    onClick = { viewModel.setPrimaryMetric(metric.id) },
                                    label = { Text(metric.label) },
                                )
                            }
                        }

                        HorizontalDivider()
                        Text("Secondary Stat", style = MaterialTheme.typography.titleMedium)
                        Row(
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            metricOptions
                                .filter { it.id != selectedPrimaryMetric }
                                .forEach { metric ->
                                    FilterChip(
                                        selected = selectedSecondaryMetric == metric.id,
                                        onClick = { viewModel.setSecondaryMetric(metric.id) },
                                        label = { Text(metric.label) },
                                    )
                                }
                        }
                        Text(
                            "These stats appear first in the home-screen widgets.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    SettingsTab.Notifications -> {
                        Text(
                            "Thresholds appear for providers you have connected. 0% means Off.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )

                        if (!claudeConnected && !openAIConnected && !cursorConnected && !elevenConnected) {
                            Text(
                                "Connect a provider in the Connections tab to configure alerts.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        if (claudeConnected) {
                            Text("Claude", style = MaterialTheme.typography.titleMedium)
                            ThresholdSlider(
                                "Session usage",
                                settings.claudeSessionThreshold,
                                viewModel::setClaudeSessionThreshold,
                            )
                            ThresholdSlider(
                                "Seven-day usage",
                                settings.claudeSevenDayThreshold,
                                viewModel::setClaudeSevenDayThreshold,
                            )
                            ThresholdSlider(
                                "Fable usage",
                                settings.claudeFableThreshold,
                                viewModel::setClaudeFableThreshold,
                            )
                        }

                        if (openAIConnected) {
                            if (claudeConnected) HorizontalDivider()
                            Text("Codex", style = MaterialTheme.typography.titleMedium)
                            ThresholdSlider(
                                "Weekly usage limits",
                                settings.openAIWeeklyThreshold,
                                viewModel::setOpenAIWeeklyThreshold,
                            )
                            ThresholdSlider(
                                "Reset credits (remaining count)",
                                settings.openAIResetCreditsThreshold,
                                viewModel::setOpenAIResetCreditsThreshold,
                            )
                        }

                        if (cursorConnected) {
                            if (claudeConnected || openAIConnected) HorizontalDivider()
                            Text("Cursor", style = MaterialTheme.typography.titleMedium)
                            ThresholdSlider(
                                "API usage",
                                settings.cursorAPIThreshold,
                                viewModel::setCursorAPIThreshold,
                            )
                            ThresholdSlider(
                                "Auto usage",
                                settings.cursorAutoThreshold,
                                viewModel::setCursorAutoThreshold,
                            )
                            ThresholdSlider(
                                "Credit",
                                settings.cursorCreditThreshold,
                                viewModel::setCursorCreditThreshold,
                            )
                        }
                    }

                    SettingsTab.Devices -> {
                        Icon(
                            Icons.Outlined.Devices,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Text("Sync from your Mac", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "On the Mac, open Settings → Devices → Add Device. Choose what to sync, then scan the temporary QR code here.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(
                            onClick = {
                                scanner?.startScan()
                                    ?.addOnSuccessListener { barcode ->
                                        barcode.rawValue?.let(viewModel::startDevicePairing)
                                    }
                                    ?.addOnFailureListener {
                                        viewModel.showMessage(
                                            it.message ?: "Could not scan the QR code.",
                                        )
                                    }
                            },
                            enabled = scanner != null && !devicePairing.isPairing,
                        ) {
                            Text("Scan QR Code")
                        }
                        if (devicePairing.isPairing) {
                            HorizontalDivider()
                            CircularProgressIndicator()
                            devicePairing.desktopName?.let {
                                Text("Waiting for approval on $it")
                            }
                            devicePairing.confirmationCode?.let { code ->
                                Text(
                                    "Confirm this code matches the Mac:",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Text(
                                    "${code.take(3)} ${code.takeLast(3)}",
                                    style = MaterialTheme.typography.headlineMedium,
                                )
                            }
                            TextButton(onClick = viewModel::cancelDevicePairing) {
                                Text("Cancel Pairing")
                            }
                        }
                        Text(
                            "Imported connection secrets are saved in Android's encrypted app storage. Claude sign-in stays device-specific.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            "Only scan a code you just generated on a Mac you trust. Codes expire after 10 minutes.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        HorizontalDivider()
                        Text("Trusted Macs", style = MaterialTheme.typography.titleMedium)
                        if (trustedDevices.isEmpty()) {
                            Text(
                                "No Macs are paired yet.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            trustedDevices.forEach { device ->
                                val action = deviceActions[device.desktopID]
                                Card(modifier = Modifier.fillMaxWidth()) {
                                    Column(
                                        modifier = Modifier.padding(16.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                        ) {
                                            Text(
                                                device.desktopName,
                                                style = MaterialTheme.typography.titleMedium,
                                            )
                                            Text(
                                                "Paired",
                                                style = MaterialTheme.typography.labelLarge,
                                                color = MaterialTheme.colorScheme.primary,
                                            )
                                        }
                                        Text(
                                            "Last successful contact: ${formatDeviceTime(device.lastCheckedAtEpochMs)}",
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                        Text(
                                            "Last settings sync: ${formatDeviceTime(device.lastSettingsSyncAtEpochMs)}",
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                        action?.message?.let { status ->
                                            Row(
                                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                            ) {
                                                if (
                                                    action.phase == DeviceActionPhase.CHECKING ||
                                                    action.phase == DeviceActionPhase.UNLINKING
                                                ) {
                                                    CircularProgressIndicator(
                                                        modifier = Modifier.size(18.dp),
                                                        strokeWidth = 2.dp,
                                                    )
                                                }
                                                Text(
                                                    status,
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = when (action.phase) {
                                                        DeviceActionPhase.ERROR ->
                                                            MaterialTheme.colorScheme.error
                                                        DeviceActionPhase.SUCCESS ->
                                                            MaterialTheme.colorScheme.primary
                                                        else ->
                                                            MaterialTheme.colorScheme.onSurfaceVariant
                                                    },
                                                )
                                            }
                                        }
                                        Row(
                                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            Button(
                                                onClick = {
                                                    viewModel.checkForSync(
                                                        device.desktopID,
                                                        device.desktopName,
                                                    )
                                                },
                                                enabled = action?.phase !in setOf(
                                                    DeviceActionPhase.CHECKING,
                                                    DeviceActionPhase.UNLINKING,
                                                ),
                                            ) { Text("Check for Sync") }
                                            OutlinedButton(
                                                onClick = {
                                                    removeImportedCredentials = false
                                                    pendingUnlink = device
                                                },
                                                enabled = action?.phase !in setOf(
                                                    DeviceActionPhase.CHECKING,
                                                    DeviceActionPhase.UNLINKING,
                                                ),
                                            ) { Text("Unlink Mac") }
                                        }
                                    }
                                }
                            }
                        }
                        HorizontalDivider()
                        Text("Lost device?", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Removing a phone on the Mac queues a wipe for the next local-network check. For immediate protection, revoke sessions or keys at the provider.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        TextButton(
                            onClick = { uriHandler.openUri("https://chatgpt.com/") },
                        ) { Text("OpenAI active sessions") }
                        TextButton(
                            onClick = {
                                uriHandler.openUri("https://claude.ai/settings/account")
                            },
                        ) { Text("Claude account sessions") }
                        TextButton(
                            onClick = {
                                uriHandler.openUri("https://elevenlabs.io/app/settings/api-keys")
                            },
                        ) { Text("ElevenLabs API keys") }
                    }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

private val deviceTimeFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)

private fun formatDeviceTime(epochMs: Long?): String {
    if (epochMs == null) return "Never"
    return deviceTimeFormatter.format(
        Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault()),
    )
}
