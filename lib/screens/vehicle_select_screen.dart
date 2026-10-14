import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../models/vehicle_type.dart';
import '../services/attendance_service.dart';
import '../services/pendings_service.dart';
import '../widgets/pendings_bell.dart';
import '../services/business_service.dart';
import '../services/shop_vehicle_service.dart';
import '../services/session_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import '../widgets/forgot_shift_dialog.dart';
import '../widgets/session_menu.dart';
import 'admin_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'my_tasks_screen.dart';
import 'orders_screen.dart';
import 'shop_vehicle_detail_screen.dart';

/// Pantalla de selección: pregunta si se usará la sección de motos o la de carros.
/// El admin ve una insignia morada con cuántas órdenes esperan revisión en cada
/// sección; si no hay nada pendiente, la pantalla se ve normal.
class VehicleSelectScreen extends StatefulWidget {
  final Mechanic mechanic;

  const VehicleSelectScreen({super.key, required this.mechanic});

  @override
  State<VehicleSelectScreen> createState() => _VehicleSelectScreenState();
}

class _VehicleSelectScreenState extends LocaleAwareState<VehicleSelectScreen> {
  int _pendingCarro = 0;
  int _pendingMoto = 0;
  int _pendingShifts = 0;
  PendingsData _pendings = const PendingsData();
  bool _showBadge = false;
  MechanicPendingsData _mechPendings =
      const MechanicPendingsData();
  bool _showMechBadge = false;
  String _businessName = 'Mi Taller';

  @override
  void initState() {
    super.initState();
    _loadPending();
    _loadBell();
    _loadBusinessName();
    // Si quedó un turno abierto de otro día, hay que cerrarlo antes
    // de seguir: sin eso el mecánico no se considera en turno.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkStaleShift());
  }

  Future<void> _checkStaleShift() async {
    final stale = await AttendanceService.getStaleShift(
        widget.mechanic.id);
    if (stale == null || !mounted) return;
    final closed = await showForgotShiftDialog(
        context, widget.mechanic, stale);
    if (closed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              t('vehicle_select_shift_closed_pending')),
        ),
      );
    }
  }

  Future<void> _loadBusinessName() async {
    final name = await BusinessService.getName();
    if (mounted) setState(() => _businessName = name);
  }

  Future<void> _loadPending() async {
    if (!widget.mechanic.isAdmin) return;
    final list = await WorkOrderService().pendingReview();
    final shifts = await AttendanceService.pendingConfirmation();
    if (!mounted) return;
    setState(() {
      // Las órdenes internas (vehículos del taller) se revisan en su
      // propia sección, no en Órdenes.
      _pendingCarro = list
          .where((o) =>
              o.vehicleType == VehicleType.carro &&
              !o.isInternal)
          .length;
      _pendingMoto = list
          .where((o) =>
              o.vehicleType == VehicleType.moto &&
              !o.isInternal)
          .length;
      _pendingShifts = shifts.length;
    });
  }

  Future<void> _loadBell() async {
    final svc = PendingsService();
    if (widget.mechanic.isAdmin) {
      final data = await svc.load(mechanicId: widget.mechanic.id);
      final show = svc.shouldShowBadge(data);
      if (mounted) {
        setState(() {
          _pendings = data;
          _showBadge = show;
        });
      }
    } else {
      final data =
          await svc.loadForMechanic(widget.mechanic.id);
      final show = svc.shouldShowMechBadge(data);
      if (mounted) {
        setState(() {
          _mechPendings = data;
          _showMechBadge = show;
        });
      }
    }
  }

  Future<void> _openPendings() async {
    await showPendingsSheet(
      context,
      mechanic: widget.mechanic,
      data: _pendings,
      fallbackType: VehicleType.carro,
    );
    if (mounted) {
      _loadBell();
      _loadPending();
    }
  }

  Future<void> _openMechPendings() async {
    final target = await showMechanicPendingsSheet(
      context,
      data: _mechPendings,
    );
    if (!mounted) return;
    _loadBell();
    _loadPending();
    if (target == null) return;
    switch (target.kind) {
      case MechTargetKind.tasks:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyTasksScreen(
              mechanic: widget.mechanic,
              vehicleType:
                  target.vehicleType ?? VehicleType.carro,
            ),
          ),
        );
        break;
      case MechTargetKind.myTasks:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyTasksScreen(
              mechanic: widget.mechanic,
              vehicleType: VehicleType.carro,
            ),
          ),
        );
        break;
      case MechTargetKind.rejected:
        final e = target.expense;
        if (e == null) break;
        final vehicles =
            await ShopVehicleService().loadVehicles();
        final idx =
            vehicles.indexWhere((v) => v.id == e.vehicleId);
        if (idx == -1 || !mounted) break;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShopVehicleDetailScreen(
              vehicle: vehicles[idx],
              mechanic: widget.mechanic,
            ),
          ),
        );
        break;
    }
  }

  /// Abre la administración directo en la pestaña de Horas.
  void _goToShiftReview(BuildContext context) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AdminScreen(
              currentMechanicId: widget.mechanic.id,
              initialTab: 2, // Horas
            ),
          ),
        )
        .then((_) => _loadPending());
  }

  /// Lleva directo a Órdenes de servicio de la sección (pestaña "En taller").
  void _goToOrders(BuildContext context, VehicleType type) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                OrdersScreen(vehicleType: type, mechanic: widget.mechanic),
          ),
        )
        .then((_) => _loadPending());
  }

  void _goTo(BuildContext context, VehicleType type) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                HomeScreen(vehicleType: type, mechanic: widget.mechanic),
          ),
        )
        .then((_) {
      _loadPending();
      _loadBell();
    });
  }

  /// Botón atrás del sistema: en vez de cerrar la app, pregunta si
  /// quiere cerrar su sesión y lo manda a la pantalla de usuarios.
  bool _backDialogOpen = false;

  Future<void> _onBack() async {
    if (_backDialogOpen) return;
    _backDialogOpen = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(t('session_menu_logout')),
        content: Text(
          t('session_menu_logout_confirm',
              {'name': widget.mechanic.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(
              t('common_cancel'),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => safePop(ctx, true),
            child: Text(
              t('session_menu_logout'),
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      _backDialogOpen = false;
      return;
    }
    await SessionService.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1D22), AppTheme.background],
          ),
        ),
        child: SafeArea(
          // Desplazable: con los avisos morado/ámbar visibles el contenido
          // fijo puede no caber en pantallas cortas (overflow).
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ajustes del administrador + mecánico en sesión
                // (toca el nombre para ver la opción de cerrar sesión)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.mechanic.isAdmin)
                      IconButton(
                        tooltip: t('vehicle_select_admin'),
                        icon: const Icon(
                          Icons.settings,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () =>
                            Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminScreen(
                              currentMechanicId: widget.mechanic.id,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PendingsBell(
                          count: widget.mechanic.isAdmin
                              ? (_showBadge
                                  ? _pendings.total
                                  : 0)
                              : (_showMechBadge
                                  ? _mechPendings.total
                                  : 0),
                          onTap: widget.mechanic.isAdmin
                              ? _openPendings
                              : _openMechPendings,
                        ),
                        SessionMenu(
                            mechanic: widget.mechanic),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Logotipo / nombre del taller
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.build_circle,
                      size: 44,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _businessName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('vehicle_select_what_today'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                // Turnos cerrados a mano por olvido: el admin confirma
                // que la hora sea correcta. Lleva a Horas.
                if (_pendingShifts > 0)
                  _ShiftConfirmBanner(
                    count: _pendingShifts,
                    onTap: () => _goToShiftReview(context),
                  ),
                // Aviso para el admin: hay notificaciones por revisar.
                // Lleva al panel de pendientes (la campanita).
                if (widget.mechanic.isAdmin && _pendings.total > 0)
                  _NotificationsBanner(
                    count: _pendings.total,
                    onTap: _openPendings,
                  ),
                // Botón extra: aparece solo cuando hay órdenes mandadas a
                // revisión. Lleva directo a Órdenes de esa sección.
                // Si no hay nada pendiente, la pantalla queda original.
                if (_pendingCarro > 0)
                  _ReviewButton(
                    count: _pendingCarro,
                    section: t('vehicle_select_carros'),
                    onTap: () =>
                        _goToOrders(context, VehicleType.carro),
                  ),
                if (_pendingMoto > 0)
                  _ReviewButton(
                    count: _pendingMoto,
                    section: t('vehicle_select_motos'),
                    onTap: () => _goToOrders(context, VehicleType.moto),
                  ),
                // Tarjetas de selección (altura fija: antes eran Expanded,
                // pero con los avisos visibles no cabían en la columna).
                SizedBox(
                  height: 172,
                  child: _VehicleCard(
                    type: VehicleType.carro,
                    onTap: () => _goTo(context, VehicleType.carro),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 172,
                  child: _VehicleCard(
                    type: VehicleType.moto,
                    onTap: () => _goTo(context, VehicleType.moto),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  t('vehicle_select_switch_anytime'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleType type;
  final VoidCallback onTap;

  const _VehicleCard({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = type == VehicleType.moto
        ? t('vehicle_select_motos')
        : t('vehicle_select_carros');
    final desc = type == VehicleType.moto
        ? t('vehicle_select_moto_desc')
        : t('vehicle_select_carro_desc');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.surfaceLight, AppTheme.surface],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.surfaceLight, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.accent, AppTheme.accentDark],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(type.icon, size: 48, color: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón morado que aparece arriba de las tarjetas cuando hay órdenes
/// mandadas a revisión en una sección. Lleva directo a Órdenes.
/// Mensaje para el admin: "Tienes N notificaciones por revisar".
/// Al tocarlo abre el panel de pendientes.
class _NotificationsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NotificationsBanner(
      {required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.purple.withValues(alpha: 0.5),
                width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active,
                  color: Colors.purple, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('vehicle_select_notifications',
                      {'n': '$count'}),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  final int count;
  final String section;
  final VoidCallback onTap;

  const _ReviewButton({
    required this.count,
    required this.section,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8B3DFF), Color(0xFF6A1FD6)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7B2FF7).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(
                      count == 1
                          ? 'vehicle_select_review_one'
                          : 'vehicle_select_review_many',
                      {'n': '$count', 'section': section},
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner ámbar para el admin: turnos cerrados a mano por olvido que
/// esperan su confirmación de que la hora sea correcta.
class _ShiftConfirmBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ShiftConfirmBanner({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFB97A00), Color(0xFF8A5B00)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB97A00).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(
                      count == 1
                          ? 'vehicle_select_shifts_one'
                          : 'vehicle_select_shifts_many',
                      {'n': '$count'},
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
