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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.agentusagebar.android.data.model.UsageMetricPreferences
import com.agentusagebar.android.data.model.UsageProvider
import com.agentusagebar.android.ui.components.ProviderDetailSection
import com.agentusagebar.android.ui.components.ProviderOverviewGrid
import com.agentusagebar.android.ui.components.formatUpdated
import com.agentusagebar.android.ui.settings.SettingsScreen
import com.agentusagebar.android.widget.formatClaudePlanRow
import com.agentusagebar.android.widget.formatCursorPlanRow
import com.agentusagebar.android.widget.formatCursorSpendRow
import kotlinx.coroutines.delay

@Composable
fun UsageApp(
    viewModel: UsageViewModel,
    initialDestination: String = "home",
) {
    val navController = rememberNavController()
    val settings by viewModel.settings.collectAsStateWithLifecycle()

    NavHost(navController = navController, startDestination = initialDestination) {
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
                onBack = {
                    if (!navController.popBackStack()) {
                        navController.navigate("home") { launchSingleTop = true }
                    }
                },
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
    val trustedDevices by viewModel.trustedDevices.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val resetCreditState by viewModel.resetCreditState.collectAsStateWithLifecycle()
    val resetCreditSummary by viewModel.resetCreditSummary.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                viewModel.refresh()
                delay(60_000)
            }
        }
    }

    val selectedState = snapshot.providers[selected]
    val paired = trustedDevices.isNotEmpty()

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
                preferredProvider = appSettings.widgetProvider,
                primaryMetric = appSettings.primaryMetric,
                secondaryMetric = appSettings.secondaryMetric,
                fillMode = appSettings.fillMode,
            )

            HorizontalDivider()

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = selected.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = {
                        val uri = Uri.parse(selected.usagePageUrl)
                        runCatching {
                            CustomTabsIntent.Builder().build()
                                .launchUrl(context, uri)
                        }.onFailure {
                            context.startActivity(Intent(Intent.ACTION_VIEW, uri))
                        }
                    },
                ) {
                    Text("Details")
                }
            }

            when {
                !paired -> {
                    Text(
                        text = "Pair with the Agent Usage Bar app on your Mac to see usage here.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Button(onClick = onOpenSettings) { Text("Open Settings to pair") }
                }

                selectedState?.isConfigured != true -> {
                    Text(
                        text = "Not configured on the Mac.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }

                selectedState.metrics.isEmpty() &&
                    selectedState.error == null &&
                    !snapshot.macUnreachable -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.height(18.dp))
                        Spacer(modifier = Modifier.padding(6.dp))
                        Text("Loading…")
                    }
                }

                else -> {
                    val usesPreferredStats = selected == appSettings.widgetProvider
                    val defaults = UsageMetricPreferences.defaults(selected)

                    when (selected) {
                        UsageProvider.CURSOR -> {
                            val planInfo = snapshot.cursorPlanInfo?.planInfo
                            val renewsAt = planInfo?.billingCycleEnd?.toDoubleOrNull()?.toLong()
                            formatCursorPlanRow(
                                planName = planInfo?.planName,
                                price = planInfo?.price,
                                renewsAtEpochMs = renewsAt,
                            )?.let { line ->
                                Text(
                                    text = line,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            formatCursorSpendRow(
                                usedAmountCents = planInfo?.usedAmountCents,
                                includedAmountCents = planInfo?.includedAmountCents,
                            )?.let { line ->
                                Text(
                                    text = line,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        UsageProvider.CLAUDE -> {
                            formatClaudePlanRow(
                                planLabel = snapshot.claudeProfile?.planLabel,
                                subscriptionStatus = snapshot.claudeProfile
                                    ?.organization
                                    ?.subscriptionStatus,
                            )?.let { line ->
                                Text(
                                    text = line,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        UsageProvider.OPENAI -> {
                            snapshot.openAIPlanType?.takeIf { it.isNotBlank() }?.let { planType ->
                                Text(
                                    text = planType,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        else -> Unit
                    }

                    ProviderDetailSection(
                        metrics = selectedState?.metrics.orEmpty(),
                        style = appSettings.detailStyle,
                        provider = selected,
                        primaryMetric = if (usesPreferredStats) {
                            appSettings.primaryMetric
                        } else {
                            defaults.first
                        },
                        secondaryMetric = if (usesPreferredStats) {
                            appSettings.secondaryMetric
                        } else {
                            defaults.second
                        },
                        fillMode = appSettings.fillMode,
                    )

                    if (selected == UsageProvider.OPENAI) {
                        if (resetCreditSummary.availableCount > 0) {
                            val expiresLabel = resetCreditSummary.nextExpiresInDays?.let {
                                " · next expires in ${it}d"
                            }.orEmpty()
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "${resetCreditSummary.availableCount} banked$expiresLabel",
                                    style = MaterialTheme.typography.bodyMedium,
                                    modifier = Modifier.weight(1f),
                                )
                                Button(
                                    onClick = viewModel::beginResetCreditConfirm,
                                    enabled = !snapshot.macUnreachable &&
                                        resetCreditState !is ResetCreditUiState.InFlight &&
                                        resetCreditSummary.soonestCreditId != null,
                                ) {
                                    Text("Use reset")
                                }
                            }
                            if (snapshot.macUnreachable) {
                                Text(
                                    text = "Mac unreachable",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        when (val state = resetCreditState) {
                            is ResetCreditUiState.Outcome -> Text(
                                text = state.message,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            is ResetCreditUiState.Error -> Text(
                                text = state.message,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                            else -> Unit
                        }
                    }
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
                text = footerCopy(snapshot),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }

    if (resetCreditState is ResetCreditUiState.Confirming) {
        AlertDialog(
            onDismissRequest = viewModel::cancelResetCreditConfirm,
            title = { Text("Use reset credit") },
            text = {
                Text(
                    "Use a reset credit? This redeems one credit on your account " +
                        "and clears the current rate-limit windows. It cannot be undone.",
                )
            },
            confirmButton = {
                TextButton(onClick = viewModel::confirmResetCredit) {
                    Text("Use credit")
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::cancelResetCreditConfirm) {
                    Text("Cancel")
                }
            },
        )
    }
}

internal fun footerCopy(snapshot: com.agentusagebar.android.data.model.AppUsageSnapshot): String {
    if (snapshot.macUnreachable) {
        val since = snapshot.lastSuccessfulPullEpochMs
        return if (since == null || since == 0L) {
            "Mac unreachable"
        } else {
            "Mac unreachable since ${formatUpdated(since)}"
        }
    }
    val asOf = "As of ${formatUpdated(snapshot.generatedAtEpochMs)}"
    val name = snapshot.sourceDesktopName
    return if (snapshot.pairedDesktopCount > 1 && !name.isNullOrBlank()) {
        "$asOf · $name"
    } else {
        asOf
    }
}
