package com.goodusestudios.weldinggaswallet.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.goodusestudios.weldinggaswallet.backend.LegalLinks
import com.goodusestudios.weldinggaswallet.backend.domain.*
import com.goodusestudios.weldinggaswallet.backend.money.LocaleMoney
import java.time.Instant
import java.time.temporal.ChronoUnit


@Composable
fun SuppliersScreen(
    wallet: WalletData,
    onBack: () -> Unit,
    onCreate: (String, String?) -> Unit,
    onDelete: (String) -> Unit,
) {
    var adding by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        WalletTopBar("Suppliers", "Optional references for cylinders and costs", onBack = onBack, action = { adding = true }, actionIcon = Icons.Rounded.Add)
        if (wallet.suppliers.isEmpty()) {
            EmptyState(Icons.Rounded.Storefront, "No suppliers", "Add a supplier once, then reuse it across cylinder records.", "Add supplier") { adding = true }
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 6.dp)) {
                items(wallet.suppliers.sortedBy { it.name.lowercase() }, key = { it.id }) { supplier ->
                    Card(
                        Modifier.fillMaxWidth().padding(vertical = 5.dp),
                        colors = CardDefaults.cardColors(containerColor = Surface),
                        border = BorderStroke(1.dp, Divider),
                    ) {
                        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Storefront, null, tint = SteelBlue)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(supplier.name, fontWeight = FontWeight.SemiBold)
                                supplier.notes?.let { Text(it, color = MutedInk, style = MaterialTheme.typography.bodySmall, maxLines = 1) }
                            }
                            IconButton(onClick = { onDelete(supplier.id) }) { Icon(Icons.Rounded.DeleteOutline, "Delete", tint = Danger) }
                        }
                    }
                }
            }
        }
    }
    if (adding) SupplierDialog(onDismiss = { adding = false }, onSubmit = { name, notes -> adding = false; onCreate(name, notes) })
}

@Composable
fun SettingsScreen(
    wallet: WalletData,
    contentPadding: PaddingValues,
    billingConfigured: Boolean,
    onToggleReminders: (Boolean) -> Unit,
    onRequestNotifications: () -> Unit,
    onSuppliers: () -> Unit,
    onUpdateSettings: (String?, String?, String?, String?) -> Unit,
    onShowPaywall: () -> Unit,
    onManageSubscription: () -> Unit,
) {
    val context = LocalContext.current
    val isPro = wallet.entitlementCache.isProAt(Instant.now())
    var currencyMenu by remember { mutableStateOf(false) }
    var localeMenu by remember { mutableStateOf(false) }
    var massMenu by remember { mutableStateOf(false) }
    var volumeMenu by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(contentPadding),
        contentPadding = PaddingValues(bottom = 28.dp),
    ) {
        item { WalletTopBar("Settings", "Wallet preferences and account-free controls") }
        item {
            SettingCard {
                SettingRow(
                    icon = Icons.Rounded.WorkspacePremium,
                    title = if (isPro) "Welding Gas Wallet Pro" else "Free tier",
                    subtitle = if (isPro) "Unlimited current-cylinder editing" else "Up to 3 current cylinders editable",
                    action = {
                        TextButton(onClick = if (isPro) onManageSubscription else onShowPaywall) {
                            Text(if (isPro) "Manage" else "Upgrade")
                        }
                    },
                )
                if (!billingConfigured) {
                    Text(
                        "This test APK is not carrying the Play license key; purchase verification activates in the Play-connected build.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MutedInk,
                        modifier = Modifier.padding(start = 54.dp, end = 8.dp, bottom = 8.dp),
                    )
                }
            }
        }
        item { SectionTitle("Wallet") }
        item {
            SettingCard {
                SettingRow(Icons.Rounded.Storefront, "Suppliers", "${wallet.suppliers.size} saved", onClick = onSuppliers)
                HorizontalDivider(color = Divider)
                Box {
                    SettingRow(Icons.Rounded.Language, "Language", wallet.settings.locale, onClick = { localeMenu = true })
                    DropdownMenu(expanded = localeMenu, onDismissRequest = { localeMenu = false }) {
                        SUPPORTED_LOCALES.forEach { locale ->
                            DropdownMenuItem(text = { Text(locale) }, onClick = { localeMenu = false; onUpdateSettings(locale, null, null, null) })
                        }
                    }
                }
                HorizontalDivider(color = Divider)
                Box {
                    SettingRow(Icons.Rounded.CurrencyExchange, "Currency", wallet.settings.currencyCode, onClick = { currencyMenu = true })
                    DropdownMenu(expanded = currencyMenu, onDismissRequest = { currencyMenu = false }) {
                        listOf("USD", "CAD", "GBP", "EUR", "AUD", "NZD", "JPY", "CNY", "INR", "NGN", "ZAR", "AED", "SAR", "BRL", "MXN").forEach { code ->
                            DropdownMenuItem(text = { Text(code) }, onClick = { currencyMenu = false; onUpdateSettings(null, code, null, null) })
                        }
                    }
                }
                HorizontalDivider(color = Divider)
                Box {
                    SettingRow(Icons.Rounded.Straighten, "Mass unit", wallet.settings.defaultMassUnit, onClick = { massMenu = true })
                    DropdownMenu(expanded = massMenu, onDismissRequest = { massMenu = false }) {
                        listOf("kg", "lb").forEach { unit -> DropdownMenuItem(text = { Text(unit) }, onClick = { massMenu = false; onUpdateSettings(null, null, unit, null) }) }
                    }
                }
                HorizontalDivider(color = Divider)
                Box {
                    SettingRow(Icons.Rounded.Straighten, "Volume unit", wallet.settings.defaultVolumeUnit, onClick = { volumeMenu = true })
                    DropdownMenu(expanded = volumeMenu, onDismissRequest = { volumeMenu = false }) {
                        listOf("L", "m3", "ft3").forEach { unit -> DropdownMenuItem(text = { Text(unit) }, onClick = { volumeMenu = false; onUpdateSettings(null, null, null, unit) }) }
                    }
                }
            }
        }
        item { SectionTitle("Reminders") }
        item {
            SettingCard {
                SettingRow(
                    icon = Icons.Rounded.Notifications,
                    title = "Cylinder reminders",
                    subtitle = if (wallet.settings.remindersEnabled) "Enabled" else "Off",
                    action = { Switch(checked = wallet.settings.remindersEnabled, onCheckedChange = onToggleReminders) },
                )
                if (wallet.settings.remindersEnabled) {
                    HorizontalDivider(color = Divider)
                    SettingRow(Icons.Rounded.Security, "Notification permission", "Android controls delivery", onClick = onRequestNotifications)
                }
            }
        }
        item { SectionTitle("Legal & support") }
        item {
            SettingCard {
                LegalSetting("Privacy policy", LegalLinks.privacy, context)
                HorizontalDivider(color = Divider)
                LegalSetting("Terms of use", LegalLinks.terms, context)
                HorizontalDivider(color = Divider)
                LegalSetting("Safety disclaimer", LegalLinks.disclaimer, context)
                HorizontalDivider(color = Divider)
                LegalSetting("Support", LegalLinks.support, context)
            }
        }
        item {
            Text(
                "The app records your facts. It does not determine legal ownership, cylinder safety, fillability, inspection validity, regulatory compliance or gas suitability.",
                style = MaterialTheme.typography.bodySmall,
                color = MutedInk,
                modifier = Modifier.padding(20.dp),
            )
        }
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 8.dp),
    )
}

@Composable
private fun SettingCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp),
        colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Divider),
        shape = MaterialTheme.shapes.large,
    ) { Column(content = content) }
}

@Composable
private fun SettingRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    action: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(shape = MaterialTheme.shapes.medium, color = SteelBlueSoft) {
            Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) { Icon(icon, null, tint = SteelBlue, modifier = Modifier.size(19.dp)) }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MutedInk)
        }
        if (action != null) action() else if (onClick != null) Icon(Icons.Rounded.ChevronRight, null, tint = MutedInk)
    }
}

@Composable
private fun LegalSetting(label: String, url: String, context: android.content.Context) {
    SettingRow(Icons.Rounded.OpenInNew, label, "Open in browser", onClick = {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    })
}
