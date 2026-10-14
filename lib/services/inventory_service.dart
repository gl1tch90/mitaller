import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_item.dart';
import 'lang_service.dart';

/// Inventario del taller: solo insumos que rotan (aceites, filtros,
/// bujías, líquidos). Todo en el dispositivo.
class InventoryService {
  static const _key = 'inventory_items';
  static const _marginKey = 'inventory_margin_pct';

  /// Margen de ganancia predeterminado (porcentaje). Se usa para sugerir
  /// el precio de venta al registrar un producto.
  static const double defaultMarginPct = 30;

  Future<List<InventoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) =>
            InventoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _save(
      SharedPreferences prefs, List<InventoryItem> items) async {
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> add(InventoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.add(item);
    await _save(prefs, items);
  }

  Future<void> update(InventoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final i = items.indexWhere((e) => e.id == item.id);
    if (i == -1) return;
    items[i] = item;
    await _save(prefs, items);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.removeWhere((e) => e.id == id);
    await _save(prefs, items);
  }

  /// Busca un producto por su código de barras.
  Future<InventoryItem?> findByBarcode(String barcode) async {
    final items = await load();
    final code = barcode.trim();
    if (code.isEmpty) return null;
    for (final item in items) {
      if (item.barcode != null && item.barcode!.trim() == code) {
        return item;
      }
    }
    return null;
  }

  /// Descuenta [qty] de las existencias. No deja bajar de cero.
  /// Retorna false si no hay suficiente.
  Future<bool> deduct(String id, double qty) async {
    if (qty <= 0) return true;
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return false;
    final item = items[i];
    if (item.quantity < qty) return false;
    items[i] = item.copyWith(quantity: item.quantity - qty);
    await _save(prefs, items);
    return true;
  }

  /// Suma [qty] a las existencias (resurtir). Si [newCost] viene,
  /// actualiza el costo al último precio de compra.
  Future<void> restock(String id, double qty, {double? newCost}) async {
    if (qty <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final item = items[i];
    // Si se capturó un costo nuevo (distinto al actual), el precio de venta
    // se recalcula con el margen; si no cambió, se respeta el que tenía.
    double salePrice = item.salePrice;
    if (newCost != null && newCost > 0 && newCost != item.cost) {
      final margin = prefs.getDouble(_marginKey) ?? defaultMarginPct;
      salePrice = suggestSalePrice(newCost, margin);
    }
    items[i] = item.copyWith(
      quantity: item.quantity + qty,
      cost: newCost ?? item.cost,
      salePrice: salePrice,
    );
    await _save(prefs, items);
  }

  /// Productos que llegaron al mínimo.
  Future<List<InventoryItem>> lowStock() async {
    final items = await load();
    return items.where((e) => e.isLow).toList();
  }

  /// Catálogo inicial de insumos comunes del taller.
  /// Solo agrega los que no existan ya (por nombre). Cantidades en cero:
  /// el taller pone sus existencias y precios al editar cada uno.
  /// Los nombres salen en el idioma actual de la app.
  static List<String> get seedNames =>
      LangService.isEnglish ? _seedNamesEn : _seedNamesEs;

  static const List<String> _seedNamesEs = [
    // Aceites y líquidos
    'Aceite 5W-30 (garrafa)',
    'Aceite 10W-30 (garrafa)',
    'Aceite 20W-50 (garrafa)',
    'Aceite 10W-40 moto',
    'Líquido de frenos DOT 3',
    'Líquido de frenos DOT 4',
    'Anticongelante',
    'Aceite de transmisión',
    'Aceite de dirección hidráulica',
    // Filtros
    'Filtro de aceite',
    'Filtro de aire',
    'Filtro de gasolina',
    'Filtro de cabina',
    // Encendido
    'Bujías',
    'Cables de bujías',
    // Frenos
    'Balatas',
    // Químicos
    'Limpiador de frenos',
    'Desengrasante',
    'Aflojatodo (WD-40)',
    'Grasa',
    // Eléctrico y varios
    'Focos',
    'Fusibles',
    'Abrazaderas',
    'Cinta aislante',
    'Tornillería surtida',
    // Motos
    'Chicotes',
    'Cámaras',
  ];

  static const List<String> _seedNamesEn = [
    // Oils and fluids
    '5W-30 oil (jug)',
    '10W-30 oil (jug)',
    '20W-50 oil (jug)',
    '10W-40 motorcycle oil',
    'DOT 3 brake fluid',
    'DOT 4 brake fluid',
    'Antifreeze/coolant',
    'Transmission oil',
    'Power steering fluid',
    // Filters
    'Oil filter',
    'Air filter',
    'Fuel filter',
    'Cabin filter',
    // Ignition
    'Spark plugs',
    'Spark plug wires',
    // Brakes
    'Brake pads',
    // Chemicals
    'Brake cleaner',
    'Degreaser',
    'Penetrating oil (WD-40)',
    'Grease',
    // Electrical and misc
    'Bulbs',
    'Fuses',
    'Hose clamps',
    'Electrical tape',
    'Assorted hardware',
    // Motorcycles
    'Cables',
    'Inner tubes',
  ];

  /// Carga el catálogo inicial. Retorna cuántos se agregaron.
  Future<int> seedCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final existing =
        items.map((e) => e.name.toLowerCase()).toSet();
    var added = 0;
    final now = DateTime.now();
    for (final name in seedNames) {
      if (existing.contains(name.toLowerCase())) continue;
      items.add(InventoryItem(
        id: 'seed-${now.millisecondsSinceEpoch}-$added',
        name: name,
        quantity: 0,
        minStock: 0,
        createdAt: now,
      ));
      added++;
    }
    if (added > 0) await _save(prefs, items);
    return added;
  }

  /// Agrega solo los insumos elegidos de la lista común.
  Future<int> seedSelected(Set<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final existing =
        items.map((e) => e.name.toLowerCase()).toSet();
    var added = 0;
    final now = DateTime.now();
    for (final name in names) {
      if (existing.contains(name.toLowerCase())) continue;
      items.add(InventoryItem(
        id: 'seed-${now.millisecondsSinceEpoch}-$added',
        name: name,
        quantity: 0,
        minStock: 0,
        createdAt: now,
      ));
      added++;
    }
    if (added > 0) await _save(prefs, items);
    return added;
  }

  /// Margen configurado por el taller (porcentaje).
  Future<double> marginPct() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_marginKey) ?? defaultMarginPct;
  }

  Future<void> setMarginPct(double pct) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_marginKey, pct.clamp(0, 1000));
  }
}
