import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'models.dart';
import 'wallet_repository.dart';

typedef Now = DateTime Function();

class WalletRuleException implements Exception {
  const WalletRuleException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AddCylinderResult {
  const AddCylinderResult.added(this.cylinder) : paywallReason = null;
  const AddCylinderResult.gated(this.paywallReason) : cylinder = null;

  final Cylinder? cylinder;
  final PaywallReason? paywallReason;
  bool get wasAdded => cylinder != null;
}

class WalletEngine {
  WalletEngine({required this.repository, Uuid? uuid, Now? now})
    : _uuid = uuid ?? const Uuid(),
      _now = now ?? (() => DateTime.now().toUtc());

  final WalletRepository repository;
  final Uuid _uuid;
  final Now _now;

  String _id() => _uuid.v4();
  DateTime get _clock => _now().toUtc();

  Future<WalletData> snapshot() => repository.read();

  Future<WalletData> completeOnboarding() => repository.transact(
    (current) => current.next(
      settings: current.settings.copyWith(onboardingComplete: true),
    ),
  );

  Future<WalletData> updateSettings({
    String? locale,
    String? currencyCode,
    String? defaultMassUnit,
    String? defaultVolumeUnit,
    bool? remindersEnabled,
  }) => repository.transact(
    (current) => current.next(
      settings: current.settings.copyWith(
        locale: locale,
        currencyCode: currencyCode,
        defaultMassUnit: defaultMassUnit,
        defaultVolumeUnit: defaultVolumeUnit,
        remindersEnabled: remindersEnabled,
      ),
    ),
  );

  Future<Supplier> createSupplier(String name, {String? notes}) async {
    final safeName = name.trim();
    if (safeName.isEmpty) {
      throw const WalletRuleException('Enter a supplier name.');
    }
    final now = _clock;
    final supplier = Supplier(
      id: _id(),
      name: safeName,
      createdAt: now,
      updatedAt: now,
      notes: _clean(notes),
    );
    await repository.transact((current) {
      final duplicate = current.suppliers.any(
        (value) => value.name.toLowerCase() == safeName.toLowerCase(),
      );
      if (duplicate) {
        throw const WalletRuleException('That supplier already exists.');
      }
      return current.next(
        suppliers: <Supplier>[...current.suppliers, supplier],
      );
    });
    return supplier;
  }

  Future<void> deleteSupplier(String id) async {
    await repository.transact((current) {
      final isReferenced =
          current.cylinders.any((value) => value.supplierId == id) ||
          current.events.any((value) => value.supplierId == id) ||
          current.pendingDraft?.draft.supplierId == id;
      if (isReferenced) {
        throw const WalletRuleException(
          'This supplier is used by wallet history and cannot be deleted.',
        );
      }
      return current.next(
        suppliers: current.suppliers.where((value) => value.id != id).toList(),
      );
    });
  }

  Future<AddCylinderResult> addOrGate(AddCylinderDraft draft) async {
    _validateDraft(draft);
    AddCylinderResult? result;
    await repository.transact((current) {
      _requireSupplier(current, draft.supplierId);
      final currentCount = current.cylinders
          .where((value) => value.consumesCurrentSlot)
          .length;
      final isPro = current.entitlementCache.isProAt(_clock);
      if (!isPro && currentCount >= freeEditableCylinderLimit) {
        result = const AddCylinderResult.gated(PaywallReason.addFourthCylinder);
        return current.next(pendingDraft: PendingCylinderDraft(draft: draft));
      }
      final cylinder = _buildCylinder(draft);
      result = AddCylinderResult.added(cylinder);
      return current.next(
        cylinders: <Cylinder>[...current.cylinders, cylinder],
        events: <CylinderEvent>[
          ...current.events,
          _event(
            cylinder.id,
            CylinderEventType.created,
            supplierId: cylinder.supplierId,
          ),
        ],
        freeEditableSelection: isPro
            ? current.freeEditableSelection
            : <String>[
                ...current.freeEditableSelection,
                cylinder.id,
              ].take(freeEditableCylinderLimit).toList(),
        clearPendingDraft: true,
      );
    });
    return result!;
  }

  Future<Cylinder?> resumePendingDraft(Entitlement verified) async {
    if (!verified.isProAt(_clock)) return null;
    Cylinder? added;
    await repository.transact((current) {
      final pending = current.pendingDraft;
      if (pending == null || pending.draftResumed) {
        return current.next(entitlementCache: verified);
      }
      _requireSupplier(current, pending.draft.supplierId);
      added = _buildCylinder(pending.draft);
      return current.next(
        entitlementCache: verified,
        cylinders: <Cylinder>[...current.cylinders, added!],
        events: <CylinderEvent>[
          ...current.events,
          _event(
            added!.id,
            CylinderEventType.created,
            supplierId: added!.supplierId,
          ),
        ],
        clearPendingDraft: true,
      );
    });
    return added;
  }

  Future<bool> canEditCylinder(String cylinderId) async {
    final current = await repository.read();
    final cylinder = _cylinder(current, cylinderId);
    if (current.entitlementCache.isProAt(_clock)) return true;
    if (!cylinder.consumesCurrentSlot) return false;
    final selected = current.freeEditableSelection.isEmpty
        ? current.cylinders
              .where((value) => value.consumesCurrentSlot)
              .take(freeEditableCylinderLimit)
              .map((value) => value.id)
              .toSet()
        : current.freeEditableSelection.toSet();
    return selected.contains(cylinderId);
  }

  Future<WalletData> enforceDowngradeIfNeeded() =>
      repository.transact((current) {
        if (current.entitlementCache.isProAt(_clock)) return current;
        final allowed = current.cylinders
            .where((value) => value.consumesCurrentSlot)
            .take(freeEditableCylinderLimit)
            .map((value) => value.id)
            .toList();
        return current.next(
          freeEditableSelection: allowed,
          entitlementCache: Entitlement.free,
        );
      });

  Future<WalletData> selectFreeEditable(List<String> cylinderIds) =>
      repository.transact((current) {
        final unique = cylinderIds.toSet();
        if (unique.length > freeEditableCylinderLimit) {
          throw const WalletRuleException(
            'Choose no more than three cylinders.',
          );
        }
        final currentIds = current.cylinders
            .where((value) => value.consumesCurrentSlot)
            .map((value) => value.id)
            .toSet();
        if (!currentIds.containsAll(unique)) {
          throw const WalletRuleException(
            'Only current cylinders can be selected.',
          );
        }
        return current.next(freeEditableSelection: unique.toList());
      });

  Future<void> recordRefill(
    String cylinderId, {
    Money? amount,
    String? supplierId,
    String? note,
  }) => _recordEditableEvent(
    cylinderId,
    CylinderEventType.refill,
    amount: amount,
    supplierId: supplierId,
    note: note,
  );

  Future<void> recordCost(
    String cylinderId, {
    required Money amount,
    String? supplierId,
    String? note,
  }) => _recordEditableEvent(
    cylinderId,
    CylinderEventType.cost,
    amount: amount,
    supplierId: supplierId,
    note: note,
  );

  Future<void> recordExchange(
    String cylinderId, {
    Money? amount,
    String? supplierId,
    String? note,
  }) async {
    await _requireEditable(cylinderId);
    await repository.transact((current) {
      _requireSupplier(current, supplierId);
      final old = _cylinder(current, cylinderId);
      final updated = old.copyWith(
        lifecycle: CylinderLifecycle.exchanged,
        supplierId: supplierId,
        updatedAt: _clock,
      );
      return current.next(
        cylinders: current.cylinders
            .map((value) => value.id == cylinderId ? updated : value)
            .toList(),
        events: <CylinderEvent>[
          ...current.events,
          _event(
            cylinderId,
            CylinderEventType.exchange,
            amount: amount,
            supplierId: supplierId ?? old.supplierId,
            note: note,
          ),
        ],
      );
    });
  }

  Future<void> markReturned(String cylinderId, {String? note}) async {
    await _changeLifecycle(
      cylinderId,
      CylinderLifecycle.returned,
      CylinderEventType.returned,
      note: note,
    );
  }

  Future<void> archiveCylinder(String cylinderId) async {
    await _changeLifecycle(
      cylinderId,
      CylinderLifecycle.archived,
      CylinderEventType.archived,
    );
  }

  Future<Reminder> createReminder({
    required String cylinderId,
    required ReminderKind kind,
    required String title,
    required DateTime dueAt,
  }) async {
    await _requireEditable(cylinderId);
    if (title.trim().isEmpty) {
      throw const WalletRuleException('Enter a reminder title.');
    }
    if (!dueAt.toUtc().isAfter(_clock)) {
      throw const WalletRuleException('Choose a future date and time.');
    }
    final id = _id();
    final reminder = Reminder(
      id: id,
      cylinderId: cylinderId,
      kind: kind,
      title: title.trim(),
      dueAt: dueAt.toUtc(),
      createdAt: _clock,
      delivery: ReminderDelivery.needsScheduling,
      notificationId: stableNotificationId(id),
    );
    await repository.transact(
      (current) => current.next(
        reminders: <Reminder>[...current.reminders, reminder],
        events: <CylinderEvent>[
          ...current.events,
          _event(cylinderId, CylinderEventType.reminderCreated),
        ],
      ),
    );
    return reminder;
  }

  Future<void> completeReminder(String reminderId) async {
    await repository.transact((current) {
      final reminder = _reminder(current, reminderId);
      return current.next(
        reminders: current.reminders
            .map(
              (value) => value.id == reminderId
                  ? value.copyWith(
                      completed: true,
                      delivery: ReminderDelivery.idle,
                    )
                  : value,
            )
            .toList(),
        events: <CylinderEvent>[
          ...current.events,
          _event(reminder.cylinderId, CylinderEventType.reminderCompleted),
        ],
      );
    });
  }

  Future<void> deleteReminder(
    String reminderId, {
    Future<void> Function(Reminder reminder)? cancelSystemReminder,
    bool force = false,
  }) async {
    final current = await repository.read();
    final reminder = _reminder(current, reminderId);
    if (!force && cancelSystemReminder != null) {
      await cancelSystemReminder(reminder);
    }
    await repository.transact((latest) {
      _reminder(latest, reminderId);
      return latest.next(
        reminders: latest.reminders
            .where((value) => value.id != reminderId)
            .toList(),
        events: <CylinderEvent>[
          ...latest.events,
          _event(reminder.cylinderId, CylinderEventType.reminderDeleted),
        ],
      );
    });
  }

  Map<String, int> spendByCurrency(WalletData data, {String? cylinderId}) {
    final totals = <String, int>{};
    for (final event in data.events) {
      if (cylinderId != null && event.cylinderId != cylinderId) continue;
      final amount = event.amount;
      if (amount == null) continue;
      totals.update(
        amount.currencyCode,
        (value) => value + amount.minorUnits,
        ifAbsent: () => amount.minorUnits,
      );
    }
    return totals;
  }

  Future<String> exportBackup() async {
    final data = await repository.read();
    final encoded = jsonEncode(<String, Object?>{
      'format': 'welding-gas-wallet-backup',
      'version': walletSchemaVersion,
      'exportedAt': _clock.toIso8601String(),
      'wallet': data.toJson(
        includeEntitlement: false,
        includeLocalPhotos: false,
      ),
    });
    if (utf8.encode(encoded).length > maximumBackupBytes) {
      throw const WalletRuleException('The backup is larger than 5 MB.');
    }
    return encoded;
  }

  Future<WalletData> importBackup(
    String encoded, {
    required int expectedRevision,
  }) async {
    if (utf8.encode(encoded).length > maximumBackupBytes) {
      throw const WalletRuleException('The backup is larger than 5 MB.');
    }
    final raw = jsonDecode(encoded);
    if (raw is! Map || raw['wallet'] is! Map) {
      throw const WalletRuleException(
        'This is not a Welding Gas Wallet backup.',
      );
    }
    final current = await repository.read();
    if (current.revision != expectedRevision) {
      throw const WalletRuleException(
        'Wallet data changed. Review the backup again.',
      );
    }
    final imported = WalletData.fromJson(
      Map<String, Object?>.from(raw['wallet'] as Map),
    );
    _validateImported(imported);
    final safe = WalletData(
      schemaVersion: walletSchemaVersion,
      revision: current.revision + 1,
      settings: imported.settings,
      suppliers: imported.suppliers,
      cylinders: imported.cylinders,
      events: imported.events,
      reminders: imported.reminders,
      pendingDraft: imported.pendingDraft,
      freeEditableSelection: imported.freeEditableSelection,
      entitlementCache: current.entitlementCache,
    );
    await repository.replace(safe);
    return safe;
  }

  Future<void> deleteAllWalletData({required bool confirmed}) async {
    if (!confirmed) {
      throw const WalletRuleException('Confirm deletion before continuing.');
    }
    await repository.purge();
  }

  Future<void> _recordEditableEvent(
    String cylinderId,
    CylinderEventType type, {
    Money? amount,
    String? supplierId,
    String? note,
  }) async {
    await _requireEditable(cylinderId);
    await repository.transact((current) {
      _cylinder(current, cylinderId);
      _requireSupplier(current, supplierId);
      return current.next(
        events: <CylinderEvent>[
          ...current.events,
          _event(
            cylinderId,
            type,
            amount: amount,
            supplierId: supplierId,
            note: note,
          ),
        ],
      );
    });
  }

  Future<void> _changeLifecycle(
    String cylinderId,
    CylinderLifecycle lifecycle,
    CylinderEventType type, {
    String? note,
  }) async {
    await _requireEditable(cylinderId);
    await repository.transact((current) {
      final cylinder = _cylinder(current, cylinderId);
      final updated = cylinder.copyWith(
        lifecycle: lifecycle,
        updatedAt: _clock,
      );
      return current.next(
        cylinders: current.cylinders
            .map((value) => value.id == cylinderId ? updated : value)
            .toList(),
        events: <CylinderEvent>[
          ...current.events,
          _event(cylinderId, type, note: note),
        ],
        freeEditableSelection: current.freeEditableSelection
            .where((value) => value != cylinderId)
            .toList(),
      );
    });
  }

  Future<void> _requireEditable(String cylinderId) async {
    if (!await canEditCylinder(cylinderId)) {
      throw const WalletRuleException(
        'This cylinder is read-only on the free plan.',
      );
    }
  }

  Cylinder _buildCylinder(AddCylinderDraft draft) {
    final now = _clock;
    return Cylinder(
      id: _id(),
      nickname: draft.nickname.trim(),
      gasType: draft.gasType.trim(),
      relationship: draft.relationship,
      lifecycle: CylinderLifecycle.active,
      createdAt: now,
      updatedAt: now,
      capacityValue: draft.capacityValue,
      capacityUnit: _clean(draft.capacityUnit),
      serialNumber: _clean(draft.serialNumber),
      localPhotoUri: _clean(draft.localPhotoUri),
      supplierId: draft.supplierId,
      acquisitionAmount: draft.acquisitionAmount,
      acquiredAt: draft.acquiredAt?.toUtc(),
    );
  }

  CylinderEvent _event(
    String cylinderId,
    CylinderEventType type, {
    String? supplierId,
    Money? amount,
    String? note,
  }) => CylinderEvent(
    id: _id(),
    cylinderId: cylinderId,
    type: type,
    occurredAt: _clock,
    supplierId: supplierId,
    amount: amount,
    note: _clean(note),
  );

  void _validateDraft(AddCylinderDraft draft) {
    if (draft.nickname.trim().isEmpty) {
      throw const WalletRuleException('Enter a cylinder name.');
    }
    if (draft.gasType.trim().isEmpty) {
      throw const WalletRuleException('Choose a gas type.');
    }
    if (draft.capacityValue != null && draft.capacityValue! <= 0) {
      throw const WalletRuleException('Capacity must be greater than zero.');
    }
  }

  void _requireSupplier(WalletData current, String? supplierId) {
    if (supplierId == null) return;
    if (!current.suppliers.any((value) => value.id == supplierId)) {
      throw const WalletRuleException('Choose a supplier that still exists.');
    }
  }

  Cylinder _cylinder(WalletData data, String id) => data.cylinders.firstWhere(
    (value) => value.id == id,
    orElse: () => throw const WalletRuleException('Cylinder not found.'),
  );

  Reminder _reminder(WalletData data, String id) => data.reminders.firstWhere(
    (value) => value.id == id,
    orElse: () => throw const WalletRuleException('Reminder not found.'),
  );

  void _validateImported(WalletData data) {
    if (data.schemaVersion > walletSchemaVersion) {
      throw const WalletRuleException('This backup needs a newer app version.');
    }
    final supplierIds = data.suppliers.map((value) => value.id).toSet();
    final cylinderIds = data.cylinders.map((value) => value.id).toSet();
    if (supplierIds.length != data.suppliers.length ||
        cylinderIds.length != data.cylinders.length) {
      throw const WalletRuleException('The backup contains duplicate records.');
    }
    if (data.cylinders.any(
          (value) =>
              value.supplierId != null &&
              !supplierIds.contains(value.supplierId),
        ) ||
        data.events.any(
          (value) =>
              !cylinderIds.contains(value.cylinderId) ||
              (value.supplierId != null &&
                  !supplierIds.contains(value.supplierId)),
        ) ||
        data.reminders.any(
          (value) => !cylinderIds.contains(value.cylinderId),
        )) {
      throw const WalletRuleException('The backup contains broken references.');
    }
  }
}

String? _clean(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}
