import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/work_order.dart';
import 'inventory_service.dart';

/// Guarda y lee las órdenes de servicio (trabajo en el taller).
/// Folios: "OS-0001", "OS-0002", ...
class WorkOrderService {
  static const _key = 'work_orders';

  Future<List<WorkOrder>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map(
            (e) => WorkOrder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _persist(List<WorkOrder> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// Crea la orden y devuelve el folio asignado ("OS-0001", ...).
  Future<String> create(WorkOrder order) async {
    final items = await list();
    final folio = 'OS-${(items.length + 1).toString().padLeft(4, '0')}';
    items.add(WorkOrder(
      id: order.id,
      folio: folio,
      vehicleType: order.vehicleType,
      vehicle: order.vehicle,
      customer: order.customer,
      photos: order.photos,
      lines: order.lines,
      mechanicId: order.mechanicId,
      createdById: order.createdById,
      status: order.status,
      createdAt: order.createdAt,
      shopVehicleId: order.shopVehicleId,
    ));
    await _persist(items);
    return folio;
  }

  /// Actualiza una orden existente (cambio de estado o de precios).
  Future<void> update(WorkOrder order) async {
    final items = await list();
    final i = items.indexWhere((o) => o.id == order.id);
    if (i == -1) return;
    items[i] = order;
    await _persist(items);
  }

  /// Órdenes asignadas a un mecánico que aún no están completadas.
  Future<List<WorkOrder>> activeFor(String mechanicId) async {
    final items = await list();
    return items
        .where((o) =>
            o.mechanicId == mechanicId &&
            o.status != OrderStatus.completed)
        .toList();
  }

  /// Órdenes esperando revisión del administrador.
  Future<List<WorkOrder>> pendingReview() async {
    final items = await list();
    return items.where((o) => o.status == OrderStatus.inReview).toList();
  }

  /// Órdenes activas (no completadas), las más recientes primero.
  Future<List<WorkOrder>> active() async {
    final items = await list();
    final act =
        items.where((o) => o.status != OrderStatus.completed).toList();
    act.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return act;
  }

  /// Suma al acumulado los segundos de la racha actual y detiene el cronómetro.
  WorkOrder _accrue(WorkOrder o) {
    final start = o.timerStart;
    if (start == null) return o;
    final add = DateTime.now().difference(start).inSeconds;
    return o.copyWith(
      workSeconds: o.workSeconds + (add < 0 ? 0 : add),
      clearTimerStart: true,
    );
  }

  /// Pausa las órdenes que el mecánico tenga en curso (excepto [exceptId]).
  /// Solo se trabaja una orden a la vez: al empezar otra, la anterior se pausa sola.
  void _pauseOthers(
      List<WorkOrder> items, String mechanicId, String exceptId) {
    for (var i = 0; i < items.length; i++) {
      final o = items[i];
      if (o.id != exceptId &&
          o.mechanicId == mechanicId &&
          o.status == OrderStatus.inProgress) {
        items[i] = _accrue(o).copyWith(status: OrderStatus.paused);
      }
    }
  }

  /// Pausa las órdenes que el mecánico tenga en curso (congelando su
  /// cronómetro). Se usa al registrar la salida: el tiempo no sigue
  /// corriendo sin turno abierto.
  Future<void> pauseRunningFor(String mechanicId) async {
    final items = await list();
    var changed = false;
    for (var i = 0; i < items.length; i++) {
      final o = items[i];
      if (o.mechanicId == mechanicId &&
          o.status == OrderStatus.inProgress) {
        items[i] = _accrue(o).copyWith(status: OrderStatus.paused);
        changed = true;
      }
    }
    if (changed) await _persist(items);
  }

  Future<WorkOrder> _byId(List<WorkOrder> items, String id) async {
    final i = items.indexWhere((o) => o.id == id);
    if (i == -1) throw StateError('Orden no encontrada');
    return items[i];
  }

  /// Lee una orden por id. Null si no existe.
  Future<WorkOrder?> byId(String id) async {
    final items = await list();
    final i = items.indexWhere((o) => o.id == id);
    return i == -1 ? null : items[i];
  }

  /// El mecánico empieza el trabajo: la orden pasa a "En curso"
  /// y el cronómetro arranca automáticamente.
  Future<WorkOrder> startWork(String id) async {
    final items = await list();
    final o = await _byId(items, id);
    _pauseOthers(items, o.mechanicId, o.id);
    final updated =
        o.copyWith(status: OrderStatus.inProgress, timerStart: DateTime.now());
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return updated;
  }

  /// Pausa el trabajo sin finalizarlo: el cronómetro se detiene
  /// y el tiempo acumulado se guarda.
  Future<WorkOrder> pauseWork(String id) async {
    final items = await list();
    final o = await _byId(items, id);
    final updated = _accrue(o).copyWith(status: OrderStatus.paused);
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return updated;
  }

  /// Reanuda un trabajo pausado: vuelve a "En curso" y el cronómetro sigue.
  Future<WorkOrder> resumeWork(String id) async {
    final items = await list();
    final o = await _byId(items, id);
    _pauseOthers(items, o.mechanicId, o.id);
    final updated =
        o.copyWith(status: OrderStatus.inProgress, timerStart: DateTime.now());
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return updated;
  }

  /// El mecánico termina y manda a revisión: el cronómetro se detiene
  /// y el tiempo total queda guardado en la orden.
  Future<WorkOrder> sendToReview(String id) async {
    final items = await list();
    final o = await _byId(items, id);
    final updated = _accrue(o).copyWith(status: OrderStatus.inReview);
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return updated;
  }

  /// Guarda los materiales y compras reportados por el mecánico y manda
  /// la orden a revisión. Descuenta del inventario lo usado del taller.
  /// Retorna false si algún material no tenía suficientes existencias.
  Future<bool> completeInfo(
    String id,
    List<OrderMaterial> materials,
    List<OrderPurchase> purchases,
  ) async {
    final inv = InventoryService();
    for (final m in materials) {
      if (!m.fromShop) continue;
      final ok = await inv.deduct(m.itemId, m.qty);
      if (!ok) return false;
    }
    final items = await list();
    final o = await _byId(items, id);
    final updated = _accrue(o).copyWith(
      status: OrderStatus.inReview,
      materials: materials,
      purchases: purchases,
    );
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return true;
  }

  /// Corrige el tiempo trabajado manualmente (ej. el cronómetro se quedó
  /// corriendo de más). Detiene el cronómetro si estaba corriendo y deja
  /// el total indicado. El estado no cambia.
  Future<WorkOrder> correctTime(String id, int seconds) async {
    final items = await list();
    final o = await _byId(items, id);
    final updated = o.copyWith(
      workSeconds: seconds < 0 ? 0 : seconds,
      clearTimerStart: true,
    );
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return updated;
  }

  /// "Ya la realicé": la tarea se hizo sin iniciar el cronómetro.
  /// Guarda el tiempo indicado y la fecha en que se hizo, y la manda
  /// directo a revisión.
  Future<WorkOrder> completeManual(
      String id, int seconds, DateTime workDate) async {
    final items = await list();
    final o = await _byId(items, id);
    final updated = o.copyWith(
      status: OrderStatus.inReview,
      workSeconds: seconds < 0 ? 0 : seconds,
      clearTimerStart: true,
      manualWorkDate: DateTime(workDate.year, workDate.month,
          workDate.day),
    );
    items[items.indexWhere((e) => e.id == id)] = updated;
    await _persist(items);
    return updated;
  }
}
