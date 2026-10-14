import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/mechanic.dart';
import '../models/shop_vehicle.dart';
import '../models/ticket.dart';
import '../models/vehicle.dart';
import '../models/work_order.dart';
import '../models/task.dart';
import '../services/mechanic_service.dart';
import '../services/photo_service.dart';
import '../services/shop_vehicle_service.dart';
import '../services/ticket_service.dart';
import '../services/ticket_share_service.dart';
import '../services/work_order_service.dart';
import '../services/task_service.dart';
import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/dialog.dart';
import '../utils/duration.dart';
import '../utils/money.dart';
import '../widgets/shift_gate.dart';
import 'complete_order_screen.dart';

/// Detalle de una orden de servicio: vehículo, cliente, fotos, niveles,
/// servicios y avance del trabajo.
/// - El mecánico asignado (o el admin) avanza: Pendiente → En curso →
///   "Mandar a revisión".
/// - El administrador revisa la orden, pone el precio de los servicios
///   rápidos pendientes y completa el ticket.
class OrderDetailScreen extends StatefulWidget {
  final WorkOrder order;
  final Mechanic mechanic;
  final VoidCallback? onChanged;

  const OrderDetailScreen({
    super.key,
    required this.order,
    required this.mechanic,
    this.onChanged,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends LocaleAwareState<OrderDetailScreen> {
  final _orderService = WorkOrderService();
  late WorkOrder _order;
  Map<String, String> _names = {};
  final Map<String, TextEditingController> _priceCtrls = {};
  bool _busy = false;
  int _payMode = 0; // 0 = pagado, 1 = abono, 2 = crédito
  String _expenseKind =
      'reparacion'; // solo órdenes internas: reparacion/servicio/otro
  final _abonoCtrl = TextEditingController();
  bool _onShift = true; // el admin siempre puede trabajar

  bool get _isAdmin => widget.mechanic.isAdmin;
  bool get _isAssignee => widget.mechanic.id == _order.mechanicId;
  /// Corregir el tiempo trabajado: el admin/fundador hasta que el
  /// ticket se completa; el mecánico asignado solo mientras la orden
  /// no está en revisión (para que no cambie la hora ya enviada).
  bool get _canCorrectTime =>
      !_busy &&
      _order.status != OrderStatus.completed &&
      ((widget.mechanic.isAdmin || widget.mechanic.isFounder) ||
          (_isAssignee &&
              _order.status != OrderStatus.inReview));

  /// Avanzar el trabajo (empezar/pausar/reanudar/mandar a revisión):
  /// solo quien la tiene asignada. El admin la puede reasignar o
  /// corregir el tiempo, pero no tocar el cronómetro ajeno.
  bool get _canWork => _isAssignee;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _loadNames();
    _loadShift();
    for (final l in _order.lines) {
      if (l.needsPrice) _priceCtrls[l.serviceId] = TextEditingController();
    }
  }

  /// ¿El mecánico en sesión tiene su turno iniciado?
  Future<void> _loadShift() async {
    final onShift = await isOnShift(widget.mechanic);
    if (mounted) setState(() => _onShift = onShift);
  }

  Future<void> _clockIn() async {
    final ok = await clockInWithStaleCheck(context, widget.mechanic);
    if (!ok || !mounted) return;
    await _loadShift();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('order_detail_shift_started'))),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    _abonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    final list = await MechanicService().loadMechanics();
    if (!mounted) return;
    setState(() {
      _names = {for (final m in list) m.id: m.name};
    });
  }

  String get _assigneeName =>
      _names[_order.mechanicId] ?? t('order_detail_default_mechanic');

  /// Ejecuta una transición de la orden (empezar, pausar, reanudar,
  /// mandar a revisión) y refresca la pantalla.
  /// Arrancar/reanudar el cronómetro avisando si hay una tarea en
  /// curso: no se puede hacer tarea y orden a la vez.
  Future<void> _guardedStart(
      Future<WorkOrder> Function() op, String doneMsg) async {
    final tasks =
        await TaskService().tasksFor(widget.mechanic.id);
    final busy =
        tasks.where((t) => t.status == TaskStatus.inProgress).toList();
    if (busy.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('order_task_conflict_title')),
          content: Text(t('order_task_conflict_body',
              {'title': busy.first.title})),
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
    await _transition(op, doneMsg: doneMsg);
  }

  Future<void> _transition(Future<WorkOrder> Function() op,
      {String? doneMsg}) async {
    setState(() => _busy = true);
    try {
      final updated = await op();
      if (!mounted) return;
      setState(() {
        _order = updated;
        _busy = false;
      });
      widget.onChanged?.call();
      if (doneMsg != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(doneMsg)));
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reasigna la orden a otro mecánico (solo admin).
  Future<void> _reassign() async {
    final mechanics =
        await MechanicService().loadMechanics();
    if (!mounted) return;
    String picked = _order.mechanicId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('order_detail_reassign_title')),
          content: DropdownButtonFormField<String>(
            value: picked,
            dropdownColor: AppTheme.surface,
            style: const TextStyle(
                color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: mechanics
                .map((m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(m.name),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setD(() => picked = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(true),
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (picked == _order.mechanicId) return;
    setState(() => _busy = true);
    // Si el cronómetro estaba corriendo, se detiene al reasignar.
    final updated = _order.copyWith(
      mechanicId: picked,
      clearTimerStart: _order.isTimerRunning,
    );
    await _orderService.update(updated);
    if (!mounted) return;
    setState(() {
      _order = updated;
      _busy = false;
    });
    widget.onChanged?.call();
  }

  /// Corrige el tiempo trabajado manualmente (ej. el cronómetro se quedó
  /// corriendo de más). Pide horas y minutos del total real.
  Future<void> _correctTime() async {
    final current = _order.elapsedSeconds;
    final hCtrl =
        TextEditingController(text: '${current ~/ 3600}');
    final mCtrl =
        TextEditingController(text: '${(current % 3600) ~/ 60}');
    String? error;
    final seconds = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(t('order_detail_correct_time_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: t('order_detail_hours'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: mCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: t('order_detail_minutes'),
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => safePop(ctx),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                final h = int.tryParse(hCtrl.text.trim()) ?? -1;
                final m = int.tryParse(mCtrl.text.trim()) ?? -1;
                if (h < 0 || m < 0 || m > 59 || (h == 0 && m == 0)) {
                  setD(() =>
                      error = t('order_detail_time_invalid'));
                  return;
                }
                safePop(ctx, h * 3600 + m * 60);
              },
              child: Text(t('common_save')),
            ),
          ],
        ),
      ),
    );
    disposeDialogControllers([hCtrl, mCtrl]);
    if (seconds != null && mounted) {
      await _transition(
          () => _orderService.correctTime(_order.id, seconds),
          doneMsg: t('order_detail_time_corrected'));
    }
  }

  /// "Ya la realicé": la tarea se hizo sin iniciar el cronómetro.
  /// Pide fecha y hora de inicio/fin, calcula la duración y la manda
  /// a revisión.
  Future<void> _markAsDone() async {
    DateTime workDate = DateTime.now();
    TimeOfDay start = TimeOfDay.now();
    start = start.replacing(
        hour: (start.hour - 1) < 0 ? 0 : start.hour - 1);
    TimeOfDay end = TimeOfDay.now();
    String? error;
    int minutesOf(TimeOfDay tod) => tod.hour * 60 + tod.minute;
    // Devuelve [seconds, workDate] o null si se cancela.
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final dur = minutesOf(end) - minutesOf(start);
          final today = DateTime.now();
          final isToday = workDate.year == today.year &&
              workDate.month == today.month &&
              workDate.day == today.day;
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title:
                Text(t('order_detail_already_done_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('order_detail_work_date')),
                  trailing: Text(
                    _formatShortDate(workDate),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: workDate,
                      firstDate: today.subtract(
                          const Duration(days: 30)),
                      lastDate: today,
                    );
                    if (picked != null) {
                      setD(() {
                        workDate = picked;
                        error = null;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(t('order_detail_start_time')),
                  trailing: Text(
                    start.format(ctx),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent),
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: start,
                    );
                    if (picked != null) {
                      setD(() {
                        start = picked;
                        error = null;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('order_detail_end_time')),
                  trailing: Text(
                    end.format(ctx),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent),
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: end,
                    );
                    if (picked != null) {
                      setD(() {
                        end = picked;
                        error = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  dur > 0
                      ? t('order_detail_duration',
                          {'time': formatWorkTime(dur * 60)})
                      : t('order_detail_time_invalid'),
                  style: TextStyle(
                    color: dur > 0
                        ? AppTheme.textSecondary
                        : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
                if (!isToday) ...[
                  const SizedBox(height: 4),
                  Text(
                    t('order_detail_done_days_ago', {
                      'n': '${today.difference(DateTime(
                              workDate.year,
                              workDate.month,
                              workDate.day)).inDays}'
                    }),
                    style: const TextStyle(
                        color: Colors.amber, fontSize: 12),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => safePop(ctx),
                child: Text(t('common_cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final d =
                      minutesOf(end) - minutesOf(start);
                  if (d <= 0) {
                    setD(() => error =
                        t('order_detail_time_invalid'));
                    return;
                  }
                  safePop(ctx, [d * 60, workDate]);
                },
                child:
                    Text(t('order_detail_send_review')),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      final seconds = result[0] as int;
      final date = result[1] as DateTime;
      setState(() => _busy = true);
      try {
        final updated = await _orderService.completeManual(
            _order.id, seconds, date);
        if (!mounted) return;
        setState(() {
          _order = updated;
          _busy = false;
        });
        widget.onChanged?.call();
        // Sigue a Completar información para anotar materiales.
        await _goToCompleteInfo();
      } catch (_) {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// Fecha corta para mostrar (ej. "4 oct 2026").
  String _formatShortDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  double get _reviewTotal {
    var sum = 0.0;
    for (final l in _order.lines) {
      if (l.price != null) {
        sum += l.price!;
      } else {
        sum += double.tryParse(
                _priceCtrls[l.serviceId]?.text.trim() ?? '') ??
            0;
      }
    }
    // Materiales del taller a precio de venta + compras para el trabajo.
    sum += _order.materials
        .where((m) => m.fromShop)
        .fold(0.0, (s, m) => s + m.totalPrice);
    sum += _order.purchases.fold(0.0, (s, p) => s + p.amount);
    return sum;
  }

  /// Costo de los materiales para el taller (a precio de costo).
  /// Se usa en órdenes internas: el gasto del vehículo lleva el costo,
  /// no el precio de venta.
  double get _materialsCost =>
      _order.materials
          .where((m) => m.fromShop)
          .fold(0.0, (s, m) => s + m.totalCost) +
      _order.purchases.fold(0.0, (s, p) => s + p.amount);

  Future<void> _completeTicket() async {
    final priced = <OrderLine>[];
    for (final l in _order.lines) {
      if (l.price != null) {
        priced.add(l);
      } else {
        final p = double.tryParse(
            _priceCtrls[l.serviceId]?.text.trim() ?? '');
        if (p == null || p <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(t('order_detail_price_needed',
                    {'name': '"${l.name}"'}))),
          );
          return;
        }
        priced.add(OrderLine(
          serviceId: l.serviceId,
          name: l.name,
          price: p,
          note: l.note,
        ));
      }
    }
    setState(() => _busy = true);
    final total = priced.fold(0.0, (s, l) => s + (l.price ?? 0));

    // Orden interna (vehículo del taller): no genera ticket de cliente;
    // el total se registra como gasto del vehículo. Los materiales
    // van a costo (es gasto propio, no venta).
    if (_order.isInternal) {
      final desc = priced.map((l) => l.name).join(', ');
      final matDesc = _order.materials
          .where((m) => m.fromShop)
          .map((m) => '${m.name} × ${m.qty.round()}')
          .join(', ');
      final purDesc =
          _order.purchases.map((p) => p.description).join(', ');
      final notes = [
        desc,
        if (matDesc.isNotEmpty) 'Materiales: $matDesc',
        if (purDesc.isNotEmpty) 'Compras: $purDesc',
      ].join(' · ');
      await ShopVehicleService().addExpense(VehicleExpense(
        id: DateTime.now()
            .millisecondsSinceEpoch
            .toString(),
        vehicleId: _order.shopVehicleId!,
        date: DateTime.now(),
        kind: _expenseKind,
        amount: total + _materialsCost,
        notes: notes,
      ));
      final updated =
          _order.copyWith(status: OrderStatus.completed, lines: priced);
      await _orderService.update(updated);
      // El vehículo sale del taller: vuelve a activo, salvo que tenga
      // otros trabajos abiertos o el admin le haya cambiado el estado.
      final vehicleSvc = ShopVehicleService();
      final vehicles = await vehicleSvc.loadVehicles();
      final idx = vehicles
          .indexWhere((v) => v.id == _order.shopVehicleId);
      if (idx != -1 && vehicles[idx].status == 'taller') {
        final others = await _orderService.list();
        final stillOpen = others.any((o) =>
            o.id != _order.id &&
            o.isInternal &&
            o.shopVehicleId == _order.shopVehicleId &&
            o.status != OrderStatus.completed);
        if (!stillOpen) {
          await vehicleSvc
              .updateVehicle(vehicles[idx].copyWith(status: 'activo'));
        }
      }
      if (!mounted) return;
      setState(() {
        _order = updated;
        _busy = false;
      });
      widget.onChanged?.call();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  color: Colors.green, size: 64),
              const SizedBox(height: 12),
              Text(t('order_detail_internal_done'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text(formatMoney(total),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 26)),
              const SizedBox(height: 4),
              Text(t('order_detail_internal_expense'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('common_accept')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    // Materiales del inventario (del taller) y compras para el trabajo
    // se suman como líneas del ticket a precio de venta. El admin las
    // puede editar después desde el ticket.
    final ticketLines =
        priced.map((l) => l.toTicketLine()).toList();
    for (final m in _order.materials) {
      if (!m.fromShop || m.totalPrice <= 0) continue;
      ticketLines.add(TicketLine(
        serviceId: 'inv-${m.itemId}',
        name: '${m.name} × ${m.qty.round()}',
        price: m.totalPrice,
        quantity: 1,
      ));
    }
    for (final p in _order.purchases) {
      ticketLines.add(TicketLine(
        serviceId: 'pur-${p.id}',
        name: p.description,
        price: p.amount,
        quantity: 1,
      ));
    }
    final ticketTotal =
        ticketLines.fold(0.0, (sum, l) => sum + l.subtotal);

    // Estado del pago elegido por el admin en la revisión.
    double? amountPaid; // null = pagado completo
    final payments = <TicketPayment>[];
    if (_payMode == 2) {
      amountPaid = 0; // crédito: no se cobró nada aún
    } else if (_payMode == 1) {
      final abono = double.tryParse(_abonoCtrl.text.trim()) ?? 0;
      if (abono <= 0 || abono >= ticketTotal) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('order_detail_abono_invalid'))),
        );
        return;
      }
      amountPaid = abono;
      payments.add(TicketPayment(date: DateTime.now(), amount: abono));
    }

    final ticket = Ticket(
      id: '',
      dateTime: DateTime.now(),
      mechanicId: _order.mechanicId,
      mechanicName: _assigneeName,
      vehicleType: _order.vehicleType,
      vehicle: _order.vehicle,
      customer: _order.customer,
      photos: _order.photos,
      lines: ticketLines,
      total: ticketTotal,
      workSeconds: _order.elapsedSeconds,
      amountPaid: amountPaid,
      payments: payments,
    );
    final ticketFolio = await TicketService().save(ticket);
    final savedTicket = ticket.copyWith(id: ticketFolio);
    final updated = _order.copyWith(status: OrderStatus.completed, lines: priced);
    await _orderService.update(updated);
    if (!mounted) return;
    setState(() {
      _order = updated;
      _busy = false;
    });
    widget.onChanged?.call();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle,
                color: Colors.green, size: 64),
            const SizedBox(height: 12),
            Text(t('order_detail_ticket_done'),
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            const SizedBox(height: 8),
            Text(t('order_detail_ticket_folio', {'folio': '$ticketFolio'}),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15)),
            Text(formatMoney(total),
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 26)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                TicketShareService.showSheet(context, savedTicket),
            icon: const Icon(Icons.share),
            label: Text(t('order_detail_share')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t('common_accept')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('order_detail_title', {'folio': '${_order.folio}'})),
        centerTitle: true,
        actions: [
          // Reasignar a otro mecánico (solo admin, orden no completada).
          if (_isAdmin &&
              _order.status != OrderStatus.completed)
            IconButton(
              tooltip: t('order_detail_reassign'),
              icon: const Icon(Icons.person_add_alt),
              onPressed: _busy ? null : _reassign,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(),
          if (_order.status != OrderStatus.pending) ...[
            const SizedBox(height: 16),
            _WorkTimer(
              order: _order,
              // Corregir el tiempo: el admin/fundador puede hasta
              // completar el ticket; el mecánico asignado solo
              // mientras la trabaja (en revisión ya no toca la hora).
              onCorrectTime: _canCorrectTime ? _correctTime : null,
            ),
          ],
          // Si se registró manual ("Ya la realicé"), mostrar cuándo se hizo.
          if (_order.manualWorkDate != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('order_detail_manual_date', {
                        'date': _formatShortDate(
                            _order.manualWorkDate!)
                      }),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_order.isQuickOrder) ...[
            _section(t('order_detail_quick_section')),
            const SizedBox(height: 6),
            _info(_order.lines.first.note ?? ''),
            _info(t('order_detail_attended', {'name': '$_assigneeName'})),
            const SizedBox(height: 14),
          ] else ...[
            _section(t('order_detail_vehicle')),
            const SizedBox(height: 6),
            _info(_order.vehicle.label),
            if ((_order.vehicle.vin ?? '').isNotEmpty)
              _info('VIN: ${_order.vehicle.vin}'),
            _info(t('order_detail_attended', {'name': '$_assigneeName'})),
            const SizedBox(height: 14),
            _section(t('order_detail_customer')),
            const SizedBox(height: 6),
            _info(_order.isInternal
                ? _order.displayCustomerName
                : _order.customer.label),
            const SizedBox(height: 14),
            _section(t('order_detail_photos')),
            const SizedBox(height: 8),
            _photosGrid(),
            const SizedBox(height: 14),
            _section(t('order_detail_levels')),
            const SizedBox(height: 6),
            _condition(t('order_detail_oil'), _order.vehicle.oilCondition),
            _level(t('order_detail_fuel'), _order.vehicle.fuelLevel),
            _condition(t('order_detail_coolant'), _order.vehicle.coolantCondition),
            if (_order.vehicle.conditionNotes?.isNotEmpty == true) ...[
              const SizedBox(height: 14),
              _section(t('order_detail_notes')),
              const SizedBox(height: 6),
              _info(_order.vehicle.conditionNotes!),
            ],
            const SizedBox(height: 14),
          ],
          _section(t('order_detail_services')),
          const SizedBox(height: 8),
          ..._order.lines.map(_lineRow),
          if (_order.status == OrderStatus.inReview && _isAdmin) ...[
            const SizedBox(height: 20),
            _reviewCard(),
          ],
          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: _actionBar(),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap,
      {bool secondary = false}) {
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      backgroundColor: secondary ? AppTheme.surface : null,
      foregroundColor: secondary ? AppTheme.textPrimary : null,
    );
    return FilledButton(
      onPressed: _busy ? null : onTap,
      style: style,
      child: Text(label,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  /// Barra que bloquea el trabajo hasta registrar la entrada.
  /// [extraButtons] permite conservar acciones que no arrancan el
  /// Abre "Completar información" y, si el mecánico confirma, manda la
  /// orden a revisión con los materiales y compras reportados.
  Future<void> _goToCompleteInfo() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CompleteOrderScreen(order: _order),
      ),
    );
    if (done == true && mounted) {
      final updated =
          await _orderService.byId(_order.id);
      if (mounted && updated != null) {
        setState(() => _order = updated);
        widget.onChanged?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('order_detail_sent_review'))),
        );
      }
    }
  }

  /// cronómetro (ej. "Mandar a revisión").
  Widget _shiftGateBar(String message, {List<Widget>? extraButtons}) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        color: AppTheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.6)),
              ),
              child: Text(
                t('order_detail_gate_msg', {'message': message}),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _clockIn,
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green.shade700,
                    ),
                    child: Text(t('order_detail_clock_in'),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                if (extraButtons != null) ...[
                  const SizedBox(width: 12),
                  for (final b in extraButtons) Expanded(child: b),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _actionBar() {
    if (_order.status == OrderStatus.completed) return null;
    if (_order.status == OrderStatus.inReview && !_isAdmin) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          color: AppTheme.surface,
          child: Text(
            t('order_detail_pending_review'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    // Sin turno iniciado, el mecánico no puede echar a andar el cronómetro
    // (empezar ni reanudar). Pausar y mandar a revisión siempre se puede.
    final needsShift = !_isAdmin && !_onShift && _canWork;
    if (needsShift && _order.status == OrderStatus.pending) {
      return _shiftGateBar(
        t('order_detail_gate_start'),
        extraButtons: [
          _actionButton(
            t('order_detail_already_done'),
            _markAsDone,
            secondary: true,
          ),
        ],
      );
    }
    if (needsShift && _order.status == OrderStatus.paused) {
      return _shiftGateBar(
        t('order_detail_gate_resume'),
        extraButtons: [
          _actionButton(
            t('order_detail_send_review'),
            () => _goToCompleteInfo(),
          ),
        ],
      );
    }
    final buttons = <Widget>[];
    if (_canWork) {
      if (_order.status == OrderStatus.pending) {
        buttons.add(_actionButton(
          t('order_detail_start_work'),
          () => _guardedStart(
              () => _orderService.startWork(_order.id),
              t('order_detail_started')),
        ));
        // "Ya la realicé": se hizo sin iniciar el cronómetro; pide los
        // tiempos y la manda a revisión.
        buttons.add(_actionButton(
          t('order_detail_already_done'),
          _markAsDone,
          secondary: true,
        ));
      } else if (_order.status == OrderStatus.inProgress) {
        buttons.add(_actionButton(
          t('order_detail_pause'),
          () => _transition(() => _orderService.pauseWork(_order.id)),
          secondary: true,
        ));
        buttons.add(_actionButton(
          t('order_detail_send_review'),
          () => _goToCompleteInfo(),
        ));
      } else if (_order.status == OrderStatus.paused) {
        buttons.add(_actionButton(
          t('order_detail_resume'),
          () => _guardedStart(
              () => _orderService.resumeWork(_order.id),
              t('order_detail_resumed')),
          secondary: true,
        ));
        buttons.add(_actionButton(
          t('order_detail_send_review'),
          () => _goToCompleteInfo(),
        ));
      }
    }
    if (buttons.isEmpty) {
      // Admin viendo la orden ACTIVA de otro: sin botones de trabajo,
      // solo se indica quién la trae (puede reasignarla arriba).
      // En revisión o completada no aplica: ya nadie la trabaja.
      if (_isAdmin &&
          !_isAssignee &&
          (_order.status == OrderStatus.pending ||
              _order.status == OrderStatus.inProgress ||
              _order.status == OrderStatus.paused)) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                t('order_detail_working_by', {'name': _assigneeName}),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
          ),
        );
      }
      return null;
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: buttons[i]),
            ],
          ],
        ),
      ),
    );
  }

  /// Panel del administrador para revisar: pone los precios pendientes
  /// (servicio rápido) y completa el ticket.
  Widget _reviewCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.accent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check,
                    color: AppTheme.accent, size: 22),
                const SizedBox(width: 8),
                Text(t('order_detail_review_title'),
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.timer, color: AppTheme.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  t('order_detail_time_worked',
                      {'time': formatWorkTime(_order.elapsedSeconds)}),
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_order.materials.isNotEmpty) ...[
              _materialsReview(),
              const SizedBox(height: 12),
            ],
            if (_order.purchases.isNotEmpty) ...[
              _purchasesReview(),
              const SizedBox(height: 12),
            ],
            ..._order.lines.where((l) => l.needsPrice).map((l) {
              final ctrl = _priceCtrls[l.serviceId]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_order.displayLineName(l),
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                    if (l.note?.isNotEmpty == true)
                      Text(l.note!,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ctrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      style: const TextStyle(
                          color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: t('order_detail_price_label'),
                        prefixText: '\$ ',
                        labelStyle: TextStyle(
                            color: AppTheme.textSecondary),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              );
            }),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t('order_detail_ticket_total'),
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15)),
                Text(formatMoney(_reviewTotal),
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 24)),
              ],
            ),
            const SizedBox(height: 12),
            if (_order.isInternal) ...[
              // Orden interna: el total se registra como gasto
              // del vehículo del taller, no como ticket de cliente.
              Text(t('order_detail_expense_kind'),
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final k in [
                    'reparacion',
                    'servicio',
                    'otro'
                  ])
                    ChoiceChip(
                      label: Text(
                          t('shop_expense_kind_$k')),
                      selected: _expenseKind == k,
                      selectedColor: AppTheme.accent,
                      onSelected: (_) => setState(
                          () => _expenseKind = k),
                    ),
                ],
              ),
            ] else ...[
              Text(t('order_detail_payment_q'),
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                      value: 0,
                      label: Text(t('order_detail_pay_paid'))),
                  ButtonSegment(
                      value: 1,
                      label: Text(t('order_detail_pay_abono')),
                      icon: const Icon(Icons.payments, size: 18)),
                  ButtonSegment(
                      value: 2,
                      label: Text(t('order_detail_pay_fiado')),
                      icon: const Icon(Icons.schedule, size: 18)),
                ],
                selected: {_payMode},
                onSelectionChanged: (s) =>
                    setState(() => _payMode = s.first),
              ),
            ],
            if (_payMode == 1) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _abonoCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'))
                ],
                style:
                    const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: t('order_detail_abono_label'),
                  prefixText: '\$ ',
                  labelStyle:
                      TextStyle(color: AppTheme.textSecondary),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _completeTicket,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(t('order_detail_complete'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );

  /// Materiales usados vistos por el admin al revisar.
  Widget _materialsReview() {
    final mats = _order.materials;
    final cost = mats
        .where((m) => m.fromShop)
        .fold(0.0, (s, m) => s + m.totalCost);
    final sale = mats
        .where((m) => m.fromShop)
        .fold(0.0, (s, m) => s + m.totalPrice);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('review_materials_title'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          for (final m in mats)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${m.name} × ${m.qty.round()}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    m.fromShop
                        ? formatMoney(m.totalPrice)
                        : t('complete_from_client'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: m.fromShop
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(t('review_materials_cost'),
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              Text(formatMoney(cost),
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
            ],
          ),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(t('review_materials_sale'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              Text(formatMoney(sale),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  /// Compras para el trabajo vistas por el admin al revisar.
  Widget _purchasesReview() {
    final total =
        _order.purchases.fold(0.0, (s, p) => s + p.amount);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('review_purchases_cost'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          for (final p in _order.purchases)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  if (p.photoPath != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.receipt_outlined,
                          size: 16,
                          color: AppTheme.textSecondary),
                    ),
                  Expanded(
                    child: Text(p.description,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(formatMoney(p.amount),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const Divider(),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(t('review_purchases_cost'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              Text(formatMoney(total),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineRow(OrderLine l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_order.displayLineName(l),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  if (l.note?.isNotEmpty == true)
                    Text(l.note!,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13)),
                ],
              ),
            ),
            if (_isAdmin)
              Text(
                l.price == null
                    ? t('order_detail_no_price')
                    : formatMoney(l.price!),
                style: TextStyle(
                    color: l.price == null
                        ? AppTheme.textSecondary
                        : AppTheme.accent,
                    fontWeight: FontWeight.w700),
              ),
          ],
        ),
      );

  Widget _headerCard() {
    Color chipColor;
    switch (_order.status) {
      case OrderStatus.pending:
        chipColor = Colors.orange;
        break;
      case OrderStatus.inProgress:
        chipColor = Colors.blue;
        break;
      case OrderStatus.paused:
        chipColor = Colors.amber;
        break;
      case OrderStatus.inReview:
        chipColor = Colors.purple;
        break;
      case OrderStatus.completed:
        chipColor = Colors.green;
        break;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Las insignias se envuelven a dos líneas en ventanas angostas
          // en vez de desbordar la fila.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      t('order_detail_folio', {'folio': '${_order.folio}'}),
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(t('orders_status_${_order.status.name}'),
                      style: TextStyle(
                          color: chipColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatDateTime(_order.createdAt),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _section(String text) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17),
      );

  Widget _info(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 15)),
      );

  Widget _photosGrid() {
    final slots = PhotoService.slots;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemCount: slots.length,
      itemBuilder: (context, i) {
        final slot = slots[i];
        final path = _order.photos[slot];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: path != null
                    ? Image.file(File(path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => _noPhoto())
                    : _noPhoto(),
              ),
            ),
            const SizedBox(height: 4),
            Text(PhotoService.slotLabels[slot] ?? slot,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        );
      },
    );
  }

  Widget _noPhoto() => Container(
        color: AppTheme.surfaceLight,
        child: const Center(
          child: Icon(Icons.image_not_supported,
              color: AppTheme.textSecondary),
        ),
      );

  Widget _level(String name, int? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15)),
            ),
            Text(value == null ? '—' : '$value%',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      );

  Color _conditionColor(ConditionLevel level) {
    switch (level) {
      case ConditionLevel.malo:
        return Colors.red;
      case ConditionLevel.regular:
        return Colors.orange;
      case ConditionLevel.bien:
        return Colors.green;
    }
  }

  Widget _condition(String name, ConditionLevel? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15)),
            ),
            Text(
              value == null ? '—' : value.label,
              style: TextStyle(
                  color: value == null
                      ? AppTheme.textSecondary
                      : _conditionColor(value),
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ],
        ),
      );
}

/// Cronómetro de la orden: muestra el tiempo trabajado y se actualiza
/// cada segundo mientras el trabajo está en curso.
class _WorkTimer extends StatefulWidget {
  final WorkOrder order;

  /// Si no es null, muestra el lápiz para corregir el tiempo.
  final VoidCallback? onCorrectTime;

  const _WorkTimer({required this.order, this.onCorrectTime});

  @override
  State<_WorkTimer> createState() => _WorkTimerState();
}

class _WorkTimerState extends LocaleAwareState<_WorkTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _WorkTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final running = widget.order.isTimerRunning;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.order.isTimerRunning;
    final paused = widget.order.status == OrderStatus.paused;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: running
              ? Colors.blue.withValues(alpha: 0.6)
              : Colors.amber.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer,
              color: running ? Colors.blue : Colors.amber, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatWorkTime(widget.order.elapsedSeconds),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? t('order_detail_timer_running')
                      : paused
                          ? t('order_detail_timer_paused')
                          : t('order_detail_timer_idle'),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (widget.onCorrectTime != null)
            IconButton(
              tooltip: t('order_detail_correct_time'),
              icon: const Icon(Icons.edit_outlined,
                  color: AppTheme.textSecondary),
              onPressed: widget.onCorrectTime,
            ),
        ],
      ),
    );
  }
}
