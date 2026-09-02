import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'core/models.dart';
import 'core/wallet_engine.dart';
import 'services/billing_service.dart';
import 'services/backup_service.dart';
import 'services/document_store.dart';
import 'services/reminder_service.dart';

class SelectedBackup {
  const SelectedBackup({
    required this.encoded,
    required this.preview,
    required this.expectedRevision,
  });

  final String encoded;
  final WalletData preview;
  final int expectedRevision;
}

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required this.engine,
    BillingService? billing,
    ReminderService? reminders,
    DocumentStore? documents,
    BackupService? backups,
  }) : billing = billing ?? BillingService(),
       reminders = reminders ?? ReminderService(),
       documents = documents ?? DocumentStore(),
       backups = backups ?? BackupService();

  final WalletEngine engine;
  final BillingService billing;
  final ReminderService reminders;
  final DocumentStore documents;
  final BackupService backups;

  WalletData? wallet;
  bool loading = true;
  String? error;
  String? notice;
  int tabIndex = 0;
  StreamSubscription<Entitlement>? _entitlementSubscription;
  bool _observingLifecycle = false;

  Future<void> initialize() async {
    try {
      if (!_observingLifecycle) {
        WidgetsBinding.instance.addObserver(this);
        _observingLifecycle = true;
      }
      await billing.initialize();
      await reminders.initialize();
      _entitlementSubscription = billing.verifiedEntitlements.listen((
        entitlement,
      ) async {
        await engine.resumePendingDraft(entitlement);
        await engine.resumePendingConsumableDraft(entitlement);
        await reload(notify: true);
        notice = 'Welding Wallet Pro is active.';
        notifyListeners();
      });
      try {
        await billing.restore();
      } catch (_) {
        // Offline startup must not be blocked by an unavailable store.
      }
      wallet = await engine.snapshot();
      if (wallet!.settings.remindersEnabled) await reconcileReminders();
      await engine.enforceDowngradeIfNeeded();
      wallet = await engine.snapshot();
    } catch (value) {
      error = _message(value);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(restorePurchases(silent: true));
    }
  }

  Future<void> reload({bool notify = true}) async {
    wallet = await engine.snapshot();
    if (notify) notifyListeners();
  }

  void selectTab(int index) {
    tabIndex = index;
    notifyListeners();
  }

  void clearMessage() {
    error = null;
    notice = null;
  }

  Future<bool> run(Future<void> Function() action, {String? success}) async {
    clearMessage();
    try {
      await action();
      await reload(notify: false);
      notice = success;
      notifyListeners();
      return true;
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return false;
    }
  }

  Future<AddCylinderResult?> addCylinder(AddCylinderDraft draft) async {
    clearMessage();
    try {
      final result = await engine.addOrGate(draft);
      await reload(notify: false);
      notice = result.wasAdded ? 'Cylinder added.' : null;
      notifyListeners();
      return result;
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return null;
    }
  }

  Future<AddConsumableResult?> addConsumable(AddConsumableDraft draft) async {
    clearMessage();
    try {
      final result = await engine.addConsumableOrGate(draft);
      await reload(notify: false);
      notice = result.wasAdded ? 'Consumable batch added.' : null;
      notifyListeners();
      return result;
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return null;
    }
  }

  Future<bool> pickAndAttachCertificate(String consumableId) async {
    clearMessage();
    try {
      final current = wallet!.consumables.firstWhere(
        (value) => value.id == consumableId,
      );
      final oldPath = current.certificateLocalPath;
      final stored = await documents.pickAndStoreCertificate(consumableId);
      if (stored == null) return false;
      try {
        await engine.attachConsumableCertificate(
          consumableId,
          localPath: stored.path,
          originalName: stored.originalName,
        );
      } catch (_) {
        await documents.delete(stored.path);
        rethrow;
      }
      if (oldPath != stored.path) await documents.delete(oldPath);
      await reload(notify: false);
      notice = 'Certificate attached.';
      notifyListeners();
      return true;
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return false;
    }
  }

  Future<bool> openCertificate(String localPath) async {
    clearMessage();
    try {
      await documents.open(localPath);
      return true;
    } catch (value) {
      error = 'The certificate file could not be opened.';
      notifyListeners();
      return false;
    }
  }

  Future<void> createReminder({
    required String cylinderId,
    required ReminderKind kind,
    required String title,
    required DateTime dueAt,
  }) async {
    final reminder = await engine.createReminder(
      cylinderId: cylinderId,
      kind: kind,
      title: title,
      dueAt: dueAt,
    );
    final current = await engine.snapshot();
    if (current.settings.remindersEnabled) {
      final cylinder = current.cylinders.firstWhere(
        (value) => value.id == cylinderId,
      );
      try {
        await reminders.schedule(reminder, cylinderName: cylinder.nickname);
        await engine.setReminderDelivery(
          reminder.id,
          ReminderDelivery.scheduled,
        );
      } catch (_) {
        await engine.setReminderDelivery(
          reminder.id,
          ReminderDelivery.needsScheduling,
        );
        throw const WalletRuleException(
          'Reminder saved. Device alert is pending.',
        );
      }
    } else {
      await engine.setReminderDelivery(reminder.id, ReminderDelivery.idle);
    }
  }

  Future<void> completeReminder(String reminderId) async {
    final current = await engine.snapshot();
    final reminder = current.reminders.firstWhere(
      (value) => value.id == reminderId,
    );
    await reminders.cancel(reminder);
    await engine.completeReminder(reminderId);
  }

  Future<void> deleteReminder(String reminderId) async {
    await engine.deleteReminder(
      reminderId,
      cancelSystemReminder: reminders.cancel,
    );
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    if (enabled && !await reminders.requestPermission()) {
      throw const WalletRuleException(
        'Notifications are disabled. Allow them in device settings first.',
      );
    }
    await engine.updateSettings(remindersEnabled: enabled);
    if (enabled) {
      await reconcileReminders();
    } else {
      await reminders.cancelAll();
    }
  }

  Future<void> reconcileReminders() async {
    final current = await engine.snapshot();
    for (final reminder in current.reminders.where(
      (value) =>
          !value.completed && value.dueAt.isAfter(DateTime.now().toUtc()),
    )) {
      final cylinder = current.cylinders.firstWhere(
        (value) => value.id == reminder.cylinderId,
      );
      try {
        await reminders.schedule(reminder, cylinderName: cylinder.nickname);
        await engine.setReminderDelivery(
          reminder.id,
          ReminderDelivery.scheduled,
        );
      } catch (_) {
        await engine.setReminderDelivery(
          reminder.id,
          ReminderDelivery.needsScheduling,
        );
      }
    }
  }

  Future<List<ProductDetails>> products() async {
    try {
      return await billing.products();
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return const <ProductDetails>[];
    }
  }

  Future<void> purchase(ProductDetails product) async {
    await run(() => billing.purchase(product));
  }

  Future<void> restorePurchases({bool silent = false}) async {
    if (silent) {
      try {
        await billing.restore();
      } catch (_) {
        // A background entitlement refresh must never interrupt the user.
      }
      return;
    }
    final restored = await run(
      billing.restore,
      success: 'Purchases checked.',
    );
    if (!restored) return;
  }

  Future<void> openPurchaseManagement() async {
    await run(billing.openManagement);
  }

  Future<bool> exportBackup() async {
    clearMessage();
    try {
      final saved = await backups.save(await engine.exportBackup());
      notice = saved ? 'Backup saved.' : null;
      notifyListeners();
      return saved;
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return false;
    }
  }

  Future<SelectedBackup?> chooseBackup() async {
    clearMessage();
    try {
      final encoded = await backups.pick();
      if (encoded == null) return null;
      final current = await engine.snapshot();
      return SelectedBackup(
        encoded: encoded,
        preview: engine.inspectBackup(encoded),
        expectedRevision: current.revision,
      );
    } catch (value) {
      error = _message(value);
      notifyListeners();
      return null;
    }
  }

  Future<bool> restoreBackup(SelectedBackup backup) async {
    final restored = await run(() async {
      await reminders.cancelAll();
      await engine.importBackup(
        backup.encoded,
        expectedRevision: backup.expectedRevision,
      );
      final current = await engine.snapshot();
      if (current.settings.remindersEnabled) await reconcileReminders();
    }, success: 'Backup restored.');
    return restored;
  }

  Future<bool> deleteAllData() async => run(() async {
    await reminders.cancelAll();
    await documents.deleteAll();
    await engine.deleteAllWalletData(confirmed: true);
  }, success: 'Wallet deleted.');

  String _message(Object value) => switch (value) {
    WalletRuleException exception => exception.message,
    StateError exception => exception.message.toString(),
    _ => 'Something went wrong. Check the wallet before retrying.',
  };

  @override
  void dispose() {
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _entitlementSubscription?.cancel();
    unawaited(billing.dispose());
    super.dispose();
  }
}
