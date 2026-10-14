import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../models/vehicle_type.dart';
import '../models/shop_vehicle.dart';
import '../services/pendings_service.dart';
import '../services/mechanic_service.dart';
import '../services/shop_vehicle_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pendings_bell.dart';
import 'pos_screen.dart';
import 'orders_screen.dart';
import 'quick_service_screen.dart';
import 'clients_screen.dart';
import 'my_tasks_screen.dart';
import 'shop_vehicle_detail_screen.dart';
import 'inventory_screen.dart';
import 'shop_vehicles_screen.dart';

/// Pantalla principal de la sección elegida (motos o carros).
/// Si el administrador tiene órdenes mandadas a revisión, aparece un
/// aviso de "servicio pendiente" que lo lleva a revisarlas.
class HomeScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;

  const HomeScreen({
    super.key,
    required this.vehicleType,
    required this.mechanic,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends LocaleAwareState<HomeScreen> {
  PendingsData _pendings = const PendingsData();
  bool _showBadge = false; // número en la campanita
  bool _showVehicleBanner = false; // banner naranja (con ✕)
  bool _showLowStockBanner = false; // banner naranja (con ✕)
  int _pendingCount = 0; // tareas sin empezar asignadas al mecánico
  int _pausedCount = 0; // tareas en pausa asignadas al mecánico
  List<VehicleExpense> _rejectedExpenses =
      []; // gastos rechazados por el admin
  MechanicPendingsData _mechPendings =
      const MechanicPendingsData();
  bool _showMechBadge = false; // número en la campanita del mecánico
  bool _showTasksBanner = false; // banner azul (con ✕)
  bool _showRejectedBanner = false; // banner rojo (con ✕)

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  /// Órdenes de clientes por revisar en esta sección.
  int get _sectionReviewCount =>
      widget.vehicleType == VehicleType.carro
          ? _pendings.reviewCarro
          : _pendings.reviewMoto;

  Future<void> _loadPending() async {
    final me = widget.mechanic;
    if (me.isAdmin) {
      final svc = PendingsService();
      final data = await svc.load();
      final showBadge = svc.shouldShowBadge(data);
      final showV = data.vehicleAlerts.isNotEmpty &&
          await svc.showVehicleBanner(data.vehicleAlerts);
      final showL = data.lowStockIds.isNotEmpty &&
          await svc.showLowStockBanner(data.lowStockIds);
      if (mounted) {
        setState(() {
          _pendings = data;
          _showBadge = showBadge;
          _showVehicleBanner = showV;
          _showLowStockBanner = showL;
        });
      }
    } else {
      final svc = PendingsService();
      final data = await svc.loadForMechanic(me.id);
      final showBadge = svc.shouldShowMechBadge(data);
      final sectionPending =
          widget.vehicleType == VehicleType.carro
              ? data.pendingCarro.length
              : data.pendingMoto.length;
      final sectionPaused =
          widget.vehicleType == VehicleType.carro
              ? data.pausedCarro.length
              : data.pausedMoto.length;
      final showT =
          await svc.showTasksBanner(data, widget.vehicleType);
      final showR = await svc.showRejectedBanner(data);
      if (mounted) {
        setState(() {
          _mechPendings = data;
          _showMechBadge = showBadge;
          // Solo lo sin empezar (pending) y lo pausado cuentan.
          // Lo que ya está en curso no se anuncia.
          _pendingCount = sectionPending;
          _pausedCount = sectionPaused;
          _rejectedExpenses = data.rejected;
          _showTasksBanner = showT;
          _showRejectedBanner = showR;
        });
      }
    }
  }

  void _goToMyTasks() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => MyTasksScreen(
              vehicleType: widget.vehicleType,
              mechanic: widget.mechanic,
            ),
          ),
        )
        .then((_) => _loadPending());
  }

  Widget _lowStockBanner() => InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                InventoryScreen(mechanic: widget.mechanic),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.orange.withValues(alpha: 0.5),
                width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: Colors.orange, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('inv_low_alert',
                      {'n': '${_pendings.lowStockIds.length}'}),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: t('common_dismiss'),
                icon: const Icon(Icons.close,
                    color: AppTheme.textSecondary, size: 18),
                onPressed: _dismissLowStockBanner,
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      );

  /// Abre el panel de pendientes y marca lo actual como visto
  /// (el número de la campanita se quita hasta que algo cambie).
  Future<void> _openPendings() async {
    final mechanics = await MechanicService().loadMechanics();
    if (!mounted) return;
    await showPendingsSheet(
      context,
      mechanic: widget.mechanic,
      data: _pendings,
      fallbackType: widget.vehicleType,
      mechNames: {for (final m in mechanics) m.id: m.name},
    );
    if (mounted) _loadPending();
  }

  Future<void> _dismissVehicleBanner() async {
    await PendingsService()
        .dismissVehicleBanner(_pendings.vehicleAlerts);
    if (mounted) setState(() => _showVehicleBanner = false);
  }

  /// Abre el panel de pendientes del mecánico.
  Future<void> _openMechPendings() async {
    final target = await showMechanicPendingsSheet(
      context,
      data: _mechPendings,
      section: widget.vehicleType,
    );
    if (!mounted) return;
    if (target == null) {
      _loadPending();
      return;
    }
    switch (target.kind) {
      case MechTargetKind.tasks:
        _goToMyTasks();
        break;
      case MechTargetKind.myTasks:
        _goToMyTasks();
        break;
      case MechTargetKind.rejected:
        final e = target.expense;
        if (e != null) _goToRejectedVehicle(e);
        break;
    }
  }

  Future<void> _dismissTasksBanner() async {
    await PendingsService()
        .dismissTasksBanner(_mechPendings, widget.vehicleType);
    if (mounted) setState(() => _showTasksBanner = false);
  }

  Future<void> _dismissRejectedBanner() async {
    await PendingsService()
        .dismissRejectedBanner(_mechPendings);
    if (mounted) setState(() => _showRejectedBanner = false);
  }

  Future<void> _dismissLowStockBanner() async {
    await PendingsService()
        .dismissLowStockBanner(_pendings.lowStockIds);
    if (mounted) setState(() => _showLowStockBanner = false);
  }

  void _goToShopVehicles() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ShopVehiclesScreen(
              mechanic: widget.mechanic,
              vehicleType: widget.vehicleType,
            ),
          ),
        )
        .then((_) => _loadPending());
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = widget.vehicleType == VehicleType.moto
        ? t('home_motos')
        : t('home_carros');
    final modules = <_Module>[
      _Module(
        title: t('home_quick_service'),
        subtitle: t('home_quick_service_sub'),
        icon: Icons.flash_on,
        accent: true,
        screen: QuickServiceScreen(
            vehicleType: widget.vehicleType,
            mechanic: widget.mechanic),
      ),
      _Module(
        title: t('home_pos'),
        subtitle: t('home_pos_sub'),
        icon: Icons.point_of_sale,
        screen: PosScreen(
            vehicleType: widget.vehicleType,
            mechanic: widget.mechanic),
      ),
      _Module(
        title: t('home_orders'),
        subtitle: t('home_orders_sub'),
        icon: Icons.build,
        badge: _sectionReviewCount > 0
            ? '$_sectionReviewCount'
            : null,
        screen: OrdersScreen(
            vehicleType: widget.vehicleType,
            mechanic: widget.mechanic),
      ),
      _Module(
        title: t('home_my_tasks'),
        subtitle: t('home_my_tasks_sub'),
        icon: Icons.task_alt,
        badge: _pendingCount + _pausedCount > 0
            ? '${_pendingCount + _pausedCount}'
            : null,
        screen: MyTasksScreen(
            mechanic: widget.mechanic,
            vehicleType: widget.vehicleType),
      ),
      _Module(
        title: t('home_clients'),
        subtitle: t('home_clients_sub'),
        icon: Icons.people,
        screen: ClientsScreen(
            vehicleType: widget.vehicleType, mechanic: widget.mechanic),
      ),
      _Module(
        title: t('home_shop_vehicles'),
        subtitle: t('home_shop_vehicles_sub'),
        icon: Icons.directions_car,
        screen: ShopVehiclesScreen(
            mechanic: widget.mechanic,
            vehicleType: widget.vehicleType),
      ),
      // Inventario: el admin lo gestiona; el mecánico solo
      // consulta existencias (sin modificar nada).
      _Module(
        title: t('inv_title'),
        subtitle: widget.mechanic.isAdmin
            ? t('inv_subtitle')
            : t('inv_subtitle_readonly'),
        icon: Icons.inventory_2_outlined,
        screen: InventoryScreen(
          mechanic: widget.mechanic,
          readOnly: !widget.mechanic.isAdmin,
        ),
      ),
    ];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          child: Container(
            color: AppTheme.surface,
            child: Stack(
              children: [
                // Título perfectamente centrado
                Center(
                  child: Text(
                    typeLabel,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                // Flecha para volver al selector de sección
                Positioned(
                  left: 4,
                  top: 0,
                  child: IconButton(
                    tooltip: t('home_back'),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                // Campanita de pendientes (cada rol ve lo suyo)
                Positioned(
                  right: 4,
                  top: 8,
                  child: PendingsBell(
                    count: widget.mechanic.isAdmin
                        ? (_showBadge ? _pendings.total : 0)
                        : (_showMechBadge
                            ? _mechPendings.total
                            : 0),
                    onTap: widget.mechanic.isAdmin
                        ? _openPendings
                        : _openMechPendings,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // El nombre del mecánico en sesión solo aparece en la pantalla
            // de selección de sección (vehicle_select_screen).
            Text(
              t('home_what_today', {'type': typeLabel.toLowerCase()}),
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            // Avisos de vehículos del taller (solo admin, con ✕).
            if (_showVehicleBanner) ...[
              const SizedBox(height: 12),
              _vehicleBanner(),
            ],
            if (_showLowStockBanner) ...[
              const SizedBox(height: 12),
              _lowStockBanner(),
            ],
            // Aviso para el mecánico: tareas sin empezar y en pausa.
            // Lo lleva directo a Mis tareas. Lo que ya está en curso
            // no se anuncia.
            if (_showTasksBanner) ...[
              const SizedBox(height: 12),
              _tasksBanner(),
            ],
            // Gastos rechazados por el admin: volver a reportarlos.
            if (_showRejectedBanner) ...[
              const SizedBox(height: 12),
              _rejectedBanner(),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  // Celdas más altas: en ventanas angostas el título se
                  // parte en dos líneas y la tarjeta se desbordaba.
                  childAspectRatio: 0.8,
                ),
                itemCount: modules.length,
                itemBuilder: (context, i) {
                  final m = modules[i];
                  return _ModuleCard(
                    module: m,
                    onTap: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                              builder: (_) => m.screen),
                        )
                        .then((_) => _loadPending()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aviso para el administrador: vehículos del taller con daños,
  /// aceite vencido o documentos por vencer.
  /// Aviso para el administrador: vehículos del taller con daños,
  /// aceite vencido o documentos por vencer. La ✕ lo oculta hasta
  /// que haya movimiento en los avisos.
  Widget _vehicleBanner() => InkWell(
        onTap: _goToShopVehicles,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.orange.withValues(alpha: 0.5),
                width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.directions_car,
                  color: Colors.orange, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    for (final a in _pendings.vehicleAlerts)
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: 2),
                        child: Text(
                          '• $a',
                          style: const TextStyle(
                            color:
                                AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t('common_dismiss'),
                icon: const Icon(Icons.close,
                    color: AppTheme.textSecondary, size: 18),
                onPressed: _dismissVehicleBanner,
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      );

  /// Aviso para el mecánico: cuántas tareas tiene sin empezar y en pausa.
  /// Lo que ya está en curso no se anuncia: ya lo está trabajando.
  /// Lo lleva directo a Mis tareas.
  String _tasksBannerText() {
    final parts = <String>[];
    if (_pausedCount == 1) {
      parts.add(t('home_tasks_paused_one_short'));
    } else if (_pausedCount > 1) {
      parts.add(t('home_tasks_paused_many_short',
          {'n': '$_pausedCount'}));
    }
    if (_pendingCount == 1) {
      parts.add(t('home_tasks_pending_one_short'));
    } else if (_pendingCount > 1) {
      parts.add(t('home_tasks_pending_many_short',
          {'n': '$_pendingCount'}));
    }
    return '${t('home_tasks_have')} '
        '${parts.join(' ${t('home_tasks_and')} ')}';
  }

  Widget _tasksBanner() => InkWell(
        onTap: _goToMyTasks,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.blue.withValues(alpha: 0.5),
                width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.task_alt,
                  color: Colors.blue, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tasksBannerText(),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                tooltip: t('common_dismiss'),
                icon: const Icon(Icons.close,
                    color: AppTheme.textSecondary, size: 18),
                onPressed: _dismissTasksBanner,
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      );

  /// Aviso de gastos rechazados: el mecánico debe volver a reportarlos.
  Widget _rejectedBanner() {
    final e = _rejectedExpenses.first;
    return InkWell(
      onTap: () => _goToRejectedVehicle(e),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.red.withValues(alpha: 0.5),
              width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    t('home_rejected_expense',
                        {'n': '${_rejectedExpenses.length}'}),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (e.rejectReason.isNotEmpty)
                    Text(
                      e.rejectReason,
                      style: const TextStyle(
                        color:
                            AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: t('common_dismiss'),
              icon: const Icon(Icons.close,
                  color: AppTheme.textSecondary, size: 18),
              onPressed: _dismissRejectedBanner,
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  void _goToRejectedVehicle(VehicleExpense e) async {
    final vehicles =
        await ShopVehicleService().loadVehicles();
    final idx =
        vehicles.indexWhere((v) => v.id == e.vehicleId);
    if (idx == -1 || !mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                ShopVehicleDetailScreen(
              vehicle: vehicles[idx],
              mechanic: widget.mechanic,
            ),
          ),
        )
        .then((_) => _loadPending());
  }
}

class _Module {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool accent;
  final String? badge;
  final Widget screen;

  _Module({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accent = false,
    this.badge,
    required this.screen,
  });
}

class _ModuleCard extends StatelessWidget {
  final _Module module;
  final VoidCallback onTap;

  const _ModuleCard({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        module.accent ? Colors.amberAccent : AppTheme.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: module.accent
                ? color.withValues(alpha: 0.5)
                : AppTheme.surfaceLight,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        Icon(module.icon, color: color, size: 30),
                  ),
                  if (module.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        module.badge!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    module.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
