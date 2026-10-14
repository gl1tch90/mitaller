import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/client_summary.dart';
import '../models/customer.dart';
import '../models/mechanic.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import 'order_detail_screen.dart';
import 'services_screen.dart';
import 'ticket_detail_screen.dart';

/// Ficha del cliente: sus vehículos, botón para llamarle
/// y su historial (órdenes activas + tickets cobrados).
class ClientDetailScreen extends StatelessWidget {
  final ClientSummary client;
  final Mechanic mechanic;

  const ClientDetailScreen({
    super.key,
    required this.client,
    required this.mechanic,
  });

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: client.phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('client_detail_snackbar_cannot_open_dialer'))),
      );
    }
  }

  /// Nuevo servicio para un vehículo que ya es del cliente:
  /// va directo a elegir servicios con vehículo y cliente precargados.
  void _newService(BuildContext context, Vehicle v) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServicesScreen(
          vehicleType: v.type,
          mechanic: mechanic,
          vehicle: v,
          customer:
              Customer(name: client.name, phone: client.phone),
          photos: const {},
        ),
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = mechanic.isAdmin;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(client.name),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Ficha + llamar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.person,
                      color: AppTheme.accent, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(client.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 19)),
                      const SizedBox(height: 2),
                      Text(
                          client.phone.isNotEmpty
                              ? client.phone
                              : t('client_detail_no_phone'),
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 15)),
                    ],
                  ),
                ),
                if (client.phone.isNotEmpty)
                  IconButton.filled(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.phone),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    tooltip: t('client_detail_call_tooltip'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t('client_detail_vehicles'),
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 8),
          ...client.vehicles.map((v) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                        v.type == VehicleType.moto
                            ? Icons.two_wheeler
                            : Icons.directions_car,
                        color: AppTheme.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(v.label,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15)),
                    ),
                    IconButton(
                      tooltip: t('client_detail_new_service'),
                      icon: const Icon(Icons.add_circle,
                          color: AppTheme.accent),
                      onPressed: () => _newService(context, v),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 20),
          Text(t('client_detail_history'),
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 8),
          if (client.orders.isEmpty && client.tickets.isEmpty)
            Text(t('client_detail_empty_history'),
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
          ...client.orders.map((o) => _historyCard(
                context,
                title: o.vehicle.label,
                subtitle: t('client_detail_order_subtitle', {
                  'folio': '${o.folio}',
                  'date': formatDateTime(o.createdAt),
                }),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(o.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(t('orders_status_${o.status.name}'),
                      style: TextStyle(
                          color: _statusColor(o.status),
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(
                      order: o,
                      mechanic: mechanic,
                    ),
                  ),
                ),
              )),
          ...client.tickets.map((tk) => _historyCard(
                context,
                title: tk.vehicle.label,
                subtitle: t('client_detail_ticket_subtitle', {
                  'folio': '${tk.id}',
                  'date': formatDateTime(tk.dateTime),
                }),
                trailing: isAdmin
                    ? Text(formatMoney(tk.total),
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 16))
                    : const Icon(Icons.receipt_long,
                        color: AppTheme.textSecondary),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TicketDetailScreen(
                      ticket: tk,
                      mechanic: mechanic,
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _historyCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      );
}
