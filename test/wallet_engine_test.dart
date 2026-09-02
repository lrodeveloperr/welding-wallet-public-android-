import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:welding_wallet/core/models.dart';
import 'package:welding_wallet/core/wallet_engine.dart';
import 'package:welding_wallet/core/wallet_repository.dart';

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

  AddCylinderDraft draft(String name, {String? supplierId, String? serial}) =>
      AddCylinderDraft(
        nickname: name,
        gasType: 'Argon',
        relationship: RelationshipType.owned,
        supplierId: supplierId,
        serialNumber: serial,
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

  test('cylinder serials are unique', () async {
    await engine.addOrGate(draft('Argon', serial: 'CODE-1'));
    expect(
      () => engine.addOrGate(draft('Duplicate', serial: ' code-1 ')),
      throwsA(isA<WalletRuleException>()),
    );
  });

  test('exchange replaces the previous physical serial', () async {
    final cylinder = (await engine.addOrGate(draft('Rental', serial: 'OLD-1')))
        .cylinder!;
    await engine.recordExchange(cylinder.id, newSerialNumber: 'NEW-2');
    final wallet = await engine.snapshot();
    expect(wallet.cylinders.single.serialNumber, 'NEW-2');
    expect(wallet.events.last.note, contains('Previous serial: OLD-1'));
    expect(wallet.events.last.note, contains('New serial: NEW-2'));
  });

  test('verified Pro resumes a pending cylinder exactly once', () async {
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
    'supplier deletion is blocked while cylinder history references it',
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

  test('legacy v5 wrapper is accepted and obsolete fields are ignored', () {
    final raw = <String, Object?>{
      'format': 'welding-wallet-backup',
      'wallet': <String, Object?>{
        'schemaVersion': 5,
        'revision': 1,
        'settings': AppSettings.create(onboardingComplete: true).toJson(),
        'suppliers': <Object?>[],
        'cylinders': <Object?>[],
        'events': <Object?>[],
        'reminders': <Object?>[],
        'freeEditableSelection': <Object?>[],
        'consumables': <Object?>[
          <String, Object?>{'obsolete': true},
        ],
        'consumableEvents': <Object?>[],
      },
    };
    final inspected = engine.inspectBackup(jsonEncode(raw));
    expect(inspected.schemaVersion, 5);
    expect(inspected.cylinders, isEmpty);
  });

  test('backup rejects duplicate cylinder serials', () {
    Cylinder cylinder(String id, String serial) => Cylinder(
      id: id,
      nickname: id,
      gasType: 'Argon',
      relationship: RelationshipType.owned,
      lifecycle: CylinderLifecycle.active,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      serialNumber: serial,
    );
    final wallet = WalletData(
      schemaVersion: walletSchemaVersion,
      revision: 1,
      settings: AppSettings.create(onboardingComplete: true),
      suppliers: const [],
      cylinders: [cylinder('a', 'SAME'), cylinder('b', ' same ')],
      events: const [],
      reminders: const [],
      pendingDraft: null,
      freeEditableSelection: const [],
      entitlementCache: Entitlement.free,
    );
    final raw = jsonEncode(<String, Object?>{
      'format': 'welding-gas-wallet-backup',
      'wallet': wallet.toJson(includeEntitlement: false),
    });
    expect(
      () => engine.inspectBackup(raw),
      throwsA(isA<WalletRuleException>()),
    );
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
