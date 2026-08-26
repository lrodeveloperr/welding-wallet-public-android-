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
fun OnboardingScreen(onContinue: () -> Unit) {
    var privacy by remember { mutableStateOf(false) }
    var terms by remember { mutableStateOf(false) }
    var safety by remember { mutableStateOf(false) }
    Surface(color = Pearl, modifier = Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 30.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                Modifier.size(68.dp),
                contentAlignment = Alignment.Center,
            ) {
                Surface(shape = MaterialTheme.shapes.extraLarge, color = SteelBlueSoft) {
                    Box(Modifier.size(68.dp), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.PropaneTank, contentDescription = null, tint = SteelBlue, modifier = Modifier.size(34.dp))
                    }
                }
            }
            Spacer(Modifier.height(22.dp))
            Text("Welding Gas Wallet", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            Text(
                "Keep a clean personal record of your cylinders, suppliers, refills, exchanges, costs and reminders — stored on this device.",
                style = MaterialTheme.typography.bodyLarge,
                color = MutedInk,
            )
            Spacer(Modifier.height(28.dp))
            OnboardingCheck(
                checked = privacy,
                onChecked = { privacy = it },
                title = "Privacy",
                body = "Core wallet data stays local. No account is required.",
            )
            OnboardingCheck(
                checked = terms,
                onChecked = { terms = it },
                title = "Terms of use",
                body = "The wallet records facts you enter; it is not a supplier or ownership authority.",
            )
            OnboardingCheck(
                checked = safety,
                onChecked = { safety = it },
                title = "Safety scope",
                body = "The app does not determine cylinder safety, fillability, inspection validity or gas suitability.",
            )
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = onContinue,
                enabled = privacy && terms && safety,
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) { Text("Continue") }
        }
    }
}

@Composable
private fun OnboardingCheck(
    checked: Boolean,
    onChecked: (Boolean) -> Unit,
    title: String,
    body: String,
) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp).clickable { onChecked(!checked) },
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Divider),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            Checkbox(checked = checked, onCheckedChange = onChecked)
            Spacer(Modifier.width(8.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(3.dp))
                Text(body, style = MaterialTheme.typography.bodySmall, color = MutedInk)
            }
        }
    }
}

@Composable
fun WalletHomeScreen(
    wallet: WalletData,
    contentPadding: PaddingValues,
    onCylinder: (String) -> Unit,
    onAdd: (AddCylinderDraft) -> Unit,
    onShowPaywall: () -> Unit,
) {
    var adding by remember { mutableStateOf(false) }
    val currentCount = wallet.cylinders.count { it.consumesCurrentSlot }
    val dueSoon = wallet.reminders.count {
        !it.completed && !it.dueAt.isAfter(Instant.now().plus(7, ChronoUnit.DAYS))
    }
    val currentCurrencySpend = wallet.events.mapNotNull { it.amount }
        .filter { it.normalizedCurrencyCode == wallet.settings.currencyCode }
        .sumOf { it.minorUnits }
    val isPro = wallet.entitlementCache.isProAt(Instant.now())

    Box(Modifier.fillMaxSize().padding(contentPadding)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 104.dp),
        ) {
            item {
                WalletTopBar(
                    title = "Welding Gas Wallet",
                    subtitle = if (isPro) "Pro · Local cylinder record" else "Local cylinder record",
                )
            }
            item {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    SummaryCard(
                        label = "Current",
                        value = currentCount.toString(),
                        icon = Icons.Rounded.PropaneTank,
                        modifier = Modifier.weight(1f),
                    )
                    SummaryCard(
                        label = "Due soon",
                        value = dueSoon.toString(),
                        icon = Icons.Rounded.NotificationsActive,
                        modifier = Modifier.weight(1f),
                        tone = AmberSoft,
                        iconTint = Amber,
                    )
                    SummaryCard(
                        label = "Recorded spend",
                        value = LocaleMoney.formatMinorUnits(currentCurrencySpend, wallet.settings.currencyCode, wallet.settings.locale),
                        icon = Icons.Rounded.Payments,
                        modifier = Modifier.weight(1.15f),
                        tone = WeldingGreenSoft,
                        iconTint = WeldingGreen,
                    )
                }
            }
            item {
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Your cylinders", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    if (!isPro && currentCount >= FREE_EDITABLE_CYLINDER_LIMIT) {
                        TextButton(onClick = onShowPaywall) { Text("Go Pro") }
                    }
                }
            }
            if (wallet.cylinders.isEmpty()) {
                item {
                    EmptyState(
                        icon = Icons.Rounded.PropaneTank,
                        title = "No cylinders yet",
                        body = "Add your first bottle and the wallet starts building its history.",
                        actionLabel = "Add cylinder",
                        onAction = { adding = true },
                    )
                }
            } else {
                items(wallet.cylinders.sortedWith(compareByDescending<Cylinder> { it.consumesCurrentSlot }.thenByDescending { it.updatedAt }), key = { it.id }) { cylinder ->
                    CylinderCard(
                        cylinder = cylinder,
                        supplier = wallet.suppliers.firstOrNull { it.id == cylinder.supplierId },
                        locale = wallet.settings.locale,
                        onClick = { onCylinder(cylinder.id) },
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 5.dp),
                    )
                }
            }
        }
        ExtendedFloatingActionButton(
            onClick = { adding = true },
            icon = { Icon(Icons.Rounded.Add, contentDescription = null) },
            text = { Text("Add cylinder") },
            modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
        )
    }

    if (adding) {
        AddCylinderSheet(
            wallet = wallet,
            onDismiss = { adding = false },
            onSubmit = { adding = false; onAdd(it) },
        )
    }
}
