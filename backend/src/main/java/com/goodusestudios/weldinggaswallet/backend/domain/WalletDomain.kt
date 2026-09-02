package com.goodusestudios.weldinggaswallet.backend.domain

import java.time.Instant
import java.util.Locale

const val WALLET_SCHEMA_VERSION: Int = 4
const val MINIMUM_SUPPORTED_WALLET_SCHEMA_VERSION: Int = 3
const val FREE_EDITABLE_CYLINDER_LIMIT: Int = 3
const val MAXIMUM_BACKUP_BYTES: Int = 5 * 1024 * 1024
const val WELDING_GAS_WALLET_ANDROID_PACKAGE_NAME: String =
    "com.goodusestudios.weldinggaswallet"
const val ANDROID_LAST_VERIFIED_CONTINUITY_HOURS: Long = 24

val SUPPORTED_LOCALES: List<String> = listOf(
    "en", "es", "pt", "fr", "de", "it", "nl", "pl", "cs", "ro",
    "hu", "sv", "nb", "da", "fi", "tr", "ar", "hi", "bn", "id",
    "vi", "th", "ja", "ko", "zh-Hans", "zh-Hant", "uk", "el", "ms", "fil",
)

val CYLINDER_CAPACITY_UNITS: Set<String> = setOf("ft3", "L", "m3", "kg", "lb")

val ISO_4217_CODES: Set<String> = setOf(
    "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
    "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BOV",
    "BRL", "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHE", "CHF",
    "CHW", "CLF", "CLP", "CNY", "COP", "COU", "CRC", "CUP", "CVE", "CZK",
    "DJF", "DKK", "DOP", "DZD", "EGP", "ERN", "ETB", "EUR", "FJD", "FKP",
    "GBP", "GEL", "GHS", "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL",
    "HTG", "HUF", "IDR", "ILS", "INR", "IQD", "IRR", "ISK", "JMD", "JOD",
    "JPY", "KES", "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT",
    "LAK", "LBP", "LKR", "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD",
    "MMK", "MNT", "MOP", "MRU", "MUR", "MVR", "MWK", "MXN", "MXV", "MYR",
    "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN",
    "PGK", "PHP", "PKR", "PLN", "PYG", "QAR", "RON", "RSD", "RUB", "RWF",
    "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLE", "SOS", "SRD",
    "SSP", "STN", "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TND", "TOP",
    "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD", "USN", "UYI", "UYU",
    "UYW", "UZS", "VED", "VES", "VND", "VUV", "WST", "XAF", "XAG", "XAU",
    "XBA", "XBB", "XBC", "XBD", "XCD", "XDR", "XOF", "XPD", "XPF", "XPT",
    "XSU", "XTS", "XUA", "XXX", "YER", "ZAR", "ZMW", "ZWG",
)

enum class AccessTier { free, pro }
enum class EntitlementSource { none, googlePlaySubscription }
enum class RelationshipType { owned, rented, leased, deposit, notSure }
enum class CylinderLifecycle { active, returned, exchanged, archived }
enum class CylinderState { ready, low, empty, away }
enum class CylinderEventType {
    created,
    stateChanged,
    acquisitionUpdated,
    cylinderUpdated,
    refill,
    exchange,
    purchase,
    rentalPayment,
    leasePayment,
    depositPaid,
    depositReturned,
    cost,
    supplierChanged,
    relationshipChanged,
    note,
    photoAdded,
    reminderCreated,
    reminderUpdated,
    reminderCompleted,
    reminderDeleted,
    returned,
    archived,
}
enum class ReminderKind { refill, rental, lease, deposit, check, custom }
enum class ReminderDelivery {
    idle,
    needsScheduling,
    permissionRequired,
    scheduled,
    needsCancellation,
}
enum class PaywallReason { addFourthCylinder, editLockedCylinderAfterDowngrade }

fun canonicalLocale(candidate: String?): String {
    if (candidate.isNullOrBlank()) return "en"
    val normalized = candidate.trim().replace('_', '-')
    SUPPORTED_LOCALES.firstOrNull { it.equals(normalized, ignoreCase = true) }?.let { return it }

    val parsed = Locale.forLanguageTag(normalized)
    val language = parsed.language.lowercase(Locale.ROOT)
    if (language.isBlank()) return "en"
    if (language == "zh") {
        val script = parsed.script.lowercase(Locale.ROOT)
        val region = parsed.country.lowercase(Locale.ROOT)
        return if (script == "hant" || region in setOf("tw", "hk", "mo")) {
            "zh-Hant"
        } else {
            "zh-Hans"
        }
    }
    return SUPPORTED_LOCALES.firstOrNull { it.substringBefore('-') == language } ?: "en"
}

fun isSupportedLocaleCandidate(candidate: String): Boolean {
    val normalized = candidate.trim().replace('_', '-')
    if (normalized.isBlank()) return false
    if (SUPPORTED_LOCALES.any { it.equals(normalized, ignoreCase = true) }) return true
    val parsed = Locale.forLanguageTag(normalized)
    val language = parsed.language.lowercase(Locale.ROOT)
    return language == "zh" || SUPPORTED_LOCALES.any { it.substringBefore('-') == language }
}

fun isRtlLocale(locale: String): Boolean = canonicalLocale(locale) == "ar"

fun defaultCylinderCapacityUnitForLocale(locale: String): String {
    val region = Locale.forLanguageTag(locale.trim().replace('_', '-'))
        .country
        .uppercase(Locale.ROOT)
    return if (region == "US" || region == "CA") "ft3" else "L"
}

fun capacityUnitLabel(unit: String): String = when (unit) {
    "ft3" -> "ft³"
    "m3" -> "m³"
    else -> unit
}

fun automaticCylinderName(
    gasType: String,
    capacityValue: Double?,
    capacityUnit: String?,
): String {
    val gas = gasType.trim()
    if (capacityValue == null || capacityUnit.isNullOrBlank()) return gas
    val amount = if (capacityValue % 1.0 == 0.0) {
        capacityValue.toLong().toString()
    } else {
        capacityValue.toString()
    }
    return "$gas · $amount ${capacityUnitLabel(capacityUnit)}"
}

fun normalizedCurrency(candidate: String?, fallback: String = "USD"): String {
    val value = candidate.orEmpty().trim().uppercase(Locale.ROOT)
    if (value in ISO_4217_CODES) return value
    val safeFallback = fallback.trim().uppercase(Locale.ROOT)
    return if (safeFallback in ISO_4217_CODES) safeFallback else "USD"
}

fun defaultCurrencyForLocale(locale: String): String = when (canonicalLocale(locale)) {
    "en" -> "USD"
    "es", "fr", "de", "it", "nl", "fi", "el" -> "EUR"
    "pt" -> "BRL"
    "pl" -> "PLN"
    "cs" -> "CZK"
    "ro" -> "RON"
    "hu" -> "HUF"
    "sv" -> "SEK"
    "nb" -> "NOK"
    "da" -> "DKK"
    "tr" -> "TRY"
    "ar" -> "AED"
    "hi" -> "INR"
    "bn" -> "BDT"
    "id" -> "IDR"
    "vi" -> "VND"
    "th" -> "THB"
    "ja" -> "JPY"
    "ko" -> "KRW"
    "zh-Hans" -> "CNY"
    "zh-Hant" -> "TWD"
    "uk" -> "UAH"
    "ms" -> "MYR"
    "fil" -> "PHP"
    else -> "USD"
}

sealed interface FieldPatch<T> {
    class Keep<T> : FieldPatch<T>
    data class SetValue<T>(val value: T) : FieldPatch<T>
    class Clear<T> : FieldPatch<T>
}

fun <T> FieldPatch<T>.applyTo(current: T?): T? = when (this) {
    is FieldPatch.Keep -> current
    is FieldPatch.SetValue -> value
    is FieldPatch.Clear -> null
}

class Money(
    val minorUnits: Long,
    currencyCode: String,
) {
    val currencyCode: String = currencyCode.trim().uppercase(Locale.ROOT).also { normalized ->
        require(normalized in ISO_4217_CODES) {
            "Unsupported ISO 4217 currency: $currencyCode"
        }
    }

    val normalizedCurrencyCode: String get() = currencyCode

    override fun equals(other: Any?): Boolean =
        other is Money && minorUnits == other.minorUnits && currencyCode == other.currencyCode

    override fun hashCode(): Int = 31 * minorUnits.hashCode() + currencyCode.hashCode()

    override fun toString(): String = "Money(minorUnits=$minorUnits, currencyCode=$currencyCode)"
}

data class Supplier(
    val id: String,
    val name: String,
    val createdAt: Instant,
    val updatedAt: Instant,
    val notes: String? = null,
)

data class AppSettings(
    val locale: String,
    val currencyCode: String,
    val defaultMassUnit: String,
    val defaultVolumeUnit: String,
    val remindersEnabled: Boolean,
    val onboardingComplete: Boolean,
) {
    companion object {
        fun create(
            locale: String,
            currencyCode: String,
            defaultMassUnit: String,
            defaultVolumeUnit: String,
            remindersEnabled: Boolean,
            onboardingComplete: Boolean,
        ): AppSettings {
            val safeLocale = canonicalLocale(locale)
            return AppSettings(
                locale = safeLocale,
                currencyCode = normalizedCurrency(currencyCode, defaultCurrencyForLocale(safeLocale)),
                defaultMassUnit = if (defaultMassUnit in setOf("kg", "lb")) defaultMassUnit else "kg",
                defaultVolumeUnit = if (defaultVolumeUnit in setOf("L", "m3", "ft3")) defaultVolumeUnit else "L",
                remindersEnabled = remindersEnabled,
                onboardingComplete = onboardingComplete,
            )
        }
    }
}

data class Cylinder(
    val id: String,
    val nickname: String,
    val gasType: String,
    val relationship: RelationshipType,
    val lifecycle: CylinderLifecycle,
    val state: CylinderState = CylinderState.ready,
    val createdAt: Instant,
    val updatedAt: Instant,
    val capacityValue: Double? = null,
    val capacityUnit: String? = null,
    val serialNumber: String? = null,
    val localPhotoUri: String? = null,
    val supplierId: String? = null,
    val acquisitionAmount: Money? = null,
    val acquiredAt: Instant? = null,
    val isFreeEditableSelection: Boolean = false,
) {
    val consumesCurrentSlot: Boolean
        get() = lifecycle == CylinderLifecycle.active || lifecycle == CylinderLifecycle.exchanged
}

data class CylinderEvent(
    val id: String,
    val cylinderId: String,
    val type: CylinderEventType,
    val occurredAt: Instant,
    val supplierId: String? = null,
    val amount: Money? = null,
    val note: String? = null,
    val metadata: Map<String, Any?> = emptyMap(),
)

data class Reminder(
    val id: String,
    val cylinderId: String,
    val kind: ReminderKind,
    val title: String,
    val dueAt: Instant,
    val createdAt: Instant,
    val delivery: ReminderDelivery,
    val completed: Boolean = false,
    val notificationId: Int = stableNotificationId(id),
)

data class AddCylinderDraft(
    val nickname: String,
    val gasType: String,
    val relationship: RelationshipType,
    val capacityValue: Double? = null,
    val capacityUnit: String? = null,
    val serialNumber: String? = null,
    val localPhotoUri: String? = null,
    val supplierId: String? = null,
    val acquisitionAmount: Money? = null,
    val acquiredAt: Instant? = null,
)

data class PendingCylinderDraft(
    val draft: AddCylinderDraft,
    val draftResumed: Boolean = false,
)

data class Entitlement(
    val tier: AccessTier,
    val source: EntitlementSource,
    val validUntil: Instant? = null,
    val willRenew: Boolean = false,
) {
    fun isProAt(now: Instant): Boolean {
        if (tier != AccessTier.pro) return false
        if (source != EntitlementSource.googlePlaySubscription) return false
        return validUntil != null && !now.isAfter(validUntil)
    }

    companion object {
        val Free = Entitlement(AccessTier.free, EntitlementSource.none)
    }
}

data class WalletData(
    val schemaVersion: Int,
    val revision: Int,
    val settings: AppSettings,
    val suppliers: List<Supplier>,
    val cylinders: List<Cylinder>,
    val events: List<CylinderEvent>,
    val reminders: List<Reminder>,
    val pendingDraft: PendingCylinderDraft?,
    val freeEditableSelection: List<String>,
    val entitlementCache: Entitlement,
) {
    fun next(
        settings: AppSettings = this.settings,
        suppliers: List<Supplier> = this.suppliers,
        cylinders: List<Cylinder> = this.cylinders,
        events: List<CylinderEvent> = this.events,
        reminders: List<Reminder> = this.reminders,
        pendingDraft: FieldPatch<PendingCylinderDraft> = FieldPatch.Keep(),
        freeEditableSelection: List<String> = this.freeEditableSelection,
        entitlementCache: Entitlement = this.entitlementCache,
    ): WalletData = WalletData(
        schemaVersion = WALLET_SCHEMA_VERSION,
        revision = revision + 1,
        settings = settings,
        suppliers = suppliers.toList(),
        cylinders = cylinders.toList(),
        events = events.toList(),
        reminders = reminders.toList(),
        pendingDraft = pendingDraft.applyTo(this.pendingDraft),
        freeEditableSelection = freeEditableSelection.distinct(),
        entitlementCache = entitlementCache,
    )

    companion object {
        fun empty(locale: String = "en", currencyCode: String? = null): WalletData {
            val safeLocale = canonicalLocale(locale)
            return WalletData(
                schemaVersion = WALLET_SCHEMA_VERSION,
                revision = 0,
                settings = AppSettings.create(
                    locale = safeLocale,
                    currencyCode = normalizedCurrency(currencyCode, defaultCurrencyForLocale(safeLocale)),
                    defaultMassUnit = "kg",
                    defaultVolumeUnit = defaultCylinderCapacityUnitForLocale(locale),
                    remindersEnabled = false,
                    onboardingComplete = false,
                ),
                suppliers = emptyList(),
                cylinders = emptyList(),
                events = emptyList(),
                reminders = emptyList(),
                pendingDraft = null,
                freeEditableSelection = emptyList(),
                entitlementCache = Entitlement.Free,
            )
        }
    }
}

data class TransactionOutcome<T>(val state: WalletData, val value: T)

class WalletConflictException(val expected: Int, val actual: Int) :
    IllegalStateException("Wallet changed (expected revision $expected, found $actual).")

class SupplierInUseException(val supplierId: String) :
    IllegalStateException("Supplier $supplierId is still referenced by wallet history or a current record.")

class CannotDeleteDueToRemindersException(
    val cylinderId: String,
    val failedReminderIds: List<String>,
) : IllegalStateException(
    "Cylinder $cylinderId could not be deleted because reminder cancellation failed: " +
        failedReminderIds.joinToString(),
)

data class CylinderDeleteResult(
    val forced: Boolean,
    val reminderCancellationFailures: List<String>,
)

data class ImportNormalization(
    val state: WalletData,
    val warnings: List<String> = emptyList(),
)

data class ImportResult(
    val state: WalletData,
    val warnings: List<String>,
    val downgradeDecision: DowngradeDecision,
)

interface AtomicWalletRepository {
    suspend fun read(): WalletData

    suspend fun <T> transact(
        expectedRevision: Int? = null,
        mutation: (WalletData) -> TransactionOutcome<T>,
    ): T

    suspend fun replaceFromBackup(imported: WalletData, expectedRevision: Int): WalletData
}

interface SessionEntitlementTrust {
    fun acceptStoreVerifiedEntitlement(entitlement: Entitlement)
}

interface ResidualWalletDataPurger {
    suspend fun purgeResidualWalletFiles()
}

interface CorruptionRecoveryRepository {
    suspend fun replaceCorruptStore(validatedBackup: WalletData): WalletData
    suspend fun clearCorruptStore(confirmed: Boolean): WalletData
}

fun interface IdFactory { fun newId(): String }
fun interface Clock { fun now(): Instant }

interface ReminderScheduler {
    suspend fun schedule(reminder: Reminder)
    suspend fun cancel(reminder: Reminder)
    suspend fun dismiss(reminder: Reminder)
    suspend fun cancelAll()

    fun canPostNotifications(): Boolean = true

    suspend fun consumePermissionFailure(reminderId: String): Boolean = false
}

data class StoreProduct(
    val id: String,
    val localizedPrice: String,
    val localizedPeriodLabel: String,
    val isDefault: Boolean,
)

enum class PurchaseOutcome { pending, cancelled, failed, unverified, notFound }

class PurchaseOutcomeException(val outcome: PurchaseOutcome) :
    IllegalStateException("Purchase flow ended with ${outcome.name}.")

interface StoreBillingGateway {
    suspend fun loadProducts(): List<StoreProduct>
    suspend fun purchaseVerified(productId: String): Entitlement
    suspend fun restoreOrRefreshVerified(): Entitlement
    suspend fun openSubscriptionManagement()
}

object ProductIds {
    const val androidMonthly = "com.gooduse.weldinggaswallet.pro.monthly"
    const val androidAnnual = "com.gooduse.weldinggaswallet.pro.annual"
    val android: List<String> = listOf(androidAnnual, androidMonthly)
}

sealed interface AddResult
data class CylinderAdded(val cylinder: Cylinder) : AddResult
data class AddRequiresPaywall(val reason: PaywallReason) : AddResult

sealed interface EditDecision
data object Editable : EditDecision
data class Locked(val reason: PaywallReason) : EditDecision
data class ReadOnly(val reason: String) : EditDecision
data object MissingCylinder : EditDecision

sealed interface DowngradeDecision
data object DowngradeReady : DowngradeDecision
data class RequiresFreeSelection(val maximumEditable: Int) : DowngradeDecision

data class ReminderResult(
    val reminder: Reminder,
    val systemScheduleConfirmed: Boolean,
)

interface WalletBackupCodec {
    fun encode(state: WalletData, exportedAt: Instant): String
    fun decode(encoded: String): WalletData
}

fun stableNotificationId(value: String): Int {
    var hash = 0x811c9dc5u
    value.encodeToByteArray().forEach { byte ->
        hash = hash xor byte.toUByte().toUInt()
        hash *= 0x01000193u
    }
    return (hash and 0x7fffffffu).toInt()
}

object SafetyGuard {
    val forbiddenAutomatedClaims: List<String> = listOf(
        "you legally own this cylinder",
        "this cylinder is safe",
        "this cylinder is safe to fill",
        "this cylinder is eligible for refill",
        "this cylinder passes inspection",
        "this test mark is valid",
        "this cylinder complies with local law",
        "this supplier must accept this cylinder",
    )

    fun isAllowedUserFacingConclusion(text: String): Boolean {
        val normalized = text.trim().lowercase(Locale.ROOT)
        return forbiddenAutomatedClaims.none(normalized::contains)
    }
}
