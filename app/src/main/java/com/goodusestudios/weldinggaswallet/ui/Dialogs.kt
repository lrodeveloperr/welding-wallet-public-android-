package com.goodusestudios.weldinggaswallet.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import com.goodusestudios.weldinggaswallet.backend.domain.*
import com.goodusestudios.weldinggaswallet.backend.money.LocaleMoney
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AddCylinderSheet(
    wallet: WalletData,
    onDismiss: () -> Unit,
    onSubmit: (AddCylinderDraft) -> Unit,
) {
    var nickname by remember { mutableStateOf("") }
    var gasType by remember { mutableStateOf("") }
    var capacity by remember { mutableStateOf("") }
    var capacityUnit by remember { mutableStateOf(wallet.settings.defaultVolumeUnit) }
    var serial by remember { mutableStateOf("") }
    var relationship by remember { mutableStateOf(RelationshipType.owned) }
    var supplierId by remember { mutableStateOf<String?>(null) }
    var amount by remember { mutableStateOf("") }
    var supplierMenu by remember { mutableStateOf(false) }
    var unitMenu by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Text("Add cylinder", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(6.dp))
            Text("Save the facts you know now. You can add more detail later.", color = MutedInk)
            Spacer(Modifier.height(20.dp))
            OutlinedTextField(
                value = nickname, onValueChange = { nickname = it },
                label = { Text("Nickname") }, placeholder = { Text("Shop argon") },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = gasType, onValueChange = { gasType = it },
                label = { Text("Gas / mix") }, placeholder = { Text("Argon 75/25") },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
            )
            Spacer(Modifier.height(16.dp))
            Text("Relationship", style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RelationshipType.entries.forEach { item ->
                    FilterChip(
                        selected = relationship == item,
                        onClick = { relationship = item },
                        label = { Text(relationshipLabel(item)) },
                        leadingIcon = if (relationship == item) { { Icon(Icons.Rounded.Check, null, Modifier.size(16.dp)) } } else null,
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = capacity, onValueChange = { capacity = it },
                    label = { Text("Capacity") }, modifier = Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
                )
                Box(Modifier.weight(0.8f)) {
                    OutlinedButton(onClick = { unitMenu = true }, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                        Text(capacityUnit)
                    }
                    DropdownMenu(expanded = unitMenu, onDismissRequest = { unitMenu = false }) {
                        listOf("L", "m3", "ft3", "kg", "lb").forEach {
                            DropdownMenuItem(text = { Text(it) }, onClick = { capacityUnit = it; unitMenu = false })
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = serial, onValueChange = { serial = it }, label = { Text("Serial number (optional)") },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            Box {
                OutlinedButton(onClick = { supplierMenu = true }, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                    Text(wallet.suppliers.firstOrNull { it.id == supplierId }?.name ?: "No supplier")
                }
                DropdownMenu(expanded = supplierMenu, onDismissRequest = { supplierMenu = false }) {
                    DropdownMenuItem(text = { Text("No supplier") }, onClick = { supplierId = null; supplierMenu = false })
                    wallet.suppliers.forEach { supplier ->
                        DropdownMenuItem(text = { Text(supplier.name) }, onClick = { supplierId = supplier.id; supplierMenu = false })
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = amount, onValueChange = { amount = it },
                label = { Text("Acquisition cost (${wallet.settings.currencyCode})") },
                modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
            )
            Spacer(Modifier.height(22.dp))
            Button(
                onClick = {
                    onSubmit(
                        AddCylinderDraft(
                            nickname = nickname,
                            gasType = gasType,
                            relationship = relationship,
                            capacityValue = capacity.trim().takeIf { it.isNotEmpty() }?.let {
                                LocaleMoney.parseMajor(it, wallet.settings.locale)
                            },
                            capacityUnit = capacityUnit,
                            serialNumber = serial.trim().ifEmpty { null },
                            supplierId = supplierId,
                            acquisitionAmount = LocaleMoney.parseMoney(amount, wallet.settings.currencyCode, wallet.settings.locale),
                            acquiredAt = Instant.now(),
                        )
                    )
                },
                enabled = nickname.isNotBlank() && gasType.isNotBlank(),
                modifier = Modifier.fillMaxWidth().height(54.dp),
            ) { Text("Save cylinder") }
        }
    }
}

enum class RecordKind { Refill, Exchange, Cost }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordActionSheet(
    wallet: WalletData,
    cylinder: Cylinder,
    kind: RecordKind,
    onDismiss: () -> Unit,
    onSubmit: (supplierId: String?, amount: Money?, note: String?) -> Unit,
) {
    var supplierId by remember { mutableStateOf(cylinder.supplierId) }
    var supplierMenu by remember { mutableStateOf(false) }
    var amount by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    val title = when (kind) {
        RecordKind.Refill -> "Record refill"
        RecordKind.Exchange -> "Record exchange"
        RecordKind.Cost -> "Record cost"
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
            Text(title, style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(6.dp))
            Text(cylinder.nickname + " · " + cylinder.gasType, color = MutedInk)
            Spacer(Modifier.height(20.dp))
            Box {
                OutlinedButton(onClick = { supplierMenu = true }, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                    Text(wallet.suppliers.firstOrNull { it.id == supplierId }?.name ?: "No supplier")
                }
                DropdownMenu(expanded = supplierMenu, onDismissRequest = { supplierMenu = false }) {
                    DropdownMenuItem(text = { Text("No supplier") }, onClick = { supplierId = null; supplierMenu = false })
                    wallet.suppliers.forEach { supplier ->
                        DropdownMenuItem(text = { Text(supplier.name) }, onClick = { supplierId = supplier.id; supplierMenu = false })
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = amount, onValueChange = { amount = it },
                label = { Text("Amount (${wallet.settings.currencyCode})") },
                modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = note, onValueChange = { note = it }, label = { Text("Note (optional)") },
                modifier = Modifier.fillMaxWidth(), minLines = 2,
            )
            Spacer(Modifier.height(20.dp))
            Button(
                onClick = {
                    val money = LocaleMoney.parseMoney(amount, wallet.settings.currencyCode, wallet.settings.locale)
                    onSubmit(supplierId, money, note.trim().ifEmpty { null })
                },
                enabled = kind != RecordKind.Cost || LocaleMoney.parseMoney(amount, wallet.settings.currencyCode, wallet.settings.locale) != null,
                modifier = Modifier.fillMaxWidth().height(54.dp),
            ) { Text("Save") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ReminderSheet(
    cylinder: Cylinder,
    onDismiss: () -> Unit,
    onSubmit: (ReminderKind, String, Instant) -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf(ReminderKind.refill) }
    var days by remember { mutableStateOf("30") }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
            Text("Add reminder", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(6.dp))
            Text(cylinder.nickname, color = MutedInk)
            Spacer(Modifier.height(18.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ReminderKind.entries.forEach { item ->
                    FilterChip(
                        selected = kind == item,
                        onClick = { kind = item },
                        label = { Text(item.name.replaceFirstChar { it.uppercase() }) },
                    )
                }
            }
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = title, onValueChange = { title = it },
                label = { Text("Reminder title") }, placeholder = { Text("Check refill") },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = days, onValueChange = { days = it.filter(Char::isDigit) },
                label = { Text("Days from now") }, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), singleLine = true,
            )
            Spacer(Modifier.height(20.dp))
            Button(
                onClick = {
                    val due = Instant.now().plus((days.toLongOrNull() ?: 0L), ChronoUnit.DAYS)
                    onSubmit(kind, title, due)
                },
                enabled = title.isNotBlank() && (days.toLongOrNull() ?: -1L) >= 0L,
                modifier = Modifier.fillMaxWidth().height(54.dp),
            ) { Text("Save reminder") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallSheet(
    products: List<StoreProduct>,
    billingConfigured: Boolean,
    onDismiss: () -> Unit,
    onPurchase: (String) -> Unit,
    onRestore: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp)) {
            Text("Keep every current cylinder editable", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            Text("Your first three current cylinders stay fully usable. Pro removes the current-cylinder limit without deleting or hiding history.", color = MutedInk)
            Spacer(Modifier.height(20.dp))
            if (products.isEmpty()) {
                Card(colors = CardDefaults.cardColors(containerColor = SteelBlueSoft), shape = MaterialTheme.shapes.large) {
                    Text(
                        if (billingConfigured) "Google Play pricing is temporarily unavailable."
                        else "This test APK has no Play license key. Install the Play-connected build to purchase Pro.",
                        modifier = Modifier.padding(16.dp), color = Ink,
                    )
                }
            } else {
                products.forEach { product ->
                    OutlinedCard(Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
                        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Column {
                                Text(if (product.isDefault) "Annual Pro" else "Monthly Pro", fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
                                Text(product.localizedPeriodLabel, color = MutedInk)
                            }
                            Button(onClick = { onPurchase(product.id) }) { Text(product.localizedPrice) }
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onRestore, modifier = Modifier.fillMaxWidth()) { Text("Restore purchases") }
        }
    }
}

@Composable
fun SupplierDialog(
    onDismiss: () -> Unit,
    onSubmit: (String, String?) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add supplier") },
        text = {
            Column {
                OutlinedTextField(name, { name = it }, label = { Text("Supplier name") }, singleLine = true)
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(notes, { notes = it }, label = { Text("Notes (optional)") }, minLines = 2)
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onSubmit(name, notes.trim().ifEmpty { null }) }) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
