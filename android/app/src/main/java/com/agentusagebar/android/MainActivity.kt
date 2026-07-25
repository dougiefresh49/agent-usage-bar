package com.agentusagebar.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.agentusagebar.android.ui.theme.AgentUsageBarTheme
import com.agentusagebar.android.ui.usage.UsageApp
import com.agentusagebar.android.ui.usage.UsageViewModel
import com.agentusagebar.android.ui.usage.UsageViewModelFactory

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val initialDestination = if (intent.getBooleanExtra(EXTRA_OPEN_SETTINGS, false)) {
            "settings"
        } else {
            "home"
        }
        setContent {
            AgentUsageBarTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val viewModel: UsageViewModel = viewModel(
                        factory = UsageViewModelFactory(AgentUsageBarApp.instance.repository),
                    )
                    UsageApp(
                        viewModel = viewModel,
                        initialDestination = initialDestination,
                    )
                }
            }
        }
    }

    companion object {
        const val EXTRA_OPEN_SETTINGS = "com.agentusagebar.android.extra.OPEN_SETTINGS"
    }
}
