enum ConsumableType { wire, electrode, rod, flux, other }

enum ConsumableLifecycle { active, archived }

enum ConsumableEventType {
  received,
  issued,
  used,
  certificateAttached,
  certificateReplaced,
  archived,
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.firstWhere((value) => value.name == raw, orElse: () => fallback);

DateTime _date(Object? raw, {DateTime? fallback}) =>
    DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
    fallback ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class ConsumableBatch {
  const ConsumableBatch({
    required this.id,
    required this.primaryCode,
    required this.type,
    required this.productName,
    required this.batchLot,
    required this.receiptDate,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    this.classification,
    this.manufacturer,
    this.supplierId,
    this.location,
    this.certificateLocalPath,
    this.certificateOriginalName,
    this.certificateNumber,
    this.certificateDate,
  });

  final String id;
  final String primaryCode;
  final ConsumableType type;
  final String productName;
  final String batchLot;
  final DateTime receiptDate;
  final ConsumableLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? classification;
  final String? manufacturer;
  final String? supplierId;
  final String? location;
  final String? certificateLocalPath;
  final String? certificateOriginalName;
  final String? certificateNumber;
  final DateTime? certificateDate;

  bool get isActive => lifecycle == ConsumableLifecycle.active;
  bool get hasCertificate =>
      certificateLocalPath != null && certificateLocalPath!.trim().isNotEmpty;

  ConsumableBatch copyWith({
    ConsumableLifecycle? lifecycle,
    DateTime? updatedAt,
    String? certificateLocalPath,
    String? certificateOriginalName,
    String? certificateNumber,
    DateTime? certificateDate,
    bool clearCertificate = false,
  }) => ConsumableBatch(
    id: id,
    primaryCode: primaryCode,
    type: type,
    productName: productName,
    batchLot: batchLot,
    receiptDate: receiptDate,
    lifecycle: lifecycle ?? this.lifecycle,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    classification: classification,
    manufacturer: manufacturer,
    supplierId: supplierId,
    location: location,
    certificateLocalPath: clearCertificate
        ? null
        : certificateLocalPath ?? this.certificateLocalPath,
    certificateOriginalName: clearCertificate
        ? null
        : certificateOriginalName ?? this.certificateOriginalName,
    certificateNumber: clearCertificate
        ? null
        : certificateNumber ?? this.certificateNumber,
    certificateDate: clearCertificate
        ? null
        : certificateDate ?? this.certificateDate,
  );

  Map<String, Object?> toJson({bool includeLocalDocuments = true}) =>
      <String, Object?>{
        'id': id,
        'primaryCode': primaryCode,
        'type': type.name,
        'productName': productName,
        'batchLot': batchLot,
        'receiptDate': receiptDate.toIso8601String(),
        'lifecycle': lifecycle.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'classification': classification,
        'manufacturer': manufacturer,
        'supplierId': supplierId,
        'location': location,
        'certificateLocalPath': includeLocalDocuments
            ? certificateLocalPath
            : null,
        'certificateOriginalName': certificateOriginalName,
        'certificateNumber': certificateNumber,
        'certificateDate': certificateDate?.toIso8601String(),
      };

  factory ConsumableBatch.fromJson(Map<String, Object?> json) =>
      ConsumableBatch(
        id: json['id']?.toString() ?? '',
        primaryCode: json['primaryCode']?.toString() ?? '',
        type: _enumValue(
          ConsumableType.values,
          json['type'],
          ConsumableType.other,
        ),
        productName: json['productName']?.toString() ?? '',
        batchLot: json['batchLot']?.toString() ?? '',
        receiptDate: _date(json['receiptDate']),
        lifecycle: _enumValue(
          ConsumableLifecycle.values,
          json['lifecycle'],
          ConsumableLifecycle.active,
        ),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        classification: json['classification']?.toString(),
        manufacturer: json['manufacturer']?.toString(),
        supplierId: json['supplierId']?.toString(),
        location: json['location']?.toString(),
        certificateLocalPath: json['certificateLocalPath']?.toString(),
        certificateOriginalName: json['certificateOriginalName']?.toString(),
        certificateNumber: json['certificateNumber']?.toString(),
        certificateDate: json['certificateDate'] == null
            ? null
            : _date(json['certificateDate']),
      );
}

class ConsumableEvent {
  const ConsumableEvent({
    required this.id,
    required this.consumableId,
    required this.type,
    required this.occurredAt,
    this.quantity,
    this.reference,
    this.note,
  });

  final String id;
  final String consumableId;
  final ConsumableEventType type;
  final DateTime occurredAt;
  final double? quantity;
  final String? reference;
  final String? note;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'consumableId': consumableId,
    'type': type.name,
    'occurredAt': occurredAt.toIso8601String(),
    'quantity': quantity,
    'reference': reference,
    'note': note,
  };

  factory ConsumableEvent.fromJson(Map<String, Object?> json) =>
      ConsumableEvent(
        id: json['id']?.toString() ?? '',
        consumableId: json['consumableId']?.toString() ?? '',
        type: _enumValue(
          ConsumableEventType.values,
          json['type'],
          ConsumableEventType.received,
        ),
        occurredAt: _date(json['occurredAt']),
        quantity: (json['quantity'] as num?)?.toDouble(),
        reference: json['reference']?.toString(),
        note: json['note']?.toString(),
      );
}

class AddConsumableDraft {
  const AddConsumableDraft({
    required this.type,
    required this.productName,
    required this.batchLot,
    this.primaryCode,
    this.classification,
    this.manufacturer,
    this.supplierId,
    this.location,
    this.receiptDate,
  });

  final ConsumableType type;
  final String productName;
  final String batchLot;
  final String? primaryCode;
  final String? classification;
  final String? manufacturer;
  final String? supplierId;
  final String? location;
  final DateTime? receiptDate;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'productName': productName,
    'batchLot': batchLot,
    'primaryCode': primaryCode,
    'classification': classification,
    'manufacturer': manufacturer,
    'supplierId': supplierId,
    'location': location,
    'receiptDate': receiptDate?.toIso8601String(),
  };

  factory AddConsumableDraft.fromJson(Map<String, Object?> json) =>
      AddConsumableDraft(
        type: _enumValue(
          ConsumableType.values,
          json['type'],
          ConsumableType.other,
        ),
        productName: json['productName']?.toString() ?? '',
        batchLot: json['batchLot']?.toString() ?? '',
        primaryCode: json['primaryCode']?.toString(),
        classification: json['classification']?.toString(),
        manufacturer: json['manufacturer']?.toString(),
        supplierId: json['supplierId']?.toString(),
        location: json['location']?.toString(),
        receiptDate: json['receiptDate'] == null
            ? null
            : _date(json['receiptDate']),
      );
}

class PendingConsumableDraft {
  const PendingConsumableDraft({
    required this.draft,
    this.draftResumed = false,
  });

  final AddConsumableDraft draft;
  final bool draftResumed;

  Map<String, Object?> toJson() => <String, Object?>{
    'draft': draft.toJson(),
    'draftResumed': draftResumed,
  };

  factory PendingConsumableDraft.fromJson(Map<String, Object?> json) =>
      PendingConsumableDraft(
        draft: AddConsumableDraft.fromJson(
          Map<String, Object?>.from(json['draft']! as Map),
        ),
        draftResumed: json['draftResumed'] == true,
      );
}
