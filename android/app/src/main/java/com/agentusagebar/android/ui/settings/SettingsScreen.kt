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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.model.DetailVisualizationStyle
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.data.model.UsageTextSize
import com.agentusagebar.android.ui.usage.ThresholdSlider
import com.agentusagebar.android.ui.usage.UsageViewModel
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

private enum class SettingsTab(val title: String) {
    Connections("Connections"),
    Appearance("Appearance"),
    Notifications("Notifications"),
    Devices("Devices"),
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
    val snackbar = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }

    var openAIToken by remember { mutableStateOf("") }
    var cursorToken by remember { mutableStateOf("") }
    var elevenLabsKey by remember { mutableStateOf("") }
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

    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
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
                        text = { Text(tab.title) },
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
