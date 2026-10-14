import 'package:flutter/material.dart';

import '../l10n/strings.dart' as l10n;
import '../models/mechanic.dart';
import '../l10n/locale_state.dart';
import '../models/ticket.dart';
import '../models/vehicle_type.dart';
import '../services/ticket_service.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/search.dart';
import '../widgets/search_field.dart';
import 'ticket_detail_screen.dart';

/// Historial de tickets (ventas cobradas) de la sección,
/// del más reciente al más viejo.
/// Vive dentro de la pestaña "Tickets" del Punto de venta.
/// Solo el administrador ve los totales.
class TicketsHistoryView extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;

  const TicketsHistoryView({
    super.key,
    required this.vehicleType,
    required this.mechanic,
  });

  @override
  State<TicketsHistoryView> createState() => TicketsHistoryViewState();
}

class TicketsHistoryViewState extends LocaleAwareState<TicketsHistoryView> {
  List<Ticket> _tickets = [];
  bool _loading = true;
  String _query = '';

  List<Ticket> get _filtered =>
      _tickets.where((t) => ticketMatches(t, _query)).toList();

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Recarga la lista (se llama al entrar a la pestaña).
  Future<void> reload() async {
    final tickets = await TicketService().list();
    if (!mounted) return;
    setState(() {
      _tickets = tickets
          .where((t) => t.vehicleType == widget.vehicleType)
          .toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
      _loading = false;
    });
  }

  bool get _isAdmin => widget.mechanic.isAdmin;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long,
                color: AppTheme.textSecondary, size: 64),
            const SizedBox(height: 12),
            Text(l10n.t('tickets_empty_title'),
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.t('tickets_empty_desc'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        SearchField(
          hint: l10n.t('tickets_search_hint'),
          onChanged: (v) => setState(() => _query = v),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    l10n.t('tickets_no_results', {'query': _query}),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) =>
                        _ticketCard(_filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _ticketCard(Ticket t) => InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TicketDetailScreen(
              ticket: t,
              mechanic: widget.mechanic,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(l10n.t('tickets_folio', {'id': t.id}),
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ),
                  const Spacer(),
                  Text(formatDateTime(t.dateTime),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                  t.isQuickOrder
                      ? '⚡ ${t.lines.first.displayName.replaceFirst('${l10n.t('my_tasks_quick_service')}: ', '')}'
                      : t.vehicle.label,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                  t.isQuickOrder
                      ? l10n.t('tickets_served_by', {'name': t.mechanicName})
                      : l10n.t('tickets_customer_served_by', {
                          'customer': t.customer.label,
                          'name': t.mechanicName
                        }),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
              if (_isAdmin) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Si el pago no está completo, avisar con el saldo.
                    if (!t.isPaid)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange
                              .withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.orange
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          l10n.t(
                              'tickets_payment_incomplete',
                              {
                                'balance':
                                    formatMoney(t.balance)
                              }),
                          style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5),
                        ),
                      ),
                    const Spacer(),
                    Text(formatMoney(t.total),
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 19)),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}
