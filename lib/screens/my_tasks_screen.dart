import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../models/task.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../services/mechanic_service.dart';
import '../services/task_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/duration.dart';
import '../widgets/shift_gate.dart';
import '../widgets/task_dialog.dart';
import 'order_detail_screen.dart';

/// Lo que el mecánico en sesión tiene que hacer:
/// - Sus órdenes de servicio de la sección (las avanza hasta mandarlas
///   a revisión).
/// - Las tareas que el administrador le asignó.
class MyTasksScreen extends StatefulWidget {
  final Mechanic mechanic;
  final VehicleType vehicleType;

  const MyTasksScreen(
      {super.key, required this.mechanic, required this.vehicleType});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends LocaleAwareState<MyTasksScreen> {
  final _taskService = TaskService();
  final _orderService = WorkOrderService();
  List<Task> _tasks = [];
  List<WorkOrder> _orders = [];
  bool _loading = true;
  bool _onShift = true; // el admin siempre puede trabajar
  Timer? _ticker; // actualiza los cronómetros en vivo

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _orders.any((o) => o.isTimerRunning)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final tasks = await _taskService.tasksFor(widget.mechanic.id);
    tasks.sort((a, b) {
      // Pendientes primero, terminadas al final.
      const order = {
        TaskStatus.pending: 0,
        TaskStatus.inProgress: 1,
        TaskStatus.inReview: 2,
        TaskStatus.done: 3
      };
      return order[a.status]!.compareTo(order[b.status]!);
    });
    final orders = await _orderService.activeFor(widget.mechanic.id);
    orders.removeWhere((o) => o.vehicleType != widget.vehicleType);
    orders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // Sin turno iniciado, el mecánico no puede empezar a trabajar.
    final onShift = await isOnShift(widget.mechanic);
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _orders = orders;
        _onShift = onShift;
        _loading = false;
      });
    }
  }

  Future<void> _createTask() async {
    final mechanics = await MechanicService().loadMechanics();
    if (!mounted) return;
    if (mechanics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('admin_add_mechanic_first'))),
      );
      return;
    }
    final result = await showTaskDialog(
      context,
      mechanics: mechanics,
    );
    if (result == null) return;
    await _taskService.addTask(
      result.title,
      result.description,
      result.mechanicId,
    );
    _load();
  }

  Future<void> _advance(Task task) async {
    // En revisión la decide el admin/fundador, no el asignado.
    if (task.status == TaskStatus.inReview) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('task_waiting_review'))),
        );
      }
      return;
    }
    // Confirmar al iniciar la tarea (evita toques accidentales).
    if (task.status == TaskStatus.pending) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('task_start_title')),
          content: Text(t('task_start_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('common_continue')),
            ),
          ],
        ),
      );
      if (ok != true) return;
      // No se puede hacer tarea y orden a la vez: si hay cronómetro
      // corriendo, se pausa la orden primero.
      final orders =
          await _orderService.activeFor(widget.mechanic.id);
      final running =
          orders.where((o) => o.isTimerRunning).toList();
      if (running.isNotEmpty) {
        final folios = running.map((o) => o.folio).join(', ');
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title:
                Text(t('task_timer_conflict_title')),
            content: Text(t('task_timer_conflict_body',
                {'folio': folios})),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(false),
                child: Text(t('common_cancel')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                child:
                    Text(t('task_timer_conflict_go')),
              ),
            ],
          ),
        );
        if (go != true) return;
        for (final o in running) {
          await _orderService.pauseWork(o.id);
        }
      }
    }
    // Confirmar antes de mandarla a revisión (evita toques accidentales).
    if (task.status == TaskStatus.inProgress) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('task_send_review_title')),
          content: Text(t('task_send_review_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('common_continue')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final next = task.status.next;
    await _taskService.updateTask(task.copyWith(
      status: next,
      // Al iniciarla se registra cuándo empezó (para la duración).
      startedAt: next == TaskStatus.inProgress && task.startedAt == null
          ? DateTime.now()
          : null,
    ));
    _load();
  }

  /// Oculta las terminadas: al mecánico ya no le salen (lógica de
  /// George: lo completado no debe acumularse en su lista).
  List<Task> get _visibleTasks =>
      _tasks.where((t) => t.status != TaskStatus.done).toList();

  /// Reasignar la tarea a otra persona (admin/fundador).
  Future<void> _reassign(Task task) async {
    final mechanics = await MechanicService().loadMechanics();
    if (!mounted) return;
    final others =
        mechanics.where((m) => m.id != task.mechanicId).toList();
    if (others.isEmpty) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(t('task_reassign_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in others)
                ListTile(
                  title: Text(m.name),
                  onTap: () => Navigator.of(ctx).pop(m.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(t('common_cancel')),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await _taskService.updateTask(
        task.copyWith(mechanicId: picked));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('task_reassigned'))),
      );
    }
    _load();
  }

  Color _taskColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending:
        return AppTheme.accent;
      case TaskStatus.inProgress:
        return Colors.lightBlueAccent;
      case TaskStatus.done:
        return Colors.greenAccent;
      case TaskStatus.inReview:
        return Colors.purpleAccent;
    }
  }

  IconData _taskIcon(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending:
        return Icons.radio_button_unchecked;
      case TaskStatus.inProgress:
        return Icons.timelapse;
      case TaskStatus.done:
        return Icons.check_circle;
      case TaskStatus.inReview:
        return Icons.hourglass_top;
    }
  }

  Color _orderColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.inProgress:
        return Colors.blue;
      case OrderStatus.paused:
        return Colors.amber;
      case OrderStatus.inReview:
        return Colors.purple;
      case OrderStatus.completed:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _visibleTasks;
    final empty = _orders.isEmpty && tasks.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('my_tasks_title')),
        actions: [
          // El fundador y los administradores pueden crear tareas
          // desde aquí sin ir al panel de administración.
          if (widget.mechanic.isAdmin || widget.mechanic.isFounder)
            IconButton(
              tooltip: t('admin_task_assign_title'),
              icon: const Icon(Icons.add),
              onPressed: _createTask,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : empty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      t('my_tasks_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 15),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Sin turno no se puede trabajar: la tarjeta invita a
                    // registrar la entrada ahí mismo.
                    if (!_onShift)
                      ShiftGateCard(
                        mechanic: widget.mechanic,
                        onShiftStarted: _load,
                      ),
                    if (_orders.isNotEmpty) ...[
                      _header(t('my_tasks_my_orders')),
                      const SizedBox(height: 8),
                      ..._orders.map(_orderCard),
                      const SizedBox(height: 20),
                    ],
                    if (tasks.isNotEmpty) ...[
                      _header(t('my_tasks_tasks')),
                      const SizedBox(height: 8),
                      ...tasks.map(_taskCard),
                    ],
                  ],
                ),
    );
  }

  Widget _header(String text) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17),
      );

  /// Tarjeta de orden: al tocarla abre el detalle para avanzar el trabajo.
  Widget _orderCard(WorkOrder o) {
    final color = _orderColor(o.status);
    return InkWell(
      onTap: () => Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => OrderDetailScreen(
                order: o,
                mechanic: widget.mechanic,
                onChanged: _load,
              ),
            ),
          )
          .then((_) => _load()),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.build_circle, color: color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      t('my_tasks_order_title', {
                        'folio': o.folio,
                        'label': o.isQuickOrder
                            ? '⚡ ${o.lines.first.note ?? ''}'
                            : o.vehicle.label,
                      }),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    o.isQuickOrder
                        ? t('my_tasks_quick_service')
                        : t('my_tasks_services_customer', {
                            'n': '${o.lines.length}',
                            's': o.lines.length == 1 ? '' : 's',
                            'customer': o.displayCustomerName,
                          }),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(t('my_tasks_status_${o.status.name}'),
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  if (o.status != OrderStatus.pending) ...[
                    const SizedBox(height: 4),
                    Text(
                      t('my_tasks_elapsed', {
                        'time': formatWorkTime(o.elapsedSeconds),
                        'paused': o.status == OrderStatus.paused
                            ? t('my_tasks_paused_suffix')
                            : '',
                      }),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(Task task) {
    final color = _taskColor(task.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.surfaceLight, width: 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: IconButton(
          tooltip: t('my_tasks_advance_tooltip', {
            'label': t('my_tasks_status_${task.status.next.name}'),
          }),
          icon: Icon(_taskIcon(task.status), color: color, size: 30),
          onPressed: () => _advance(task),
        ),
        // Reasignar (admin/fundador), igual que en las órdenes.
        trailing:
            (widget.mechanic.isAdmin || widget.mechanic.isFounder)
                ? IconButton(
                    tooltip: t('task_reassign_title'),
                    icon: const Icon(Icons.person_add_alt,
                        color: AppTheme.textSecondary,
                        size: 22),
                    onPressed: () => _reassign(task),
                  )
                : null,
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            decoration: task.status == TaskStatus.done
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.description,
                  style: const TextStyle(
                      color: AppTheme.textSecondary),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('my_tasks_status_${task.status.name}'),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if ((task.reviewNote ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        task.reviewNote!,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
