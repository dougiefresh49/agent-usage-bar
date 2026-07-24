package com.agentusagebar.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Green = Color(0xFF34C759)
private val Yellow = Color(0xFFFFCC00)
private val Red = Color(0xFFFF3B30)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF9BB6FF),
    secondary = Green,
    tertiary = Yellow,
    error = Red,
    background = Color(0xFF121212),
    surface = Color(0xFF1C1B1F),
    surfaceVariant = Color(0xFF2B2930),
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF3D5AFE),
    secondary = Green,
    tertiary = Yellow,
    error = Red,
    background = Color(0xFFF7F7F8),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFF0F0F3),
)

@Composable
fun AgentUsageBarTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}

fun usageColor(percent: Double?): Color {
    val value = (percent ?: 0.0) / 100.0
    return when {
        value < 0.60 -> Green
        value < 0.80 -> Yellow
        else -> Red
    }
}
