import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';

const String monthlyProductId = 'com.gooduse.weldinggaswallet.pro.monthly';
const String annualProductId = 'com.gooduse.weldinggaswallet.pro.annual';

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
    final response = await _store.queryProductDetails(const <String>{
      monthlyProductId,
      annualProductId,
    });
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
      final knownProduct =
          purchase.productID == monthlyProductId ||
          purchase.productID == annualProductId;
      final storeConfirmed =
          purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      if (knownProduct && storeConfirmed) {
        // The store SDK is the authority. Cached access is deliberately short and
        // is refreshed through restore/on-resume rather than granted indefinitely.
        _verified.add(
          Entitlement(
            tier: AccessTier.pro,
            source: Platform.isIOS
                ? EntitlementSource.appStorePurchase
                : EntitlementSource.googlePlaySubscription,
            validUntil: DateTime.now().toUtc().add(const Duration(hours: 24)),
            willRenew: true,
          ),
        );
      }
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    }
  }

  Future<void> openManagement() async {
    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse(
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
