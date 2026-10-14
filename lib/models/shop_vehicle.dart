import 'vehicle.dart';

/// Vehículo propio del taller (para mandados).
class ShopVehicle {
  final String id;
  final String name; // ej. "Tsuru blanco"
  final String kind; // 'carro' o 'moto'
  final String plates;
  final String? vin; // VIN de 17 caracteres
  final int? year;
  final String? model;
  final String? photoPath; // foto opcional del vehículo
  final int currentKm;
  final int? oilChangeKm; // km al último cambio de aceite
  final DateTime? oilChangeDate;
  final DateTime createdAt;
  /// Estado: 'activo' (en uso), 'taller' (en el taller / fuera de
  /// circulación) o 'vendido'.
  final String status;

  const ShopVehicle({
    required this.id,
    required this.name,
    required this.kind,
    required this.plates,
    this.vin,
    this.year,
    this.model,
    this.photoPath,
    required this.currentKm,
    this.oilChangeKm,
    this.oilChangeDate,
    required this.createdAt,
    this.status = 'activo',
  });

  ShopVehicle copyWith({
    String? name,
    String? kind,
    String? plates,
    String? vin,
    int? year,
    String? model,
    String? photoPath,
    int? currentKm,
    int? oilChangeKm,
    DateTime? oilChangeDate,
    String? status,
  }) =>
      ShopVehicle(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        plates: plates ?? this.plates,
        vin: vin ?? this.vin,
        year: year ?? this.year,
        model: model ?? this.model,
        photoPath: photoPath ?? this.photoPath,
        currentKm: currentKm ?? this.currentKm,
        oilChangeKm: oilChangeKm ?? this.oilChangeKm,
        oilChangeDate: oilChangeDate ?? this.oilChangeDate,
        createdAt: createdAt,
        status: status ?? this.status,
      );

  /// Km que faltan para el próximo cambio (cada [everyKm]).
  /// Negativo = ya le toca.
  int kmToNextOil(int everyKm) {
    final base = oilChangeKm ?? 0;
    return everyKm - (currentKm - base);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'plates': plates,
        'vin': vin,
        'year': year,
        'model': model,
        'photoPath': photoPath,
        'currentKm': currentKm,
        'oilChangeKm': oilChangeKm,
        'oilChangeDate': oilChangeDate?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'status': status,
      };

  factory ShopVehicle.fromJson(Map<String, dynamic> json) => ShopVehicle(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String? ?? 'carro',
        plates: json['plates'] as String? ?? '',
        vin: json['vin'] as String?,
        year: json['year'] as int?,
        model: json['model'] as String?,
        photoPath: json['photoPath'] as String?,
        currentKm: json['currentKm'] as int? ?? 0,
        oilChangeKm: json['oilChangeKm'] as int?,
        oilChangeDate: json['oilChangeDate'] == null
            ? null
            : DateTime.parse(json['oilChangeDate'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: json['status'] as String? ?? 'activo',
      );
}

/// Entrada de la bitácora diaria: la primera persona que agarra el
/// vehículo en el día llena el formulario una sola vez.
class VehicleLogEntry {
  final String id;
  final String vehicleId;
  final DateTime date; // día (sin hora)
  final String mechanicId;
  final String mechanicName;
  final int km;
  final ConditionLevel oil; // nivel de aceite
  final ConditionLevel coolant; // anticongelante
  final ConditionLevel tires; // estado de las llantas
  final bool lightsOk;
  final String notes;

  const VehicleLogEntry({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.mechanicId,
    required this.mechanicName,
    required this.km,
    required this.oil,
    required this.coolant,
    required this.tires,
    required this.lightsOk,
    this.notes = '',
  });

  /// Clave del día: "2026-10-06".
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'date': date.toIso8601String(),
        'mechanicId': mechanicId,
        'mechanicName': mechanicName,
        'km': km,
        'oil': oil.name,
        'coolant': coolant.name,
        'tires': tires.name,
        'lightsOk': lightsOk,
        'notes': notes,
      };

  factory VehicleLogEntry.fromJson(Map<String, dynamic> json) {
    ConditionLevel levelOf(dynamic raw, ConditionLevel fallback) {
      if (raw is String) {
        for (final v in ConditionLevel.values) {
          if (v.name == raw) return v;
        }
      }
      // Formato viejo (bool): true = bien, false = malo.
      if (raw is bool) {
        return raw ? ConditionLevel.bien : ConditionLevel.malo;
      }
      return fallback;
    }

    return VehicleLogEntry(
      id: json['id'] as String,
      vehicleId: json['vehicleId'] as String,
      date: DateTime.parse(json['date'] as String),
      mechanicId: json['mechanicId'] as String,
      mechanicName: json['mechanicName'] as String? ?? '',
      km: json['km'] as int? ?? 0,
      oil: levelOf(json['oil'], ConditionLevel.bien),
      coolant: levelOf(json['coolant'], ConditionLevel.bien),
      tires: levelOf(
          json['tires'] ?? json['tiresOk'], ConditionLevel.bien),
      lightsOk: json['lightsOk'] as bool? ?? true,
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// Daño o falla reportada en un vehículo del taller.
class VehicleIssue {
  final String id;
  final String vehicleId;
  final String reportedById;
  final String reportedByName;
  final DateTime date;
  final String description;
  final String? photoPath;
  final String notes;
  final bool resolved;
  final DateTime? resolvedAt;

  const VehicleIssue({
    required this.id,
    required this.vehicleId,
    required this.reportedById,
    required this.reportedByName,
    required this.date,
    required this.description,
    this.photoPath,
    this.notes = '',
    this.resolved = false,
    this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'reportedById': reportedById,
        'reportedByName': reportedByName,
        'date': date.toIso8601String(),
        'description': description,
        'photoPath': photoPath,
        'notes': notes,
        'resolved': resolved,
        'resolvedAt': resolvedAt?.toIso8601String(),
      };

  factory VehicleIssue.fromJson(Map<String, dynamic> json) => VehicleIssue(
        id: json['id'] as String,
        vehicleId: json['vehicleId'] as String,
        reportedById: json['reportedById'] as String,
        reportedByName: json['reportedByName'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        description: json['description'] as String,
        photoPath: json['photoPath'] as String?,
        notes: json['notes'] as String? ?? '',
        resolved: json['resolved'] as bool? ?? false,
        resolvedAt: json['resolvedAt'] == null
            ? null
            : DateTime.parse(json['resolvedAt'] as String),
      );
}

/// Documento del vehículo con vencimiento (seguro, placas, verificación).
class VehicleDocument {
  final String id;
  final String vehicleId;
  final String kind; // 'seguro', 'placas', 'verificacion', 'otro'
  final String label;
  final DateTime expiryDate;
  final String notes;

  /// Foto del documento (póliza, tarjeta de circulación...), opcional.
  final String? photoPath;

  const VehicleDocument({
    required this.id,
    required this.vehicleId,
    required this.kind,
    required this.label,
    required this.expiryDate,
    this.notes = '',
    this.photoPath,
  });

  /// Días que faltan para vencer (negativo = vencido).
  int daysToExpiry() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(
        expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'kind': kind,
        'label': label,
        'expiryDate': expiryDate.toIso8601String(),
        'notes': notes,
        'photoPath': photoPath,
      };

  factory VehicleDocument.fromJson(Map<String, dynamic> json) =>
      VehicleDocument(
        id: json['id'] as String,
        vehicleId: json['vehicleId'] as String,
        kind: json['kind'] as String? ?? 'otro',
        label: json['label'] as String? ?? '',
        expiryDate: DateTime.parse(json['expiryDate'] as String),
        notes: json['notes'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
      );
}

/// Gasto del vehículo (reparación, servicio u otro).
class VehicleExpense {
  final String id;
  final String vehicleId;
  final DateTime date;
  final String kind; // 'reparacion', 'servicio', 'gasolina', 'otro'
  final double amount;
  final String notes;
  final String? photoPath; // foto del ticket/recibo (opcional)
  /// Quién lo registró (id y nombre del mecánico).
  final String createdById;
  final String createdByName;
  /// Si lo registró un mecánico, queda pendiente hasta que el
  /// admin lo apruebe. Lo del admin entra aprobado directo.
  final bool approved;
  /// Si el admin lo rechazó: el mecánico recibe un aviso para
  /// volver a reportarlo con la corrección.
  final bool rejected;
  final String rejectReason;

  const VehicleExpense({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.kind,
    required this.amount,
    this.notes = '',
    this.photoPath,
    this.createdById = '',
    this.createdByName = '',
    this.approved = true,
    this.rejected = false,
    this.rejectReason = '',
  });

  VehicleExpense copyWith({bool? approved}) => VehicleExpense(
        id: id,
        vehicleId: vehicleId,
        date: date,
        kind: kind,
        amount: amount,
        notes: notes,
        photoPath: photoPath,
        createdById: createdById,
        createdByName: createdByName,
        approved: approved ?? this.approved,
        rejected: rejected,
        rejectReason: rejectReason,
      );

  VehicleExpense copyAsRejected(String reason) => VehicleExpense(
        id: id,
        vehicleId: vehicleId,
        date: date,
        kind: kind,
        amount: amount,
        notes: notes,
        photoPath: photoPath,
        createdById: createdById,
        createdByName: createdByName,
        approved: false,
        rejected: true,
        rejectReason: reason,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'date': date.toIso8601String(),
        'kind': kind,
        'amount': amount,
        'notes': notes,
        'photoPath': photoPath,
        'createdById': createdById,
        'createdByName': createdByName,
        'approved': approved,
        'rejected': rejected,
        'rejectReason': rejectReason,
      };

  factory VehicleExpense.fromJson(Map<String, dynamic> json) =>
      VehicleExpense(
        id: json['id'] as String,
        vehicleId: json['vehicleId'] as String,
        date: DateTime.parse(json['date'] as String),
        kind: json['kind'] as String? ?? 'otro',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
        createdById: json['createdById'] as String? ?? '',
        createdByName: json['createdByName'] as String? ?? '',
        // Los gastos viejos (sin el campo) cuentan como aprobados.
        approved: json['approved'] as bool? ?? true,
        rejected: json['rejected'] as bool? ?? false,
        rejectReason: json['rejectReason'] as String? ?? '',
      );
}
