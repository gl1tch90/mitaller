import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/mechanic.dart';
import '../models/ticket.dart';
import '../models/vehicle.dart';
import '../services/photo_service.dart';
import '../services/ticket_share_service.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/duration.dart';
import '../utils/money.dart';

/// Detalle de un ticket (orden de servicio): vehículo, cliente,
/// fotos de condición, niveles, notas y servicios realizados.
/// Los costos solo se muestran al administrador.
class TicketDetailScreen extends StatelessWidget {
  final Ticket ticket;
  final Mechanic mechanic;

  const TicketDetailScreen({
    super.key,
    required this.ticket,
    required this.mechanic,
  });

  bool get _isAdmin => mechanic.isAdmin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('ticket_detail_folio', {'id': '${ticket.id}'})),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: t('ticket_detail_share_tooltip'),
            onPressed: () =>
                TicketShareService.showSheet(context, ticket),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _folioHeader(),
          const SizedBox(height: 20),
          if (ticket.isQuickOrder) ...[
            _section(t('ticket_detail_quick_service')),
            const SizedBox(height: 8),
            _info(ticket.lines.first.displayName.replaceFirst(
                '${t('my_tasks_quick_service')}: ', '')),
            _info(t('ticket_detail_attended', {'name': ticket.mechanicName})),
            if (ticket.workSeconds > 0)
              _info(t('ticket_detail_work_time',
                {'time': formatWorkTime(ticket.workSeconds)})),
            const SizedBox(height: 20),
          ] else ...[
            _section(t('ticket_detail_vehicle')),
            const SizedBox(height: 8),
            _info(ticket.vehicle.label),
            _info(t('ticket_detail_plate', {'plate': ticket.vehicle.plate})),
            if (ticket.vehicle.vin != null && ticket.vehicle.vin!.isNotEmpty)
              _info('VIN ${ticket.vehicle.vin}'),
            const SizedBox(height: 20),
            _section('Cliente'),
            const SizedBox(height: 8),
            _info(ticket.customer.name),
            if (ticket.customer.phone.isNotEmpty)
              _info(t('ticket_detail_phone', {'phone': ticket.customer.phone})),
            const SizedBox(height: 20),
            _section(t('ticket_detail_condition_photos')),
            const SizedBox(height: 8),
            _photosGrid(),
            const SizedBox(height: 20),
            _section(t('ticket_detail_recorded_levels')),
            const SizedBox(height: 8),
            _condition(t('ticket_detail_oil'), ticket.vehicle.oilCondition),
            _level(t('ticket_detail_fuel'), ticket.vehicle.fuelLevel),
            _condition(t('ticket_detail_coolant'), ticket.vehicle.coolantCondition),
            if (ticket.vehicle.conditionNotes != null &&
                ticket.vehicle.conditionNotes!.isNotEmpty) ...[
              const SizedBox(height: 20),
              _section(t('ticket_detail_condition_notes')),
              const SizedBox(height: 8),
              _info(ticket.vehicle.conditionNotes!),
            ],
            const SizedBox(height: 20),
          ],
          _section(t('ticket_detail_services_done')),
          const SizedBox(height: 8),
          ...ticket.lines.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${l.quantity} × ${l.displayName}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15)),
                  ),
                  if (_isAdmin)
                    Text(formatMoney(l.subtotal),
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(t('ticket_detail_total'),
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14)),
                  Text(formatMoney(ticket.total),
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 40)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
              t('ticket_detail_attended_date', {
                'name': ticket.mechanicName,
                'date': formatDateTime(ticket.dateTime)
              }),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12.5)),
          if (ticket.workSeconds > 0)
            Text(
                t('ticket_detail_work_time',
                    {'time': formatWorkTime(ticket.workSeconds)}),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12.5)),
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

  Widget _folioHeader() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(t('ticket_detail_folio', {'id': '${ticket.id}'}),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ),
            const Spacer(),
            Text(formatDateTime(ticket.dateTime),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );

  Widget _photosGrid() {
    final slots = PhotoService.slots;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemCount: slots.length,
      itemBuilder: (context, i) {
        final slot = slots[i];
        final path = ticket.photos[slot];
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

  /// Estado de aceite/anticongelante: la etiqueta sale en el color
  /// del estado (rojo = malo, naranja = regular, verde = bien).
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
            Text(value == null ? '—' : value.label,
                style: TextStyle(
                    color: value == null
                        ? AppTheme.textPrimary
                        : _conditionColor(value),
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      );
}
