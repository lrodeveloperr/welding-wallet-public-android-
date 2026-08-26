package com.goodusestudios.weldinggaswallet.backend

import com.goodusestudios.weldinggaswallet.backend.billing.GooglePlayPurchaseVerifier
import com.goodusestudios.weldinggaswallet.backend.billing.PlaySubscriptionPlanEvidence
import com.goodusestudios.weldinggaswallet.backend.billing.matchesLockedPlaySubscriptionContract
import com.goodusestudios.weldinggaswallet.backend.domain.ProductIds
import com.android.billingclient.api.ProductDetails
import org.junit.Assert.*
import org.junit.Test
import java.nio.charset.StandardCharsets
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class GooglePlayVerifierTest {
    @Test
    fun verifierAcceptsSignedMatchingPurchaseAndRejectsTamper() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val key = Base64.getEncoder().encodeToString(pair.public.encoded)
        val json = """{"packageName":"com.goodusestudios.weldinggaswallet","productId":"${ProductIds.androidAnnual}","purchaseToken":"token-1","purchaseState":0}"""
        val signer = Signature.getInstance("SHA1withRSA")
        signer.initSign(pair.private)
        signer.update(json.toByteArray(StandardCharsets.UTF_8))
        val signature = Base64.getEncoder().encodeToString(signer.sign())
        val verifier = GooglePlayPurchaseVerifier(key)
        assertTrue(verifier.verify(json, signature, ProductIds.androidAnnual, "com.goodusestudios.weldinggaswallet", "token-1"))
        assertFalse(verifier.verify(json.replace("token-1", "token-2"), signature, ProductIds.androidAnnual, "com.goodusestudios.weldinggaswallet", "token-2"))
    }

    @Test
    fun lockedAnnualPlanRejectsOffersAndWrongCadence() {
        val valid = PlaySubscriptionPlanEvidence(
            productId = ProductIds.androidAnnual,
            basePlanId = "annual",
            offerId = null,
            offerTags = emptyList(),
            hasInstallmentPlan = false,
            pricingPhaseCount = 1,
            billingPeriod = "P1Y",
            priceAmountMicros = 12_990_000L,
            recurrenceMode = ProductDetails.RecurrenceMode.INFINITE_RECURRING,
            billingCycleCount = 0,
        )
        assertTrue(matchesLockedPlaySubscriptionContract(valid))
        assertFalse(matchesLockedPlaySubscriptionContract(valid.copy(offerId = "intro")))
        assertFalse(matchesLockedPlaySubscriptionContract(valid.copy(billingPeriod = "P1M")))
    }
}
