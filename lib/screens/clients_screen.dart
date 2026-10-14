import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/client_summary.dart';
import '../models/mechanic.dart';
import '../models/vehicle_type.dart';
import '../services/ticket_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import 'client_detail_screen.dart';

/// Directorio de clientes de la sección: nombre, teléfono, sus vehículos
/// y cuántas veces han venido. Toca un cliente para ver su historial.
class ClientsScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;

  const ClientsScreen({
    super.key,
    required this.vehicleType,
    required this.mechanic,
  });

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends LocaleAwareState<ClientsScreen> {
  List<ClientSummary> _clients = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orders = await WorkOrderService().active();
    final tickets = await TicketService().list();
    if (!mounted) return;
    setState(() {
      _clients = ClientSummary.aggregate(
        orders: orders
            .where((o) => o.vehicleType == widget.vehicleType)
            .toList(),
        tickets: tickets
            .where((t) => t.vehicleType == widget.vehicleType)
            .toList(),
      );
      _loading = false;
    });
  }

  List<ClientSummary> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _clients;
    return _clients.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q) ||
          c.vehicles.any((v) => v.label.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('clients_title')),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: t('clients_search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            t('clients_empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) =>
                              _clientCard(_filtered[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _clientCard(ClientSummary c) => InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientDetailScreen(
              client: c,
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
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.person,
                    color: AppTheme.accent, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (c.phone.isNotEmpty) c.phone,
                        t('clients_vehicles', {
                          'n': '${c.vehicles.length}',
                          's': c.vehicles.length == 1 ? '' : 's'
                        }),
                        t('clients_visits', {
                          'n': '${c.totalVisits}',
                          's': c.totalVisits == 1 ? '' : 's'
                        }),
                      ].join(' · '),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      );
}
