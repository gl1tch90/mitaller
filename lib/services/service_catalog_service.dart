import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/service_item.dart';
import '../models/vehicle_type.dart';
import 'lang_service.dart';

/// Catálogo de servicios con precios, guardado en el dispositivo.
/// La primera vez se siembra con servicios comunes del taller.
class ServiceCatalogService {
  static const _key = 'service_catalog';
  static const _seededKey = 'service_catalog_seeded';

  Future<List<ServiceItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_seededKey) ?? false)) {
      final seed = _seed();
      await _saveAll(prefs, seed);
      await prefs.setBool(_seededKey, true);
      return seed;
    }
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            ServiceItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> add(ServiceItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.add(item);
    await _saveAll(prefs, items);
  }

  /// Actualiza nombre y/o precio de un servicio existente (por id).
  Future<void> update(ServiceItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final i = items.indexWhere((e) => e.id == item.id);
    if (i == -1) return;
    items[i] = item;
    await _saveAll(prefs, items);
  }

  /// Elimina un servicio del catálogo (por id).
  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.removeWhere((e) => e.id == id);
    await _saveAll(prefs, items);
  }

  Future<void> _saveAll(
      SharedPreferences prefs, List<ServiceItem> items) async {
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// Siembra el catálogo en el idioma activo (solo instalaciones nuevas;
  /// las existentes conservan sus servicios).
  List<ServiceItem> _seed() {
    final en = LangService.isEnglish;
    String n(String es, String enName) => en ? enName : es;
    return [
      ServiceItem(
          id: 'seed-01',
          name: n('Cambio de aceite (auto)', 'Oil change (car)'),
          price: 450,
          types: {VehicleType.carro}),
      ServiceItem(
          id: 'seed-02',
          name: n('Afinación mayor (auto)', 'Full tune-up (car)'),
          price: 1800,
          types: {VehicleType.carro}),
      ServiceItem(
          id: 'seed-03',
          name: n('Cambio de balatas (auto)', 'Brake pad replacement (car)'),
          price: 650,
          types: {VehicleType.carro}),
      ServiceItem(
          id: 'seed-04',
          name: n('Alineación y balanceo', 'Alignment and balancing'),
          price: 500,
          types: {VehicleType.carro}),
      ServiceItem(
          id: 'seed-05',
          name: n('Cambio de clutch (auto)', 'Clutch replacement (car)'),
          price: 2500,
          types: {VehicleType.carro}),
      ServiceItem(
          id: 'seed-06',
          name: n('Cambio de aceite (moto)', 'Oil change (motorcycle)'),
          price: 250,
          types: {VehicleType.moto}),
      ServiceItem(
          id: 'seed-07',
          name: n('Afinación (moto)', 'Tune-up (motorcycle)'),
          price: 600,
          types: {VehicleType.moto}),
      ServiceItem(
          id: 'seed-08',
          name: n('Cambio de balatas (moto)', 'Brake pad replacement (motorcycle)'),
          price: 300,
          types: {VehicleType.moto}),
      ServiceItem(
          id: 'seed-09',
          name: n('Ajuste de cadena', 'Chain adjustment'),
          price: 150,
          types: {VehicleType.moto}),
      ServiceItem(
          id: 'seed-10',
          name: n('Kit de arrastre (mano de obra)', 'Sprocket kit (labor)'),
          price: 400,
          types: {VehicleType.moto}),
      ServiceItem(
          id: 'seed-11',
          name: n('Diagnóstico con escáner', 'Scanner diagnostics'),
          price: 300,
          types: {VehicleType.carro, VehicleType.moto}),
      ServiceItem(
          id: 'seed-12',
          name: n('Cambio de llanta', 'Tire change'),
          price: 150,
          types: {VehicleType.carro, VehicleType.moto}),
      ServiceItem(
          id: 'seed-13',
          name: n('Revisión general', 'General inspection'),
          price: 200,
          types: {VehicleType.carro, VehicleType.moto}),
      ServiceItem(
          id: 'seed-14',
          name: n('Cambio de batería (mano de obra)', 'Battery replacement (labor)'),
          price: 200,
          types: {VehicleType.carro, VehicleType.moto}),
    ];
  }
}
