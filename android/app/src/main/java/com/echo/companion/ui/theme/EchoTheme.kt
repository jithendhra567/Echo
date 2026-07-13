package com.echo.companion.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val Ink = Color(0xFF12141A)
private val Fog = Color(0xFFF3F1EC)
private val Accent = Color(0xFF2F6B4F)
private val AccentSoft = Color(0xFFD7E8DE)
private val Mist = Color(0xFFE7E4DD)

private val LightColors = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondary = Color(0xFF4A5560),
    background = Fog,
    surface = Color.White,
    onBackground = Ink,
    onSurface = Ink,
    surfaceVariant = Mist,
    primaryContainer = AccentSoft,
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8FCBAD),
    onPrimary = Ink,
    secondary = Color(0xFFB8C0C8),
    background = Color(0xFF0E1014),
    surface = Color(0xFF181B22),
    onBackground = Fog,
    onSurface = Fog,
    surfaceVariant = Color(0xFF242833),
    primaryContainer = Color(0xFF1E3A2D),
)

private val EchoTypography = androidx.compose.material3.Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.Bold,
        fontSize = 40.sp,
        lineHeight = 44.sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 26.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 16.sp,
        lineHeight = 22.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
)

@Composable
fun EchoTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = EchoTypography,
        content = content,
    )
}
