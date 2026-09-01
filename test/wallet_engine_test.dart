import 'package:flutter_test/flutter_test.dart';
import 'package:welding_gas_wallet/core/models.dart';
import 'package:welding_gas_wallet/core/wallet_engine.dart';
import 'package:welding_gas_wallet/core/wallet_repository.dart';

void main() {
  late MemoryWalletRepository repository;
  late WalletEngine engine;

  setUp(() {
    repository = MemoryWalletRepository();
    engine = WalletEngine(
      repository: repository,
      now: () => DateTime.utc(2026, 9),
    );
  });

  AddCylinderDraft draft(String name, {String? supplierId}) => AddCylinderDraft(
    nickname: name,
    gasType: 'Argon',
    relationship: RelationshipType.owned,
    supplierId: supplierId,
  );

  test(
    'the fourth current cylinder is preserved as a pending gated draft',
    () async {
      for (var index = 1; index <= 3; index++) {
        expect(
          (await engine.addOrGate(draft('Cylinder $index'))).wasAdded,
          isTrue,
        );
      }

      final result = await engine.addOrGate(draft('Cylinder 4'));
      final wallet = await engine.snapshot();

      expect(result.wasAdded, isFalse);
      expect(result.paywallReason, PaywallReason.addFourthCylinder);
      expect(wallet.cylinders, hasLength(3));
      expect(wallet.pendingDraft?.draft.nickname, 'Cylinder 4');
    },
  );

  test('verified Pro resumes a pending draft exactly once', () async {
    for (var index = 1; index <= 4; index++) {
      await engine.addOrGate(draft('Cylinder $index'));
    }
    final entitlement = Entitlement(
      tier: AccessTier.pro,
      source: EntitlementSource.googlePlaySubscription,
      validUntil: DateTime.utc(2026, 9, 2),
    );

    expect(await engine.resumePendingDraft(entitlement), isNotNull);
    expect(await engine.resumePendingDraft(entitlement), isNull);
    expect((await engine.snapshot()).cylinders, hasLength(4));
  });

  test(
    'supplier deletion is blocked while wallet history references it',
    () async {
      final supplier = await engine.createSupplier('City Gas');
      await engine.addOrGate(draft('Shop Argon', supplierId: supplier.id));

      expect(
        () => engine.deleteSupplier(supplier.id),
        throwsA(isA<WalletRuleException>()),
      );
    },
  );

  test('backup excludes entitlement and local photo paths', () async {
    await engine.addOrGate(
      AddCylinderDraft(
        nickname: 'Private photo cylinder',
        gasType: 'CO₂',
        relationship: RelationshipType.rented,
        localPhotoUri: '/private/device/photo.jpg',
      ),
    );

    final backup = await engine.exportBackup();

    expect(backup, isNot(contains('entitlementCache')));
    expect(backup, isNot(contains('/private/device/photo.jpg')));
  });

  test('spend is aggregated without mixing currencies', () async {
    final cylinder = (await engine.addOrGate(draft('Shop Argon'))).cylinder!;
    await engine.recordRefill(
      cylinder.id,
      amount: Money(minorUnits: 3400, currencyCode: 'USD'),
    );
    await engine.recordCost(
      cylinder.id,
      amount: Money(minorUnits: 1800, currencyCode: 'EUR'),
    );

    expect(engine.spendByCurrency(await engine.snapshot()), {
      'USD': 3400,
      'EUR': 1800,
    });
  });
}
