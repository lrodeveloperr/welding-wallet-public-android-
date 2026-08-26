package com.goodusestudios.weldinggaswallet

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.goodusestudios.weldinggaswallet.backend.domain.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant

class WalletViewModel(private val graph: WalletAppGraph) : ViewModel() {
    private val _wallet = MutableStateFlow<WalletData?>(null)
    val wallet: StateFlow<WalletData?> = _wallet.asStateFlow()

    private val _loading = MutableStateFlow(true)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    private val _paywallVisible = MutableStateFlow(false)
    val paywallVisible: StateFlow<Boolean> = _paywallVisible.asStateFlow()

    private val _products = MutableStateFlow<List<StoreProduct>>(emptyList())
    val products: StateFlow<List<StoreProduct>> = _products.asStateFlow()

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val messages: SharedFlow<String> = _messages.asSharedFlow()

    val billingConfigured: Boolean get() = graph.billingConfigured

    init { bootstrap() }

    fun bootstrap() = viewModelScope.launch {
        _loading.value = true
        runCatching { graph.bootstrap() }
            .onSuccess { _wallet.value = it }
            .onFailure { _messages.tryEmit(it.userMessage()) }
        _loading.value = false
    }

    fun onResume() = viewModelScope.launch {
        runCatching { graph.onResume() }
            .onSuccess { _wallet.value = it }
    }

    suspend fun canEditCylinder(cylinderId: String): EditDecision =
        runCatching { graph.engine.canEditCylinder(cylinderId) }.getOrDefault(MissingCylinder)

    fun completeOnboarding() = mutate("Welcome to your cylinder wallet") {
        graph.engine.updateSettings(onboardingComplete = true)
    }

    fun addCylinder(draft: AddCylinderDraft) = viewModelScope.launch {
        runCatching { graph.engine.addOrGate(draft) }
            .onSuccess { result ->
                refresh()
                when (result) {
                    is CylinderAdded -> _messages.tryEmit("Cylinder added")
                    is AddRequiresPaywall -> showPaywall()
                }
            }
            .onFailure { _messages.tryEmit(it.userMessage()) }
    }

    fun recordRefill(
        cylinderId: String,
        occurredAt: Instant,
        supplierId: FieldPatch<String>,
        amount: Money?,
        note: String?,
    ) = mutate("Refill recorded") {
        graph.engine.recordRefill(cylinderId, occurredAt, supplierId, amount, note)
    }

    fun recordExchange(
        cylinderId: String,
        occurredAt: Instant,
        supplierId: String?,
        amount: Money?,
        note: String?,
    ) = mutate("Exchange recorded") {
        graph.engine.recordExchange(cylinderId, occurredAt, supplierId, amount, note = note)
    }

    fun recordCost(
        cylinderId: String,
        occurredAt: Instant,
        amount: Money,
        supplierId: String?,
        note: String?,
    ) = mutate("Cost recorded") {
        graph.engine.recordCost(cylinderId, occurredAt, amount, supplierId, note)
    }

    fun markReturned(cylinderId: String, note: String?) = mutate("Cylinder marked returned") {
        graph.engine.markReturned(cylinderId, note)
    }

    fun archiveCylinder(cylinderId: String) = mutate("Cylinder archived") {
        graph.engine.archiveCylinder(cylinderId)
    }

    fun createReminder(
        cylinderId: String,
        kind: ReminderKind,
        title: String,
        dueAt: Instant,
    ) = mutate("Reminder saved") {
        graph.engine.createReminder(cylinderId, kind, title, dueAt)
    }

    fun completeReminder(reminderId: String) = mutate("Reminder completed") {
        graph.engine.completeReminder(reminderId)
    }

    fun deleteReminder(reminderId: String) = mutate("Reminder deleted") {
        graph.engine.deleteReminder(reminderId)
    }

    fun setRemindersEnabled(enabled: Boolean) = mutate(
        if (enabled) "Reminders enabled" else "Reminders disabled"
    ) { graph.engine.setRemindersEnabled(enabled) }

    fun createSupplier(name: String, notes: String?) = mutate("Supplier added") {
        graph.engine.createSupplier(name, notes)
    }

    fun deleteSupplier(id: String) = mutate("Supplier deleted") {
        graph.engine.deleteSupplier(id)
    }

    fun updateSettings(
        locale: String? = null,
        currency: String? = null,
        mass: String? = null,
        volume: String? = null,
    ) = mutate("Settings updated") {
        graph.engine.updateSettings(
            locale = locale,
            currencyCode = currency,
            defaultMassUnit = mass,
            defaultVolumeUnit = volume,
        )
    }

    fun showPaywall() = viewModelScope.launch {
        _paywallVisible.value = true
        _products.value = runCatching { graph.engine.getPaywallProducts() }.getOrDefault(emptyList())
    }

    fun hidePaywall() { _paywallVisible.value = false }

    fun purchase(productId: String) = viewModelScope.launch {
        runCatching { graph.engine.purchaseAndResume(productId) }
            .onSuccess {
                _paywallVisible.value = false
                refresh()
                _messages.tryEmit("Pro access restored")
            }
            .onFailure { _messages.tryEmit(it.userMessage()) }
    }

    fun restorePurchases() = viewModelScope.launch {
        runCatching { graph.engine.restoreAndResume() }
            .onSuccess {
                refresh()
                _messages.tryEmit("Purchases checked")
            }
            .onFailure { _messages.tryEmit(it.userMessage()) }
    }

    fun manageSubscription() = viewModelScope.launch {
        runCatching { graph.engine.billing.openSubscriptionManagement() }
            .onFailure { _messages.tryEmit(it.userMessage()) }
    }

    private fun mutate(success: String, block: suspend () -> Unit) = viewModelScope.launch {
        runCatching { block() }
            .onSuccess {
                refresh()
                _messages.tryEmit(success)
            }
            .onFailure { _messages.tryEmit(it.userMessage()) }
    }

    private suspend fun refresh() { _wallet.value = graph.engine.snapshot() }

    override fun onCleared() { graph.close() }

    class Factory(private val graph: WalletAppGraph) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            WalletViewModel(graph) as T
    }
}

private fun Throwable.userMessage(): String = when (this) {
    is SupplierInUseException -> "That supplier is still referenced by wallet history."
    is WalletConflictException -> "The wallet changed. Try that action again."
    is PurchaseOutcomeException -> "Google Play could not complete that purchase."
    else -> message?.takeIf { it.isNotBlank() } ?: "Something went wrong."
}
