import 'vehicle_type.dart';
import '../l10n/strings.dart';

/// Servicio del catálogo con su precio. Puede aplicar a carros, a motos
/// o a ambos.
class ServiceItem {
  final String id;
  final String name;
  final double price;
  final Set<VehicleType> types;

  const ServiceItem({
    required this.id,
    required this.name,
    required this.price,
    required this.types,
  });

  bool appliesTo(VehicleType t) => types.contains(t);

  /// Nombre para mostrar: los servicios semilla se traducen en vivo
  /// (los guardados quedaron en el idioma de la instalación).
  String get displayName => seedServiceName(id) ?? name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'types': types.map((t) => t.name).toList(),
      };

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        types: (json['types'] as List)
            .map((e) => VehicleType.values.byName(e as String))
            .toSet(),
      );
}
