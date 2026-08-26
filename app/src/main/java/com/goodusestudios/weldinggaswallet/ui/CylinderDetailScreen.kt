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
fun CylinderDetailScreen(
    wallet: WalletData,
    cylinder: Cylinder,
    editDecision: EditDecision?,
    onBack: () -> Unit,
    onRefill: (String?, Money?, String?) -> Unit,
    onExchange: (String?, Money?, String?) -> Unit,
    onCost: (String?, Money?, String?) -> Unit,
    onReminder: (ReminderKind, String, Instant) -> Unit,
    onReturned: (String?) -> Unit,
    onArchive: () -> Unit,
    onShowPaywall: () -> Unit,
) {
    var recordKind by remember { mutableStateOf<RecordKind?>(null) }
    var reminderSheet by remember { mutableStateOf(false) }
    var confirmReturn by remember { mutableStateOf(false) }
    var confirmArchive by remember { mutableStateOf(false) }
    var tab by remember { mutableIntStateOf(0) }
    val supplier = wallet.suppliers.firstOrNull { it.id == cylinder.supplierId }
    val editable = editDecision == Editable
    val locked = editDecision is Locked
    val events = wallet.events.filter { it.cylinderId == cylinder.id }.sortedByDescending { it.occurredAt }
    val costEvents = events.filter { it.amount != null }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 28.dp)) {
        item {
            WalletTopBar(cylinder.nickname, cylinder.gasType, onBack = onBack)
        }
        item {
            Card(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                colors = CardDefaults.cardColors(containerColor = Surface),
                border = BorderStroke(1.dp, Divider),
                shape = MaterialTheme.shapes.extraLarge,
            ) {
                Column(Modifier.padding(18.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(shape = MaterialTheme.shapes.large, color = SteelBlueSoft) {
                            Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
                                Icon(Icons.Rounded.PropaneTank, null, tint = SteelBlue, modifier = Modifier.size(32.dp))
                            }
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(cylinder.gasType, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                LifecyclePill(cylinder.lifecycle)
                            }
                            Spacer(Modifier.height(4.dp))
                            Text(
                                listOfNotNull(
                                    supplier?.name,
                                    relationshipLabel(cylinder.relationship),
                                    cylinder.capacityValue?.let { LocaleMoney.formatDecimal(it, wallet.settings.locale) + " " + (cylinder.capacityUnit ?: "") },
                                ).joinToString(" · "),
                                color = MutedInk,
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                    if (editDecision is ReadOnly) {
                        Spacer(Modifier.height(14.dp))
                        Surface(color = AmberSoft, shape = MaterialTheme.shapes.medium) {
                            Text(editDecision.reason, modifier = Modifier.padding(12.dp), color = Amber, style = MaterialTheme.typography.bodySmall)
                        }
                    } else if (locked) {
                        Spacer(Modifier.height(14.dp))
                        Surface(color = SteelBlueSoft, shape = MaterialTheme.shapes.medium, modifier = Modifier.clickable(onClick = onShowPaywall)) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.Lock, null, tint = SteelBlue)
                                Spacer(Modifier.width(8.dp))
                                Text("This current cylinder is read-only after downgrade. Tap to restore Pro.", color = Ink, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }
        item {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                ActionTile(Icons.Rounded.LocalGasStation, "Refill", { recordKind = RecordKind.Refill }, editable, Modifier.weight(1f))
                ActionTile(Icons.Rounded.SwapHoriz, "Exchange", { recordKind = RecordKind.Exchange }, editable, Modifier.weight(1f))
                ActionTile(Icons.Rounded.Payments, "Cost", { recordKind = RecordKind.Cost }, editable, Modifier.weight(1f))
                ActionTile(Icons.Rounded.Notifications, "Reminder", { reminderSheet = true }, editable, Modifier.weight(1f))
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("Overview", "History", "Costs").forEachIndexed { index, label ->
                    FilterChip(selected = tab == index, onClick = { tab = index }, label = { Text(label) })
                }
            }
            Spacer(Modifier.height(8.dp))
        }
        when (tab) {
            0 -> item {
                Column(Modifier.padding(horizontal = 20.dp)) {
                    DetailCard("Cylinder details") {
                        DetailLine("Relationship", relationshipLabel(cylinder.relationship))
                        DetailLine("Supplier", supplier?.name ?: "Not recorded")
                        DetailLine("Serial", cylinder.serialNumber ?: "Not recorded")
                        DetailLine("Capacity", cylinder.capacityValue?.let { LocaleMoney.formatDecimal(it, wallet.settings.locale) + " " + (cylinder.capacityUnit ?: "") } ?: "Not recorded")
                        cylinder.acquisitionAmount?.let { DetailLine("Acquisition cost", LocaleMoney.formatMoney(it, wallet.settings.locale)) }
                        cylinder.acquiredAt?.let { DetailLine("Acquired", formatDate(it)) }
                    }
                    if (editable && cylinder.consumesCurrentSlot) {
                        Spacer(Modifier.height(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            OutlinedButton(onClick = { confirmReturn = true }, modifier = Modifier.weight(1f)) {
                                Icon(Icons.Rounded.AssignmentReturn, null); Spacer(Modifier.width(6.dp)); Text("Mark returned")
                            }
                            OutlinedButton(onClick = { confirmArchive = true }, modifier = Modifier.weight(1f)) {
                                Icon(Icons.Rounded.Archive, null); Spacer(Modifier.width(6.dp)); Text("Archive")
                            }
                        }
                    }
                }
            }
            1 -> {
                if (events.isEmpty()) item { EmptyState(Icons.Rounded.History, "No history", "Activity for this cylinder will appear here.") }
                else items(events, key = { it.id }) { event ->
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        EventRow(event, wallet)
                        HorizontalDivider(color = Divider)
                    }
                }
            }
            2 -> {
                if (costEvents.isEmpty()) item { EmptyState(Icons.Rounded.Payments, "No costs yet", "Record refills, exchanges or other costs to build spend history.") }
                else items(costEvents, key = { it.id }) { event ->
                    Column(Modifier.padding(horizontal = 20.dp)) {
                        EventRow(event, wallet)
                        HorizontalDivider(color = Divider)
                    }
                }
            }
        }
    }

    recordKind?.let { kind ->
        RecordActionSheet(
            wallet = wallet,
            cylinder = cylinder,
            kind = kind,
            onDismiss = { recordKind = null },
            onSubmit = { supplierId, amount, note ->
                recordKind = null
                when (kind) {
                    RecordKind.Refill -> onRefill(supplierId, amount, note)
                    RecordKind.Exchange -> onExchange(supplierId, amount, note)
                    RecordKind.Cost -> onCost(supplierId, amount, note)
                }
            },
        )
    }
    if (reminderSheet) {
        ReminderSheet(
            cylinder = cylinder,
            onDismiss = { reminderSheet = false },
            onSubmit = { kind, title, dueAt -> reminderSheet = false; onReminder(kind, title, dueAt) },
        )
    }
    if (confirmReturn) {
        ConfirmDialog(
            title = "Mark cylinder returned?",
            body = "It will remain visible with its full history, but free-tier editing stops because it is no longer current.",
            confirm = "Mark returned",
            onDismiss = { confirmReturn = false },
            onConfirm = { confirmReturn = false; onReturned(null) },
        )
    }
    if (confirmArchive) {
        ConfirmDialog(
            title = "Archive cylinder?",
            body = "Archiving keeps the complete record and removes it from the current-cylinder count.",
            confirm = "Archive",
            onDismiss = { confirmArchive = false },
            onConfirm = { confirmArchive = false; onArchive() },
        )
    }
}

@Composable
private fun DetailCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Divider),
        shape = MaterialTheme.shapes.large,
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            content()
        }
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Text(label, color = MutedInk, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun ConfirmDialog(
    title: String,
    body: String,
    confirm: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(body) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
