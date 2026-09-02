import 'dart:collection';

const int walletSchemaVersion = 5;
const int freeEditableCylinderLimit = 3;
const int maximumBackupBytes = 5 * 1024 * 1024;

const List<String> supportedLocales = <String>[
  'en',
  'es',
  'pt',
  'fr',
  'de',
  'it',
  'nl',
  'pl',
  'cs',
  'ro',
  'hu',
  'sv',
  'nb',
  'da',
  'fi',
  'tr',
  'ar',
  'hi',
  'bn',
  'id',
  'vi',
  'th',
  'ja',
  'ko',
  'zh-Hans',
  'zh-Hant',
  'uk',
  'el',
  'ms',
  'fil',
];

enum AccessTier { free, pro }

enum EntitlementSource { none, googlePlaySubscription, appStorePurchase }

enum RelationshipType { owned, rented, leased, deposit, notSure }

enum CylinderLifecycle { active, returned, exchanged, archived }

enum CylinderEventType {
  created,
  acquisitionUpdated,
  cylinderUpdated,
  refill,
  exchange,
  purchase,
  rentalPayment,
  leasePayment,
  depositPaid,
  depositReturned,
  cost,
  supplierChanged,
  relationshipChanged,
  note,
  photoAdded,
  reminderCreated,
  reminderUpdated,
  reminderCompleted,
  reminderDeleted,
  returned,
  archived,
}

enum ReminderKind { refill, rental, lease, deposit, check, custom }

enum ReminderDelivery {
  idle,
  needsScheduling,
  permissionRequired,
  scheduled,
  needsCancellation,
}

enum PaywallReason { addFourthCylinder, editLockedCylinderAfterDowngrade }

String canonicalLocale(String? candidate) {
  final normalized = candidate?.trim().replaceAll('_', '-') ?? '';
  if (normalized.isEmpty) return 'en';
  for (final locale in supportedLocales) {
    if (locale.toLowerCase() == normalized.toLowerCase()) return locale;
  }
  final bits = normalized.split('-');
  final language = bits.first.toLowerCase();
  if (language == 'zh') {
    final remainder = bits.skip(1).map((value) => value.toLowerCase()).toSet();
    return remainder.intersection(<String>{'hant', 'tw', 'hk', 'mo'}).isNotEmpty
        ? 'zh-Hant'
        : 'zh-Hans';
  }
  return supportedLocales.firstWhere(
    (locale) => locale.split('-').first == language,
    orElse: () => 'en',
  );
}

bool isRtlLocale(String locale) => canonicalLocale(locale) == 'ar';

const Set<String> iso4217Codes = <String>{
  'AED',
  'AFN',
  'ALL',
  'AMD',
  'ANG',
  'AOA',
  'ARS',
  'AUD',
  'AWG',
  'AZN',
  'BAM',
  'BBD',
  'BDT',
  'BGN',
  'BHD',
  'BIF',
  'BMD',
  'BND',
  'BOB',
  'BRL',
  'BSD',
  'BTN',
  'BWP',
  'BYN',
  'BZD',
  'CAD',
  'CDF',
  'CHF',
  'CLP',
  'CNY',
  'COP',
  'CRC',
  'CUP',
  'CVE',
  'CZK',
  'DJF',
  'DKK',
  'DOP',
  'DZD',
  'EGP',
  'ERN',
  'ETB',
  'EUR',
  'FJD',
  'FKP',
  'GBP',
  'GEL',
  'GHS',
  'GIP',
  'GMD',
  'GNF',
  'GTQ',
  'GYD',
  'HKD',
  'HNL',
  'HTG',
  'HUF',
  'IDR',
  'ILS',
  'INR',
  'IQD',
  'IRR',
  'ISK',
  'JMD',
  'JOD',
  'JPY',
  'KES',
  'KGS',
  'KHR',
  'KMF',
  'KRW',
  'KWD',
  'KYD',
  'KZT',
  'LAK',
  'LBP',
  'LKR',
  'LRD',
  'LSL',
  'LYD',
  'MAD',
  'MDL',
  'MGA',
  'MKD',
  'MMK',
  'MNT',
  'MOP',
  'MRU',
  'MUR',
  'MVR',
  'MWK',
  'MXN',
  'MYR',
  'MZN',
  'NAD',
  'NGN',
  'NIO',
  'NOK',
  'NPR',
  'NZD',
  'OMR',
  'PAB',
  'PEN',
  'PGK',
  'PHP',
  'PKR',
  'PLN',
  'PYG',
  'QAR',
  'RON',
  'RSD',
  'RUB',
  'RWF',
  'SAR',
  'SBD',
  'SCR',
  'SDG',
  'SEK',
  'SGD',
  'SHP',
  'SLE',
  'SOS',
  'SRD',
  'SSP',
  'STN',
  'SVC',
  'SYP',
  'SZL',
  'THB',
  'TJS',
  'TMT',
  'TND',
  'TOP',
  'TRY',
  'TTD',
  'TWD',
  'TZS',
  'UAH',
  'UGX',
  'USD',
  'UYU',
  'UZS',
  'VED',
  'VES',
  'VND',
  'VUV',
  'WST',
  'XAF',
  'XCD',
  'XOF',
  'XPF',
  'YER',
  'ZAR',
  'ZMW',
  'ZWG',
};

String defaultCurrencyForLocale(String locale) =>
    switch (canonicalLocale(locale)) {
      'es' || 'fr' || 'de' || 'it' || 'nl' || 'fi' || 'el' => 'EUR',
      'pt' => 'BRL',
      'pl' => 'PLN',
      'cs' => 'CZK',
      'ro' => 'RON',
      'hu' => 'HUF',
      'sv' => 'SEK',
      'nb' => 'NOK',
      'da' => 'DKK',
      'tr' => 'TRY',
      'ar' => 'AED',
      'hi' => 'INR',
      'bn' => 'BDT',
      'id' => 'IDR',
      'vi' => 'VND',
      'th' => 'THB',
      'ja' => 'JPY',
      'ko' => 'KRW',
      'zh-Hans' => 'CNY',
      'zh-Hant' => 'TWD',
      'uk' => 'UAH',
      'ms' => 'MYR',
      'fil' => 'PHP',
      _ => 'USD',
    };

String normalizedCurrency(String? value, {String fallback = 'USD'}) {
  final normalized = value?.trim().toUpperCase() ?? '';
  if (iso4217Codes.contains(normalized)) return normalized;
  final safeFallback = fallback.trim().toUpperCase();
  return iso4217Codes.contains(safeFallback) ? safeFallback : 'USD';
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.firstWhere((value) => value.name == raw, orElse: () => fallback);

DateTime _date(Object? raw, {DateTime? fallback}) =>
    DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
    fallback ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class Money {
  Money({required this.minorUnits, required String currencyCode})
    : currencyCode = normalizedCurrency(currencyCode);

  final int minorUnits;
  final String currencyCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'minorUnits': minorUnits,
    'currencyCode': currencyCode,
  };

  factory Money.fromJson(Map<String, Object?> json) => Money(
    minorUnits: (json['minorUnits'] as num?)?.toInt() ?? 0,
    currencyCode: json['currencyCode']?.toString() ?? 'USD',
  );

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'notes': notes,
  };

  factory Supplier.fromJson(Map<String, Object?> json) => Supplier(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    notes: json['notes']?.toString(),
  );
}

class AppSettings {
  const AppSettings({
    required this.locale,
    required this.currencyCode,
    required this.defaultMassUnit,
    required this.defaultVolumeUnit,
    required this.remindersEnabled,
    required this.onboardingComplete,
  });

  final String locale;
  final String currencyCode;
  final String defaultMassUnit;
  final String defaultVolumeUnit;
  final bool remindersEnabled;
  final bool onboardingComplete;

  factory AppSettings.create({
    String locale = 'en',
    String? currencyCode,
    String defaultMassUnit = 'kg',
    String defaultVolumeUnit = 'L',
    bool remindersEnabled = false,
    bool onboardingComplete = false,
  }) {
    final safeLocale = canonicalLocale(locale);
    return AppSettings(
      locale: safeLocale,
      currencyCode: normalizedCurrency(
        currencyCode,
        fallback: defaultCurrencyForLocale(safeLocale),
      ),
      defaultMassUnit: <String>{'kg', 'lb'}.contains(defaultMassUnit)
          ? defaultMassUnit
          : 'kg',
      defaultVolumeUnit: <String>{'L', 'm3', 'ft3'}.contains(defaultVolumeUnit)
          ? defaultVolumeUnit
          : 'L',
      remindersEnabled: remindersEnabled,
      onboardingComplete: onboardingComplete,
    );
  }

  AppSettings copyWith({
    String? locale,
    String? currencyCode,
    String? defaultMassUnit,
    String? defaultVolumeUnit,
    bool? remindersEnabled,
    bool? onboardingComplete,
  }) => AppSettings.create(
    locale: locale ?? this.locale,
    currencyCode: currencyCode ?? this.currencyCode,
    defaultMassUnit: defaultMassUnit ?? this.defaultMassUnit,
    defaultVolumeUnit: defaultVolumeUnit ?? this.defaultVolumeUnit,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'locale': locale,
    'currencyCode': currencyCode,
    'defaultMassUnit': defaultMassUnit,
    'defaultVolumeUnit': defaultVolumeUnit,
    'remindersEnabled': remindersEnabled,
    'onboardingComplete': onboardingComplete,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings.create(
    locale: json['locale']?.toString() ?? 'en',
    currencyCode: json['currencyCode']?.toString(),
    defaultMassUnit: json['defaultMassUnit']?.toString() ?? 'kg',
    defaultVolumeUnit: json['defaultVolumeUnit']?.toString() ?? 'L',
    remindersEnabled: json['remindersEnabled'] == true,
    onboardingComplete: json['onboardingComplete'] == true,
  );
}

class Cylinder {
  const Cylinder({
    required this.id,
    required this.nickname,
    required this.gasType,
    required this.relationship,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    this.capacityValue,
    this.capacityUnit,
    this.serialNumber,
    this.localPhotoUri,
    this.supplierId,
    this.acquisitionAmount,
    this.acquiredAt,
  });

  final String id;
  final String nickname;
  final String gasType;
  final RelationshipType relationship;
  final CylinderLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? capacityValue;
  final String? capacityUnit;
  final String? serialNumber;
  final String? localPhotoUri;
  final String? supplierId;
  final Money? acquisitionAmount;
  final DateTime? acquiredAt;

  bool get consumesCurrentSlot =>
      lifecycle == CylinderLifecycle.active ||
      lifecycle == CylinderLifecycle.exchanged;

  Cylinder copyWith({
    String? nickname,
    String? gasType,
    RelationshipType? relationship,
    CylinderLifecycle? lifecycle,
    DateTime? updatedAt,
    double? capacityValue,
    bool clearCapacity = false,
    String? capacityUnit,
    bool clearCapacityUnit = false,
    String? serialNumber,
    bool clearSerial = false,
    String? supplierId,
    bool clearSupplier = false,
    Money? acquisitionAmount,
    bool clearAcquisitionAmount = false,
    DateTime? acquiredAt,
    bool clearAcquiredAt = false,
  }) => Cylinder(
    id: id,
    nickname: nickname ?? this.nickname,
    gasType: gasType ?? this.gasType,
    relationship: relationship ?? this.relationship,
    lifecycle: lifecycle ?? this.lifecycle,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    capacityValue: clearCapacity ? null : capacityValue ?? this.capacityValue,
    capacityUnit: clearCapacityUnit ? null : capacityUnit ?? this.capacityUnit,
    serialNumber: clearSerial ? null : serialNumber ?? this.serialNumber,
    localPhotoUri: localPhotoUri,
    supplierId: clearSupplier ? null : supplierId ?? this.supplierId,
    acquisitionAmount: clearAcquisitionAmount
        ? null
        : acquisitionAmount ?? this.acquisitionAmount,
    acquiredAt: clearAcquiredAt ? null : acquiredAt ?? this.acquiredAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'nickname': nickname,
    'gasType': gasType,
    'relationship': relationship.name,
    'lifecycle': lifecycle.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'capacityValue': capacityValue,
    'capacityUnit': capacityUnit,
    'serialNumber': serialNumber,
    'localPhotoUri': localPhotoUri,
    'supplierId': supplierId,
    'acquisitionAmount': acquisitionAmount?.toJson(),
    'acquiredAt': acquiredAt?.toIso8601String(),
  };

  factory Cylinder.fromJson(Map<String, Object?> json) => Cylinder(
    id: json['id']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? '',
    gasType: json['gasType']?.toString() ?? '',
    relationship: _enumValue(
      RelationshipType.values,
      json['relationship'],
      RelationshipType.notSure,
    ),
    lifecycle: _enumValue(
      CylinderLifecycle.values,
      json['lifecycle'],
      CylinderLifecycle.active,
    ),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    capacityValue: (json['capacityValue'] as num?)?.toDouble(),
    capacityUnit: json['capacityUnit']?.toString(),
    serialNumber: json['serialNumber']?.toString(),
    localPhotoUri: json['localPhotoUri']?.toString(),
    supplierId: json['supplierId']?.toString(),
    acquisitionAmount: json['acquisitionAmount'] is Map
        ? Money.fromJson(
            Map<String, Object?>.from(json['acquisitionAmount']! as Map),
          )
        : null,
    acquiredAt: json['acquiredAt'] == null ? null : _date(json['acquiredAt']),
  );
}

class CylinderEvent {
  CylinderEvent({
    required this.id,
    required this.cylinderId,
    required this.type,
    required this.occurredAt,
    this.supplierId,
    this.amount,
    this.note,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : metadata = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.from(metadata),
       );

  final String id;
  final String cylinderId;
  final CylinderEventType type;
  final DateTime occurredAt;
  final String? supplierId;
  final Money? amount;
  final String? note;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'cylinderId': cylinderId,
    'type': type.name,
    'occurredAt': occurredAt.toIso8601String(),
    'supplierId': supplierId,
    'amount': amount?.toJson(),
    'note': note,
    'metadata': metadata,
  };

  factory CylinderEvent.fromJson(Map<String, Object?> json) => CylinderEvent(
    id: json['id']?.toString() ?? '',
    cylinderId: json['cylinderId']?.toString() ?? '',
    type: _enumValue(
      CylinderEventType.values,
      json['type'],
      CylinderEventType.note,
    ),
    occurredAt: _date(json['occurredAt']),
    supplierId: json['supplierId']?.toString(),
    amount: json['amount'] is Map
        ? Money.fromJson(Map<String, Object?>.from(json['amount']! as Map))
        : null,
    note: json['note']?.toString(),
    metadata: json['metadata'] is Map
        ? Map<String, Object?>.from(json['metadata']! as Map)
        : const <String, Object?>{},
  );
}

class Reminder {
  const Reminder({
    required this.id,
    required this.cylinderId,
    required this.kind,
    required this.title,
    required this.dueAt,
    required this.createdAt,
    required this.delivery,
    this.completed = false,
    required this.notificationId,
  });

  final String id;
  final String cylinderId;
  final ReminderKind kind;
  final String title;
  final DateTime dueAt;
  final DateTime createdAt;
  final ReminderDelivery delivery;
  final bool completed;
  final int notificationId;

  Reminder copyWith({
    ReminderKind? kind,
    String? title,
    DateTime? dueAt,
    ReminderDelivery? delivery,
    bool? completed,
  }) => Reminder(
    id: id,
    cylinderId: cylinderId,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    dueAt: dueAt ?? this.dueAt,
    createdAt: createdAt,
    delivery: delivery ?? this.delivery,
    completed: completed ?? this.completed,
    notificationId: notificationId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'cylinderId': cylinderId,
    'kind': kind.name,
    'title': title,
    'dueAt': dueAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'delivery': delivery.name,
    'completed': completed,
    'notificationId': notificationId,
  };

  factory Reminder.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    return Reminder(
      id: id,
      cylinderId: json['cylinderId']?.toString() ?? '',
      kind: _enumValue(ReminderKind.values, json['kind'], ReminderKind.custom),
      title: json['title']?.toString() ?? '',
      dueAt: _date(json['dueAt']),
      createdAt: _date(json['createdAt']),
      delivery: _enumValue(
        ReminderDelivery.values,
        json['delivery'],
        ReminderDelivery.idle,
      ),
      completed: json['completed'] == true,
      notificationId:
          (json['notificationId'] as num?)?.toInt() ?? stableNotificationId(id),
    );
  }
}

class AddCylinderDraft {
  const AddCylinderDraft({
    required this.nickname,
    required this.gasType,
    required this.relationship,
    this.capacityValue,
    this.capacityUnit,
    this.serialNumber,
    this.localPhotoUri,
    this.supplierId,
    this.acquisitionAmount,
    this.acquiredAt,
  });

  final String nickname;
  final String gasType;
  final RelationshipType relationship;
  final double? capacityValue;
  final String? capacityUnit;
  final String? serialNumber;
  final String? localPhotoUri;
  final String? supplierId;
  final Money? acquisitionAmount;
  final DateTime? acquiredAt;

  Map<String, Object?> toJson({bool includeLocalPhotos = true}) =>
      <String, Object?>{
        'nickname': nickname,
        'gasType': gasType,
        'relationship': relationship.name,
        'capacityValue': capacityValue,
        'capacityUnit': capacityUnit,
        'serialNumber': serialNumber,
        'localPhotoUri': includeLocalPhotos ? localPhotoUri : null,
        'supplierId': supplierId,
        'acquisitionAmount': acquisitionAmount?.toJson(),
        'acquiredAt': acquiredAt?.toIso8601String(),
      };

  factory AddCylinderDraft.fromJson(Map<String, Object?> json) =>
      AddCylinderDraft(
        nickname: json['nickname']?.toString() ?? '',
        gasType: json['gasType']?.toString() ?? '',
        relationship: _enumValue(
          RelationshipType.values,
          json['relationship'],
          RelationshipType.notSure,
        ),
        capacityValue: (json['capacityValue'] as num?)?.toDouble(),
        capacityUnit: json['capacityUnit']?.toString(),
        serialNumber: json['serialNumber']?.toString(),
        localPhotoUri: json['localPhotoUri']?.toString(),
        supplierId: json['supplierId']?.toString(),
        acquisitionAmount: json['acquisitionAmount'] is Map
            ? Money.fromJson(
                Map<String, Object?>.from(json['acquisitionAmount']! as Map),
              )
            : null,
        acquiredAt: json['acquiredAt'] == null
            ? null
            : _date(json['acquiredAt']),
      );
}

class PendingCylinderDraft {
  const PendingCylinderDraft({required this.draft, this.draftResumed = false});
  final AddCylinderDraft draft;
  final bool draftResumed;

  Map<String, Object?> toJson({bool includeLocalPhotos = true}) =>
      <String, Object?>{
        'draft': draft.toJson(includeLocalPhotos: includeLocalPhotos),
        'draftResumed': draftResumed,
      };

  factory PendingCylinderDraft.fromJson(Map<String, Object?> json) =>
      PendingCylinderDraft(
        draft: AddCylinderDraft.fromJson(
          Map<String, Object?>.from(json['draft']! as Map),
        ),
        draftResumed: json['draftResumed'] == true,
      );
}

class Entitlement {
  const Entitlement({
    required this.tier,
    required this.source,
    this.validUntil,
    this.willRenew = false,
  });

  final AccessTier tier;
  final EntitlementSource source;
  final DateTime? validUntil;
  final bool willRenew;

  static const Entitlement free = Entitlement(
    tier: AccessTier.free,
    source: EntitlementSource.none,
  );

  bool isProAt(DateTime now) =>
      tier == AccessTier.pro &&
      source != EntitlementSource.none &&
      validUntil != null &&
      !now.toUtc().isAfter(validUntil!.toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
    'tier': tier.name,
    'source': source.name,
    'validUntil': validUntil?.toIso8601String(),
    'willRenew': willRenew,
  };

  factory Entitlement.fromJson(Map<String, Object?> json) => Entitlement(
    tier: _enumValue(AccessTier.values, json['tier'], AccessTier.free),
    source: _enumValue(
      EntitlementSource.values,
      json['source'],
      EntitlementSource.none,
    ),
    validUntil: json['validUntil'] == null ? null : _date(json['validUntil']),
    willRenew: json['willRenew'] == true,
  );
}

class WalletData {
  WalletData({
    required this.schemaVersion,
    required this.revision,
    required this.settings,
    required List<Supplier> suppliers,
    required List<Cylinder> cylinders,
    required List<CylinderEvent> events,
    required List<Reminder> reminders,
    required this.pendingDraft,
    required List<String> freeEditableSelection,
    required this.entitlementCache,
  }) : suppliers = List<Supplier>.unmodifiable(suppliers),
       cylinders = List<Cylinder>.unmodifiable(cylinders),
       events = List<CylinderEvent>.unmodifiable(events),
       reminders = List<Reminder>.unmodifiable(reminders),
       freeEditableSelection = List<String>.unmodifiable(
         freeEditableSelection.toSet(),
       );

  final int schemaVersion;
  final int revision;
  final AppSettings settings;
  final List<Supplier> suppliers;
  final List<Cylinder> cylinders;
  final List<CylinderEvent> events;
  final List<Reminder> reminders;
  final PendingCylinderDraft? pendingDraft;
  final List<String> freeEditableSelection;
  final Entitlement entitlementCache;

  factory WalletData.empty({String locale = 'en', String? currencyCode}) =>
      WalletData(
        schemaVersion: walletSchemaVersion,
        revision: 0,
        settings: AppSettings.create(
          locale: locale,
          currencyCode: currencyCode,
        ),
        suppliers: const <Supplier>[],
        cylinders: const <Cylinder>[],
        events: const <CylinderEvent>[],
        reminders: const <Reminder>[],
        pendingDraft: null,
        freeEditableSelection: const <String>[],
        entitlementCache: Entitlement.free,
      );

  WalletData next({
    AppSettings? settings,
    List<Supplier>? suppliers,
    List<Cylinder>? cylinders,
    List<CylinderEvent>? events,
    List<Reminder>? reminders,
    PendingCylinderDraft? pendingDraft,
    bool clearPendingDraft = false,
    List<String>? freeEditableSelection,
    Entitlement? entitlementCache,
  }) => WalletData(
    schemaVersion: walletSchemaVersion,
    revision: revision + 1,
    settings: settings ?? this.settings,
    suppliers: suppliers ?? this.suppliers,
    cylinders: cylinders ?? this.cylinders,
    events: events ?? this.events,
    reminders: reminders ?? this.reminders,
    pendingDraft: clearPendingDraft ? null : pendingDraft ?? this.pendingDraft,
    freeEditableSelection: freeEditableSelection ?? this.freeEditableSelection,
    entitlementCache: entitlementCache ?? this.entitlementCache,
  );

  WalletData withSessionEntitlement(Entitlement entitlement) => WalletData(
    schemaVersion: schemaVersion,
    revision: revision,
    settings: settings,
    suppliers: suppliers,
    cylinders: cylinders,
    events: events,
    reminders: reminders,
    pendingDraft: pendingDraft,
    freeEditableSelection: freeEditableSelection,
    entitlementCache: entitlement,
  );

  Map<String, Object?> toJson({
    bool includeEntitlement = true,
    bool includeLocalPhotos = true,
  }) => <String, Object?>{
    'schemaVersion': walletSchemaVersion,
    'revision': revision,
    'settings': settings.toJson(),
    'suppliers': suppliers.map((value) => value.toJson()).toList(),
    'cylinders': cylinders.map((value) {
      final json = value.toJson();
      if (!includeLocalPhotos) json['localPhotoUri'] = null;
      return json;
    }).toList(),
    'events': events.map((value) => value.toJson()).toList(),
    'reminders': reminders.map((value) => value.toJson()).toList(),
    'pendingDraft': pendingDraft?.toJson(
      includeLocalPhotos: includeLocalPhotos,
    ),
    'freeEditableSelection': freeEditableSelection,
    if (includeEntitlement) 'entitlementCache': entitlementCache.toJson(),
  };

  factory WalletData.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> maps(Object? raw) => raw is List
        ? raw
              .whereType<Map>()
              .map((value) => Map<String, Object?>.from(value))
              .toList()
        : <Map<String, Object?>>[];
    return WalletData(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? walletSchemaVersion,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      settings: AppSettings.fromJson(
        Map<String, Object?>.from(json['settings']! as Map),
      ),
      suppliers: maps(json['suppliers']).map(Supplier.fromJson).toList(),
      cylinders: maps(json['cylinders']).map(Cylinder.fromJson).toList(),
      events: maps(json['events']).map(CylinderEvent.fromJson).toList(),
      reminders: maps(json['reminders']).map(Reminder.fromJson).toList(),
      pendingDraft: json['pendingDraft'] is Map
          ? PendingCylinderDraft.fromJson(
              Map<String, Object?>.from(json['pendingDraft']! as Map),
            )
          : null,
      freeEditableSelection:
          (json['freeEditableSelection'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const <String>[],
      entitlementCache: json['entitlementCache'] is Map
          ? Entitlement.fromJson(
              Map<String, Object?>.from(json['entitlementCache']! as Map),
            )
          : Entitlement.free,
    );
  }
}

int stableNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final byte in value.codeUnits) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
