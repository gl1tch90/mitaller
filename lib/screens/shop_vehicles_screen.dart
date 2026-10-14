import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/mechanic.dart';
import '../models/shop_vehicle.dart';
import '../models/vehicle_type.dart';
import '../models/work_order.dart';
import '../services/mechanic_service.dart';
import '../services/shop_vehicle_service.dart';
import '../services/work_order_service.dart';
import '../theme/app_theme.dart';
import 'order_detail_screen.dart';
import 'shop_vehicle_detail_screen.dart';
import 'shop_vehicle_form_screen.dart';

/// Vehículos del taller: lista de los vehículos propios (mandados).
class ShopVehiclesScreen extends StatefulWidget {
  final Mechanic mechanic;
  final VehicleType vehicleType;

  const ShopVehiclesScreen(
      {super.key, required this.mechanic, required this.vehicleType});

  @override
  State<ShopVehiclesScreen> createState() => _ShopVehiclesScreenState();
}

class _ShopVehiclesScreenState extends LocaleAwareState<ShopVehiclesScreen> {
  final _service = ShopVehicleService();
  List<ShopVehicle> _vehicles = [];
  Map<String, VehicleLogEntry?> _todayEntries = {};
  Map<String, int> _openIssues = {};
  Map<String, VehicleDocument?> _nextExpiry = {};
  List<WorkOrder> _internalOrders = [];
  Map<String, String> _mechNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vehicles = await _service.loadVehicles();
    final todayEntries = <String, VehicleLogEntry?>{};
    final openIssues = <String, int>{};
    final nextExpiry = <String, VehicleDocument?>{};
    for (final v in vehicles) {
      todayEntries[v.id] = await _service.todayEntry(v.id);
      final issues = await _service.issuesFor(v.id, resolved: false);
      openIssues[v.id] = issues.length;
      final docs = await _service.docsFor(v.id);
      VehicleDocument? nearest;
      for (final d in docs) {
        if (nearest == null ||
            d.expiryDate.isBefore(nearest.expiryDate)) {
          nearest = d;
        }
      }
      nextExpiry[v.id] = nearest;
    }
    // Órdenes internas activas (trabajos en vehículos del taller).
    final allOrders = await WorkOrderService().list();
    final internal = allOrders
        .where((o) =>
            o.isInternal &&
            o.status != OrderStatus.completed)
        .toList();
    internal.sort((a, b) {
      int rank(OrderStatus s) {
        switch (s) {
          case OrderStatus.inReview:
            return 0;
          case OrderStatus.inProgress:
            return 1;
          case OrderStatus.paused:
            return 2;
          default:
            return 3;
        }
      }

      return rank(a.status).compareTo(rank(b.status));
    });
    Map<String, String> mechNames = {};
    if (widget.mechanic.isAdmin && internal.isNotEmpty) {
      final mechanics =
          await MechanicService().loadMechanics();
      mechNames = {
        for (final m in mechanics) m.id: m.name
      };
    }
    if (mounted) {
      setState(() {
        _vehicles = vehicles;
        _todayEntries = todayEntries;
        _openIssues = openIssues;
        _nextExpiry = nextExpiry;
        _internalOrders = internal;
        _mechNames = mechNames;
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(ShopVehicle v) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShopVehicleDetailScreen(
        mechanic: widget.mechanic,
        vehicle: v,
      ),
    ));
    _load();
  }

  Future<void> _addVehicle() async {
    final created = await Navigator.of(context).push<ShopVehicle>(
      MaterialPageRoute(
        builder: (_) => const ShopVehicleFormScreen(),
      ),
    );
    if (created != null) {
      await _service.addVehicle(created);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(t('shop_vehicles_title')),
        actions: [
          if (widget.mechanic.isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: t('shop_vehicles_add'),
              onPressed: _addVehicle,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Trabajos internos por revisar (solo admin).
                  if (widget.mechanic.isAdmin &&
                      _internalOrders.isNotEmpty)
                    _reviewCard(),
                  if (_vehicles.isEmpty &&
                      _internalOrders.isEmpty)
                    Center(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(24),
                        child: Text(
                          t('shop_vehicles_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color:
                                  AppTheme.textSecondary),
                        ),
                      ),
                    )
                  else
                    ..._vehicles.map(_vehicleCard),
                ],
              ),
            ),
    );
  }

  /// Trabajos en vehículos del taller (órdenes internas).
  /// Las por revisar van primero.
  Widget _reviewCard() {
    String statusLabel(WorkOrder o) {
      switch (o.status) {
        case OrderStatus.inReview:
          return t('shop_vehicles_status_review');
        case OrderStatus.inProgress:
          return t('shop_vehicles_status_progress');
        case OrderStatus.paused:
          return t('shop_vehicles_status_paused');
        default:
          return t('shop_vehicles_status_pending');
      }
    }

    String vehicleName(WorkOrder o) {
      for (final v in _vehicles) {
        if (v.id == o.shopVehicleId) return v.name;
      }
      return '';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Colors.purple.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build,
                  color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('shop_vehicles_work_orders'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._internalOrders.map((o) {
            final name = vehicleName(o);
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        OrderDetailScreen(
                      order: o,
                      mechanic: widget.mechanic,
                      onChanged: _load,
                    ),
                  ),
                );
                _load();
              },
              child: Container(
                margin:
                    const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: o.status ==
                          OrderStatus.inReview
                      ? Colors.purple
                          .withValues(alpha: 0.12)
                      : AppTheme.surfaceLight
                          .withValues(alpha: 0.3),
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${o.folio}${name.isNotEmpty ? ' · $name' : ''}',
                            style: const TextStyle(
                                fontWeight:
                                    FontWeight.w600,
                                fontSize: 13),
                          ),
                          Text(
                            '${_mechNames[o.mechanicId] ?? ''} · ${statusLabel(o)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme
                                    .textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color:
                            AppTheme.textSecondary,
                        size: 20),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _vehicleCard(ShopVehicle v) {
    final today = _todayEntries[v.id];
    final issues = _openIssues[v.id] ?? 0;
    final doc = _nextExpiry[v.id];
    final oilLeft = v.kmToNextOil(ShopVehicleService.oilEveryKm);

    Color? docColor;
    String? docText;
    if (doc != null) {
      final days = doc.daysToExpiry();
      if (days < 0) {
        docColor = Colors.redAccent;
        docText = t('shop_vehicles_doc_expired',
            {'doc': doc.label});
      } else if (days <= ShopVehicleService.docWarnDays) {
        docColor = Colors.amber;
        docText = t('shop_vehicles_doc_soon',
            {'doc': doc.label, 'days': '$days'});
      }
    }

    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(v),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _thumb(v),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${v.kind == 'moto' ? t('shop_vehicles_moto') : t('shop_vehicles_carro')}'
                      '${v.plates.isNotEmpty ? ' · ${v.plates}' : ''}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusChip(v),
                        _chip(
                          today != null
                              ? t('shop_vehicles_logged_today')
                              : t('shop_vehicles_not_logged'),
                          today != null
                              ? Colors.green
                              : Colors.orange,
                        ),
                        if (issues > 0)
                          _chip(
                            t('shop_vehicles_issues_open',
                                {'n': '$issues'}),
                            Colors.redAccent,
                          ),
                        if (docText != null)
                          _chip(docText, docColor!),
                        _chip(
                          oilLeft < 0
                              ? t('shop_vehicles_oil_due')
                              : t('shop_vehicles_oil_left',
                                  {'km': '$oilLeft'}),
                          oilLeft < 0
                              ? Colors.redAccent
                              : AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(ShopVehicle v) {
    if (v.photoPath != null && File(v.photoPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(v.photoPath!),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        v.kind == 'moto'
            ? Icons.two_wheeler
            : Icons.directions_car,
        color: AppTheme.accent,
        size: 32,
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  /// Distintivo de estado del vehículo: círculo de color + etiqueta.
  Widget _statusChip(ShopVehicle v) {
    Color color;
    String label;
    switch (v.status) {
      case 'taller':
        color = Colors.orange;
        label = t('shop_vehicle_status_taller');
        break;
      case 'vendido':
        color = Colors.grey;
        label = t('shop_vehicle_status_vendido');
        break;
      default:
        color = Colors.green;
        label = t('shop_vehicle_status_activo');
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
