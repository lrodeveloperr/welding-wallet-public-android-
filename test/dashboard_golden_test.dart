@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:welding_wallet/app_controller.dart';
import 'package:welding_wallet/core/models.dart';
import 'package:welding_wallet/core/wallet_engine.dart';
import 'package:welding_wallet/core/wallet_repository.dart';
import 'package:welding_wallet/ui/wallet_app.dart';

void main() {
  testWidgets('Inventorya-inspired wallet dashboard', (tester) async {
    final fontLoader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
    await fontLoader.load();

    // Flutter's test renderer does not automatically load the Material icon
    // font. Load the same font family explicitly so golden evidence contains
    // the real app icons instead of missing-glyph squares.
    final materialIconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIconLoader.load();

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
        locale: 'en',
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

    expect(find.text('Welding Wallet Dashboard'), findsOneWidget);
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
    expect(find.text('SUMMARY & COUNTS'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });
}
