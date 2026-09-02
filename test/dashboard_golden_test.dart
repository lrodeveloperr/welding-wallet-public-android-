import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:welding_wallet/app_controller.dart';
import 'package:welding_wallet/core/models.dart';
import 'package:welding_wallet/core/wallet_engine.dart';
import 'package:welding_wallet/core/wallet_repository.dart';
import 'package:welding_wallet/ui/wallet_app.dart';

void main() {
  testWidgets('dashboard keeps only essential actions', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.utc(2026, 9, 1, 9);
    final cylinder = Cylinder(
      id: 'cylinder-1',
      nickname: 'Workshop Argon',
      gasType: 'Argon',
      relationship: RelationshipType.owned,
      lifecycle: CylinderLifecycle.active,
      createdAt: now.subtract(const Duration(days: 100)),
      updatedAt: now,
      capacityValue: 20,
      capacityUnit: 'kg',
      supplierId: 'supplier-1',
    );
    final wallet = WalletData(
      schemaVersion: walletSchemaVersion,
      revision: 8,
      settings: AppSettings.create(
        locale: 'en-US',
        currencyCode: 'USD',
        onboardingComplete: true,
      ),
      suppliers: [
        Supplier(
          id: 'supplier-1',
          name: 'City Gas Supply',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      cylinders: [cylinder],
      events: [
        CylinderEvent(
          id: 'event-1',
          cylinderId: cylinder.id,
          type: CylinderEventType.refill,
          occurredAt: now,
          amount: Money(minorUnits: 4860, currencyCode: 'USD'),
        ),
      ],
      reminders: [
        Reminder(
          id: 'reminder-1',
          cylinderId: cylinder.id,
          kind: ReminderKind.check,
          title: 'Inspect valve',
          dueAt: now.add(const Duration(days: 4)),
          createdAt: now,
          delivery: ReminderDelivery.scheduled,
          notificationId: 1,
        ),
      ],
      pendingDraft: null,
      freeEditableSelection: [cylinder.id],
      entitlementCache: Entitlement.free,
    );
    final controller =
        AppController(
            engine: WalletEngine(
              repository: MemoryWalletRepository(wallet),
              now: () => now,
            ),
          )
          ..wallet = wallet
          ..loading = false;

    await tester.pumpWidget(
      WeldingWalletApp(controller: controller, autoInitialize: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welding Gas Wallet'), findsOneWidget);
    expect(find.text('QUICK ACTIONS'), findsNothing);
    expect(find.text('SUMMARY & COUNTS'), findsNothing);
    expect(find.text('Scan'), findsNothing);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pumpAndSettle();
    expect(find.text('LOW'), findsOneWidget);
    expect(find.text('Reminder'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.text('Name (optional)'), findsOneWidget);
    expect(find.text('ft³'), findsOneWidget);
  });

  testWidgets('empty dashboard offers only Add', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final wallet = WalletData.empty().next(
      settings: AppSettings.create(onboardingComplete: true),
    );
    final controller =
        AppController(
            engine: WalletEngine(
              repository: MemoryWalletRepository(wallet),
              now: () => DateTime.utc(2026, 9, 1, 9),
            ),
          )
          ..wallet = wallet
          ..loading = false;

    await tester.pumpWidget(
      WeldingWalletApp(controller: controller, autoInitialize: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('No cylinders'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Reminder'), findsNothing);
    expect(find.text('Low'), findsNothing);
    expect(find.text('Empty'), findsNothing);
    expect(find.text('Away'), findsNothing);
  });
}
