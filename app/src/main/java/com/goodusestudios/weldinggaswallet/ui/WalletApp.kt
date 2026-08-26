package com.goodusestudios.weldinggaswallet.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import com.goodusestudios.weldinggaswallet.WalletViewModel

private data class NavItem(val route: String, val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector)
private val mainNavItems = listOf(
    NavItem("wallet", "Wallet", Icons.Rounded.AccountBalanceWallet),
    NavItem("activity", "Activity", Icons.Rounded.History),
    NavItem("reminders", "Reminders", Icons.Rounded.Notifications),
    NavItem("settings", "Settings", Icons.Rounded.Settings),
)

@Composable
fun WalletApp(
    viewModel: WalletViewModel,
    requestNotificationPermission: () -> Unit,
) {
    WeldingWalletTheme {
        val wallet by viewModel.wallet.collectAsStateWithLifecycle()
        val loading by viewModel.loading.collectAsStateWithLifecycle()
        val paywallVisible by viewModel.paywallVisible.collectAsStateWithLifecycle()
        val products by viewModel.products.collectAsStateWithLifecycle()
        val snackbarHostState = remember { SnackbarHostState() }

        LaunchedEffect(Unit) {
            viewModel.messages.collect { snackbarHostState.showSnackbar(it) }
        }

        when {
            loading && wallet == null -> Box(Modifier.fillMaxSize()) {
                CircularProgressIndicator(modifier = Modifier.align(androidx.compose.ui.Alignment.Center))
            }
            wallet == null -> Box(Modifier.fillMaxSize()) {
                Text("Wallet could not be loaded.", modifier = Modifier.align(androidx.compose.ui.Alignment.Center))
            }
            wallet?.settings?.onboardingComplete != true -> OnboardingScreen(
                onContinue = { viewModel.completeOnboarding() },
            )
            else -> {
                val currentWallet = wallet!!
                val navController = rememberNavController()
                val backStack by navController.currentBackStackEntryAsState()
                val route = backStack?.destination?.route
                val showBottomBar = route in mainNavItems.map { it.route }

                Scaffold(
                    containerColor = Pearl,
                    snackbarHost = { SnackbarHost(snackbarHostState) },
                    bottomBar = {
                        if (showBottomBar) {
                            NavigationBar(containerColor = Surface) {
                                mainNavItems.forEach { item ->
                                    NavigationBarItem(
                                        selected = route == item.route,
                                        onClick = {
                                            navController.navigate(item.route) {
                                                popUpTo("wallet") { saveState = true }
                                                launchSingleTop = true
                                                restoreState = true
                                            }
                                        },
                                        icon = { Icon(item.icon, contentDescription = null) },
                                        label = { Text(item.label) },
                                    )
                                }
                            }
                        }
                    },
                ) { padding ->
                    NavHost(
                        navController = navController,
                        startDestination = "wallet",
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        composable("wallet") {
                            WalletHomeScreen(
                                wallet = currentWallet,
                                contentPadding = padding,
                                onCylinder = { navController.navigate("cylinder/$it") },
                                onAdd = { viewModel.addCylinder(it) },
                                onShowPaywall = { viewModel.showPaywall() },
                            )
                        }
                        composable("activity") {
                            ActivityScreen(wallet = currentWallet, contentPadding = padding)
                        }
                        composable("reminders") {
                            RemindersScreen(
                                wallet = currentWallet,
                                contentPadding = padding,
                                onComplete = { viewModel.completeReminder(it) },
                                onDelete = { viewModel.deleteReminder(it) },
                                onRequestNotifications = requestNotificationPermission,
                            )
                        }
                        composable("settings") {
                            SettingsScreen(
                                wallet = currentWallet,
                                contentPadding = padding,
                                billingConfigured = viewModel.billingConfigured,
                                onToggleReminders = { viewModel.setRemindersEnabled(it) },
                                onRequestNotifications = requestNotificationPermission,
                                onSuppliers = { navController.navigate("suppliers") },
                                onUpdateSettings = { locale, currency, mass, volume -> viewModel.updateSettings(locale, currency, mass, volume) },
                                onShowPaywall = { viewModel.showPaywall() },
                                onManageSubscription = { viewModel.manageSubscription() },
                            )
                        }
                        composable("suppliers") {
                            SuppliersScreen(
                                wallet = currentWallet,
                                onBack = { navController.popBackStack() },
                                onCreate = { name, notes -> viewModel.createSupplier(name, notes) },
                                onDelete = { viewModel.deleteSupplier(it) },
                            )
                        }
                        composable(
                            route = "cylinder/{id}",
                            arguments = listOf(navArgument("id") { type = NavType.StringType }),
                        ) { entry ->
                            val id = entry.arguments?.getString("id").orEmpty()
                            val cylinder = currentWallet.cylinders.firstOrNull { it.id == id }
                            if (cylinder == null) {
                                LaunchedEffect(Unit) { navController.popBackStack() }
                            } else {
                                var decision by remember(id, currentWallet.revision) { mutableStateOf<com.goodusestudios.weldinggaswallet.backend.domain.EditDecision?>(null) }
                                LaunchedEffect(id, currentWallet.revision) { decision = viewModel.canEditCylinder(id) }
                                CylinderDetailScreen(
                                    wallet = currentWallet,
                                    cylinder = cylinder,
                                    editDecision = decision,
                                    onBack = { navController.popBackStack() },
                                    onRefill = { supplierId, amount, note ->
                                        viewModel.recordRefill(
                                            id,
                                            java.time.Instant.now(),
                                            if (supplierId == cylinder.supplierId) com.goodusestudios.weldinggaswallet.backend.domain.FieldPatch.Keep()
                                            else if (supplierId == null) com.goodusestudios.weldinggaswallet.backend.domain.FieldPatch.Clear()
                                            else com.goodusestudios.weldinggaswallet.backend.domain.FieldPatch.SetValue(supplierId),
                                            amount,
                                            note,
                                        )
                                    },
                                    onExchange = { supplierId, amount, note ->
                                        viewModel.recordExchange(id, java.time.Instant.now(), supplierId, amount, note)
                                    },
                                    onCost = { supplierId, amount, note ->
                                        if (amount != null) viewModel.recordCost(id, java.time.Instant.now(), amount, supplierId, note)
                                    },
                                    onReminder = { kind, title, dueAt -> viewModel.createReminder(id, kind, title, dueAt) },
                                    onReturned = { viewModel.markReturned(id, it) },
                                    onArchive = { viewModel.archiveCylinder(id) },
                                    onShowPaywall = { viewModel.showPaywall() },
                                )
                            }
                        }
                    }
                }
            }
        }

        if (paywallVisible) {
            PaywallSheet(
                products = products,
                billingConfigured = viewModel.billingConfigured,
                onDismiss = { viewModel.hidePaywall() },
                onPurchase = { viewModel.purchase(it) },
                onRestore = { viewModel.restorePurchases() },
            )
        }
    }
}
