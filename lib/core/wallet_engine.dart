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

class AddConsumableResult {
  const AddConsumableResult.added(this.consumable) : paywallReason = null;
  const AddConsumableResult.gated(this.paywallReason) : consumable = null;

  final ConsumableBatch? consumable;
  final PaywallReason? paywallReason;
  bool get wasAdded => consumable != null;
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
          current.consumables.any((value) => value.supplierId == id) ||
          current.pendingDraft?.draft.supplierId == id ||
          current.pendingConsumableDraft?.draft.supplierId == id;
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
      _requireUniqueCode(current, draft.serialNumber);
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

  Future<AddConsumableResult> addConsumableOrGate(
    AddConsumableDraft draft,
  ) async {
    _validateConsumableDraft(draft);
    AddConsumableResult? result;
    await repository.transact((current) {
      _requireSupplier(current, draft.supplierId);
      final currentCount = current.consumables
          .where((value) => value.isActive)
          .length;
      final isPro = current.entitlementCache.isProAt(_clock);
      if (!isPro && currentCount >= freeEditableConsumableLimit) {
        result = const AddConsumableResult.gated(
          PaywallReason.addFourthConsumableBatch,
        );
        return current.next(
          pendingConsumableDraft: PendingConsumableDraft(draft: draft),
        );
      }
      final consumable = _buildConsumable(current, draft);
      result = AddConsumableResult.added(consumable);
      return current.next(
        consumables: <ConsumableBatch>[...current.consumables, consumable],
        consumableEvents: <ConsumableEvent>[
          ...current.consumableEvents,
          _consumableEvent(consumable.id, ConsumableEventType.received),
        ],
        freeEditableConsumableSelection: isPro
            ? current.freeEditableConsumableSelection
            : <String>[
                ...current.freeEditableConsumableSelection,
                consumable.id,
              ].take(freeEditableConsumableLimit).toList(),
        clearPendingConsumableDraft: true,
      );
    });
    return result!;
  }

  Future<ConsumableBatch?> resumePendingConsumableDraft(
    Entitlement verified,
  ) async {
    if (!verified.isProAt(_clock)) return null;
    ConsumableBatch? added;
    await repository.transact((current) {
      final pending = current.pendingConsumableDraft;
      if (pending == null || pending.draftResumed) {
        return current.next(entitlementCache: verified);
      }
      _requireSupplier(current, pending.draft.supplierId);
      added = _buildConsumable(current, pending.draft);
      return current.next(
        entitlementCache: verified,
        consumables: <ConsumableBatch>[...current.consumables, added!],
        consumableEvents: <ConsumableEvent>[
          ...current.consumableEvents,
          _consumableEvent(added!.id, ConsumableEventType.received),
        ],
        clearPendingConsumableDraft: true,
      );
    });
    return added;
  }

  Future<bool> canEditConsumable(String consumableId) async {
    final current = await repository.read();
    final consumable = _consumable(current, consumableId);
    if (current.entitlementCache.isProAt(_clock)) return true;
    if (!consumable.isActive) return false;
    final selected = current.freeEditableConsumableSelection.isEmpty
        ? current.consumables
              .where((value) => value.isActive)
              .take(freeEditableConsumableLimit)
              .map((value) => value.id)
              .toSet()
        : current.freeEditableConsumableSelection.toSet();
    return selected.contains(consumableId);
  }

  Future<void> attachConsumableCertificate(
    String consumableId, {
    required String localPath,
    required String originalName,
    String? certificateNumber,
    DateTime? certificateDate,
  }) async {
    await _requireEditableConsumable(consumableId);
    await repository.transact((current) {
      final old = _consumable(current, consumableId);
      final eventType = old.hasCertificate
          ? ConsumableEventType.certificateReplaced
          : ConsumableEventType.certificateAttached;
      final updated = old.copyWith(
        updatedAt: _clock,
        certificateLocalPath: localPath.trim(),
        certificateOriginalName: originalName.trim(),
        certificateNumber: _clean(certificateNumber),
        certificateDate: certificateDate?.toUtc(),
      );
      return current.next(
        consumables: current.consumables
            .map((value) => value.id == consumableId ? updated : value)
            .toList(),
        consumableEvents: <ConsumableEvent>[
          ...current.consumableEvents,
          _consumableEvent(consumableId, eventType),
        ],
      );
    });
  }

  Future<void> recordConsumableAction(
    String consumableId,
    ConsumableEventType type, {
    double? quantity,
    String? reference,
    String? note,
  }) async {
    if (type != ConsumableEventType.issued &&
        type != ConsumableEventType.used) {
      throw const WalletRuleException('Choose Issue or Use.');
    }
    final usedQuantity = quantity;
    if (usedQuantity == null ||
        !usedQuantity.isFinite ||
        usedQuantity <= 0) {
      throw const WalletRuleException('Quantity must be greater than zero.');
    }
    await _requireEditableConsumable(consumableId);
    await repository.transact((current) {
      final consumable = _consumable(current, consumableId);
      final remaining = consumable.remainingQuantity(
        current.consumableEvents,
      );
      if (usedQuantity > remaining) {
        throw WalletRuleException(
          'Only ${_plainNumber(remaining)} ${consumable.quantityUnit} remains.',
        );
      }
      return current.next(
        consumableEvents: <ConsumableEvent>[
          ...current.consumableEvents,
          _consumableEvent(
            consumableId,
            type,
            quantity: usedQuantity,
            reference: reference,
            note: note,
          ),
        ],
      );
    });
  }

  Future<void> archiveConsumable(String consumableId) async {
    await _requireEditableConsumable(consumableId);
    await repository.transact((current) {
      final old = _consumable(current, consumableId);
      final updated = old.copyWith(
        lifecycle: ConsumableLifecycle.archived,
        updatedAt: _clock,
      );
      return current.next(
        consumables: current.consumables
            .map((value) => value.id == consumableId ? updated : value)
            .toList(),
        consumableEvents: <ConsumableEvent>[
          ...current.consumableEvents,
          _consumableEvent(consumableId, ConsumableEventType.archived),
        ],
        freeEditableConsumableSelection: <String>[
          ...current.freeEditableConsumableSelection.where(
            (value) => value != consumableId,
          ),
          ...current.consumables
              .where((value) => value.id != consumableId && value.isActive)
              .map((value) => value.id),
        ].toSet().take(freeEditableConsumableLimit).toList(),
      );
    });
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
      _requireUniqueCode(current, pending.draft.serialNumber);
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
        final currentCylinderIds = current.cylinders
            .where((value) => value.consumesCurrentSlot)
            .map((value) => value.id)
            .toList();
        final allowed = <String>[
          ...current.freeEditableSelection.where(currentCylinderIds.contains),
          ...currentCylinderIds,
        ].toSet().take(freeEditableCylinderLimit).toList();
        final currentConsumableIds = current.consumables
            .where((value) => value.isActive)
            .map((value) => value.id)
            .toList();
        final allowedConsumables = <String>[
          ...current.freeEditableConsumableSelection.where(
            currentConsumableIds.contains,
          ),
          ...currentConsumableIds,
        ].toSet().take(freeEditableConsumableLimit).toList();
        return current.next(
          freeEditableSelection: allowed,
          freeEditableConsumableSelection: allowedConsumables,
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

  Future<WalletData> selectFreeEditableConsumables(
    List<String> consumableIds,
  ) => repository.transact((current) {
    final unique = consumableIds.toSet();
    if (unique.length > freeEditableConsumableLimit) {
      throw const WalletRuleException('Choose no more than three batches.');
    }
    final currentIds = current.consumables
        .where((value) => value.isActive)
        .map((value) => value.id)
        .toSet();
    if (!currentIds.containsAll(unique)) {
      throw const WalletRuleException('Only active batches can be selected.');
    }
    return current.next(
      freeEditableConsumableSelection: unique.toList(),
    );
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
    String? newSerialNumber,
    String? note,
  }) async {
    await _requireEditable(cylinderId);
    await repository.transact((current) {
      _requireSupplier(current, supplierId);
      final old = _cylinder(current, cylinderId);
      _requireUniqueCode(
        current,
        newSerialNumber,
        excludingCylinderId: cylinderId,
      );
      final nextSerial = _clean(newSerialNumber);
      final serialChange = <String>[
        if (old.serialNumber != null) 'Previous serial: ${old.serialNumber}',
        if (nextSerial != null) 'New serial: $nextSerial',
      ].join('. ');
      final cleanNote = _clean(note);
      final updated = old.copyWith(
        lifecycle: CylinderLifecycle.exchanged,
        supplierId: supplierId,
        serialNumber: nextSerial,
        clearSerial: nextSerial == null,
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
            note: <String>[
              if (serialChange.isNotEmpty) serialChange,
              if (cleanNote != null) cleanNote,
            ].join('. '),
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

  Future<void> setReminderDelivery(
    String reminderId,
    ReminderDelivery delivery,
  ) => repository.transact((current) {
    _reminder(current, reminderId);
    return current.next(
      reminders: current.reminders
          .map(
            (value) => value.id == reminderId
                ? value.copyWith(delivery: delivery)
                : value,
          )
          .toList(),
    );
  });

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
      'format': 'welding-wallet-backup',
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
    final current = await repository.read();
    if (current.revision != expectedRevision) {
      throw const WalletRuleException(
        'Wallet data changed. Review the backup again.',
      );
    }
    final imported = inspectBackup(encoded);
    final safe = WalletData(
      schemaVersion: walletSchemaVersion,
      revision: current.revision + 1,
      settings: imported.settings,
      suppliers: imported.suppliers,
      cylinders: imported.cylinders,
      consumables: imported.consumables,
      events: imported.events,
      consumableEvents: imported.consumableEvents,
      reminders: imported.reminders,
      pendingDraft: imported.pendingDraft,
      pendingConsumableDraft: imported.pendingConsumableDraft,
      freeEditableSelection: imported.freeEditableSelection,
      freeEditableConsumableSelection:
          imported.freeEditableConsumableSelection,
      entitlementCache: current.entitlementCache,
    );
    await repository.replace(safe);
    return safe;
  }

  WalletData inspectBackup(String encoded) {
    if (utf8.encode(encoded).length > maximumBackupBytes) {
      throw const WalletRuleException('The backup is larger than 5 MB.');
    }
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map ||
          raw['format'] != 'welding-wallet-backup' ||
          raw['wallet'] is! Map) {
        throw const WalletRuleException(
          'This is not a Welding Wallet backup.',
        );
      }
      final imported = WalletData.fromJson(
        Map<String, Object?>.from(raw['wallet'] as Map),
      );
      _validateImported(imported);
      return imported;
    } on WalletRuleException {
      rethrow;
    } catch (_) {
      throw const WalletRuleException('This is not a Welding Wallet backup.');
    }
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
        freeEditableSelection: <String>[
          ...current.freeEditableSelection.where(
            (value) => value != cylinderId,
          ),
          ...current.cylinders
              .where(
                (value) =>
                    value.id != cylinderId && value.consumesCurrentSlot,
              )
              .map((value) => value.id),
        ].toSet().take(freeEditableCylinderLimit).toList(),
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

  Future<void> _requireEditableConsumable(String consumableId) async {
    if (!await canEditConsumable(consumableId)) {
      throw const WalletRuleException(
        'This consumable batch is read-only on the free plan.',
      );
    }
  }

  ConsumableBatch _buildConsumable(
    WalletData current,
    AddConsumableDraft draft,
  ) {
    final now = _clock;
    final id = _id();
    final code = _clean(draft.primaryCode) ?? 'WW:$id';
    final normalized = code.toLowerCase();
    final duplicate =
        current.consumables.any(
          (value) => value.primaryCode.toLowerCase() == normalized,
        ) ||
        current.cylinders.any(
          (value) => value.serialNumber?.trim().toLowerCase() == normalized,
        );
    if (duplicate) {
      throw const WalletRuleException(
        'That barcode or QR code is already saved.',
      );
    }
    return ConsumableBatch(
      id: id,
      primaryCode: code,
      type: draft.type,
      productName: draft.productName.trim(),
      batchLot: draft.batchLot.trim(),
      receiptDate: (draft.receiptDate ?? now).toUtc(),
      lifecycle: ConsumableLifecycle.active,
      createdAt: now,
      updatedAt: now,
      initialQuantity: draft.initialQuantity,
      quantityUnit: draft.quantityUnit.trim(),
      classification: _clean(draft.classification),
      manufacturer: _clean(draft.manufacturer),
      supplierId: draft.supplierId,
      location: _clean(draft.location),
    );
  }

  ConsumableEvent _consumableEvent(
    String consumableId,
    ConsumableEventType type, {
    double? quantity,
    String? reference,
    String? note,
  }) => ConsumableEvent(
    id: _id(),
    consumableId: consumableId,
    type: type,
    occurredAt: _clock,
    quantity: quantity,
    reference: _clean(reference),
    note: _clean(note),
  );

  void _validateConsumableDraft(AddConsumableDraft draft) {
    if (draft.productName.trim().isEmpty) {
      throw const WalletRuleException('Enter the consumable product.');
    }
    if (draft.batchLot.trim().isEmpty) {
      throw const WalletRuleException('Enter the batch or lot number.');
    }
    if (!draft.initialQuantity.isFinite || draft.initialQuantity <= 0) {
      throw const WalletRuleException('Quantity must be greater than zero.');
    }
    if (draft.quantityUnit.trim().isEmpty) {
      throw const WalletRuleException('Choose a quantity unit.');
    }
    if (draft.productName.trim().length > 200 ||
        draft.batchLot.trim().length > 200 ||
        (draft.primaryCode?.trim().length ?? 0) > 300) {
      throw const WalletRuleException('Shorten the entered text.');
    }
  }

  ConsumableBatch _consumable(WalletData data, String id) =>
      data.consumables.firstWhere(
        (value) => value.id == id,
        orElse: () =>
            throw const WalletRuleException('Consumable batch not found.'),
      );

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
    if (draft.nickname.trim().length > 200 ||
        (draft.serialNumber?.trim().length ?? 0) > 300) {
      throw const WalletRuleException('Shorten the entered text.');
    }
  }

  void _requireUniqueCode(
    WalletData current,
    String? candidate, {
    String? excludingCylinderId,
  }) {
    final normalized = candidate?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return;
    final duplicate = current.cylinders.any(
          (value) =>
              value.id != excludingCylinderId &&
              value.serialNumber?.trim().toLowerCase() == normalized,
        ) ||
        current.consumables.any(
          (value) => value.primaryCode.trim().toLowerCase() == normalized,
        );
    if (duplicate) {
      throw const WalletRuleException(
        'That serial, barcode or QR code is already saved.',
      );
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
    final consumableIds = data.consumables.map((value) => value.id).toSet();
    final consumableCodes = data.consumables
        .map((value) => value.primaryCode.trim().toLowerCase())
        .toSet();
    final cylinderCodes = data.cylinders
        .map((value) => value.serialNumber?.trim().toLowerCase())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    final allCodes = <String>[...consumableCodes, ...cylinderCodes];
    final recordIds = <String>[
      ...data.suppliers.map((value) => value.id),
      ...data.cylinders.map((value) => value.id),
      ...data.consumables.map((value) => value.id),
      ...data.events.map((value) => value.id),
      ...data.consumableEvents.map((value) => value.id),
      ...data.reminders.map((value) => value.id),
    ];
    if (supplierIds.length != data.suppliers.length ||
        cylinderIds.length != data.cylinders.length ||
        consumableIds.length != data.consumables.length ||
        consumableCodes.length != data.consumables.length ||
        cylinderCodes.toSet().length != cylinderCodes.length ||
        allCodes.toSet().length != allCodes.length ||
        recordIds.toSet().length != recordIds.length ||
        recordIds.any((value) => value.trim().isEmpty) ||
        data.consumables.any(
          (value) =>
              value.primaryCode.trim().isEmpty ||
              !value.initialQuantity.isFinite ||
              value.initialQuantity <= 0 ||
              value.quantityUnit.trim().isEmpty,
        )) {
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
        ) ||
        data.consumables.any(
          (value) =>
              value.supplierId != null &&
              !supplierIds.contains(value.supplierId),
        ) ||
        data.consumableEvents.any(
          (value) =>
              !consumableIds.contains(value.consumableId) ||
              (value.quantity != null &&
                  (!value.quantity!.isFinite || value.quantity! <= 0)),
        ) ||
        !cylinderIds.containsAll(data.freeEditableSelection) ||
        !consumableIds.containsAll(data.freeEditableConsumableSelection)) {
      throw const WalletRuleException('The backup contains broken references.');
    }
    for (final consumable in data.consumables) {
      final outbound = data.consumableEvents
          .where(
            (value) =>
                value.consumableId == consumable.id &&
                (value.type == ConsumableEventType.issued ||
                    value.type == ConsumableEventType.used),
          )
          .fold<double>(0, (total, value) => total + (value.quantity ?? 0));
      if (outbound > consumable.initialQuantity) {
        throw const WalletRuleException(
          'The backup contains an invalid consumable balance.',
        );
      }
    }
  }
}

String _plainNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
        RegExp(r'\.$'),
        '',
      );

String? _clean(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}
