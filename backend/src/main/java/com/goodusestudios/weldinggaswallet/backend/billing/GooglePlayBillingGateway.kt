package com.goodusestudios.weldinggaswallet.backend.billing

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.android.billingclient.api.*
import com.goodusestudios.weldinggaswallet.backend.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.time.Duration
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

fun interface ActivityProvider {
    fun currentActivity(): Activity?
}

class BillingGatewayException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : IllegalStateException("BillingGatewayException($code): $message", cause)

data class PlaySubscriptionPlanEvidence(
    val productId: String,
    val basePlanId: String,
    val offerId: String?,
    val offerTags: List<String>,
    val hasInstallmentPlan: Boolean,
    val pricingPhaseCount: Int,
    val billingPeriod: String,
    val priceAmountMicros: Long,
    val recurrenceMode: Int,
    val billingCycleCount: Int,
)

fun matchesLockedPlaySubscriptionContract(evidence: PlaySubscriptionPlanEvidence): Boolean {
    val expected = when (evidence.productId) {
        ProductIds.androidAnnual -> "annual" to "P1Y"
        ProductIds.androidMonthly -> "monthly" to "P1M"
        else -> return false
    }
    return evidence.basePlanId == expected.first &&
        evidence.offerId == null &&
        evidence.offerTags.isEmpty() &&
        !evidence.hasInstallmentPlan &&
        evidence.pricingPhaseCount == 1 &&
        evidence.billingPeriod == expected.second &&
        evidence.priceAmountMicros > 0L &&
        evidence.recurrenceMode == ProductDetails.RecurrenceMode.INFINITE_RECURRING &&
        evidence.billingCycleCount == 0
}

class GooglePlayPurchaseVerifier(licenseKeyBase64: String) {
    private val normalizedKey = licenseKeyBase64.filterNot(Char::isWhitespace).also {
        if (it.isEmpty()) {
            throw BillingGatewayException(
                "play_license_key_missing",
                "The Google Play public license key is required.",
            )
        }
        if (it.length > MAX_KEY_CHARS) {
            throw BillingGatewayException(
                "play_license_key_invalid",
                "The Google Play public license key exceeds the supported size.",
            )
        }
    }
    private val publicKey: PublicKey = decodePublicKey(normalizedKey)
        ?: throw BillingGatewayException(
            "play_license_key_invalid",
            "The Google Play public license key is not valid RSA X.509 material.",
        )

    fun verify(
        originalJson: String,
        signatureBase64: String,
        expectedProductId: String,
        expectedPackageName: String,
        expectedPurchaseToken: String,
    ): Boolean {
        if (originalJson.isBlank() || originalJson.length > MAX_PAYLOAD_CHARS ||
            signatureBase64.isBlank() || signatureBase64.length > MAX_SIGNATURE_CHARS ||
            expectedPurchaseToken.isBlank()
        ) return false

        return try {
            val root = Json.parseToJsonElement(originalJson) as? JsonObject ?: return false
            if (root.string("packageName") != expectedPackageName ||
                root.string("purchaseToken") != expectedPurchaseToken
            ) return false

            val signedProductId = root.stringOrNull("productId")
            val signedProducts = (root["products"] ?: root["productIds"]) as? JsonArray
            val productMatches = signedProductId == expectedProductId ||
                (signedProductId == null && signedProducts?.size == 1 &&
                    (signedProducts.single() as? JsonPrimitive)?.contentOrNull == expectedProductId)
            if (!productMatches) return false

            val purchaseState = (root["purchaseState"] as? JsonPrimitive)?.intOrNull
            if (purchaseState != 0) return false

            val signatureBytes = Base64.getDecoder().decode(signatureBase64.filterNot(Char::isWhitespace))
            val verifier = Signature.getInstance("SHA1withRSA")
            verifier.initVerify(publicKey)
            verifier.update(originalJson.toByteArray(StandardCharsets.UTF_8))
            verifier.verify(signatureBytes)
        } catch (_: Throwable) {
            false
        }
    }

    private fun decodePublicKey(value: String): PublicKey? = try {
        val bytes = Base64.getDecoder().decode(value)
        KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(bytes))
            .takeIf { it.algorithm.equals("RSA", ignoreCase = true) }
    } catch (_: Throwable) {
        null
    }

    companion object {
        private const val MAX_KEY_CHARS = 32_768
        private const val MAX_PAYLOAD_CHARS = 1_048_576
        private const val MAX_SIGNATURE_CHARS = 32_768
    }
}

fun subscriptionManagementUri(
    verifiedAndroidProductId: String? = null,
    androidPackageName: String = WELDING_GAS_WALLET_ANDROID_PACKAGE_NAME,
): Uri {
    val productId = verifiedAndroidProductId?.trim()
    if (productId == null || productId !in ProductIds.android) {
        return Uri.parse("https://play.google.com/store/account/subscriptions")
    }
    return Uri.parse(
        "https://play.google.com/store/account/subscriptions" +
            "?sku=${Uri.encode(productId)}&package=${Uri.encode(androidPackageName)}",
    )
}

class GooglePlayBillingGateway(
    context: Context,
    private val activityProvider: ActivityProvider,
    private val clock: Clock,
    playLicenseKeyBase64: String,
    private val androidPackageName: String = WELDING_GAS_WALLET_ANDROID_PACKAGE_NAME,
    private val purchaseResultTimeout: Duration = Duration.ofMinutes(2),
) : StoreBillingGateway, AutoCloseable {
    private val appContext = context.applicationContext
    private val verifier = GooglePlayPurchaseVerifier(playLicenseKeyBase64)
    private val connectionMutex = Mutex()
    private val operationMutex = Mutex()
    private val updates = MutableSharedFlow<PurchaseUpdate>(extraBufferCapacity = 16)

    private val productDetails = linkedMapOf<String, ProductDetails>()
    private val offerDetails = linkedMapOf<String, ProductDetails.SubscriptionOfferDetails>()
    @Volatile private var lastVerifiedProductId: String? = null
    @Volatile private var operationInProgress: Boolean = false

    val entitlementRefreshRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 8)

    private val purchasesUpdatedListener = PurchasesUpdatedListener { billingResult, purchases ->
        val batch = PurchaseUpdate(billingResult, purchases.orEmpty())
        updates.tryEmit(batch)
        if (!operationInProgress &&
            billingResult.responseCode == BillingClient.BillingResponseCode.OK &&
            batch.purchases.any { purchase ->
                purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                    purchase.products.any { it in ProductIds.android }
            }
        ) {
            entitlementRefreshRequests.tryEmit(Unit)
        }
    }

    private val billingClient: BillingClient = BillingClient.newBuilder(appContext)
        .setListener(purchasesUpdatedListener)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build(),
        )
        .enableAutoServiceReconnection()
        .build()

    override suspend fun loadProducts(): List<StoreProduct> {
        ensureConnected()
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                ProductIds.android.map { id ->
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(id)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                },
            )
            .build()

        val (billingResult, queryResult) = suspendCancellableCoroutine { continuation ->
            billingClient.queryProductDetailsAsync(params) { result, detailsResult ->
                if (continuation.isActive) continuation.resume(result to detailsResult)
            }
        }
        if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
            throw BillingGatewayException(
                "product_query_failed",
                "Google Play could not load products (${billingResult.responseCode}).",
            )
        }

        val returned = queryResult.productDetailsList.associateBy { it.productId }
        val missing = ProductIds.android.filterNot(returned::containsKey)
        if (missing.isNotEmpty()) {
            throw BillingGatewayException(
                "products_missing",
                "Google Play is missing required products: ${missing.joinToString()}.",
            )
        }

        productDetails.clear()
        offerDetails.clear()
        return ProductIds.android.map { id ->
            val details = returned.getValue(id)
            val offers = details.subscriptionOfferDetails.orEmpty()
            if (offers.size != 1) {
                throw BillingGatewayException(
                    "play_subscription_contract_mismatch",
                    "Google Play returned an unexpected number of base plans/offers for $id.",
                )
            }
            val offer = offers.single()
            val phases = offer.pricingPhases.pricingPhaseList
            val phase = phases.singleOrNull()
            val evidence = PlaySubscriptionPlanEvidence(
                productId = id,
                basePlanId = offer.basePlanId,
                offerId = offer.offerId,
                offerTags = offer.offerTags,
                hasInstallmentPlan = offer.installmentPlanDetails != null,
                pricingPhaseCount = phases.size,
                billingPeriod = phase?.billingPeriod.orEmpty(),
                priceAmountMicros = phase?.priceAmountMicros ?: 0L,
                recurrenceMode = phase?.recurrenceMode ?: ProductDetails.RecurrenceMode.NON_RECURRING,
                billingCycleCount = phase?.billingCycleCount ?: -1,
            )
            if (!matchesLockedPlaySubscriptionContract(evidence) || offer.offerToken.isBlank()) {
                throw BillingGatewayException(
                    "play_subscription_contract_mismatch",
                    "Google Play base-plan cadence or pricing phases do not match the locked paywall.",
                )
            }
            productDetails[id] = details
            offerDetails[id] = offer
            StoreProduct(
                id = id,
                localizedPrice = phase!!.formattedPrice,
                localizedPeriodLabel = details.title,
                isDefault = id == ProductIds.androidAnnual,
            )
        }
    }

    override suspend fun purchaseVerified(productId: String): Entitlement = operationMutex.withLock {
        requireAllowedProduct(productId)
        operationInProgress = true
        try {
            ensureConnected()
            if (productDetails[productId] == null || offerDetails[productId] == null) loadProducts()
            val details = productDetails[productId]
                ?: throw BillingGatewayException("product_unavailable", "Selected product is unavailable.")
            val offer = offerDetails[productId]
                ?: throw BillingGatewayException("product_unavailable", "Selected offer is unavailable.")
            val activity = activityProvider.currentActivity()
                ?: throw BillingGatewayException("activity_unavailable", "No resumed Activity is available.")

            coroutineScope {
                val waiter = async(start = CoroutineStart.UNDISPATCHED) {
                    withTimeout(purchaseResultTimeout.toMillis()) {
                        updates.first { update ->
                            update.billingResult.responseCode != BillingClient.BillingResponseCode.OK ||
                                update.purchases.any { productId in it.products }
                        }
                    }
                }

                val params = BillingFlowParams.newBuilder()
                    .setProductDetailsParamsList(
                        listOf(
                            BillingFlowParams.ProductDetailsParams.newBuilder()
                                .setProductDetails(details)
                                .setOfferToken(offer.offerToken)
                                .build(),
                        ),
                    )
                    .build()
                val launchResult = withContext(Dispatchers.Main.immediate) {
                    billingClient.launchBillingFlow(activity, params)
                }
                if (launchResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    waiter.cancel()
                    throw outcomeForBillingResult(launchResult)
                }

                val update = try {
                    waiter.await()
                } catch (_: TimeoutCancellationException) {
                    throw PurchaseOutcomeException(PurchaseOutcome.failed)
                }
                if (update.billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    throw outcomeForBillingResult(update.billingResult)
                }
                val relevant = update.purchases.filter { productId in it.products }
                if (relevant.any { it.purchaseState == Purchase.PurchaseState.PENDING }) {
                    throw PurchaseOutcomeException(PurchaseOutcome.pending)
                }
                val purchased = relevant.firstOrNull {
                    it.purchaseState == Purchase.PurchaseState.PURCHASED
                } ?: throw PurchaseOutcomeException(PurchaseOutcome.failed)
                verifyAndComplete(purchased, expectedProductId = productId)
                    ?: throw PurchaseOutcomeException(PurchaseOutcome.unverified)
            }
        } finally {
            operationInProgress = false
        }
    }

    override suspend fun restoreOrRefreshVerified(): Entitlement = operationMutex.withLock {
        operationInProgress = true
        try {
            ensureConnected()
            val params = QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
            val (result, purchases) = suspendCancellableCoroutine { continuation ->
                billingClient.queryPurchasesAsync(params) { billingResult, purchaseList ->
                    if (continuation.isActive) continuation.resume(billingResult to purchaseList)
                }
            }
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                throw BillingGatewayException(
                    "restore_failed",
                    "Google Play could not refresh purchases (${result.responseCode}).",
                )
            }
            val candidates = purchases
                .filter { purchase ->
                    purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                        purchase.products.size == 1 && purchase.products.single() in ProductIds.android
                }
                .sortedWith(
                    compareByDescending<Purchase> { it.isAutoRenewing }
                        .thenBy { ProductIds.android.indexOf(it.products.single()) },
                )
            for (purchase in candidates) {
                verifyAndComplete(purchase)?.let { return@withLock it }
            }
            Entitlement.Free
        } finally {
            operationInProgress = false
        }
    }

    private suspend fun verifyAndComplete(
        purchase: Purchase,
        expectedProductId: String? = null,
    ): Entitlement? {
        val productId = purchase.products.singleOrNull() ?: return null
        if (productId !in ProductIds.android ||
            (expectedProductId != null && productId != expectedProductId) ||
            purchase.purchaseState != Purchase.PurchaseState.PURCHASED ||
            purchase.purchaseToken.isBlank() ||
            purchase.originalJson.isBlank() ||
            purchase.signature.isBlank()
        ) return null

        val verified = verifier.verify(
            originalJson = purchase.originalJson,
            signatureBase64 = purchase.signature,
            expectedProductId = productId,
            expectedPackageName = androidPackageName,
            expectedPurchaseToken = purchase.purchaseToken,
        )
        if (!verified) return null

        if (!purchase.isAcknowledged) {
            val params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            val result = suspendCancellableCoroutine { continuation ->
                billingClient.acknowledgePurchase(params) { billingResult ->
                    if (continuation.isActive) continuation.resume(billingResult)
                }
            }
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                throw BillingGatewayException(
                    "acknowledgement_failed",
                    "Google Play could not acknowledge the verified purchase.",
                )
            }
        }

        lastVerifiedProductId = productId
        return Entitlement(
            tier = AccessTier.pro,
            source = EntitlementSource.googlePlaySubscription,
            validUntil = clock.now().plus(Duration.ofHours(ANDROID_LAST_VERIFIED_CONTINUITY_HOURS)),
            willRenew = purchase.isAutoRenewing,
        )
    }

    override suspend fun openSubscriptionManagement() {
        val uri = subscriptionManagementUri(lastVerifiedProductId, androidPackageName)
        val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            appContext.startActivity(intent)
        } catch (error: Throwable) {
            throw BillingGatewayException(
                "subscription_management_unavailable",
                "The Play subscription-management page could not be opened.",
                error,
            )
        }
    }

    private suspend fun ensureConnected() {
        if (billingClient.isReady) return
        connectionMutex.withLock {
            if (billingClient.isReady) return
            suspendCancellableCoroutine<Unit> { continuation ->
                billingClient.startConnection(object : BillingClientStateListener {
                    override fun onBillingSetupFinished(billingResult: BillingResult) {
                        if (!continuation.isActive) return
                        if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                            continuation.resume(Unit)
                        } else {
                            continuation.resumeWithException(
                                BillingGatewayException(
                                    "store_unavailable",
                                    "Google Play Billing setup failed (${billingResult.responseCode}).",
                                ),
                            )
                        }
                    }

                    override fun onBillingServiceDisconnected() {
                        // Auto-service reconnection is enabled. The next API call reconnects.
                    }
                })
            }
        }
    }

    private fun requireAllowedProduct(productId: String) {
        if (productId !in ProductIds.android) {
            throw BillingGatewayException("wrong_product", "Selected product is not an Android SKU.")
        }
    }

    private fun outcomeForBillingResult(result: BillingResult): PurchaseOutcomeException =
        when (result.responseCode) {
            BillingClient.BillingResponseCode.USER_CANCELED ->
                PurchaseOutcomeException(PurchaseOutcome.cancelled)
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED ->
                PurchaseOutcomeException(PurchaseOutcome.failed)
            else -> PurchaseOutcomeException(PurchaseOutcome.failed)
        }

    override fun close() {
        billingClient.endConnection()
    }

    private data class PurchaseUpdate(
        val billingResult: BillingResult,
        val purchases: List<Purchase>,
    )
}

private fun JsonObject.string(field: String): String? =
    (this[field] as? JsonPrimitive)?.contentOrNull

private fun JsonObject.stringOrNull(field: String): String? = string(field)
