import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/mechanic.dart';
import '../models/shop_vehicle.dart';
import '../utils/money.dart';
import '../models/vehicle_type.dart';
import '../screens/inventory_screen.dart';
import '../models/task.dart';
import '../screens/my_tasks_screen.dart';
import '../services/task_service.dart';
import 'task_review_dialog.dart';
import '../screens/orders_screen.dart';
import '../screens/shop_vehicles_screen.dart';
import '../services/pendings_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';

/// Campanita de pendientes. El número siempre muestra el total
/// actual de cosas por atender.
class PendingsBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const PendingsBell(
      {super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.notifications_outlined,
              color: AppTheme.textPrimary,
              size: 24,
            ),
            if (count > 0)
              Positioned(
                top: -6,
                right: -8,
                child: Container(
                  constraints: const BoxConstraints(
                      minWidth: 17, minHeight: 17),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PendingsKind {
  myTasks,
  reviewCarro,
  reviewMoto,
  expenses,
  inventory,
  vehicles,
  taskReview,
}

/// Destino del panel del admin. [task] solo se usa en taskReview.
class _PendingsTarget {
  final _PendingsKind kind;
  final Task? task;

  const _PendingsTarget(this.kind, [this.task]);

  static const myTasks = _PendingsTarget(_PendingsKind.myTasks);
  static const reviewCarro =
      _PendingsTarget(_PendingsKind.reviewCarro);
  static const reviewMoto =
      _PendingsTarget(_PendingsKind.reviewMoto);
  static const expenses = _PendingsTarget(_PendingsKind.expenses);
  static const inventory =
      _PendingsTarget(_PendingsKind.inventory);
  static const vehicles = _PendingsTarget(_PendingsKind.vehicles);
}

/// Abre el panel "Pendientes" con todo agrupado. Devuelve después de
/// que se cierra; la navegación a cada pantalla la hace el llamador.
Future<void> showPendingsSheet(
  BuildContext context, {
  required Mechanic mechanic,
  required PendingsData data,
  required VehicleType fallbackType,
  Map<String, String> mechNames = const {},
}) async {
  final target =
      await showModalBottomSheet<_PendingsTarget>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ).centered(),
            Text(
              t('pendings_title'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              data.total == 1
                  ? t('pendings_count_one')
                  : t('pendings_count_many',
                      {'n': '${data.total}'}),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    if (data.total == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 24),
                        child: Text(
                          t('pendings_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14),
                        ),
                      ),
                    if (data.myTasks > 0)
                      _Section(
                        label: t('pendings_my_tasks'),
                        color: AppTheme.accent,
                        children: [
                          _Row(
                            target: _PendingsTarget.myTasks,
                            title: data.myTasks == 1
                                ? t('pendings_my_tasks_one')
                                : t('pendings_my_tasks_many',
                                    {'n': '${data.myTasks}'}),
                            subtitle: t('pendings_my_tasks_desc'),
                          ),
                        ],
                      ),
                    if (data.tasksInReview.isNotEmpty)
                      _Section(
                        label: t('pendings_tasks_review'),
                        color: Colors.purple,
                        children: [
                          for (final task in data.tasksInReview)
                            _Row(
                              target: _PendingsTarget(
                                  _PendingsKind.taskReview,
                                  task),
                              title: task.title,
                              subtitle: mechNames[
                                      task.mechanicId] ??
                                  '',
                            ),
                        ],
                      ),
                    if (data.reviewTotal > 0)
                      _Section(
                        label: t('pendings_review'),
                        color: Colors.purple,
                        children: [
                          if (data.reviewCarro > 0)
                            _Row(
                              target: _PendingsTarget
                                  .reviewCarro,
                              title: t('pendings_in_section', {
                                'n': '${data.reviewCarro}',
                                'section':
                                    t('vehicle_select_carros')
                              }),
                              subtitle: t(
                                  'pendings_review_desc'),
                            ),
                          if (data.reviewMoto > 0)
                            _Row(
                              target: _PendingsTarget
                                  .reviewMoto,
                              title: t('pendings_in_section', {
                                'n': '${data.reviewMoto}',
                                'section':
                                    t('vehicle_select_motos')
                              }),
                              subtitle: t(
                                  'pendings_review_desc'),
                            ),
                        ],
                      ),
                    if (data.pendingExpenses > 0)
                      _Section(
                        label: t('pendings_expenses'),
                        color: Colors.orange,
                        children: [
                          _Row(
                            target:
                                _PendingsTarget.expenses,
                            title: data.pendingExpenses == 1
                                ? t(
                                    'pendings_expenses_one')
                                : t(
                                    'pendings_expenses_many',
                                    {
                                        'n':
                                            '${data.pendingExpenses}'
                                      }),
                            subtitle: t(
                                'pendings_expenses_desc'),
                          ),
                        ],
                      ),
                    if (data.lowStockIds.isNotEmpty)
                      _Section(
                        label: t('pendings_inventory'),
                        color: Colors.orange,
                        children: [
                          _Row(
                            target:
                                _PendingsTarget.inventory,
                            title: data.lowStockIds.length ==
                                    1
                                ? t(
                                    'pendings_inventory_one')
                                : t(
                                    'pendings_inventory_many',
                                    {
                                        'n':
                                            '${data.lowStockIds.length}'
                                      }),
                            subtitle: data.lowStockNames
                                .take(3)
                                .join(', '),
                          ),
                        ],
                      ),
                    if (data.vehicleAlerts.isNotEmpty)
                      _Section(
                        label: t('pendings_vehicles'),
                        color: Colors.orange,
                        children: [
                          for (final a
                              in data.vehicleAlerts)
                            _Row(
                              target: _PendingsTarget
                                  .vehicles,
                              title: a,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (target == null || !context.mounted) return;
  switch (target.kind) {
    case _PendingsKind.myTasks:
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MyTasksScreen(
              mechanic: mechanic,
              vehicleType: fallbackType)));
      break;
    case _PendingsKind.taskReview:
      final task = target.task;
      if (task == null) break;
      final ok = await showTaskReviewDialog(
        context,
        task: task,
        assigneeName: mechNames[task.mechanicId] ?? '',
      );
      if (ok == null) break;
      if (ok) {
        await TaskService().updateTask(task.copyWith(
          status: TaskStatus.done,
          clearReviewNote: true,
          completedAt: DateTime.now(),
        ));
      } else {
        await TaskService().updateTask(task.copyWith(
          status: TaskStatus.inProgress,
          reviewNote: t('task_incomplete_note'),
        ));
      }
      break;
    case _PendingsKind.reviewCarro:
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OrdersScreen(
              vehicleType: VehicleType.carro,
              mechanic: mechanic)));
      break;
    case _PendingsKind.reviewMoto:
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OrdersScreen(
              vehicleType: VehicleType.moto,
              mechanic: mechanic)));
      break;
    case _PendingsKind.expenses:
    case _PendingsKind.vehicles:
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ShopVehiclesScreen(
              mechanic: mechanic,
              vehicleType: fallbackType)));
      break;
    case _PendingsKind.inventory:
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              InventoryScreen(mechanic: mechanic)));
      break;
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Color color;
  final List<Widget> children;

  const _Section(
      {required this.label,
      required this.color,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final _PendingsTarget target;
  final String title;
  final String? subtitle;

  const _Row(
      {required this.target, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => safePop(context, target),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.surfaceLight),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (subtitle != null &&
                        subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              color:
                                  AppTheme.textSecondary,
                              fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

extension _Centered on Widget {
  Widget centered() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [this],
      );
}

/// Destino elegido en el panel del mecánico. La navegación la hace
/// el llamador (el home ya tiene esos métodos).
enum MechTargetKind { tasks, rejected, myTasks }

class MechTarget {
  final MechTargetKind kind;
  final VehicleType? vehicleType;
  final VehicleExpense? expense;

  const MechTarget.tasks(this.vehicleType)
      : kind = MechTargetKind.tasks,
        expense = null;

  const MechTarget.rejected(this.expense)
      : kind = MechTargetKind.rejected,
        vehicleType = null;

  const MechTarget.myTasks()
      : kind = MechTargetKind.myTasks,
        vehicleType = null,
        expense = null;
}

/// Panel "Pendientes" del mecánico: sus tareas y gastos rechazados.
/// [section] limita a una sección (inicio); null = todas (carros/motos).
Future<MechTarget?> showMechanicPendingsSheet(
  BuildContext context, {
  required MechanicPendingsData data,
  VehicleType? section,
}) async {
  final types = section != null
      ? [section]
      : VehicleType.values;
  return showModalBottomSheet<MechTarget>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ).centered(),
            Text(
              t('pendings_title'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              data.total == 1
                  ? t('pendings_count_one')
                  : t('pendings_count_many',
                      {'n': '${data.total}'}),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    if (data.total == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 24),
                        child: Text(
                          t('pendings_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14),
                        ),
                      ),
                    if (data.myTasks > 0)
                      _Section(
                        label: t('pendings_my_tasks'),
                        color: AppTheme.accent,
                        children: [
                          _MechRow(
                            target: const MechTarget.myTasks(),
                            title: data.myTasks == 1
                                ? t('pendings_my_tasks_one')
                                : t('pendings_my_tasks_many',
                                    {'n': '${data.myTasks}'}),
                            subtitle:
                                t('pendings_my_tasks_desc'),
                          ),
                        ],
                      ),
                    if (data.tasksTotal > 0)
                      _Section(
                        label: t('pendings_tasks'),
                        color: Colors.blue,
                        children: [
                          for (final type in types)
                            ..._taskRows(data, type),
                        ],
                      ),
                    if (data.rejected.isNotEmpty)
                      _Section(
                        label: t('pendings_rejected'),
                        color: Colors.red,
                        children: [
                          for (final e in data.rejected)
                            _MechRow(
                              target: MechTarget.rejected(e),
                              title: e.notes.isNotEmpty
                                  ? e.notes
                                  : formatMoney(e.amount),
                              subtitle: e.rejectReason
                                      .isNotEmpty
                                  ? e.rejectReason
                                  : t('pendings_rejected_desc'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

List<Widget> _taskRows(
    MechanicPendingsData data, VehicleType type) {
  final pending = type == VehicleType.carro
      ? data.pendingCarro.length
      : data.pendingMoto.length;
  final paused = type == VehicleType.carro
      ? data.pausedCarro.length
      : data.pausedMoto.length;
  if (pending == 0 && paused == 0) return [];
  final sectionLabel = type == VehicleType.carro
      ? t('vehicle_select_carros')
      : t('vehicle_select_motos');
  final rows = <Widget>[];
  if (pending > 0) {
    rows.add(_MechRow(
      target: MechTarget.tasks(type),
      title: t('pendings_tasks_pending', {'n': '$pending'}),
      subtitle:
          t('pendings_tasks_desc', {'section': sectionLabel}),
    ));
  }
  if (paused > 0) {
    rows.add(_MechRow(
      target: MechTarget.tasks(type),
      title: t('pendings_tasks_paused', {'n': '$paused'}),
      subtitle:
          t('pendings_tasks_desc', {'section': sectionLabel}),
    ));
  }
  return rows;
}

class _MechRow extends StatelessWidget {
  final MechTarget target;
  final String title;
  final String? subtitle;

  const _MechRow(
      {required this.target, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => safePop(context, target),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.surfaceLight),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (subtitle != null &&
                        subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              color:
                                  AppTheme.textSecondary,
                              fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
