import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../models/shop_vehicle.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../models/task.dart';
import 'inventory_service.dart';
import 'shop_vehicle_service.dart';
import 'task_service.dart';
import 'work_order_service.dart';

/// Todo lo pendiente de revisar para el admin, en un solo lugar.
/// La campanita del encabezado abre el panel con estos datos.
class PendingsData {
  /// Órdenes de clientes mandadas a revisión, por sección.
  final int reviewCarro;
  final int reviewMoto;

  /// Gastos de mecánicos sin aprobar ni rechazar.
  final int pendingExpenses;

  /// Insumos por agotarse.
  final List<String> lowStockIds;
  final List<String> lowStockNames;

  /// Avisos de vehículos del taller (daños, aceite, documentos,
  /// órdenes internas por revisar). Sin los gastos: esos van aparte.
  final List<String> vehicleAlerts;

  /// Tareas asignadas a mí (el admin también puede traer tareas).
  final int myTasks;

  /// Tareas que los mecánicos marcaron terminadas y esperan mi
  /// confirmación (✓ terminada / ✕ incompleta).
  final List<Task> tasksInReview;

  const PendingsData({
    this.reviewCarro = 0,
    this.reviewMoto = 0,
    this.pendingExpenses = 0,
    this.lowStockIds = const [],
    this.lowStockNames = const [],
    this.vehicleAlerts = const [],
    this.myTasks = 0,
    this.tasksInReview = const [],
  });

  int get reviewTotal => reviewCarro + reviewMoto;

  int get total => reviewTotal +
      pendingExpenses +
      lowStockIds.length +
      vehicleAlerts.length +
      myTasks +
      tasksInReview.length;

  /// Firma del conjunto actual: si cambia, hay movimiento en los
  /// pendientes (algo nuevo llegó o algo se atendió).
  String get signature => 'rc:$reviewCarro|rm:$reviewMoto|'
      'ex:$pendingExpenses|'
      'in:${lowStockIds.join(',')}|'
      'tr:${tasksInReview.map((t) => t.id).join(',')}|'
      'va:${vehicleAlerts.join('~')}';
}


/// Pendientes del mecánico (no admin): sus tareas y gastos rechazados.
class MechanicPendingsData {
  /// Ids de tareas sin empezar / en pausa, por sección.
  final List<String> pendingCarro;
  final List<String> pausedCarro;
  final List<String> pendingMoto;
  final List<String> pausedMoto;

  /// Gastos que el admin rechazó (hay que volver a reportarlos).
  final List<VehicleExpense> rejected;

  /// Tareas del módulo Tareas asignadas al mecánico, sin terminar.
  final int myTasks;
  final List<String> myTaskIds;

  const MechanicPendingsData({
    this.pendingCarro = const [],
    this.pausedCarro = const [],
    this.pendingMoto = const [],
    this.pausedMoto = const [],
    this.rejected = const [],
    this.myTasks = 0,
    this.myTaskIds = const [],
  });

  int get tasksTotal =>
      pendingCarro.length +
      pausedCarro.length +
      pendingMoto.length +
      pausedMoto.length;

  int get total => tasksTotal + rejected.length + myTasks;

  /// Firma del conjunto actual.
  String get signature => 'pc:${pendingCarro.join(',')}|'
      'zc:${pausedCarro.join(',')}|'
      'pm:${pendingMoto.join(',')}|'
      'zm:${pausedMoto.join(',')}|'
      'rj:${rejected.map((e) => e.id).join(',')}|'
      'mt:${myTaskIds.join(',')}';

  /// Firma solo de las tareas de una sección (para la ✕ del banner).
  String tasksSignature(VehicleType type) {
    final p =
        type == VehicleType.carro ? pendingCarro : pendingMoto;
    final z =
        type == VehicleType.carro ? pausedCarro : pausedMoto;
    return 'p:${p.join(',')}|z:${z.join(',')}';
  }
}

class PendingsService {
  static const _dismissAlertsKey = 'pendings_dismiss_alerts_sig';
  static const _dismissStockKey = 'pendings_dismiss_stock_sig';

  /// Carga todo lo pendiente para el admin. Con [mechanicId] también
  /// cuenta las tareas asignadas a ese mecánico (el admin puede traer).
  Future<PendingsData> load({String? mechanicId}) async {
    final inReview = await WorkOrderService().pendingReview();
    final reviewCarro = inReview
        .where((o) =>
            o.vehicleType == VehicleType.carro && !o.isInternal)
        .length;
    final reviewMoto = inReview
        .where((o) =>
            o.vehicleType == VehicleType.moto && !o.isInternal)
        .length;

    final expenses =
        await ShopVehicleService().loadExpenses();
    final pendingExpenses = expenses
        .where((e) => !e.approved && !e.rejected)
        .length;

    final low = await InventoryService().lowStock();

    final alerts = await vehicleAlerts();

    var myTasks = 0;
    if (mechanicId != null) {
      final tasks = await TaskService().tasksFor(mechanicId);
      myTasks =
          tasks.where((t) => t.status != TaskStatus.done).length;
    }
    final allTasks = await TaskService().loadTasks();
    final reviewTasks =
        allTasks.where((t) => t.status == TaskStatus.inReview).toList();

    return PendingsData(
      reviewCarro: reviewCarro,
      reviewMoto: reviewMoto,
      pendingExpenses: pendingExpenses,
      lowStockIds: low.map((e) => e.id).toList(),
      lowStockNames: low.map((e) => e.name).toList(),
      vehicleAlerts: alerts,
      myTasks: myTasks,
      tasksInReview: reviewTasks,
    );
  }

  /// Avisos de vehículos del taller para el admin: gastos por revisar,
  /// órdenes internas por revisar, daños sin ver, aceite vencido y
  /// documentos por vencer.
  Future<List<String>> vehicleAlerts() async {
    final svc = ShopVehicleService();
    final alerts = <String>[];
    // Órdenes internas por revisar van primero.
    final orders = await WorkOrderService().list();
    final toReview = orders
        .where((o) =>
            o.isInternal && o.status == OrderStatus.inReview)
        .length;
    if (toReview > 0) {
      alerts.add(t('home_vehicle_alert_review',
          {'n': '$toReview'}));
    }
    // Gastos por revisar (los que mandaron los mecánicos).
    final allExpenses = await svc.loadExpenses();
    final pendingExpenses = allExpenses
        .where((e) => !e.approved && !e.rejected)
        .length;
    if (pendingExpenses > 0) {
      alerts.add(t('home_vehicle_alert_expenses',
          {'n': '$pendingExpenses'}));
    }
    final vehicles = await svc.loadVehicles();
    // Los vendidos ya no generan avisos.
    for (final v in vehicles.where((e) => e.status != 'vendido')) {
      final issues =
          await svc.issuesFor(v.id, resolved: false);
      if (issues.isNotEmpty) {
        alerts.add(t('home_vehicle_alert_issues',
            {'name': v.name, 'n': '${issues.length}'}));
      }
      if (v.kmToNextOil(ShopVehicleService.oilEveryKm) < 0) {
        alerts.add(
            t('home_vehicle_alert_oil', {'name': v.name}));
      }
      final docs = await svc.docsFor(v.id);
      for (final d in docs) {
        final days = d.daysToExpiry();
        if (days < 0) {
          alerts.add(t('home_vehicle_alert_doc_expired',
              {'name': v.name, 'doc': d.label}));
        } else if (days <= ShopVehicleService.docWarnDays) {
          alerts.add(t('home_vehicle_alert_doc_soon', {
            'name': v.name,
            'doc': d.label,
            'days': '$days'
          }));
        }
      }
    }
    return alerts;
  }

  // --- Campanita: el número siempre muestra el total actual.

  /// ¿Debe mostrarse el número en la campanita?
  bool shouldShowBadge(PendingsData data) => data.total > 0;

  // --- Banners naranjas: la ✕ los oculta hasta que algo cambia.

  Future<bool> _isDismissed(String key, String sig) async {
    if (sig.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) == sig;
  }

  Future<void> _dismiss(String key, String sig) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, sig);
  }

  /// ¿Se muestra el banner de avisos de vehículos?
  Future<bool> showVehicleBanner(List<String> alerts) =>
      _isDismissed(_dismissAlertsKey, alerts.join('~'))
          .then((d) => !d);

  Future<void> dismissVehicleBanner(List<String> alerts) =>
      _dismiss(_dismissAlertsKey, alerts.join('~'));

  /// ¿Se muestra el banner de inventario bajo?
  Future<bool> showLowStockBanner(List<String> ids) =>
      _isDismissed(_dismissStockKey, ids.join(','))
          .then((d) => !d);

  Future<void> dismissLowStockBanner(List<String> ids) =>
      _dismiss(_dismissStockKey, ids.join(','));

  // --- Mecánico: campanita y banners con ✕ ---

  static const _mechDismissTasksKey = 'mech_dismiss_tasks_sig';
  static const _mechDismissRejectedKey =
      'mech_dismiss_rejected_sig';

  /// Carga los pendientes del mecánico: sus tareas (sin empezar y en
  /// pausa, por sección) y sus gastos rechazados.
  Future<MechanicPendingsData> loadForMechanic(
      String mechanicId) async {
    final active = await WorkOrderService().active();
    List<String> ids(
        VehicleType type, OrderStatus status) {
      return active
          .where((o) =>
              o.vehicleType == type &&
              o.mechanicId == mechanicId &&
              o.status == status)
          .map((o) => o.id)
          .toList();
    }

    final expenses =
        await ShopVehicleService().loadExpenses();
    final rejected = expenses
        .where(
            (e) => e.rejected && e.createdById == mechanicId)
        .toList();

    final assigned = await TaskService().tasksFor(mechanicId);
    final openTasks =
        assigned.where((t) => t.status != TaskStatus.done).toList();

    return MechanicPendingsData(
      pendingCarro: ids(VehicleType.carro, OrderStatus.pending),
      pausedCarro: ids(VehicleType.carro, OrderStatus.paused),
      pendingMoto: ids(VehicleType.moto, OrderStatus.pending),
      pausedMoto: ids(VehicleType.moto, OrderStatus.paused),
      rejected: rejected,
      myTasks: openTasks.length,
      myTaskIds: openTasks.map((t) => t.id).toList(),
    );
  }

  bool shouldShowMechBadge(MechanicPendingsData data) =>
      data.total > 0;

  /// ¿Se muestra el banner azul de tareas de la sección?
  Future<bool> showTasksBanner(
      MechanicPendingsData data, VehicleType type) async {
    final sig = data.tasksSignature(type);
    if (sig == 'p:|z:') return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mechDismissTasksKey) != sig;
  }

  Future<void> dismissTasksBanner(
      MechanicPendingsData data, VehicleType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _mechDismissTasksKey, data.tasksSignature(type));
  }

  /// ¿Se muestra el banner rojo de gastos rechazados?
  Future<bool> showRejectedBanner(
      MechanicPendingsData data) async {
    if (data.rejected.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mechDismissRejectedKey) !=
        data.rejected.map((e) => e.id).join(',');
  }

  Future<void> dismissRejectedBanner(
      MechanicPendingsData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mechDismissRejectedKey,
        data.rejected.map((e) => e.id).join(','));
  }
}
