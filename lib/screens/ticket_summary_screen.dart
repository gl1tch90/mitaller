import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/customer.dart';
import '../models/mechanic.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../services/mechanic_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/shift_gate.dart';

/// Resumen de la orden antes de crearla: qué se va a hacer y quién lo va
/// a hacer. No muestra el total final: el ticket (con precios) se genera
/// cuando el administrador revisa el trabajo terminado.
/// Al crear se asigna folio (OS-0001, ...) y se regresa al inicio.
class TicketSummaryScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;
  final Vehicle vehicle;
  final Customer customer;
  final Map<String, String> photos;
  final List<OrderLine> lines;

  const TicketSummaryScreen({
    super.key,
    required this.vehicleType,
    required this.mechanic,
    required this.vehicle,
    required this.customer,
    required this.photos,
    required this.lines,
    @Deprecated('El total se define al completar el ticket') double total = 0,
  });

  @override
  State<TicketSummaryScreen> createState() =>
      _TicketSummaryScreenState();
}

class _TicketSummaryScreenState extends LocaleAwareState<TicketSummaryScreen> {
  bool _saving = false;
  List<Mechanic> _mechanics = [];
  String? _assigneeId;
  bool _onShift = true; // el admin siempre puede trabajar

  /// Solo el administrador (jefe) puede ver los costos.
  bool get _isAdmin => widget.mechanic.isAdmin;

  @override
  void initState() {
    super.initState();
    _assigneeId = widget.mechanic.id;
    _loadMechanics();
    _loadShift();
  }

  /// Si quien crea la orden es un mecánico, se la auto-asigna:
  /// sin turno iniciado no puede tomar el trabajo.
  Future<void> _loadShift() async {
    final onShift = await isOnShift(widget.mechanic);
    if (mounted) setState(() => _onShift = onShift);
  }

  Future<void> _loadMechanics() async {
    final list = await MechanicService().loadMechanics();
    if (!mounted) return;
    setState(() {
      _mechanics = list;
      if (!_mechanics.any((m) => m.id == _assigneeId)) {
        _assigneeId = _mechanics.isEmpty ? null : _mechanics.first.id;
      }
    });
  }

  Future<void> _create() async {
    if (_saving || _assigneeId == null) return;
    setState(() => _saving = true);
    final order = WorkOrder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      folio: '',
      vehicleType: widget.vehicleType,
      vehicle: widget.vehicle,
      customer: widget.customer,
      photos: widget.photos,
      lines: widget.lines,
      mechanicId: _assigneeId!,
      createdById: widget.mechanic.id,
      createdAt: DateTime.now(),
    );
    final folio = await WorkOrderService().create(order);
    if (!mounted) return;
    setState(() => _saving = false);
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
            Text(t('ticket_summary_order_created'),
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            const SizedBox(height: 8),
            Text(t('ticket_summary_folio', {'folio': folio}),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15)),
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
    // Regresar al inicio de la sección: resumen -> servicios -> datos -> home.
    Navigator.of(context).pop();
    Navigator.of(context).pop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final assignee = _mechanics.cast<Mechanic?>().firstWhere(
          (m) => m?.id == _assigneeId,
          orElse: () => null,
        );
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('ticket_summary_title')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _vehicleCard(),
          const SizedBox(height: 20),
          _section(t('ticket_summary_services_to_do')),
          const SizedBox(height: 8),
          ...widget.lines.map(_lineRow),
          const SizedBox(height: 20),
          _section(t('ticket_summary_who_title')),
          const SizedBox(height: 8),
          // Solo el administrador puede asignar la orden a otro mecánico.
          // Si quien la crea es un mecánico, la tarea queda asignada a él.
          if (_isAdmin) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _assigneeId,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 16),
                  items: _mechanics
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _assigneeId = v),
                ),
              ),
            ),
            if (assignee != null) ...[
              const SizedBox(height: 8),
              Text(
                t('ticket_summary_appears_in_tasks_of', {'name': assignee.name}),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('ticket_summary_you_will_do_it',
                          {'name': widget.mechanic.name}),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('ticket_summary_tasks_note'),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
          // El mecánico se auto-asigna la orden: sin turno iniciado
          // no puede tomar el trabajo (el admin está exento).
          if (!_isAdmin && !_onShift) ...[
            const SizedBox(height: 20),
            ShiftGateCard(
              mechanic: widget.mechanic,
              onShiftStarted: _loadShift,
              actionLabel: t('ticket_summary_gate_action_label'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed:
                (_saving || (!_isAdmin && !_onShift)) ? null : _create,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(t('ticket_summary_create_order'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
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
                  Text(
                    displayServiceLineName(l.serviceId, l.name),
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                  if (l.note?.isNotEmpty == true)
                    Text(
                      l.note!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13),
                    ),
                ],
              ),
            ),
            if (_isAdmin)
              Text(
                l.price == null
                    ? t('ticket_summary_price_on_review')
                    : formatMoney(l.price!),
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700),
              ),
          ],
        ),
      );

  Widget _section(String text) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17),
      );

  Widget _vehicleCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.vehicleType.icon,
                    color: AppTheme.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.vehicle.label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('ticket_summary_customer_photos', {
                'customer': widget.customer.label,
                'n': '${widget.photos.length}'
              }),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
}
