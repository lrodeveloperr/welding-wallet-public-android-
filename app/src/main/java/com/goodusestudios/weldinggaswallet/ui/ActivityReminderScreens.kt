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
fun ActivityScreen(wallet: WalletData, contentPadding: PaddingValues) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(contentPadding),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item { WalletTopBar("Activity", "Everything recorded across your wallet") }
        if (wallet.events.isEmpty()) {
            item { EmptyState(Icons.Rounded.History, "No activity yet", "Refills, exchanges, costs and changes will appear here.") }
        } else {
            items(wallet.events.sortedByDescending { it.occurredAt }, key = { it.id }) { event ->
                Surface(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                    color = Surface,
                ) {
                    Column {
                        EventRow(event, wallet)
                        HorizontalDivider(color = Divider)
                    }
                }
            }
        }
    }
}

@Composable
fun RemindersScreen(
    wallet: WalletData,
    contentPadding: PaddingValues,
    onComplete: (String) -> Unit,
    onDelete: (String) -> Unit,
    onRequestNotifications: () -> Unit,
) {
    val active = wallet.reminders.filterNot { it.completed }.sortedBy { it.dueAt }
    val completed = wallet.reminders.filter { it.completed }.sortedByDescending { it.dueAt }
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(contentPadding),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item { WalletTopBar("Reminders", "Refill, rental, lease and custom follow-ups") }
        if (wallet.settings.remindersEnabled) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp),
                    colors = CardDefaults.cardColors(containerColor = WeldingGreenSoft),
                    border = BorderStroke(1.dp, WeldingGreen.copy(alpha = 0.16f)),
                ) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.NotificationsActive, null, tint = WeldingGreen)
                        Spacer(Modifier.width(10.dp))
                        Text("System reminders are enabled.", modifier = Modifier.weight(1f), color = Ink)
                        TextButton(onClick = onRequestNotifications) { Text("Permission") }
                    }
                }
            }
        }
        if (active.isEmpty() && completed.isEmpty()) {
            item { EmptyState(Icons.Rounded.NotificationsNone, "No reminders", "Add a reminder from any current cylinder.") }
        } else {
            if (active.isNotEmpty()) item { ReminderSectionTitle("Upcoming") }
            items(active, key = { it.id }) { reminder ->
                ReminderRow(reminder, wallet, onComplete, onDelete)
            }
            if (completed.isNotEmpty()) item { ReminderSectionTitle("Completed") }
            items(completed, key = { it.id }) { reminder ->
                ReminderRow(reminder, wallet, onComplete = null, onDelete = onDelete)
            }
        }
    }
}

@Composable
private fun ReminderRow(
    reminder: Reminder,
    wallet: WalletData,
    onComplete: ((String) -> Unit)?,
    onDelete: (String) -> Unit,
) {
    val cylinder = wallet.cylinders.firstOrNull { it.id == reminder.cylinderId }
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 5.dp),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Divider),
    ) {
        Row(Modifier.padding(15.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Event, null, tint = if (reminder.completed) MutedInk else SteelBlue)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(reminder.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(3.dp))
                Text(
                    listOfNotNull(cylinder?.nickname, formatDate(reminder.dueAt)).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MutedInk,
                )
            }
            if (onComplete != null) {
                IconButton(onClick = { onComplete(reminder.id) }) { Icon(Icons.Rounded.CheckCircle, "Complete", tint = WeldingGreen) }
            }
            IconButton(onClick = { onDelete(reminder.id) }) { Icon(Icons.Rounded.DeleteOutline, "Delete", tint = Danger) }
        }
    }
}


@Composable
private fun ReminderSectionTitle(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 22.dp, bottom = 8.dp),
    )
}
