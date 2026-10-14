import 'vehicle_type.dart';

/// Estado de un nivel (aceite o anticongelante):
/// Malo (rojo), Regular (naranja), Bien (verde).
enum ConditionLevel {
  malo,
  regular,
  bien;
}

extension ConditionLevelX on ConditionLevel {
  /// "Malo", "Regular", "Bien".
  String get label => name[0].toUpperCase() + name.substring(1);
}

/// Lee un [ConditionLevel] desde JSON sin lanzar si el valor es inválido.
ConditionLevel? _conditionFromJson(dynamic value) {
  if (value is! String) return null;
  try {
    return ConditionLevel.values.byName(value);
  } catch (_) {
    return null;
  }
}

/// Datos del vehículo (o moto) que entra a una venta del punto de venta.
class Vehicle {
  final String id;
  final VehicleType type;
  final int year;
  final String brand;
  final String model;
  final String plate;

  /// Número de identificación vehicular (17 caracteres). Opcional.
  final String? vin;

  /// Notas sobre la condición (rayones, golpes, etc.). Opcional.
  final String? conditionNotes;

  /// Condición del aceite (malo/regular/bien). Opcional (null = no registrada).
  final ConditionLevel? oilCondition;

  /// Nivel de gasolina 0-100 (%). Opcional (null = no registrado).
  final int? fuelLevel;

  /// Condición del anticongelante. Opcional (null = no registrada).
  final ConditionLevel? coolantCondition;

  const Vehicle({
    required this.id,
    required this.type,
    required this.year,
    required this.brand,
    required this.model,
    required this.plate,
    this.vin,
    this.conditionNotes,
    this.oilCondition,
    this.fuelLevel,
    this.coolantCondition,
  });

  /// "Nissan Versa 2020 · ABC-123"
  String get label => '$brand $model $year · $plate';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'year': year,
        'brand': brand,
        'model': model,
        'plate': plate,
        'vin': vin,
        'conditionNotes': conditionNotes,
        'oilCondition': oilCondition?.name,
        'fuelLevel': fuelLevel,
        'coolantCondition': coolantCondition?.name,
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        type: VehicleType.values.byName(json['type'] as String),
        year: json['year'] as int,
        brand: json['brand'] as String,
        model: json['model'] as String,
        plate: json['plate'] as String,
        vin: json['vin'] as String?,
        conditionNotes: json['conditionNotes'] as String?,
        oilCondition: _conditionFromJson(json['oilCondition']),
        fuelLevel: (json['fuelLevel'] as num?)?.toInt(),
        coolantCondition: _conditionFromJson(json['coolantCondition']),
      );
}
