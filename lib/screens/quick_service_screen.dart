import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../models/mechanic.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../models/quick_service.dart';
import '../models/work_order.dart';
import '../services/mechanic_service.dart';
import '../services/work_order_service.dart';
import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shift_gate.dart';

/// Botón "Servicio rápido" del inicio: crea una orden describiendo
/// solo el trabajo, sin pedir datos del vehículo ni del cliente.
/// El precio lo pone el administrador al revisar la orden.
class QuickServiceScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;

  const QuickServiceScreen({
    super.key,
    required this.vehicleType,
    required this.mechanic,
  });

  @override
  State<QuickServiceScreen> createState() => _QuickServiceScreenState();
}

class _QuickServiceScreenState extends LocaleAwareState<QuickServiceScreen> {
  final _descCtrl = TextEditingController();
  List<Mechanic> _mechanics = [];
  late String _assigneeId;
  bool _busy = false;
  bool _onShift = true; // el admin siempre puede trabajar

  bool get _isAdmin => widget.mechanic.isAdmin;

  @override
  void initState() {
    super.initState();
    // Quien crea la orden es su dueño: el mecánico se la auto-asigna;
    // solo el administrador puede elegir a otro mecánico.
    _assigneeId = widget.mechanic.id;
    _loadMechanics();
    _loadShift();
  }

  /// Sin turno iniciado, el mecánico no puede tomar el servicio.
  Future<void> _loadShift() async {
    final onShift = await isOnShift(widget.mechanic);
    if (mounted) setState(() => _onShift = onShift);
  }

  Future<void> _loadMechanics() async {
    if (!_isAdmin) return;
    final list = await MechanicService().loadMechanics();
    if (mounted) setState(() => _mechanics = list);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('quick_service_describe_error'))),
      );
      return;
    }
    setState(() => _busy = true);
    final now = DateTime.now();
    final order = WorkOrder(
      id: 'wo-${now.millisecondsSinceEpoch}',
      folio: '',
      vehicleType: widget.vehicleType,
      // Orden rápida: sin vehículo ni cliente registrados.
      vehicle: Vehicle(
          id: 'none', type: widget.vehicleType, year: 0, brand: '', model: '', plate: ''),
      customer: const Customer(name: '', phone: ''),
      photos: const {},
      lines: [
        OrderLine(serviceId: quickServiceId, name: 'Servicio rápido', note: desc),
      ],
      mechanicId: _assigneeId,
      createdById: widget.mechanic.id,
      createdAt: now,
    );
    final folio = await WorkOrderService().create(order);
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 12),
            Text(t('quick_service_order_created'),
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            const SizedBox(height: 8),
            Text(t('quick_service_folio', {'folio': '$folio'}),
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('quick_service_title')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight),
            ),
            child: Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('quick_service_no_data'),
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      SizedBox(height: 2),
                      Text(
                          t('quick_service_no_data_desc'),
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t('quick_service_describe_label'),
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            autofocus: true,
            maxLines: 3,
            maxLength: 120,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: t('quick_service_hint'),
              hintStyle:
                  const TextStyle(color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(t('quick_service_who'),
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 8),
          if (_isAdmin) ...[
            DropdownButtonFormField<String>(
              value: _assigneeId,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _mechanics
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _assigneeId = v);
              },
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person,
                      color: AppTheme.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('quick_service_self',
                          {'name': widget.mechanic.name}),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('quick_service_tasks_hint'),
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 28),
          // Quien crea la orden rápida es su dueño: sin turno iniciado
          // no se puede tomar el servicio (el admin está exento).
          if (!_isAdmin && !_onShift)
            ShiftGateCard(
              mechanic: widget.mechanic,
              onShiftStarted: _loadShift,
              actionLabel: t('quick_service_gate_action'),
            ),
          FilledButton(
            onPressed: (_busy || (!_isAdmin && !_onShift))
                ? null
                : _create,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(t('quick_service_create'),
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
