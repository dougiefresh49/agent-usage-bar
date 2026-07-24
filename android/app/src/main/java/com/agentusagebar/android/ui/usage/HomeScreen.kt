package com.agentusagebar.android.ui.usage

import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
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
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.ui.components.ProviderDetailSection
import com.agentusagebar.android.ui.components.ProviderOverviewGrid
import com.agentusagebar.android.ui.components.formatUpdated
import com.agentusagebar.android.ui.settings.SettingsScreen

@Composable
fun UsageApp(viewModel: UsageViewModel) {
    val navController = rememberNavController()
    val settings by viewModel.settings.collectAsStateWithLifecycle()

    NavHost(navController = navController, startDestination = "home") {
        composable("home") {
            if (!settings.setupComplete) {
                SetupScreen(
                    settings = settings,
                    onPollingChange = viewModel::setPollingMinutes,
                    onWidgetProviderChange = viewModel::setWidgetProvider,
                    onComplete = viewModel::completeSetup,
                )
            } else {
                HomeScreen(
                    viewModel = viewModel,
                    onOpenSettings = { navController.navigate("settings") },
                )
            }
        }
        composable("settings") {
            SettingsScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(
    viewModel: UsageViewModel,
    onOpenSettings: () -> Unit,
) {
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val appSettings by viewModel.settings.collectAsStateWithLifecycle()
    val selected by viewModel.selectedProvider.collectAsStateWithLifecycle()
    val refreshing by viewModel.isRefreshing.collectAsStateWithLifecycle()
    val awaitingCode by viewModel.awaitingClaudeCode.collectAsStateWithLifecycle()
    val claudeCode by viewModel.claudeCode.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current

    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    val selectedState = snapshot.providers[selected]
    val latestUpdated = snapshot.providers.values.mapNotNull { it.updatedAtEpochMs }.maxOrNull()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("AI Usage") },
                actions = {
                    IconButton(onClick = viewModel::refresh, enabled = !refreshing) {
                        if (refreshing) {
                            CircularProgressIndicator(modifier = Modifier.height(18.dp))
                        } else {
                            Icon(Icons.Outlined.Refresh, contentDescription = "Refresh")
                        }
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Outlined.Settings, contentDescription = "Settings")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Overview",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            ProviderOverviewGrid(
                providers = snapshot.providers,
                selected = selected,
                onSelect = viewModel::selectProvider,
                columns = appSettings.textSize.overviewColumns,
            )

            HorizontalDivider()

            Text(
                text = selected.displayName,
                style = MaterialTheme.typography.titleMedium,
            )

            when {
                selected == UsageProvider.CLAUDE && awaitingCode -> {
                    Text("Paste the code from your browser:")
                    OutlinedTextField(
                        value = claudeCode,
                        onValueChange = viewModel::setClaudeCode,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { Text("code#state") },
                    )
                    Row {
                        TextButton(onClick = viewModel::cancelClaudeOAuth) { Text("Cancel") }
                        Spacer(modifier = Modifier.weight(1f))
                        Button(
                            onClick = viewModel::submitClaudeCode,
                            enabled = claudeCode.isNotBlank(),
                        ) { Text("Submit") }
                    }
                }

                selectedState?.isConfigured != true -> {
                    Text(
                        text = when (selected) {
                            UsageProvider.CLAUDE -> "Connect Claude to view account limits."
                            UsageProvider.OPENAI -> "Add a ChatGPT session token in Settings."
                            UsageProvider.CURSOR -> "Add a Cursor session token in Settings."
                            UsageProvider.ELEVENLABS -> "Add an ElevenLabs API key in Settings."
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    if (selected == UsageProvider.CLAUDE) {
                        Button(
                            onClick = {
                                val url = viewModel.startClaudeOAuth()
                                runCatching {
                                    CustomTabsIntent.Builder().build()
                                        .launchUrl(context, Uri.parse(url))
                                }.onFailure {
                                    context.startActivity(
                                        Intent(Intent.ACTION_VIEW, Uri.parse(url)),
                                    )
                                }
                            },
                        ) { Text("Sign in with Claude") }
                    } else {
                        TextButton(onClick = onOpenSettings) { Text("Open Settings") }
                    }
                }

                selectedState.metrics.isEmpty() && selectedState.error == null -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.height(18.dp))
                        Spacer(modifier = Modifier.padding(6.dp))
                        Text("Loading…")
                    }
                }

                else -> {
                    ProviderDetailSection(
                        metrics = selectedState.metrics,
                        style = appSettings.detailStyle,
                    )
                }
            }

            selectedState?.error?.let { error ->
                Text(
                    text = error,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Updated ${formatUpdated(latestUpdated)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}
