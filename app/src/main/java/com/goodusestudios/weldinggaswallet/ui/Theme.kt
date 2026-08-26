package com.goodusestudios.weldinggaswallet.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Ink = Color(0xFF17202D)
val MutedInk = Color(0xFF687384)
val Pearl = Color(0xFFF7F8FA)
val Surface = Color(0xFFFFFFFF)
val SteelBlue = Color(0xFF345D7E)
val SteelBlueSoft = Color(0xFFE6EEF5)
val WeldingGreen = Color(0xFF287A5A)
val WeldingGreenSoft = Color(0xFFE5F3EC)
val Amber = Color(0xFF9A6700)
val AmberSoft = Color(0xFFFFF2CF)
val Danger = Color(0xFFB3261E)
val Divider = Color(0xFFE5E8ED)

private val WalletColors = lightColorScheme(
    primary = SteelBlue,
    onPrimary = Color.White,
    primaryContainer = SteelBlueSoft,
    onPrimaryContainer = Ink,
    secondary = WeldingGreen,
    onSecondary = Color.White,
    secondaryContainer = WeldingGreenSoft,
    onSecondaryContainer = Ink,
    background = Pearl,
    onBackground = Ink,
    surface = Surface,
    onSurface = Ink,
    surfaceVariant = Color(0xFFF0F2F5),
    onSurfaceVariant = MutedInk,
    outline = Color(0xFFCCD2DA),
    outlineVariant = Divider,
    error = Danger,
)

@Composable
fun WeldingWalletTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = WalletColors, content = content)
}
