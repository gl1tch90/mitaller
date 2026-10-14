import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vehicle_type.dart';

/// Catálogo local de marcas y modelos por tipo de vehículo.
///
/// Se precarga con lo más común en México y el usuario puede agregar
/// marcas y modelos nuevos desde la pantalla de datos del vehículo.
/// Funciona sin internet: es la "base de datos" propia del taller.
class VehicleCatalogService {
  static const _key = 'vehicle_catalog_v1';

  /// Semilla inicial: lo más común en talleres de México.
  static const Map<String, Map<String, List<String>>> _seed = {
    'carro': {
      'Nissan': ['Tsuru', 'Versa', 'Sentra', 'March', 'NP300'],
      'Volkswagen': ['Jetta', 'Vento', 'Gol', 'Saveiro', 'Polo'],
      'Chevrolet': ['Aveo', 'Chevy', 'Spark', 'Tornado', 'Onix'],
      'Toyota': ['Yaris', 'Corolla', 'Hilux', 'Avanza'],
      'Honda': ['Civic', 'City', 'CR-V'],
      'Ford': ['Fiesta', 'Ranger', 'F-150', 'Escape'],
      'KIA': ['Rio', 'Forte', 'Seltos'],
      'Hyundai': ['Grand i10', 'Accent', 'Creta'],
    },
    'moto': {
      'Italika': ['FT150', 'FT125', 'DT150', '250Z', 'DM200'],
      'Honda': ['Cargo 150', 'CB190R', 'XR150L', 'Dio'],
      'Yamaha': ['FZ16', 'YBR125', 'XTZ150'],
      'Bajaj': ['Pulsar NS200', 'Pulsar 150', 'Boxer 150'],
      'Vento': ['Crossmax 250', 'Storm 250'],
      'Dinamo': ['U5 150', 'Chopper 250'],
    },
  };

  Map<String, Map<String, List<String>>> _catalog = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _catalog = {
        for (final t in _seed.entries)
          t.key: {
            for (final b in t.value.entries) b.key: List.of(b.value),
          },
      };
      await _save();
    } else {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _catalog = {
        for (final t in decoded.entries)
          t.key: {
            for (final b in (t.value as Map<String, dynamic>).entries)
              b.key:
                  (b.value as List).map((m) => m.toString()).toList(),
          },
      };
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_catalog));
  }

  /// Marcas disponibles para el tipo de vehículo, en orden alfabético.
  List<String> brands(VehicleType type) {
    final brands = _catalog[type.name]?.keys.toList() ?? [];
    brands.sort();
    return brands;
  }

  /// Modelos de una marca, en orden alfabético.
  List<String> models(VehicleType type, String brand) {
    final models =
        _catalog[type.name]?[brand]?.toList() ?? <String>[];
    models.sort();
    return models;
  }

  /// Agrega una marca nueva (con lista de modelos vacía).
  Future<void> addBrand(VehicleType type, String brand) async {
    final name = brand.trim();
    if (name.isEmpty) return;
    _catalog.putIfAbsent(type.name, () => {});
    _catalog[type.name]!.putIfAbsent(name, () => []);
    await _save();
  }

  /// Agrega un modelo nuevo a una marca existente.
  Future<void> addModel(
      VehicleType type, String brand, String model) async {
    final name = model.trim();
    if (name.isEmpty) return;
    _catalog.putIfAbsent(type.name, () => {});
    final models =
        _catalog[type.name]!.putIfAbsent(brand.trim(), () => []);
    if (!models.contains(name)) {
      models.add(name);
      await _save();
    }
  }
}
