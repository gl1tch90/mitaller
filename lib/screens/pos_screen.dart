import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../models/customer.dart';
import '../models/mechanic.dart';
import '../models/vehicle.dart';
import '../models/vehicle_type.dart';
import '../theme/app_theme.dart';
import 'services_screen.dart';
import 'tickets_screen.dart';
import 'vehicle_data_screen.dart';

/// Punto de venta con dos pestañas:
/// - "Vender": el flujo de venta (datos del vehículo -> servicios).
/// - "Tickets": el historial de tickets cobrados de la sección.
class PosScreen extends StatefulWidget {
  final VehicleType vehicleType;
  final Mechanic mechanic;

  const PosScreen(
      {super.key, required this.vehicleType, required this.mechanic});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends LocaleAwareState<PosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _ticketsKey = GlobalKey<TicketsHistoryViewState>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      // Al entrar a la pestaña de Tickets, recargar por si se
      // completó alguno mientras se estaba en otra pantalla.
      if (_tabs.index == 1 && !_tabs.indexIsChanging) {
        _ticketsKey.currentState?.reload();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _continue(Vehicle vehicle, Customer customer,
      Map<String, String> photos) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServicesScreen(
          vehicleType: widget.vehicleType,
          mechanic: widget.mechanic,
          vehicle: vehicle,
          customer: customer,
          photos: photos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        title: Text(t('pos_title')),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.accent,
          indicatorWeight: 3,
          tabs: [
            Tab(text: t('pos_tab_sell')),
            Tab(text: t('pos_tab_tickets')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          VehicleDataScreen(
            vehicleType: widget.vehicleType,
            onContinue: _continue,
          ),
          TicketsHistoryView(
            key: _ticketsKey,
            vehicleType: widget.vehicleType,
            mechanic: widget.mechanic,
          ),
        ],
      ),
    );
  }
}
