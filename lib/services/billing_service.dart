import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';

const String monthlyProductId = 'com.gooduse.weldinggaswallet.pro.monthly';
const String annualProductId = 'com.gooduse.weldinggaswallet.pro.annual';
const String iosLifetimeProductId =
    'com.gooduse.weldinggaswallet.pro.lifetime';

class BillingService {
  BillingService({InAppPurchase? store}) : _storeOverride = store;

  final InAppPurchase? _storeOverride;
  InAppPurchase get _store => _storeOverride ?? InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final _verified = StreamController<Entitlement>.broadcast();

  Stream<Entitlement> get verifiedEntitlements => _verified.stream;

  Future<void> initialize() async {
    _subscription ??= _store.purchaseStream.listen(_handlePurchases);
  }

  Future<List<ProductDetails>> products() async {
    if (!await _store.isAvailable()) return const <ProductDetails>[];
    final identifiers = Platform.isIOS
        ? const <String>{iosLifetimeProductId}
        : const <String>{monthlyProductId, annualProductId};
    final response = await _store.queryProductDetails(identifiers);
    if (response.error != null) {
      throw StateError(response.error!.message);
    }
    return response.productDetails;
  }

  Future<void> purchase(ProductDetails product) async {
    final started = await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!started) throw StateError('The store could not start this purchase.');
  }

  Future<void> restore() => _store.restorePurchases();

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final knownProduct = Platform.isIOS
          ? purchase.productID == iosLifetimeProductId
          : purchase.productID == monthlyProductId ||
                purchase.productID == annualProductId;
      final storeConfirmed =
          purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      final hasStoreEvidence =
          purchase.verificationData.localVerificationData.isNotEmpty ||
          purchase.verificationData.serverVerificationData.isNotEmpty;
      if (knownProduct && storeConfirmed && hasStoreEvidence) {
        _verified.add(
          Entitlement(
            tier: AccessTier.pro,
            source: Platform.isIOS
                ? EntitlementSource.appStorePurchase
                : EntitlementSource.googlePlaySubscription,
            validUntil: Platform.isIOS
                ? DateTime.utc(9999, 12, 31)
                : DateTime.now().toUtc().add(const Duration(hours: 24)),
            willRenew: !Platform.isIOS,
          ),
        );
      }
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    }
  }

  Future<void> openManagement() async {
    if (Platform.isIOS) {
      throw StateError('The iOS unlock is a one-time purchase.');
    }
    final uri = Uri.parse(
      'https://play.google.com/store/account/subscriptions?package=com.goodusestudios.weldinggaswallet',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open subscription management.');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _verified.close();
  }
}
