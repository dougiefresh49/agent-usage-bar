package com.agentusagebar.android.ui.usage

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
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.agentusagebar.android.data.credentials.AppSettings
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.model.UsageProvider
import kotlin.math.roundToInt

@Composable
fun SetupScreen(
    settings: AppSettings,
    onPollingChange: (Int) -> Unit,
    onWidgetProviderChange: (UsageProvider) -> Unit,
    onComplete: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Welcome", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Connect providers first, then tweak appearance. Notification thresholds appear in Settings after each connection is added.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        HorizontalDivider()
        Text("1. Connections", style = MaterialTheme.typography.titleMedium)
        Text(
            "After you continue, use Settings → Connections to sign in with Claude or paste OpenAI / Cursor session tokens. Tokens stay on this phone only.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        HorizontalDivider()
        Text("2. Appearance", style = MaterialTheme.typography.titleMedium)
        Text("Polling Interval", style = MaterialTheme.typography.labelLarge)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SettingsStore.POLLING_OPTIONS.forEach { mins ->
                FilterChip(
                    selected = settings.pollingMinutes == mins,
                    onClick = { onPollingChange(mins) },
                    label = {
                        Text(if (mins == 60) "1h" else "${mins}m")
                    },
                )
            }
        }
        if (settings.pollingMinutes <= 5) {
            Text(
                "Frequent polling may cause rate limiting",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.tertiary,
            )
        }

        Text("Provider widget focus", style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            UsageProvider.entries.forEach { provider ->
                FilterChip(
                    selected = settings.widgetProvider == provider,
                    onClick = { onWidgetProviderChange(provider) },
                    label = { Text(provider.shortName) },
                )
            }
        }

        HorizontalDivider()
        Text("3. Notifications", style = MaterialTheme.typography.titleMedium)
        Text(
            "Per-provider alert thresholds show up in Settings → Notifications once that provider is connected.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(12.dp))
        Button(
            onClick = onComplete,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Get Started")
        }
    }
}

@Composable
fun ThresholdSlider(
    label: String,
    value: Int,
    onChange: (Int) -> Unit,
) {
    Column {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(label, modifier = Modifier.weight(1f))
            Text(if (value > 0) "$value%" else "Off")
        }
        Slider(
            value = value.toFloat(),
            onValueChange = { onChange((it / 5f).roundToInt() * 5) },
            valueRange = 0f..100f,
            steps = 19,
        )
    }
}
