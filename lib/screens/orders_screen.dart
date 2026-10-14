import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../services/mechanic_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/duration.dart';
import '../utils/search.dart';
import '../widgets/search_field.dart';
import 'order_detail_screen.dart';

/// Órdenes de servicio activas del taller (pendientes, en curso, en revisión).
/// Filtra por el tipo de vehículo de la sección (Carros o Motos),
/// del más reciente al más viejo.
class OrdersScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;

  const OrdersScreen({
    super.key,
    required this.vehicleType,
    required this.mechanic,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends LocaleAwareState<OrdersScreen> {
  List<WorkOrder> _orders = [];
  Map<String, String> _names = {};
  bool _loading = true;
  String _query = '';
  Timer? _ticker; // actualiza los cronómetros en vivo

  List<WorkOrder> get _filtered =>
      _orders.where((o) => orderMatches(o, _query)).toList();

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
    final orders = await WorkOrderService().active();
    final mechanics = await MechanicService().loadMechanics();
    if (!mounted) return;
    setState(() {
      // Las órdenes internas (vehículos del taller) se revisan en su
      // propia sección, no aquí.
      _orders = orders
          .where((o) =>
              o.vehicleType == widget.vehicleType &&
              !o.isInternal)
          .toList();
      _names = {for (final m in mechanics) m.id: m.name};
      _loading = false;
    });
  }

  String _assignee(WorkOrder o) => _names[o.mechanicId] ?? '—';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('orders_title')),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.vehicleType.icon,
                          color: AppTheme.textSecondary, size: 64),
                      const SizedBox(height: 12),
                      Text(t('orders_empty_title'),
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 17)),
                      const SizedBox(height: 6),
                      Text(
                        t('orders_empty_body'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    SearchField(
                      hint: t('orders_search_hint'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Text(
                                t('orders_no_results', {'q': _query}),
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 14),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filtered.length,
                              itemBuilder: (context, i) =>
                                  _orderCard(_filtered[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Color _statusColor(OrderStatus s) {
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

  Widget _orderCard(WorkOrder o) => InkWell(
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: o.status == OrderStatus.inReview
                ? Border.all(color: Colors.purple, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              t('orders_folio', {'folio': o.folio}),
                              style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(o.status)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              t('orders_status_${o.status.name}'),
                              style: TextStyle(
                                  color: _statusColor(o.status),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(formatDateTime(o.createdAt),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                  o.isQuickOrder
                      ? '⚡ ${o.lines.first.note ?? ''}'
                      : o.vehicle.label,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                  o.isQuickOrder
                      ? t('orders_assignee', {'name': _assignee(o)})
                      : t('orders_customer_assignee', {
                          'customer': o.customer.label,
                          'name': _assignee(o),
                        }),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                  t('orders_services_count', {
                    'n': '${o.lines.length}',
                    's': o.lines.length == 1 ? '' : 's',
                  }),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
              if (o.status != OrderStatus.pending) ...[
                const SizedBox(height: 4),
                Text(
                    t('orders_elapsed', {
                      'time': formatWorkTime(o.elapsedSeconds),
                      'paused': o.status == OrderStatus.paused
                          ? t('orders_paused_suffix')
                          : '',
                    }),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      );
}
