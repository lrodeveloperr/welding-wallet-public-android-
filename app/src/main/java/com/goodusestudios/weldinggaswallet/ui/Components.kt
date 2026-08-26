package com.goodusestudios.weldinggaswallet.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.goodusestudios.weldinggaswallet.backend.domain.*
import com.goodusestudios.weldinggaswallet.backend.money.LocaleMoney
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun WalletTopBar(
    title: String,
    subtitle: String? = null,
    onBack: (() -> Unit)? = null,
    action: (() -> Unit)? = null,
    actionIcon: ImageVector = Icons.Rounded.MoreVert,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(Icons.Rounded.ArrowBack, contentDescription = "Back")
            }
            Spacer(Modifier.width(4.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            if (!subtitle.isNullOrBlank()) {
                Spacer(Modifier.height(2.dp))
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MutedInk)
            }
        }
        if (action != null) {
            IconButton(onClick = action) { Icon(actionIcon, contentDescription = null) }
        }
    }
}

@Composable
fun SummaryCard(
    label: String,
    value: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    tone: Color = SteelBlueSoft,
    iconTint: Color = SteelBlue,
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Divider),
    ) {
        Column(Modifier.padding(16.dp)) {
            Box(
                Modifier.size(38.dp).clip(CircleShape).background(tone),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.height(14.dp))
            Text(value, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(2.dp))
            Text(label, style = MaterialTheme.typography.bodySmall, color = MutedInk)
        }
    }
}

@Composable
fun CylinderCard(
    cylinder: Cylinder,
    supplier: Supplier?,
    locale: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Divider),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(SteelBlueSoft),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.PropaneTank, contentDescription = null, tint = SteelBlue)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        cylinder.nickname,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(8.dp))
                    LifecyclePill(cylinder.lifecycle)
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    buildString {
                        append(cylinder.gasType)
                        if (cylinder.capacityValue != null) {
                            append(" · ")
                            append(LocaleMoney.formatDecimal(cylinder.capacityValue, locale))
                            cylinder.capacityUnit?.let { append(" $it") }
                        }
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = Ink,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    supplier?.name ?: relationshipLabel(cylinder.relationship),
                    style = MaterialTheme.typography.bodySmall,
                    color = MutedInk,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = MutedInk)
        }
    }
}

@Composable
fun LifecyclePill(lifecycle: CylinderLifecycle) {
    val (label, bg, fg) = when (lifecycle) {
        CylinderLifecycle.active -> Triple("Active", WeldingGreenSoft, WeldingGreen)
        CylinderLifecycle.exchanged -> Triple("Exchanged", SteelBlueSoft, SteelBlue)
        CylinderLifecycle.returned -> Triple("Returned", AmberSoft, Amber)
        CylinderLifecycle.archived -> Triple("Archived", Color(0xFFF0F1F3), MutedInk)
    }
    Surface(shape = CircleShape, color = bg) {
        Text(
            label,
            color = fg,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
        )
    }
}

@Composable
fun ActionTile(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.clip(RoundedCornerShape(16.dp)).clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(46.dp).clip(CircleShape).background(if (enabled) SteelBlueSoft else Color(0xFFF0F1F3)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = if (enabled) SteelBlue else MutedInk)
        }
        Spacer(Modifier.height(7.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, color = if (enabled) Ink else MutedInk)
    }
}

@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    body: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 28.dp, vertical = 54.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(68.dp).clip(CircleShape).background(SteelBlueSoft), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = SteelBlue, modifier = Modifier.size(30.dp))
        }
        Spacer(Modifier.height(18.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(7.dp))
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MutedInk)
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(18.dp))
            Button(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
fun EventRow(event: CylinderEvent, wallet: WalletData) {
    val cylinder = wallet.cylinders.firstOrNull { it.id == event.cylinderId }
    val supplier = wallet.suppliers.firstOrNull { it.id == event.supplierId }
    Row(Modifier.fillMaxWidth().padding(vertical = 11.dp), verticalAlignment = Alignment.Top) {
        Box(
            Modifier.size(40.dp).clip(CircleShape).background(eventTone(event.type).first),
            contentAlignment = Alignment.Center,
        ) {
            Icon(eventIcon(event.type), contentDescription = null, tint = eventTone(event.type).second, modifier = Modifier.size(19.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(eventTitle(event.type), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                event.amount?.let {
                    Text(LocaleMoney.formatMoney(it, wallet.settings.locale), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(2.dp))
            Text(
                listOfNotNull(cylinder?.nickname, supplier?.name, event.note).joinToString(" · ").ifBlank { "Wallet history" },
                style = MaterialTheme.typography.bodySmall,
                color = MutedInk,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(3.dp))
            Text(formatInstant(event.occurredAt), style = MaterialTheme.typography.labelSmall, color = MutedInk)
        }
    }
}

fun formatInstant(value: Instant): String = DateTimeFormatter.ofPattern("MMM d, yyyy · h:mm a", Locale.getDefault())
    .withZone(ZoneId.systemDefault()).format(value)

fun formatDate(value: Instant): String = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault())
    .withZone(ZoneId.systemDefault()).format(value)

fun relationshipLabel(value: RelationshipType): String = when (value) {
    RelationshipType.owned -> "Owned"
    RelationshipType.rented -> "Rented"
    RelationshipType.leased -> "Leased"
    RelationshipType.deposit -> "Deposit"
    RelationshipType.notSure -> "Not sure"
}

fun eventTitle(type: CylinderEventType): String = when (type) {
    CylinderEventType.created -> "Cylinder added"
    CylinderEventType.acquisitionUpdated -> "Acquisition updated"
    CylinderEventType.cylinderUpdated -> "Cylinder updated"
    CylinderEventType.refill -> "Refill"
    CylinderEventType.exchange -> "Exchange"
    CylinderEventType.purchase -> "Purchase"
    CylinderEventType.rentalPayment -> "Rental payment"
    CylinderEventType.leasePayment -> "Lease payment"
    CylinderEventType.depositPaid -> "Deposit paid"
    CylinderEventType.depositReturned -> "Deposit returned"
    CylinderEventType.cost -> "Cost"
    CylinderEventType.supplierChanged -> "Supplier changed"
    CylinderEventType.relationshipChanged -> "Relationship changed"
    CylinderEventType.note -> "Note"
    CylinderEventType.photoAdded -> "Photo added"
    CylinderEventType.reminderCreated -> "Reminder added"
    CylinderEventType.reminderUpdated -> "Reminder updated"
    CylinderEventType.reminderCompleted -> "Reminder completed"
    CylinderEventType.reminderDeleted -> "Reminder deleted"
    CylinderEventType.returned -> "Returned"
    CylinderEventType.archived -> "Archived"
}

fun eventIcon(type: CylinderEventType): ImageVector = when (type) {
    CylinderEventType.refill -> Icons.Rounded.LocalGasStation
    CylinderEventType.exchange -> Icons.Rounded.SwapHoriz
    CylinderEventType.cost, CylinderEventType.purchase, CylinderEventType.rentalPayment,
    CylinderEventType.leasePayment, CylinderEventType.depositPaid, CylinderEventType.depositReturned -> Icons.Rounded.Payments
    CylinderEventType.reminderCreated, CylinderEventType.reminderUpdated,
    CylinderEventType.reminderCompleted, CylinderEventType.reminderDeleted -> Icons.Rounded.Notifications
    CylinderEventType.returned, CylinderEventType.archived -> Icons.Rounded.Inventory2
    else -> Icons.Rounded.History
}

private fun eventTone(type: CylinderEventType): Pair<Color, Color> = when (type) {
    CylinderEventType.cost, CylinderEventType.purchase, CylinderEventType.rentalPayment,
    CylinderEventType.leasePayment, CylinderEventType.depositPaid -> AmberSoft to Amber
    CylinderEventType.refill, CylinderEventType.exchange -> WeldingGreenSoft to WeldingGreen
    else -> SteelBlueSoft to SteelBlue
}
