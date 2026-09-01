import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'core/models.dart';
import 'core/wallet_engine.dart';
import 'services/billing_service.dart';
import 'services/document_store.dart';
import 'services/reminder_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.engine,
    BillingService? billing,
    ReminderService? reminders,
    DocumentStore? documents,
  }) : billing = billing ?? BillingService(),
       reminders = reminders ?? ReminderService(),
       documents = documents ?? DocumentStore();

  final WalletEngine engine;
  final BillingService billing;
  final ReminderService reminders;
  final DocumentStore documents;

  WalletData? wallet;
  bool loading = true;
  String? error;
  String? notice;
  int tabIndex = 0;
  StreamSubscription<Entitlement>? _entitlementSubscription;

  Future<void> initialize() async {
    try {
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
      final stored = await documents.pickAndStoreCertificate(consumableId);
      if (stored == null) return false;
      await engine.attachConsumableCertificate(
        consumableId,
        localPath: stored.path,
        originalName: stored.originalName,
      );
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
      await reminders.schedule(reminder, cylinderName: cylinder.nickname);
    }
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
      await reminders.schedule(reminder, cylinderName: cylinder.nickname);
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

  String _message(Object value) => switch (value) {
    WalletRuleException exception => exception.message,
    _ => 'Something went wrong. Your saved wallet was not changed.',
  };

  @override
  void dispose() {
    _entitlementSubscription?.cancel();
    unawaited(billing.dispose());
    super.dispose();
  }
}
